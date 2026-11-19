--[[
    aire.koplugin/common/sheet.lua
    Hojas inferiores de Aire: lo que todas comparten, en un solo sitio.

      frame(content, owner)  marco de hoja (ancho de hoja, borde fino, esquinas,
                             relleno) colocado abajo con su margen. Si content es
                             una función (w -> widget) y no cabe en la pantalla,
                             se desplaza (ScrollableContainer). Lo usan también
                             las ventanas de KOReader que Aire monta como hoja.
      Sheet                  hoja propia: frame + cierre (tocar fuera, Atrás;
                             deslizar no cierra ni pasa a lo de debajo) y
                             refresco al abrirse y al cerrarse.

    Las medidas son las de common/screen.lua (SHEET). Se carga una vez desde
    main.lua en package.loaded.aire_sheet, después de common/screen.lua.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local AireScreen = package.loaded.aire_screen
local AireUI = package.loaded.aire_ui

local M = {}

local function S(n) return Screen:scaleBySize(n) end

-- Recuadro real de un widget ya pintado: FrameContainer solo guarda el tamaño
-- de la primera pintura (regla 9 del traspaso)
local function liveRect(w)
    local d = w and w.dimen
    if not (d and d.x and d.y) then return d end
    local ok, size = pcall(w.getSize, w)
    if not ok or not size then return d end
    return Geom:new{ x = d.x, y = d.y, w = size.w, h = size.h }
end
M.liveRect = liveRect

-- Alto máximo del contenido de una hoja (pantalla menos márgenes, relleno y borde)
function M.maxContentHeight()
    local SH = AireScreen.SHEET
    return Screen:getHeight() - 2 * S(SH.MARGIN) - 2 * (S(SH.PAD) + Size.border.thin)
end

--===========================================================================
-- frame(content, owner, opts) -> frame, root
--   content  widget ya montado, o function(w) -> widget (w = ancho útil); con
--            función, si no cabe, se vuelve a montar más estrecho y se desplaza
--   owner    la ventana que se muestra (para el desplazamiento: cropping_widget)
--   opts.padding_bottom  relleno inferior propio (p. ej. si lo de dentro ya
--                        deja un hueco bajo la última fila de botones)
--   opts.wrap            function(frame) -> widget que va dentro de root (p. ej.
--                        el MovableContainer que KOReader espera en ConfirmBox)
--   opts.footer          widget (de ancho útil) siempre a la vista debajo del
--                        contenido: si el contenido se desplaza, el pie no
--===========================================================================
function M.frame(content, owner, opts)
    opts = opts or {}
    local SH = AireScreen.SHEET
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local body = content
    local footer_h = 0
    if opts.footer then footer_h = opts.footer:getSize().h + S(SH.GROUP_GAP) end
    if type(content) == "function" then
        local inner = AireScreen.sheetInnerWidth()
        body = content(inner)
        local max_h = M.maxContentHeight() - footer_h
        if body:getSize().h > max_h then
            local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
            if body.free then body:free() end
            local narrow = content(inner - ScrollableContainer:getScrollbarWidth())
            body = ScrollableContainer:new{
                dimen = Geom:new{ w = inner, h = max_h },
                show_parent = owner,
                narrow,
            }
            if owner then owner.cropping_widget = body end
        end
    end
    if opts.footer then
        local VerticalGroup = require("ui/widget/verticalgroup")
        body = VerticalGroup:new{ align = "left", body, M.gap("group"), opts.footer }
    end
    local frame = FrameContainer:new{
        width = AireScreen.sheetWidth(),
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        radius = S(SH.RADIUS),
        padding = S(SH.PAD),
        padding_bottom = opts.padding_bottom,
        body,
    }
    local root = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh - S(SH.MARGIN) },
        opts.wrap and opts.wrap(frame) or frame,
    }
    return frame, root
end

--===========================================================================
-- Sheet: hoja propia de Aire
--   Sheet:new{ content = widget | function(w), footer = widget, close_callback,
--              dismissable, full_refresh }
--   footer       botones siempre a la vista (no se desplazan con el contenido)
--   o, en una subclase, llamar a Sheet.init(self) y después self:setContent(...)
--   dismissable  false: ni tocar fuera ni Atrás la cierran (p. ej. descargando)
--   full_refresh al cerrar, refrescar toda la pantalla (lo de debajo cambió)
--   close()      la cierra (y llama a close_callback); onClose respeta dismissable
--===========================================================================
local Sheet = InputContainer:extend{
    modal = true,
    dismissable = true,
    full_refresh = false,
    close_callback = nil,
    content = nil,
}
M.Sheet = Sheet

function Sheet:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        AireSheetTapOut = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        AireSheetSwipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if self.content then self:setContent(self.content) end
end

function Sheet:setContent(content, footer)
    self.frame, self[1] = M.frame(content, self, { footer = footer or self.footer })
    self.sheet = self.frame -- (nombre que usaban algunas hojas)
end

-- Tocar dentro de la hoja sin dar a un botón: nada; fuera: cerrar
function Sheet:onAireSheetTapOut(_arg, ges)
    local fd = self.frame and liveRect(self.frame)
    if ges and ges.pos and fd and fd.x and ges.pos:intersectWith(fd) then return true end
    return self:onClose()
end

-- Deslizar no cierra la hoja ni llega a la pantalla de debajo
function Sheet:onAireSheetSwipe()
    return true
end

function Sheet:onClose()
    if not self.dismissable then return true end
    return self:close()
end

function Sheet:close()
    if self._closed then return true end
    self._closed = true
    UIManager:close(self, self.full_refresh and "ui" or nil)
    if self.close_callback then self.close_callback() end
    return true
end

-- Sin tipo de refresco, UIManager:show solo pinta en memoria y en el Kindle la
-- hoja no siempre aparecía (4.19 del traspaso)
function Sheet:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame and liveRect(self.frame) end)
end

function Sheet:onCloseWidget()
    if self.full_refresh then
        UIManager:setDirty(nil, "ui")
    else
        UIManager:setDirty(nil, function() return "ui", self.frame and liveRect(self.frame) end)
    end
end

--===========================================================================
-- Piezas del contenido (todas de ancho w; medidas de SHEET)
--   title(text, w)              título de la hoja, con su hueco debajo
--   header(title, lines, w, o)  título y subtítulo (una o varias líneas, en gris),
--                               con su hueco debajo (o.no_gap: sin él)
--   subtitleLines(lines, w)     solo las líneas del subtítulo (texto que se parte)
--   section(text, w)            etiqueta de grupo ("ORDENAR POR"), con su hueco
--   separator(w)                línea fina entre grupos, con hueco a cada lado
--   gap(kind)                   hueco común: "title" | "label" | "group"
--   button(text, w, cb, opts)   botón: opts.primary (negro), opts.disabled,
--                               opts.active (elegido: relleno o, con
--                               opts.style == "outline", borde grueso),
--                               opts.on_hold, opts.lighten (estilo "gray")
--   buttons(list, w)            fila de botones del mismo ancho:
--                               { { text, callback, primary, disabled, hold_callback } }
--   choices(list, w, opts)      elegir: botones en columnas (opts.columns, 2),
--                               { { text, active, callback } }, opts.style/lighten
--   row(r, w)                   fila de opción: r.text, r.icon | r.checked (+ r.radio),
--                               r.value (gris a la derecha), r.enabled,
--                               r.callback, r.hold_callback
--===========================================================================
local function SHM() return AireScreen.SHEET end

function M.gap(kind)
    local VerticalSpan = require("ui/widget/verticalspan")
    local key = ({ title = "TITLE_GAP", label = "LABEL_GAP", group = "GROUP_GAP" })[kind] or "GROUP_GAP"
    return VerticalSpan:new{ width = S(SHM()[key]) }
end

function M.title(text, w)
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    return VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = text or "", face = AireUI.face(true, SHM().TITLE_FONT),
            fgcolor = Blitbuffer.COLOR_BLACK, max_width = w, padding = 0 },
        M.gap("title"),
    }
end

function M.subtitleLines(lines, w)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local vg = VerticalGroup:new{ align = "left" }
    for i, line in ipairs(lines or {}) do
        if line and line ~= "" then
            if i > 1 then table.insert(vg, VerticalSpan:new{ width = S(SHM().SUB_GAP) }) end
            table.insert(vg, TextBoxWidget:new{ text = line, width = w,
                face = AireUI.face(false, SHM().SUB_FONT), fgcolor = Blitbuffer.COLOR_DARK_GRAY })
        end
    end
    return vg
end

function M.header(title, lines, w, o)
    o = o or {}
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local vg = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = title or "", face = AireUI.face(true, SHM().TITLE_FONT),
            fgcolor = Blitbuffer.COLOR_BLACK, max_width = w, padding = 0 },
    }
    if lines and #lines > 0 then
        table.insert(vg, VerticalSpan:new{ width = S(SHM().SUB_GAP) })
        table.insert(vg, M.subtitleLines(lines, w))
    end
    if not o.no_gap then table.insert(vg, M.gap("title")) end
    return vg
end

function M.section(text, w)
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local P = package.loaded.aire_pages
    local label = P and P.upper and P.upper(text) or tostring(text or ""):upper()
    return VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = label, face = AireUI.face(true, SHM().LABEL_FONT),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = w, padding = 0 },
        M.gap("label"),
    }
end

function M.separator(w)
    local LineWidget = require("ui/widget/linewidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    return VerticalGroup:new{
        align = "left",
        M.gap("group"),
        LineWidget:new{ dimen = Geom:new{ w = w, h = Size.line.thin }, background = Blitbuffer.COLOR_LIGHT_GRAY },
        M.gap("group"),
    }
end

function M.button(text, w, cb, opts)
    opts = opts or {}
    local CenterContainer = require("ui/widget/container/centercontainer")
    local TextWidget = require("ui/widget/textwidget")
    local SH = SHM()
    local h = S(SH.BTN_H)
    local outline = opts.active and opts.style == "outline"
    local filled = opts.primary or (opts.active and not outline)
    local bsize = outline and Size.border.thick or Size.border.thin
    local fg = opts.disabled and Blitbuffer.COLOR_GRAY or (filled and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK)
    local box = FrameContainer:new{
        width = w, height = h,
        bordersize = bsize,
        color = opts.disabled and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK,
        background = filled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        radius = S(SH.BTN_RADIUS), padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * bsize, h = h - 2 * bsize },
            TextWidget:new{ text = text or "", face = AireUI.face(opts.active == true, SH.BTN_FONT),
                fgcolor = fg, max_width = w - S(16), padding = 0 },
        },
    }
    if filled and opts.active and opts.style == "gray" and opts.lighten then box = opts.lighten(box) end
    if opts.disabled or not (cb or opts.on_hold) then return box end
    return AireUI.tappable(box, cb, opts.on_hold)
end

function M.buttons(list, w)
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local gap = S(SHM().BTN_GAP)
    local n = math.max(1, #list)
    local bw = math.floor((w - (n - 1) * gap) / n)
    local row = HorizontalGroup:new{ align = "center" }
    for i, b in ipairs(list) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        -- el último se lleva lo que sobra del reparto
        local this_w = (i == n) and (w - (n - 1) * (bw + gap)) or bw
        table.insert(row, M.button(b.text, this_w, b.callback, {
            primary = b.primary, disabled = b.disabled, on_hold = b.hold_callback,
        }))
    end
    return row
end

function M.choices(list, w, opts)
    opts = opts or {}
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local cols = opts.columns or 2
    local gap = S(SHM().BTN_GAP)
    local vg = VerticalGroup:new{ align = "left" }
    local i = 1
    while i <= #list do
        -- la última fila, si queda una sola opción, a todo lo ancho
        local n = math.min(cols, #list - i + 1)
        local bw = math.floor((w - (n - 1) * gap) / n)
        local row = HorizontalGroup:new{ align = "center" }
        for col = 1, n do
            local c = list[i + col - 1]
            if col > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
            local this_w = (col == n) and (w - (n - 1) * (bw + gap)) or bw
            table.insert(row, M.button(c.text, this_w, c.callback, {
                active = c.active, style = opts.style, lighten = opts.lighten,
            }))
        end
        if i > 1 then table.insert(vg, VerticalSpan:new{ width = gap }) end
        table.insert(vg, row)
        i = i + n
    end
    return vg
end

function M.row(r, w)
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local SH = SHM()
    local h = S(SH.ROW_H)
    local enabled = r.enabled ~= false
    local color = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY
    local line = HorizontalGroup:new{ align = "center" }
    local lead = 0
    local icon = r.icon
    if r.checked ~= nil then
        icon = r.radio and (r.checked and "aire.radio.on" or "aire.radio.off")
            or (r.checked and "aire.checkbox.on" or "aire.checkbox.off")
    end
    if icon then
        local isz = S(SH.ICON)
        table.insert(line, IconWidget:new{ icon = icon, width = isz, height = isz, alpha = true, dim = not enabled or nil })
        table.insert(line, HorizontalSpan:new{ width = S(10) })
        lead = isz + S(10)
    end
    local value_w
    if r.value ~= nil and tostring(r.value) ~= "" then
        value_w = TextWidget:new{ text = tostring(r.value), face = AireUI.face(false, 13),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = math.floor(w * 0.45), padding = 0 }
    end
    local text_max = w - lead - (value_w and (value_w:getSize().w + S(12)) or 0)
    table.insert(line, TextWidget:new{ text = r.text or "", face = AireUI.face(false, SH.ROW_FONT),
        fgcolor = color, max_width = math.max(S(40), text_max), padding = 0 })
    local og = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, line },
    }
    if value_w then table.insert(og, RightContainer:new{ dimen = Geom:new{ w = w, h = h }, value_w }) end
    if not enabled or not (r.callback or r.hold_callback) then return og end
    return AireUI.tappable(og, r.callback, r.hold_callback)
end

--===========================================================================
-- showChoices(spec): hoja para elegir (filtro, orden, modo…). La opción
-- elegida va rellena; tocar una cierra la hoja y la aplica.
--   spec.title
--   spec.groups = { { heading = "ORDENAR POR" | nil, columns = 2,
--                     items = { { text, active, callback } } }, … }
--   (entre grupos, un separador)
--   spec.style, spec.lighten   estilo de lo seleccionado (devtools)
--===========================================================================
function M.showChoices(spec)
    local VerticalGroup = require("ui/widget/verticalgroup")
    local sheet
    -- Contenido como función del ancho: si no cabe, la hoja lo desplaza
    local function build(inner)
        local content = VerticalGroup:new{ align = "left" }
        if spec.title then table.insert(content, M.title(spec.title, inner)) end
        for gi, g in ipairs(spec.groups or {}) do
            if gi > 1 then table.insert(content, M.separator(inner)) end
            if g.heading then table.insert(content, M.section(g.heading, inner)) end
            local list = {}
            for _i, it in ipairs(g.items or {}) do
                local cb = it.callback
                table.insert(list, { text = it.text, active = it.active, callback = function()
                    UIManager:close(sheet, "ui")
                    if cb then cb() end
                end })
            end
            table.insert(content, M.choices(list, inner, {
                columns = g.columns or 2, style = spec.style, lighten = spec.lighten,
            }))
        end
        return content
    end
    sheet = Sheet:new{ content = build }
    UIManager:show(sheet, "ui")
    return sheet
end

return M
