--[[
    aire.koplugin/styles/reader/highlight.lua
    Subrayados en el lector (ReaderHighlight). Se carga una vez desde main.lua.

      - Mantener pulsada una palabra que ya está subrayada abre lo de siempre
        (la ventana del diccionario), pero su botón "Subrayar" pasa a ser
        "Eliminar subrayado" y quita ese subrayado. (En KOReader ese botón solo
        cambia a "Desubrayar" para no guardar la selección nueva; el subrayado
        que ya había no se podía quitar desde ahí.)
      - Lo mismo con "Añadir al desarrollador de vocabulario": si la palabra ya
        está guardada, el botón sale como "Quitar del desarrollador de
        vocabulario" (el plugin solo lo cambiaba después de añadirla).
--]]

local DictQuickLookup = require("ui/widget/dictquicklookup")
local ReaderHighlight = require("apps/reader/modules/readerhighlight")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local _ = require("gettext")
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Highlight"

if ReaderHighlight._aire_hold_existing then return end
ReaderHighlight._aire_hold_existing = true

local function insideBox(pos, box)
    return pos and box and box.x <= pos.x and box.y <= pos.y
        and box.x + box.w >= pos.x and box.y + box.h >= pos.y
end

-- Al mantener pulsado: recordar si se ha pulsado sobre un subrayado guardado
safeWrap(ReaderHighlight, "onHold", function(orig_onHold, self, arg, ges, ...)
    self._aire_existing_idx = nil
    pcall(function()
        if self.select_mode or not ges or not ges.pos then return end
        local boxes = self.view and self.view.highlight and self.view.highlight.visible_boxes
        if not boxes or #boxes == 0 then return end
        local pos = self.view:screenToPageTransform(ges.pos)
        for _i, box in ipairs(boxes) do
            if insideBox(pos, box.rect) then
                self._aire_existing_idx = box.index
                self._aire_existing_time = os.time()
                return
            end
        end
    end)
    return orig_onHold(self, arg, ges, ...)
end, TAG)

-- Ventana del diccionario abierta desde ahí: "Eliminar subrayado"
safeWrap(DictQuickLookup, "init", function(orig_dq_init, self, ...)
    local res = { orig_dq_init(self, ...) }
    pcall(function()
        local hl = self.highlight
        local idx = hl and hl._aire_existing_idx
        -- solo justo después de mantener pulsado (no al buscar una palabra a mano)
        if idx and os.time() - (hl._aire_existing_time or 0) > 5 then idx = nil end
        if not idx or not self.button_table or not self.button_table.getButtonById then return end
        local btn = self.button_table:getButtonById("highlight")
        if not btn then return end
        btn:setText(_("Delete highlight"), btn.width)
        btn.callback = function()
            hl._aire_existing_idx = nil
            local annotations = hl.ui and hl.ui.annotation and hl.ui.annotation.annotations
            if annotations and annotations[idx] then
                hl:deleteHighlight(idx)
            end
            self.save_highlight = false
            self:onClose()
            UIManager:setDirty(hl.dialog, "ui")
        end
    end)
    -- Vocabulario: la palabra ya está guardada -> "Quitar…" desde el principio
    pcall(function()
        local bt = self.button_table
        local btn = bt and bt.button_by_id and bt.button_by_id["vocabulary"]
        if not btn or self._vocabbuilder_action_state ~= nil then return end
        local dict = self.ui and self.ui.dictionary
        local spec = dict and dict._dict_buttons and dict._dict_buttons["vocabulary"]
        local DB = spec and type(spec.callback) == "function" and package.loaded.aire_ui.getUpValue(spec.callback, "DB")
        local word = self.lookupword or self.word
        if DB and DB.hasWord and word and DB:hasWord(word) then
            self._vocabbuilder_action_state = false
            btn:setText(_("Remove from vocabulary builder"), btn.width)
        end
    end)
    return unpack(res)
end, TAG)

logger.dbg("Aire/Highlight: aplicado desde el plugin")
