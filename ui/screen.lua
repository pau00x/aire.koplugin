--[[
    aire.koplugin/ui/screen.lua
    Estructura común de las pantallas completas de Aire (vistas propias,
    ui/pages.lua y pantallas de KOReader restiladas):

      METRICS    márgenes y espacios base (en píxeles sin escalar; S() al usarlos)
      SHEET      medidas de las hojas inferiores y submenús (sheetWidth, sheetInnerWidth)
      LIST       medidas de las listas de contenido en tarjetas (ui/list.lua)
      Pager      paginación por puntos (● activo alargado) o "3 / 12"
      statusBar  barra de estado (hora, indicadores, energía); los datos los
                 da views/topbar.lua con setStatusSource
      header     fila del título: "‹ Título" (subpágina) o "Título" (sección),
                 con icono de menú opcional a la derecha
      subtitle   fila del subtítulo (texto gris, alto mínimo común)

    Se carga una vez desde main.lua en package.loaded.aire_screen, antes de
    ui/pages.lua y de styles/.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Screen = Device.screen
local AireUI = package.loaded.aire_ui

local M = {}

-- stylua: ignore start
M.METRICS = {
    SIDE               = 16, -- margen lateral de todo el contenido
    TOP_PAD            = 10, -- encima de la barra de estado
    TOP_GAP_BELOW      = 12, -- debajo de la cabecera (modo Explorador)
    HEADER_GAP         = 12, -- entre la barra de estado y el título
    DOCK_GAP_ABOVE     = 6,  -- entre el contenido (o los puntos) y el dock
    DOCK_MARGIN_BOTTOM = 12, -- debajo del dock
    DOTS_H             = 26, -- alto de la fila de puntos de página
    DOTS_GAP           = 6,  -- entre el contenido y los puntos de página
    DOTS_BOTTOM        = 6,  -- debajo de los puntos: hasta el dock (es DOCK_GAP_ABOVE)
                             -- o, sin dock, hasta el borde inferior
    TITLE_PAD_V        = 3,  -- encima y debajo de la fila del título
    ICON               = 24, -- iconos de la cabecera (‹, menú)
    SUB_GAP            = 2,  -- entre el título y el subtítulo
    SUB_MIN_H          = 28, -- alto mínimo de la fila del subtítulo
    CONTENT_GAP        = 12, -- entre la cabecera (o el subtítulo) y el contenido
}

-- Hojas inferiores y submenús (styles/ui/sheets.lua, hojas propias de Aire,
-- menú superior y del lector): única fuente de sus medidas
M.SHEET = {
    MARGIN          = 6,  -- hueco con los bordes de la pantalla
    RADIUS          = 14, -- esquinas de la hoja
    PAD             = 14, -- relleno interior
    BTN_H           = 44, -- alto de los botones
    BTN_RADIUS      = 10, -- esquinas de los botones
    BTN_GAP         = 8,  -- hueco entre botones
    BTN_FONT        = 16, -- letra de los botones (si no piden otra)
    MENU_SIDE_INSET = 14, -- margen lateral del menú superior (= PAD)
    -- Contenido (ui/sheet.lua: title, section, row, buttons, choices)
    ROW_H           = 44, -- alto de las filas (= BTN_H: misma zona táctil)
    TITLE_FONT      = 15, -- título de la hoja (negrita)
    SUB_FONT        = 13, -- subtítulo de la hoja (gris; como el de las pantallas completas)
    SUB_GAP         = 2,  -- entre el título y el subtítulo (y entre líneas del subtítulo)
    ROW_FONT        = 15, -- texto de las filas
    BODY_FONT       = 15, -- texto del contenido (avisos, sinopsis, diccionario, lo que se escribe)
    LABEL_FONT      = 11, -- etiqueta de sección (negrita, mayúsculas, gris)
    ICON            = 22, -- icono, casilla o círculo de una fila
    TITLE_GAP       = 12, -- debajo del título
    LABEL_GAP       = 8,  -- debajo de una etiqueta de sección
    GROUP_GAP       = 12, -- entre grupos (y a cada lado de un separador)
}

-- Listas de contenido en tarjetas (ui/list.lua)
M.LIST = {
    CARD_RADIUS = 10,  -- esquinas de las tarjetas
    CARD_GAP    = 8,   -- hueco entre tarjetas
    CARD_MIN_W  = 120, -- ancho mínimo de una tarjeta
    CARD_PAD    = 12,  -- relleno interior de la tarjeta
    TITLE       = 15,  -- título (negrita si abre otra lista o es el actual)
    SUB         = 13,  -- subtítulo (gris)
    VALUE       = 13,  -- valor a la derecha (página, recuento…)
    META        = 11,  -- etiqueta de arriba (negrita, mayúsculas, gris)
    META_GAP    = 4,   -- entre la etiqueta y el texto
    ICON        = 22,  -- icono o casilla a la izquierda / derecha
    ICON_GAP    = 10,  -- entre el icono y el texto
    ROW_H       = 40,  -- alto de las filas clave / valor (ui/list.lua: row)
}

local PAGER = {
    MAX_DOTS      = 9,  -- con más páginas se muestra "3 / 12"
    DOT_SIZE      = 7,  -- diámetro de los puntos / alto de la raya
    ACTIVE_PILL_W = 28, -- largo de la raya de la página actual
    DOT_GAP       = 9,  -- separación entre puntos
}
-- stylua: ignore end
M.PAGER = PAGER

--===========================================================================
-- Pager: página actual en raya negra; las demás, puntos con borde fino.
--   get_state = function() -> cur, total   (o los campos page / pages)
--   height    alto de la fila (por defecto METRICS.DOTS_H)
--   width     opcional: ancho fijo; los puntos se centran dentro
--   max_dots  opcional: a partir de cuántas páginas sale "3 / 12"
--===========================================================================
local Pager = WidgetContainer:extend{
    get_state = nil,
    page = 1,
    pages = 1,
    height = nil,
    width = nil,
    max_dots = nil,
}
M.Pager = Pager

function Pager:init()
    self.height = self.height or Screen:scaleBySize(M.METRICS.DOTS_H)
    self.max_dots = self.max_dots or PAGER.MAX_DOTS
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width or 0, h = self.height }
end

function Pager:_state()
    local cur, total = self.page, self.pages
    if self.get_state then cur, total = self.get_state() end
    total = tonumber(total) or 1
    cur = math.max(1, math.min(total, tonumber(cur) or 1))
    return cur, total
end

local function pageText(cur, total)
    return TextWidget:new{
        text = tostring(cur) .. " / " .. tostring(total),
        face = Font:getFace("cfont", 13),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        padding = 0,
    }
end

-- Ancho de lo que se dibuja (puntos o texto)
function Pager:_contentWidth(cur, total)
    if total <= 1 then return 0 end
    if total > self.max_dots then
        local tw = pageText(cur, total)
        local w = tw:getSize().w
        tw:free()
        return w
    end
    local d = Screen:scaleBySize(PAGER.DOT_SIZE)
    local pill_w = math.max(d, Screen:scaleBySize(PAGER.ACTIVE_PILL_W))
    local gap = Screen:scaleBySize(PAGER.DOT_GAP)
    return (total - 1) * d + pill_w + (total - 1) * gap
end

function Pager:getSize()
    local cur, total = self:_state()
    self.dimen.w = self.width or self:_contentWidth(cur, total)
    self.dimen.h = self.height
    return self.dimen
end

function Pager:paintTo(bb, x, y)
    local cur, total = self:_state()
    local content_w = self:_contentWidth(cur, total)
    self.dimen.x, self.dimen.y = x, y
    self.dimen.w = self.width or content_w
    self.dimen.h = self.height
    if total <= 1 then return end
    local h = self.height
    local x0 = x + math.floor((self.dimen.w - content_w) / 2)

    if total > self.max_dots then
        local tw = pageText(cur, total)
        local ts = tw:getSize()
        tw:paintTo(bb, x0, y + math.floor((h - ts.h) / 2))
        tw:free()
        return
    end

    local d = Screen:scaleBySize(PAGER.DOT_SIZE)
    local r = math.floor(d / 2)
    local t = Size.border.thin
    local pill_w = math.max(d, Screen:scaleBySize(PAGER.ACTIVE_PILL_W))
    local gap = Screen:scaleBySize(PAGER.DOT_GAP)
    local px = x0
    local iy = y + math.floor(h / 2) - r
    for i = 1, total do
        if i == cur then
            bb:paintRoundedRect(px, iy, pill_w, d, Blitbuffer.COLOR_BLACK, r)
            px = px + pill_w + gap
        else
            bb:paintRoundedRect(px, iy, d, d, Blitbuffer.COLOR_BLACK, r)
            bb:paintRoundedRect(px + t, iy + t, d - 2 * t, d - 2 * t, Blitbuffer.COLOR_WHITE, math.max(0, r - t))
            px = px + d + gap
        end
    end
end

-- Ancho exterior de cualquier hoja (pantalla menos MARGIN a cada lado) y
-- ancho útil dentro de ella (sin relleno ni borde)
function M.sheetWidth()
    return Screen:getWidth() - 2 * Screen:scaleBySize(M.SHEET.MARGIN)
end
function M.sheetInnerWidth()
    return M.sheetWidth() - 2 * Screen:scaleBySize(M.SHEET.PAD) - 2 * Size.border.thin
end

-- Hueco bajo las hojas: su margen. En el lector también pisan la barra de
-- estado de abajo (elegido así), así que no se deja su alto
function M.sheetBottom()
    return Screen:scaleBySize(M.SHEET.MARGIN)
end

-- Pie con los puntos: con dock, los puntos tal cual (el hueco hasta el dock
-- ya va en dockReserve); sin dock, con el mismo hueco hasta el borde inferior
function M.pagerFooter(pager, has_dock)
    if has_dock then return pager end
    return VerticalGroup:new{
        align = "center",
        pager,
        VerticalSpan:new{ width = AireUI.S(M.METRICS.DOTS_BOTTOM) },
    }
end

--===========================================================================
-- Barra de estado: hora a la izquierda; indicadores (iconos propios) y botón
-- de energía (con punto de actualización opcional) a la derecha. Tocar la
-- zona de la izquierda o deslizar hacia abajo abre el menú superior.
--   setStatusSource{ clock = fn, data = fn, power = fn, menu = fn }
--   statusBar(w, { hide_clock = bool }) -> widget, parts
--     parts.clock / parts.status / parts.group (widgets vivos)
--     parts.update()  vuelve a leer la hora, los indicadores y el aviso
--===========================================================================
local status_src = {}
function M.setStatusSource(src) status_src = src or {} end

local function emptyGeom() return Geom:new{ x = 0, y = 0, w = 0, h = 0 } end
local function call(fn) if fn then return fn() end end

-- Píldora horizontal de batería dibujada en Blitbuffer: contorno fino redondeado
-- (acorde al resto de iconos de Aire), porcentaje centrado dentro, relleno
-- proporcional invertido (estilo iOS) y rayo a la derecha al cargar.
local BatteryGlyph = WidgetContainer:extend{
    level = 0,
    charging = false,
    height = nil,
}

function BatteryGlyph:init()
    local S, face = AireUI.S, AireUI.face
    local bh = self.height or S(14)
    local thin = math.max(1, Size.border.thin)
    self._body_h = bh
    self._body_w = math.max(S(24), math.floor(bh * 1.85 + 0.5))
    self._nub_gap = thin
    self._nub_w = math.max(1, math.floor(S(1.2) + 0.5))
    self._nub_h = math.max(3, math.floor(bh * 0.4 + 0.5))
    local pct = math.max(0, math.min(100, math.floor((tonumber(self.level) or 0) + 0.5)))
    self._pct = pct
    local unit = math.max(1, S(1))
    local font_pt = math.max(10, math.floor((bh / unit) * 0.90 + 0.5))
    if pct >= 100 then font_pt = math.max(9, font_pt - 2) end
    self._label = TextWidget:new{
        text = tostring(pct),
        face = face(false, font_pt),
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    local total_w = self._body_w + self._nub_gap + self._nub_w
    if self.charging then
        local bolt_h = math.max(S(8), math.floor(bh * 0.8 + 0.5))
        local bolt_w = math.max(S(6), math.floor(bolt_h * 0.75 + 0.5))
        self._bolt_gap = math.max(1, S(2))
        self._bolt = IconWidget:new{ icon = "aire.status.bolt", width = bolt_w, height = bolt_h, alpha = true }
        total_w = total_w + self._bolt_gap + bolt_w
    end
    self.dimen = Geom:new{ x = 0, y = 0, w = total_w, h = bh }
end

function BatteryGlyph:getSize()
    return self.dimen
end

function BatteryGlyph:paintTo(bb, x, y)
    local S = AireUI.S
    self.dimen.x, self.dimen.y = x, y
    local bw, bh = self._body_w, self._body_h
    local r = math.max(2, math.floor(bh * 0.25 + 0.5))
    -- Mismo grosor fino que las tarjetas, el botón de energía y los iconos de Aire
    local t = math.max(1, Size.border.thin)
    local pad = t + math.max(2, math.floor(S(1.2) + 0.5))
    local max_fw = math.max(0, bw - 2 * pad)
    local fh = math.max(2, bh - 2 * pad)
    local inner_r = math.max(1, math.min(math.floor(fh / 2), r - pad + 1))

    -- Cuerpo fino redondeado + interior blanco + relleno proporcional en gris claro
    bb:paintRoundedRect(x, y, bw, bh, Blitbuffer.COLOR_BLACK, r)
    bb:paintRoundedRect(x + t, y + t, bw - 2 * t, bh - 2 * t, Blitbuffer.COLOR_WHITE, math.max(0, r - t))
    if self._pct > 0 and max_fw > 0 then
        local fw = math.max(math.min(max_fw, inner_r * 2 + 1), math.floor(max_fw * self._pct / 100 + 0.5))
        bb:paintRoundedRect(x + pad, y + pad, fw, fh, Blitbuffer.COLOR_GRAY_B, math.min(inner_r, math.floor(fw / 2)))
    end
    -- Número siempre en negro puro, centrado ópticamente por altura de cifras
    if self._label then
        local ls = self._label:getSize()
        local bl = self._label.getBaseline and self._label:getBaseline()
        local ty = bl and (y + math.floor(bh / 2 - bl * 0.665 + 0.5)) or (y + math.floor((bh - ls.h) / 2))
        self._label:paintTo(bb, x + math.floor((bw - ls.w) / 2), ty)
    end
    -- Borne derecho
    local ny = y + math.floor((bh - self._nub_h) / 2)
    bb:paintRoundedRect(x + bw + self._nub_gap, ny, self._nub_w, self._nub_h,
        Blitbuffer.COLOR_BLACK, math.max(1, math.floor(self._nub_w / 2)))
    -- Rayo junto al borne mientras carga (sin tapar el número)
    if self._bolt then
        local bs = self._bolt:getSize()
        local bx = x + bw + self._nub_gap + self._nub_w + (self._bolt_gap or 0)
        self._bolt:paintTo(bb, bx, y + math.floor((bh - bs.h) / 2))
    end
end

function BatteryGlyph:free()
    if self._label then
        self._label:free()
        self._label = nil
    end
    if self._bolt then
        self._bolt:free()
        self._bolt = nil
    end
end
M.BatteryGlyph = BatteryGlyph

-- Intensidad de señal Wi-Fi (0..100) sin bloquear ni lanzar escaneos:
-- /proc/net/wireless → Kindle LIPC → wpa_supplicant / respaldo 100.
local function wifiSignalQuality()
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then return 0 end
    local f = io.open("/proc/net/wireless", "r")
    if f then
        local content = f:read("*a")
        f:close()
        if content then
            for line in content:gmatch("[^\n]+") do
                local link, level = line:match("^%s*[%w%-]+:%s+%x+%s+(%-?%d+)%.?%s+(%-?%d+)%.?")
                if link and level then
                    local lvl = tonumber(level)
                    local lnk = tonumber(link)
                    if lvl and lvl < 0 then
                        return math.max(1, math.min(100, math.floor((lvl + 90) * 2 + 0.5)))
                    elseif lnk and lnk > 0 then
                        return math.max(1, math.min(100, math.floor(lnk * 100 / 70 + 0.5)))
                    end
                end
            end
        end
    end
    local ok_l, lipc = pcall(require, "liblipclua")
    if ok_l and lipc then
        local ok_h, h = pcall(lipc.init, "com.github.koreader.aire")
        if ok_h and h then
            local ok_s, s = pcall(h.get_string_property, h, "com.lab126.wifid", "signalStrength")
            pcall(h.close, h)
            if ok_s and type(s) == "string" then
                local cur, tot = s:match("(%d+)%s*/%s*(%d+)")
                cur, tot = tonumber(cur), tonumber(tot)
                if cur and tot and tot > 0 then
                    return math.max(0, math.min(100, math.floor(cur * 100 / tot + 0.5)))
                end
            end
        end
    end
    if NetworkMgr.getCurrentNetwork then
        local ok_n, nw = pcall(NetworkMgr.getCurrentNetwork, NetworkMgr)
        if ok_n and type(nw) == "table" and tonumber(nw.signal_quality) then
            return math.max(0, math.min(100, tonumber(nw.signal_quality)))
        end
    end
    return 100
end

function M.wifiStatusIcon()
    local q = wifiSignalQuality()
    if q <= 0 then
        return "aire.status.wifi.0"
    elseif q <= 35 then
        return "aire.status.wifi.33"
    elseif q <= 70 then
        return "aire.status.wifi.66"
    end
    return "aire.status.wifi.100"
end

-- Envoltorio del botón de energía que pinta un punto negro discreto (con halo
-- blanco) en la esquina superior derecha cuando hay actualización disponible.
local PowerBadge = WidgetContainer:extend{
    show_dot = false,
}

function PowerBadge:getSize()
    return self[1] and self[1]:getSize() or emptyGeom()
end

function PowerBadge:paintTo(bb, x, y)
    local child = self[1]
    if not child then return end
    child:paintTo(bb, x, y)
    local sz = child:getSize()
    self.dimen = Geom:new{ x = x, y = y, w = sz.w, h = sz.h }
    if self.show_dot then
        local S = AireUI.S
        local d = math.max(6, S(7))
        local halo = math.max(2, S(2))
        local od = d + 2 * halo
        local cx = x + sz.w - math.floor(d / 2) + S(1)
        local cy = y + math.floor(d / 2) - S(1)
        bb:paintRoundedRect(cx - math.floor(od / 2), cy - math.floor(od / 2), od, od,
            Blitbuffer.COLOR_WHITE, math.floor(od / 2))
        bb:paintRoundedRect(cx - math.floor(d / 2), cy - math.floor(d / 2), d, d,
            Blitbuffer.COLOR_BLACK, math.floor(d / 2))
    end
end

-- Grupo de indicadores de estado (iconos vectoriales + texto limpio sin puntos).
-- Solo reconstruye los hijos cuando cambia la firma de los datos.
local StatusCluster = WidgetContainer:extend{}

local function statusSignature(items)
    if type(items) ~= "table" or #items == 0 then return "" end
    local parts = {}
    for _i, it in ipairs(items) do
        if it.kind == "battery" then
            table.insert(parts, "b:" .. tostring(it.level) .. ":" .. (it.charging and "1" or "0") .. ":" .. tostring(it.text or ""))
        else
            table.insert(parts, tostring(it.kind) .. ":" .. tostring(it.icon or "") .. ":" .. tostring(it.text or ""))
        end
    end
    return table.concat(parts, "|")
end

function StatusCluster:init()
    self._sig = nil
    self:setData(self.initial_data)
    self.initial_data = nil
end

function StatusCluster:setData(data)
    local items = type(data) == "table" and data.items or nil
    local sig = statusSignature(items)
    if sig == self._sig then return false end
    self._sig = sig
    if self[1] then self[1]:free() end
    local S, face = AireUI.S, AireUI.face
    local row = HorizontalGroup:new{ align = "center" }
    local icon_sz = S(16)
    local item_gap = S(11)
    if type(items) == "table" then
        for i, it in ipairs(items) do
            if i > 1 then
                table.insert(row, HorizontalSpan:new{ width = item_gap })
            end
            if it.kind == "icon" then
                table.insert(row, IconWidget:new{ icon = it.icon, width = icon_sz, height = icon_sz, alpha = true })
            elseif it.kind == "icon_text" then
                table.insert(row, HorizontalGroup:new{
                    align = "center",
                    IconWidget:new{ icon = it.icon, width = icon_sz, height = icon_sz, alpha = true },
                    HorizontalSpan:new{ width = S(4) },
                    TextWidget:new{ text = it.text or "", face = face(false, 13), fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 },
                })
            elseif it.kind == "battery" then
                table.insert(row, BatteryGlyph:new{ level = it.level, charging = it.charging })
            end
        end
    end
    self[1] = row
    return true
end

function StatusCluster:getSize()
    return self[1] and self[1]:getSize() or emptyGeom()
end

function M.statusBar(w, opts)
    opts = opts or {}
    local S, face = AireUI.S, AireUI.face
    local clk = TextWidget:new{
        text = opts.hide_clock and "" or (call(status_src.clock) or ""),
        face = face(true, 16), fgcolor = Blitbuffer.COLOR_BLACK, padding = 0,
    }
    local clk_box = FrameContainer:new{
        bordersize = 0, padding = 0, padding_top = S(6), padding_bottom = S(6),
        background = Blitbuffer.COLOR_WHITE,
        clk,
    }
    local initial = call(status_src.data)
    local st = StatusCluster:new{ initial_data = initial }
    local power_size = S(38)
    local inner = power_size - 2 * Size.border.thin
    local power_btn = AireUI.tappable(FrameContainer:new{
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        radius = S(8),
        padding = 0,
        width = power_size,
        height = power_size,
        CenterContainer:new{
            dimen = Geom:new{ w = inner, h = inner },
            IconWidget:new{ icon = "aire.power", width = S(22), height = S(22), alpha = true },
        },
    }, function() call(status_src.power) end, nil, S(8))
    local power = PowerBadge:new{
        show_dot = type(initial) == "table" and initial.update_dot == true,
        power_btn,
    }
    local group = HorizontalGroup:new{ align = "center", st, HorizontalSpan:new{ width = S(12) }, power }
    local h = math.max(power_size, clk_box:getSize().h)
    local bar = InputContainer:new{
        OverlapGroup:new{
            dimen = Geom:new{ w = w, h = h },
            LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, clk_box },
            RightContainer:new{ dimen = Geom:new{ w = w, h = h }, group },
        },
    }
    bar.ges_events = {
        AireTopMenuTap = { GestureRange:new{
            ges = "tap",
            range = function()
                local d = bar.dimen
                if not d then return emptyGeom() end
                local pd = power.dimen
                local max_w = pd and math.max(0, pd.x - S(8) - d.x) or d.w
                return Geom:new{ x = 0, y = 0, w = d.x + max_w, h = d.y + d.h }
            end,
        } },
        AireSwipeMenu = { GestureRange:new{
            ges = "swipe",
            range = function()
                local d = bar.dimen
                if not d then return emptyGeom() end
                return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = d.y + d.h }
            end,
        } },
    }
    bar.onAireTopMenuTap = function() call(status_src.menu) return true end
    bar.onAireSwipeMenu = function(_self, ges)
        if ges and ges.direction == "south" then call(status_src.menu) return true end
        return false
    end
    local parts = { clock = clk, status = st, group = group, clock_hidden = opts.hide_clock }
    function parts.update()
        if not parts.clock_hidden then clk:setText(call(status_src.clock) or "") end
        local data = call(status_src.data)
        st:setData(data)
        power.show_dot = type(data) == "table" and data.update_dot == true
        group:resetLayout()
    end
    return bar, parts
end

--===========================================================================
-- Cabecera: fila del título, de ancho w (sin márgenes laterales). Dos
-- variantes:
--   subpágina  on_back: "‹ Título" (toda la fila vuelve atrás) y, si la
--              pantalla tiene acciones, menu_icon (≡) a la derecha
--   sección    sin on_back: "Título" y, si hay, menu_text a la derecha
--              (botón con texto y ▾, p. ej. el filtro y el orden actuales)
-- opts:
--   title, on_back
--   menu_icon | menu_text, con on_menu / on_menu_hold
--   tap_left     px que la zona de volver se extiende a la izquierda (margen)
--   tap_v        px que se extiende arriba y abajo (por defecto S(8))
--   -> widget, parts  (parts.title, parts.menu_icon, parts.setTitle(text),
--                      parts.setMenuIcon(icon))
--===========================================================================
-- Mapeo centralizado en core/icons.lua (M.OVERRIDES)
function M.menuIcon(icon)
    local Icons = package.loaded.aire_icons
    return (Icons and Icons.resolve(icon)) or icon
end

-- Zona pulsable con margen extra alrededor (iconos y botones de la derecha)
local function rightTappable(widget, on_tap, on_hold, eh, ev)
    local ic = InputContainer:new{ widget }
    local range = function()
        local d = ic.dimen
        if not d then return emptyGeom() end
        return Geom:new{ x = d.x - eh, y = d.y - ev, w = d.w + 2 * eh, h = d.h + 2 * ev }
    end
    ic.ges_events = { AireRightTap = { GestureRange:new{ ges = "tap", range = range } } }
    ic.onAireRightTap = function()
        if on_tap then on_tap() end
        return true
    end
    if on_hold then
        ic.ges_events.AireRightHold = { GestureRange:new{ ges = "hold", range = range } }
        ic.onAireRightHold = function()
            on_hold()
            return true
        end
    end
    return ic
end

function M.header(w, opts)
    opts = opts or {}
    local S, face = AireUI.S, AireUI.face
    local MT = M.METRICS
    local icon_sz = S(MT.ICON)
    local parts = {}

    -- Derecha: icono (subpágina) o botón con texto (sección)
    local right, menu_reserve = nil, 0
    if opts.menu_icon then
        local icon_w = IconWidget:new{ icon = M.menuIcon(opts.menu_icon), width = icon_sz, height = icon_sz, alpha = true }
        parts.menu_icon = icon_w
        right = rightTappable(icon_w, opts.on_menu, opts.on_menu_hold, S(8), S(8))
        menu_reserve = icon_sz + S(10)
    elseif opts.menu_text then
        local btn = FrameContainer:new{
            bordersize = 0, padding = 0, padding_left = S(8), padding_top = S(4), padding_bottom = S(4),
            HorizontalGroup:new{
                align = "center",
                TextWidget:new{ text = opts.menu_text, face = face(false, 13), fgcolor = Blitbuffer.COLOR_BLACK,
                    max_width = math.floor(w * 0.5), padding = 0 },
                HorizontalSpan:new{ width = S(2) },
                IconWidget:new{ icon = "aire.chevron.down", width = S(16), height = S(16), alpha = true },
            },
        }
        right = rightTappable(btn, opts.on_menu, opts.on_menu_hold, S(8), S(10))
        menu_reserve = btn:getSize().w + S(10)
    end

    local lead = opts.on_back and (icon_sz + S(6)) or 0
    local title_w = TextWidget:new{
        text = opts.title or "",
        face = face(true, 17),
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = math.max(S(80), w - lead - menu_reserve),
        padding = 0,
    }
    parts.title = title_w
    local row = HorizontalGroup:new{ align = "center" }
    if opts.on_back then
        table.insert(row, IconWidget:new{ icon = "chevron.left", width = icon_sz, height = icon_sz, alpha = true })
        table.insert(row, HorizontalSpan:new{ width = S(6) })
    end
    table.insert(row, title_w)
    local row_h = math.max(row:getSize().h, icon_sz)
    local og = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = row_h },
        LeftContainer:new{ dimen = Geom:new{ w = w, h = row_h }, row },
    }
    if right then
        table.insert(og, RightContainer:new{ dimen = Geom:new{ w = w, h = row_h }, right })
    end

    local pad_v = S(MT.TITLE_PAD_V)
    local frame = FrameContainer:new{
        bordersize = 0, padding = 0, padding_top = pad_v, padding_bottom = pad_v,
        width = w, -- toda la fila responde, no solo el texto
        og,
    }
    local widget = frame
    if opts.on_back then
        local tap_left = opts.tap_left or 0
        local tap_v = opts.tap_v or S(8)
        local ic = InputContainer:new{ frame }
        ic.ges_events = {
            AireBackTap = { GestureRange:new{
                ges = "tap",
                range = function()
                    local d = ic.dimen
                    if not d then return emptyGeom() end
                    return Geom:new{ x = d.x - tap_left, y = d.y - tap_v,
                        w = tap_left + w - menu_reserve, h = d.h + 2 * tap_v }
                end,
            } },
        }
        ic.onAireBackTap = function()
            opts.on_back()
            return true
        end
        widget = ic
    end

    function parts.setTitle(text) title_w:setText(text or "") end
    function parts.setMenuIcon(icon)
        if not parts.menu_icon then return end
        parts.menu_icon:free()
        parts.menu_icon.icon = M.menuIcon(icon)
        parts.menu_icon.file = nil
        parts.menu_icon:init()
    end
    return widget, parts
end

--===========================================================================
-- Subtítulo: texto gris de una línea en una fila de alto mínimo común.
--   subtitle(w, text, opts) -> widget, text_widget
--   opts.truncate_left  si no cabe, se corta por la izquierda (rutas)
--===========================================================================
function M.subtitle(w, text, opts)
    opts = opts or {}
    local S, face = AireUI.S, AireUI.face
    local sub_w = TextWidget:new{
        text = text or "",
        face = face(false, 13),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = math.max(S(80), w),
        truncate_left = opts.truncate_left,
        padding = 0,
    }
    return LeftContainer:new{
        dimen = Geom:new{ w = w, h = math.max(sub_w:getSize().h, S(M.METRICS.SUB_MIN_H)) },
        sub_w,
    }, sub_w
end

--===========================================================================
-- Dock en las pantallas completas
--   setDockSource{ active = fn, build = fn(owner) }   (views/dock.lua)
--   dockAvailable(owner)  ¿lleva dock? (no en el lector, no con la pantalla
--                         de inicio desactivada, no si owner._aire_no_dock)
--   fullscreenDock(owner) -> dock, reserve   (nil, 0 si no hay)
--   dockReserve(dock)     alto que el contenido deja libre abajo para el dock
--===========================================================================
local dock_src = {}
function M.setDockSource(src) dock_src = src or {} end

function M.dockAvailable(owner)
    if owner and owner._aire_no_dock then return false end
    local RUI = package.loaded["apps/reader/readerui"]
    if RUI and RUI.instance then return false end
    if not dock_src.build then return false end
    if dock_src.active and not dock_src.active() then return false end
    return true
end

function M.dockReserve(dock)
    local S = AireUI.S
    local MT = M.METRICS
    return (dock and dock:getSize().h or 0) + S(MT.DOCK_GAP_ABOVE) + S(MT.DOCK_MARGIN_BOTTOM)
end

function M.fullscreenDock(owner)
    if not M.dockAvailable(owner) then return nil, 0 end
    local ok, dock = pcall(dock_src.build, owner)
    if not ok then
        require("logger").warn("Aire/Screen: dock:", dock)
        return nil, 0
    end
    if not dock then return nil, 0 end
    return dock, M.dockReserve(dock)
end

--===========================================================================
-- withTitleBar(opts, fn, ...): ejecuta fn(...) ajustando las barras de título
-- (TitleBar) que KOReader cree dentro, y deja TitleBar.new como estaba pase lo
-- que pase. Es la forma de dar la cabecera de Aire a una pantalla de KOReader
-- sin tocar su código. opts:
--   once             solo la primera barra que se cree
--   only_fullscreen  solo las que ya vienen con fullscreen = true
--   fullscreen       la pone a pantalla completa
--   title            título (siempre) / default_title (solo si viene vacío)
--   subtitle         subtítulo de Aire (si la pantalla no trae uno propio)
--   back, back_hold  "‹" a la izquierda (sustituye a la X de cerrar)
--   menu_icon, on_menu, on_menu_hold   icono de menú a la derecha
--   close_fallback   cierre si la pantalla no trae ni cerrar ni icono izquierdo
--   set              campos que se ponen tal cual ({ subtitle = "" }…)
--   clear            lista de campos que se quitan ({ "info_text" }…)
--===========================================================================
function M.withTitleBar(opts, fn, ...)
    local TitleBar = require("ui/widget/titlebar")
    local used = false
    return AireUI.withTemporaryNew(TitleBar, function(base_new, cls, o)
        if type(o) ~= "table" or (opts.once and used) or (opts.only_fullscreen and not o.fullscreen) then
            return base_new(cls, o)
        end
        used = true
        if opts.fullscreen then o.fullscreen = true end
        if opts.title then o.title = opts.title end
        if opts.default_title and (not o.title or o.title == "") then o.title = opts.default_title end
        if opts.subtitle and opts.subtitle ~= "" and not o._aire_subtitle then o._aire_subtitle = opts.subtitle end
        if opts.back then
            o.left_icon = "chevron.left"
            o.left_icon_tap_callback = opts.back
            o.left_icon_hold_callback = opts.back_hold
            o.close_callback = nil
            o.close_hold_callback = nil
        end
        if opts.menu_icon then
            o.right_icon = opts.menu_icon
            o.right_icon_tap_callback = opts.on_menu
            o.right_icon_hold_callback = opts.on_menu_hold
        end
        if opts.close_fallback and not o.close_callback and not o.left_icon then
            o.close_callback = opts.close_fallback
        end
        for k, v in pairs(opts.set or {}) do o[k] = v end
        for _i, k in ipairs(opts.clear or {}) do o[k] = nil end
        return base_new(cls, o)
    end, fn, ...)
end

--===========================================================================
-- root(body, dock): raíz blanca a pantalla completa. body arriba a la
-- izquierda; el dock (si hay) centrado abajo, con su margen inferior.
--===========================================================================
function M.root(body, dock)
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local og = OverlapGroup:new{ dimen = Geom:new{ w = sw, h = sh }, body }
    if dock then
        table.insert(og, BottomContainer:new{
            dimen = Geom:new{ w = sw, h = sh - AireUI.S(M.METRICS.DOCK_MARGIN_BOTTOM) },
            dock,
        })
    end
    return FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = sw, height = sh,
        og,
    }
end

return M
