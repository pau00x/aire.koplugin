--[[
    aire.koplugin/common/pages.lua
    Piezas comunes para las pantallas que Aire rehace por completo (Estadísticas
    del libro, Intervalo de tiempo, Línea de tiempo de hoy, Resumen de gestos,
    Detalles del marcador…), para que todas se vean y se comporten igual:

      Page      pantalla completa con la barra de título de Aire (título y
                subtítulo), contenido paginado (deslizar a los lados, puntos
                abajo), cerrar con la X, deslizando hacia abajo o con Atrás, y
                el dock en el explorador (no en el lector), como KeyValuePage.
      card      tarjeta redondeada (blanca o gris)
      label     etiqueta pequeña en mayúsculas grises ("LECTURA")
      bar       barra de progreso redondeada
      tile      casilla gris con un valor grande y una línea gris debajo
      row       fila clave (gris) / valor (negro), con › si abre algo
      pill      botón redondeado (negro si es el principal)
      tappable  envoltorio con toque / pulsación larga
      packPages reparte widgets en páginas según el alto disponible

    Uso: local P = require-like de main (ver getPages() en cada estilo).
--]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Screen = Device.screen

local P = {}

P.BLACK = Blitbuffer.COLOR_BLACK
P.WHITE = Blitbuffer.COLOR_WHITE
P.GRAY_DARK = Blitbuffer.COLOR_DARK_GRAY
P.GRAY_CARD = Blitbuffer.COLOR_GRAY_E
P.GRAY_BORDER = Blitbuffer.COLOR_GRAY
P.GRAY_LINE = Blitbuffer.COLOR_LIGHT_GRAY
P.SIDE = 16 -- margen lateral (como el resto de Aire)
P.GAP = 8   -- hueco entre tarjetas

-- Medidas y letra: las comunes (common/ui.lua)
local AireUI = package.loaded.aire_ui
P.S = AireUI.S
local S = P.S
P.face = AireUI.face
local face = P.face

local ok_up, Utf8Proc = pcall(require, "ffi/utf8proc")
function P.upper(str)
    str = tostring(str or "")
    if ok_up and Utf8Proc and Utf8Proc.uppercase_dumb then
        local ok, res = pcall(Utf8Proc.uppercase_dumb, str)
        if ok and type(res) == "string" then return res end
    end
    return str:upper()
end

-- Zona pulsable común; sin nada que hacer, el widget tal cual (no se come
-- los toques), y con solo mantener pulsado, los toques siguen de largo
function P.tappable(widget, on_tap, on_hold)
    if not on_tap and not on_hold then return widget end
    local ic = AireUI.tappable(widget, on_tap, on_hold)
    if not on_tap then ic.ges_events.AireTap = nil end
    return ic
end

function P.label(text, max_w)
    return TextWidget:new{ text = P.upper(text), face = Font:getFace("cfont", 11), bold = true,
        fgcolor = P.GRAY_DARK, max_width = max_w, padding = 0 }
end

-- Tarjeta: contenido dentro de un marco redondeado de ancho w (exterior)
function P.card(content, w, opts)
    opts = opts or {}
    return FrameContainer:new{
        width = w,
        height = opts.height,
        bordersize = Size.border.thin,
        color = opts.gray and P.GRAY_BORDER or Blitbuffer.COLOR_GRAY_D,
        background = opts.gray and P.GRAY_CARD or P.WHITE,
        radius = S(10),
        padding = opts.padding or S(10),
        content,
    }
end
-- Ancho útil dentro de una tarjeta de ancho w
function P.cardInner(w, padding) return w - 2 * ((padding or S(10)) + Size.border.thin) end

local Bar = Widget:extend{ width = 0, height = 0, pct = 0, track = nil }
function Bar:getSize() return Geom:new{ w = self.width, h = self.height } end
function Bar:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    local r = math.floor(self.height / 2)
    bb:paintRoundedRect(x, y, self.width, self.height, self.track or Blitbuffer.COLOR_GRAY_D, r)
    local fill = math.floor(self.width * math.max(0, math.min(1, self.pct or 0)))
    if fill > 0 then
        bb:paintRoundedRect(x, y, math.max(self.height, fill), self.height, P.BLACK, r)
    end
end
function P.bar(w, pct, h) return Bar:new{ width = w, height = h or S(5), pct = pct } end

-- Casilla gris: valor grande arriba, texto gris debajo
function P.tile(value, sub, w, on_tap)
    local in_w = P.cardInner(w, S(8))
    local vg = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = tostring(value or "—"), face = face(true, 16), fgcolor = P.BLACK, max_width = in_w, padding = 0 },
        VerticalSpan:new{ width = S(2) },
        TextWidget:new{ text = tostring(sub or ""), face = face(false, 11), fgcolor = P.GRAY_DARK, max_width = in_w, padding = 0 },
    }
    return P.tappable(P.card(LeftContainer:new{ dimen = Geom:new{ w = in_w, h = vg:getSize().h }, vg }, w,
        { gray = true, padding = S(8) }), on_tap)
end

-- Fila clave / valor (o › si abre algo y no tiene valor). Línea fina debajo.
function P.row(key, value, w, on_tap, opts)
    opts = opts or {}
    local h = opts.height or S(40)
    local has_value = value ~= nil and tostring(value) ~= "" and tostring(value) ~= " "
    local right_txt = has_value and tostring(value) or (on_tap and "›" or "")
    local right = TextWidget:new{ text = right_txt, face = face(has_value, 14),
        fgcolor = has_value and P.BLACK or P.GRAY_DARK, max_width = math.floor(w * 0.6), padding = 0 }
    local left = TextWidget:new{ text = tostring(key or ""), face = face(false, 14),
        fgcolor = (has_value or not on_tap) and P.GRAY_DARK or P.BLACK,
        max_width = math.max(S(40), w - right:getSize().w - S(12)), padding = 0 }
    local og = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, left },
        RightContainer:new{ dimen = Geom:new{ w = w, h = h }, right },
    }
    local vg = VerticalGroup:new{ align = "left", og }
    if not opts.no_line then
        table.insert(vg, P.line(w))
    end
    return P.tappable(vg, on_tap)
end

local Line = Widget:extend{ width = 0 }
function Line:getSize() return Geom:new{ w = self.width, h = Size.line.thin } end
function Line:paintTo(bb, x, y) bb:paintRect(x, y, self.width, Size.line.thin, P.GRAY_LINE) end
function P.line(w) return Line:new{ width = w } end

-- Botón redondeado; primary = negro
function P.pill(text, w, on_tap, opts)
    opts = opts or {}
    local h = opts.height or S(40)
    local primary = opts.primary
    local lbl = TextWidget:new{ text = text, face = face(primary, opts.font or 14),
        fgcolor = opts.disabled and Blitbuffer.COLOR_GRAY or (primary and P.WHITE or P.BLACK),
        max_width = w - S(10), padding = 0 }
    local frame = FrameContainer:new{
        width = w, height = h, bordersize = Size.border.thin,
        color = primary and P.BLACK or Blitbuffer.COLOR_GRAY,
        background = primary and P.BLACK or P.WHITE,
        radius = S(10), padding = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * Size.border.thin, h = h - 2 * Size.border.thin }, lbl },
    }
    if opts.disabled then return frame end
    return P.tappable(frame, on_tap, opts.on_hold)
end

-- Texto en varias líneas (con … si no cabe en max_lines)
function P.text(str, w, opts)
    opts = opts or {}
    local tb = TextBoxWidget:new{ text = tostring(str or ""), face = opts.face or face(opts.bold, opts.size or 14),
        fgcolor = opts.color or P.BLACK, bgcolor = opts.bgcolor, width = w }
    if opts.max_lines then
        local lh = tb:getLineHeight()
        if tb:getSize().h > opts.max_lines * lh then
            tb:free()
            tb = TextBoxWidget:new{ text = tostring(str or ""), face = opts.face or face(opts.bold, opts.size or 14),
                fgcolor = opts.color or P.BLACK, bgcolor = opts.bgcolor, width = w,
                height = opts.max_lines * lh, height_overflow_show_ellipsis = true }
        end
    end
    return tb
end

-- Reparte widgets (ya construidos) en páginas de alto h con huecos gap entre ellos
function P.packPages(widgets, h, gap)
    gap = gap or S(P.GAP)
    local pages, cur, used = {}, nil, 0
    for _i, w in ipairs(widgets) do
        local wh = w:getSize().h
        if not cur or (used + wh > h and #cur > 0) then
            cur = VerticalGroup:new{ align = "left" }
            table.insert(pages, cur)
            used = 0
        end
        if #cur > 0 then
            -- _aire_gap: hueco propio (p. ej. 0 entre filas seguidas)
            local g = w._aire_gap or gap
            if g > 0 then table.insert(cur, VerticalSpan:new{ width = g }) end
            used = used + g
        end
        table.insert(cur, w)
        used = used + wh
    end
    if #pages == 0 then pages[1] = VerticalGroup:new{ align = "left" } end
    return pages
end

--===========================================================================
-- Page: pantalla completa
--   title, subtitle, build = function(page, w, h) -> { widget, … } (páginas)
--   page:refresh() vuelve a llamar a build (p. ej. tras editar algo)
--===========================================================================
local Page = InputContainer:extend{
    title = "",
    subtitle = nil,
    build = nil,
    close_callback = nil,
    covers_fullscreen = true,
    page_no = 1,
    in_reader = false,
}
P.Page = Page

function Page:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        AireSwipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:refresh(true)
end

function Page:_dock()
    local TitleBar = require("ui/widget/titlebar")
    local RUI = package.loaded["apps/reader/readerui"]
    if self.in_reader or (RUI and RUI.instance) then return nil, 0 end
    if not (TitleBar._aire_build_dock and TitleBar._aire_dock_reserve) then return nil, 0 end
    if TitleBar._aire_dock_active and not TitleBar._aire_dock_active() then return nil, 0 end
    local ok, dock = pcall(TitleBar._aire_build_dock, self)
    if not ok or not dock then return nil, 0 end
    return dock, TitleBar._aire_dock_reserve()
end

function Page:refresh(first)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local TitleBar = require("ui/widget/titlebar")
    self.title_bar = TitleBar:new{
        fullscreen = true,
        width = sw,
        title = self.title,
        _aire_subtitle = self.subtitle,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }
    local dock, dock_h = self:_dock()
    local side = S(P.SIDE)
    local w = sw - 2 * side
    local dots_h = S(26)
    -- Sin subtítulo, la primera tarjeta quedaba pegada al título
    local top_gap = self.subtitle and 0 or S(12)
    local content_h = sh - self.title_bar:getHeight() - dock_h - dots_h - S(12) - top_gap
    self.content_w, self.content_h = w, content_h
    local ok, pages = pcall(self.build, self, w, content_h)
    if not ok then
        require("logger").warn("Aire/Pages:", self.title, pages)
        pages = { TextWidget:new{ text = tostring(pages), face = face(false, 12), max_width = w } }
    end
    self.pages = pages or {}
    if #self.pages == 0 then self.pages = { VerticalGroup:new{} } end
    self.page_no = math.max(1, math.min(self.page_no or 1, #self.pages))
    local DotPager = require("ui/widget/menu")._aire_dot_pager_cls
    local dots
    if DotPager and #self.pages > 1 then
        dots = DotPager:new{ height = dots_h, get_state = function() return self.page_no, #self.pages end }
    end
    -- El contenido ocupa siempre content_h (los puntos, abajo del todo)
    local cur_page = self.pages[self.page_no]
    local fill = math.max(0, content_h - cur_page:getSize().h)
    local body = VerticalGroup:new{
        align = "left",
        self.title_bar,
        VerticalSpan:new{ width = top_gap },
        FrameContainer:new{
            bordersize = 0, padding = 0, padding_left = side, padding_right = side,
            cur_page,
        },
        VerticalSpan:new{ width = fill },
        CenterContainer:new{ dimen = Geom:new{ w = sw, h = dots_h }, dots or VerticalSpan:new{ width = 0 } },
    }
    local root = OverlapGroup:new{ dimen = Geom:new{ w = sw, h = sh }, body }
    if dock then
        table.insert(root, BottomContainer:new{ dimen = Geom:new{ w = sw, h = sh }, dock })
    end
    self[1] = FrameContainer:new{
        width = sw, height = sh, padding = 0, margin = 0, bordersize = 0,
        background = P.WHITE,
        root,
    }
    if not first then UIManager:setDirty(self, "ui") end
end

-- Si algo falla al pintar, se apunta en el registro (con su traza) en vez
-- de cerrar KOReader
function Page:paintTo(bb, x, y)
    local ok, err = xpcall(InputContainer.paintTo, debug.traceback, self, bb, x, y)
    if not ok then require("logger").warn("Aire/Pages: al pintar", self.title, err) end
end

function Page:goPage(n)
    if n < 1 or n > #self.pages or n == self.page_no then return end
    self.page_no = n
    self:refresh()
end

function Page:onAireSwipe(_arg, ges)
    local dir = ges and ges.direction
    if dir == "west" then self:goPage(self.page_no + 1) return true end
    if dir == "east" then self:goPage(self.page_no - 1) return true end
    if dir == "south" then self:onClose() return true end
    return false
end

function Page:onClose()
    UIManager:close(self)
    if self.close_callback then self.close_callback() end
    return true
end

function Page:onCloseWidget()
    UIManager:setDirty(nil, "flashui")
end

function Page:show()
    UIManager:show(self)
    return self
end

-- Al mostrarse (también cuando lo muestra KOReader, p. ej. las estadísticas
-- del libro): refresco de pantalla completo. Sin él la tinta no siempre se
-- actualizaba al abrir desde el menú (quedaban restos de lo anterior)
function Page:onShow()
    UIManager:setDirty(self, "flashui", self.dimen)
end

return P
