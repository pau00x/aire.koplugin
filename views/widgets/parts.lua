--[[
    aire.koplugin/views/widgets/parts.lua
    Piezas de los widgets de Inicio (views/widgets/init.lua): formatos (tiempo,
    tamaño), utilidades (eventos, archivos, luz), icono blanco, hoja de
    opciones (OptionSheet), hueco vacío (WidgetSlot) y celda (WidgetCell).
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local lfs = require("libs/libkoreader-lfs")
local Screen = Device.screen

local WHITE = Blitbuffer.COLOR_WHITE

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
local function fmtDuration(secs)
    secs = math.floor(tonumber(secs) or 0)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return ("%d h %02d min"):format(h, m) end
    return ("%d min"):format(m)
end

-- "6,5 GB" (bytes)
local function fmtSize(bytes)
    bytes = tonumber(bytes)
    if not bytes then return "—" end
    local units = { { 1e9, "GB" }, { 1e6, "MB" }, { 1e3, "kB" } }
    for _i, u in ipairs(units) do
        if bytes >= u[1] then
            local num = ("%.1f"):format(bytes / u[1]):gsub("%.", ",")
            return num .. " " .. u[2]
        end
    end
    return ("%d B"):format(bytes)
end

-- Mandar el mismo evento que mandan los gestos de KOReader
local function fire(name, arg)
    UIManager:sendEvent(Event:new(name, arg))
end

local function fileExists(p) return p and lfs.attributes(p, "mode") == "file" end

local function powerd() return Device:getPowerDevice() end

-- Icono en blanco (para fondos negros): se pinta sobre blanco y se invierte
local WhiteIcon = Widget:extend{ icon = nil, size = nil }
function WhiteIcon:init()
    self.iw = IconWidget:new{ icon = self.icon, width = self.size, height = self.size, alpha = true }
end
function WhiteIcon:getSize() return Geom:new{ w = self.size, h = self.size } end
function WhiteIcon:paintTo(bb, x, y)
    bb:paintRect(x, y, self.size, self.size, WHITE)
    self.iw:paintTo(bb, x, y)
    bb:invertRect(x, y, self.size, self.size)
end
function WhiteIcon:free() if self.iw then self.iw:free() end end

local function themedIcon(theme, icon, size)
    if theme.inverted then return WhiteIcon:new{ icon = icon, size = size } end
    return IconWidget:new{ icon = icon, width = size, height = size, alpha = true }
end

---------------------------------------------------------------------------
-- Hoja inferior genérica con opciones (casillas, opciones de radio y botones)
--   rows_fn() -> { { text, checked = bool|nil, radio = bool, enabled = bool,
--                    callback = fn(sheet), separator = bool }, ... }
--   buttons   -> { { text, callback = fn(sheet), primary = bool }, ... }
---------------------------------------------------------------------------
-- Hoja común (ui/sheet.lua): marco, cierre y refresco; aquí solo el contenido
local OptionSheet = package.loaded.aire_sheet.Sheet:extend{
    title = nil, rows_fn = nil, buttons = nil, S = nil, face = nil, tappable = nil, on_close = nil,
    columns = 1, -- 2: filas en dos columnas (p. ej. elegir widget)
    full_refresh = true, -- lo de debajo (Inicio y el dock) puede haber cambiado
}

function OptionSheet:init()
    package.loaded.aire_sheet.Sheet.init(self)
    self.close_callback = self.on_close
    -- Los botones van en el pie fijo: si hay muchas filas, se desplazan solo ellas
    self:setContent(function(inner_w) return self:buildContent(inner_w) end, self:buildButtons())
end

function OptionSheet:buildButtons()
    if not (self.buttons and #self.buttons > 0) then return nil end
    local list = {}
    for _i, b in ipairs(self.buttons) do
        local cb = b.callback
        table.insert(list, { text = b.text, primary = b.primary, callback = function() cb(self) end })
    end
    return package.loaded.aire_sheet.buttons(list, package.loaded.aire_screen.sheetInnerWidth())
end

function OptionSheet:buildContent(inner_w)
    -- Piezas comunes de las hojas (ui/sheet.lua): título, filas y botones
    local Sh = package.loaded.aire_sheet
    local S = self.S
    local content = VerticalGroup:new{ align = "left" }
    if self.title then table.insert(content, Sh.title(self.title, inner_w)) end
    local cols = self.columns or 1
    local col_gap = S(10)
    local cell_w = cols > 1 and math.floor((inner_w - (cols - 1) * col_gap) / cols) or inner_w
    local pending -- fila de varias columnas a medio llenar
    for _i, r in ipairs(self.rows_fn() or {}) do
        local cb = r.callback
        local row = Sh.row({
            text = r.text, icon = r.icon, checked = r.checked, radio = r.radio, enabled = r.enabled,
            callback = cb and function() cb(self) end,
        }, cell_w)
        if cols > 1 then
            if not pending then
                pending = HorizontalGroup:new{ align = "center", row }
                table.insert(content, pending)
            else
                table.insert(pending, HorizontalSpan:new{ width = col_gap })
                table.insert(pending, row)
                if #pending >= 2 * cols - 1 then pending = nil end
            end
        else
            table.insert(content, row)
            if r.separator then table.insert(content, VerticalSpan:new{ width = S(4) }) end
        end
    end
    return content
end

-- Volver a dibujar con las opciones actualizadas
function OptionSheet:rebuild()
    if self._closed then return end
    self._closed = true
    local new = OptionSheet:new{
        title = self.title, rows_fn = self.rows_fn, buttons = self.buttons, columns = self.columns,
        S = self.S, face = self.face, tappable = self.tappable, on_close = self.on_close,
    }
    UIManager:close(self)
    UIManager:show(new, "ui")
end


---------------------------------------------------------------------------
-- Hueco vacío (solo en edición): contorno gris claro y "+"
---------------------------------------------------------------------------
local WidgetSlot = InputContainer:extend{ width = nil, height = nil, on_tap = nil }

function WidgetSlot:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.isz = Screen:scaleBySize(22)
    self.icon = IconWidget:new{ icon = "aire.plus", width = self.isz, height = self.isz, alpha = true, dim = true }
    self.ges_events = {
        AireTap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end

function WidgetSlot:getSize() return Geom:new{ w = self.width, h = self.height } end

function WidgetSlot:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintBorder(x, y, self.width, self.height, Size.border.thin, Blitbuffer.COLOR_LIGHT_GRAY, Screen:scaleBySize(12))
    self.icon:paintTo(bb, x + math.floor((self.width - self.isz) / 2), y + math.floor((self.height - self.isz) / 2))
end

function WidgetSlot:onAireTap()
    if self.on_tap then self.on_tap() end
    return true
end

function WidgetSlot:free() if self.icon then self.icon:free() end end

---------------------------------------------------------------------------
-- Celda con un widget: toque y pulsación larga
---------------------------------------------------------------------------
local WidgetCell = InputContainer:extend{ width = nil, height = nil, on_tap = nil, on_hold = nil }

function WidgetCell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    local range = function() return self.dimen end
    self.ges_events = {
        AireTap = { GestureRange:new{ ges = "tap", range = range } },
        AireHold = { GestureRange:new{ ges = "hold", range = range } },
    }
end

function WidgetCell:getSize() return Geom:new{ w = self.width, h = self.height } end
function WidgetCell:onAireTap() if self.on_tap then self.on_tap() end return true end
function WidgetCell:onAireHold() if self.on_hold then self.on_hold() end return true end

-- Al cerrar el diálogo de luz, avisar para actualizar el widget de Luz
do
    local ok, FLW = pcall(require, "ui/widget/frontlightwidget")
    if ok and type(FLW) == "table" and not FLW._aire_close_hooked then
        FLW._aire_close_hooked = true
        local orig = FLW.onCloseWidget
        FLW.onCloseWidget = function(fw, ...)
            local res
            if orig then res = orig(fw, ...) end
            UIManager:scheduleIn(0.2, function() UIManager:broadcastEvent(Event:new("HomeWidgetsRefresh")) end)
            return res
        end
    end
end


return {
    fmtDuration = fmtDuration,
    fmtSize = fmtSize,
    fire = fire,
    fileExists = fileExists,
    powerd = powerd,
    themedIcon = themedIcon,
    OptionSheet = OptionSheet,
    WidgetSlot = WidgetSlot,
    WidgetCell = WidgetCell,
}
