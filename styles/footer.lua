--[[
    aire.koplugin/styles/footer.lua
    Barra de estado del lector (ReaderFooter). Se carga una vez desde main.lua.

      - Batería con "Elementos compactos" (Barra de estado → Estilo de los
        elementos): KOReader solo pone el icono; Aire añade el porcentaje
        detrás, como en el estilo con iconos.

    ReaderFooter.textGeneratorMap es la misma tabla que usa KOReader para
    montar la barra; se cambia al cargar, antes de abrir ningún libro.
--]]

local Device = require("device")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local logger = require("logger")

local map = ReaderFooter.textGeneratorMap
if type(map) ~= "table" or type(map.battery) ~= "function" or map._aire_patched then
    if type(map) ~= "table" then logger.warn("Aire/Footer: no se encontró textGeneratorMap") end
    return
end
map._aire_patched = true

local orig_battery = map.battery
map.battery = function(footer, ...)
    local text, merge = orig_battery(footer, ...)
    local settings = footer and footer.settings
    if settings and settings.item_prefix == "compact_items" and type(text) == "string" and text ~= ""
            and not text:find("%d") and Device:hasBattery() then
        local ok, lvl = pcall(function()
            local powerd = Device:getPowerDevice()
            local l = powerd:getCapacity()
            if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
                l = l + powerd:getAuxCapacity()
            end
            return l
        end)
        if ok and lvl then text = text .. lvl .. "%" end
    end
    return text, merge
end

logger.dbg("Aire/Footer: aplicado desde el plugin")
