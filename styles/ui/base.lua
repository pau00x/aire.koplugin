--[[
    aire.koplugin/styles/ui/base.lua
    Funciones compartidas por las piezas de styles/ui/. Se carga la primera:
    TouchMenuItem se captura aquí ANTES de que nadie envuelva TouchMenu.
--]]

local Device = require("device")
local Geom = require("ui/geometry")
local TouchMenu = require("ui/widget/touchmenu")
local logger = require("logger")
local userpatch = require("userpatch")
local Screen = Device.screen

-- (Las opciones de Interfaz del menú se quitaron: todo activado siempre)
local function uiOpt(_key) return true end

local function isA(w, class) return type(w) == "table" and getmetatable(w) == class end

-- getUpValue seguro: userpatch.getUpValue revienta (y KOReader no arranca) si la
-- función no existe, p. ej. cuando cambia el nombre de un método en una versión.
-- Recuadro real de un widget ya pintado. FrameContainer y MovableContainer
-- solo guardan ancho y alto la PRIMERA vez que se pintan (después solo
-- actualizan x/y), así que si el contenido cambia de tamaño su dimen se queda
-- con el tamaño viejo y "tocar fuera para cerrar" falla en la zona sobrante.
local function liveRect(w)
    local d = w and w.dimen
    if not (d and d.x and d.y) then return d end
    local ok, size = pcall(w.getSize, w)
    if not ok or not size then return d end
    return Geom:new{ x = d.x, y = d.y, w = size.w, h = size.h }
end

-- Ancho del dock de la Pantalla de inicio (pantalla - 2 × 16): el máximo de
-- las ventanas que siguen flotando
local function dockWidth()
    return Screen:getWidth() - 2 * Screen:scaleBySize(16)
end

local getUpValue = package.loaded.aire_ui.getUpValue

-- Capturar los upvalues ANTES de envolver ninguna función: una vez envuelta,
-- la función nueva ya no contiene los locales del módulo original.
local TouchMenuItem = getUpValue(TouchMenu.updateItems, "TouchMenuItem")

-- Los parches de plugins se ejecutan dentro de FileManager:init; si fallan sin
-- protección, KOReader no llega a arrancar. Aquí solo dejan un aviso en el log.
local function safePluginPatch(plugin_name, fn)
    userpatch.registerPatchPluginFunc(plugin_name, function(plugin)
        local ok, err = pcall(fn, plugin)
        if not ok then logger.warn("Aire/UI: fallo parcheando el plugin", plugin_name, err) end
    end)
end

-- Medidas compartidas por varias piezas (hojas inferiores y menú superior)
-- stylua: ignore start
local SHEET_MARGIN              = 6      -- margen con los bordes de la pantalla
local SHEET_RADIUS              = 14     -- radio de las esquinas (igual que la hoja del plugin)
local MENU_SIDE_INSET           = 14     -- margen lateral del menú superior (= relleno de las hojas)
local CONFIRM_BOX_AS_SHEET      = uiOpt("confirm_sheet")   -- confirmaciones (tienen opciones) como hoja inferior, texto a la izquierda
-- stylua: ignore end

return {
    uiOpt = uiOpt,
    isA = isA,
    liveRect = liveRect,
    dockWidth = dockWidth,
    getUpValue = getUpValue,
    safePluginPatch = safePluginPatch,
    TouchMenuItem = TouchMenuItem,
    SHEET_MARGIN = SHEET_MARGIN,
    SHEET_RADIUS = SHEET_RADIUS,
    MENU_SIDE_INSET = MENU_SIDE_INSET,
    CONFIRM_BOX_AS_SHEET = CONFIRM_BOX_AS_SHEET,
}
