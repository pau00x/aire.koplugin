--[[
    aire.koplugin/styles/ui/pickers.lua
    Controles dentro de las hojas: números (− valor + y barra), fecha y hora, listas de opciones y títulos sin línea.
    Lo carga styles/ui.lua en su orden (recibe la tabla de styles/ui/base.lua
    y lo que exporta styles/ui/sheets.lua).
--]]

local B = ...
local uiOpt = B.uiOpt
local isA = B.isA
local S_ = B.S_
local sheetInnerWidth = B.sheetInnerWidth
local sheetDepth = B.sheetDepth
local Tap = B.Tap
local SliderBar = B.SliderBar
local roundButton = B.roundButton
local Button = require("ui/widget/button")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local Blitbuffer = require("ffi/blitbuffer")
local WHITE = Blitbuffer.COLOR_WHITE

if not uiOpt("sheets") then return end

--===========================================================================
-- 13) CONTROLES DE LAS HOJAS: NÚMEROS, FECHA, LISTAS Y LUZ
-- - Números (tamaño de letra, márgenes…): valor grande entre dos botones
--   redondos − y +; si es un solo número, además una barra que se toca para
--   ir directo a un valor.
-- - Fecha y hora: columnas con flechas finas arriba y abajo.
-- - Listas de opciones (orientación…): sin líneas, letra más pequeña.
-- - Títulos de las hojas sin línea debajo.
-- - Iluminación: hoja propia con escalones tocables (diseño 1B).
--===========================================================================

-------------------------------------------------------------------------
-- Números (NumberPickerWidget): según quién lo cree
-------------------------------------------------------------------------
local picker_mode = nil -- "spin" | "double" | "date"
local function withPickerMode(mode, fn)
    return function(...)
        local prev = picker_mode
        picker_mode = mode
        local res = { pcall(fn, ...) }
        picker_mode = prev
        if not res[1] then error(res[2], 0) end
        table.remove(res, 1)
        return unpack(res)
    end
end
for _i, t in ipairs({
    { "ui/widget/spinwidget", "update", "spin" },
    { "ui/widget/doublespinwidget", "update", "double" },
    { "ui/widget/datetimewidget", "createLayout", "date" },
    { "ui/widget/datetimewidget", "update", "date" },
}) do
    local ok, cls = pcall(require, t[1])
    if ok and type(cls) == "table" and type(cls[t[2]]) == "function" then
        cls[t[2]] = withPickerMode(t[3], cls[t[2]])
    end
end

local NumberPickerWidget = require("ui/widget/numberpickerwidget")
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"
if not NumberPickerWidget._aire_sheet_patched then
    NumberPickerWidget._aire_sheet_patched = true

    local function restylePicker(self, mode)
        local first = self.layout[1] and self.layout[1][1]
        local last = self.layout[#self.layout] and self.layout[#self.layout][1]
        local old_val = self.text_value
        if not (first and last and old_val and first ~= last) then return end
        local up_cb, up_hold = first.callback, first.hold_callback
        local down_cb, down_hold = last.callback, last.hold_callback
        local value_cb = old_val.callback
        local text = old_val.text
        local group
        if mode == "date" then
            local vw = self.width
            local function chevron(angle, cb, hold)
                return Button:new{
                    icon = "aire.chevron.down", icon_rotation_angle = angle,
                    icon_width = S_(26), icon_height = S_(26),
                    bordersize = 0, padding = S_(6), margin = 0, width = vw,
                    callback = cb, hold_callback = hold, show_parent = self.show_parent,
                }
            end
            local up = chevron(180, up_cb, up_hold)
            local down = chevron(0, down_cb, down_hold)
            self.text_value = Button:new{
                text = text, bordersize = 0, padding = 0, width = vw,
                text_font_face = "tfont", text_font_size = 24,
                callback = value_cb, show_parent = self.show_parent,
            }
            self._aire_value_w = vw
            group = VerticalGroup:new{ align = "center", up, self.text_value, down }
            self.layout = { { up }, { self.text_value }, { down } }
        else
            local d = S_(46)
            local gap = S_(14)
            local vw = self.value_table and S_(150) or (mode == "spin" and S_(110) or S_(70))
            local minus = roundButton("−", d, down_cb, down_hold, self.show_parent)
            local plus = roundButton("+", d, up_cb, up_hold, self.show_parent)
            self.text_value = Button:new{
                text = text, bordersize = 0, padding = 0, width = vw,
                text_font_face = "tfont", text_font_size = mode == "spin" and 30 or 22,
                callback = value_cb, show_parent = self.show_parent,
            }
            self._aire_value_w = vw
            local row = HorizontalGroup:new{ align = "center",
                minus, HorizontalSpan:new{ width = gap }, self.text_value, HorizontalSpan:new{ width = gap }, plus }
            self.layout = { { minus, self.text_value, plus } }
            group = VerticalGroup:new{ align = "center", row }
            -- Un solo número: barra para ir directo a un valor
            local range = (self.value_max or 0) - (self.value_min or 0)
            if mode == "spin" and not self.value_table and range > 0 and range / (self.value_step or 1) <= 2000 then
                local bw = sheetInnerWidth() - 2 * S_(24)
                self._aire_np_bar = SliderBar:new{ width = bw, height = S_(26),
                    ratio = (self.value - self.value_min) / range }
                table.insert(group, VerticalSpan:new{ width = S_(16) })
                table.insert(group, Tap:new{
                    callback = function(ges)
                        local bd = self._aire_np_bar.dimen
                        if not (bd and ges and ges.pos) then return end
                        local r = (ges.pos.x - bd.x - bd.h / 2) / math.max(1, bd.w - bd.h)
                        r = math.max(0, math.min(1, r))
                        local step = self.value_step or 1
                        local v = self.value_min + math.floor(r * range / step + 0.5) * step
                        self.value = math.max(self.value_min, math.min(self.value_max, v))
                        self:update()
                    end,
                    self._aire_np_bar,
                })
            end
        end
        self.frame = FrameContainer:new{ bordersize = 0, padding = Size.padding.default, group }
        self.dimen = self.frame:getSize()
        self[1] = self.frame
    end

    safeWrap(NumberPickerWidget, "init", function(_orig, self, ...)
        _orig(self, ...)
        if not picker_mode then return end
        local ok, err = pcall(restylePicker, self, picker_mode)
        if not ok then logger.warn("Aire/UI: estilo de números:", err) end
    end, TAG)

    safeWrap(NumberPickerWidget, "update", function(orig_np_update, self, ...)
        if self._aire_np_bar then
            local range = (self.value_max or 0) - (self.value_min or 0)
            if range > 0 then self._aire_np_bar.ratio = (self.value - self.value_min) / range end
        end
        if not self._aire_value_w then return orig_np_update(self, ...) end
        local w = self.width
        self.width = self._aire_value_w -- el texto se reescribe con este ancho
        local ok, err = pcall(orig_np_update, self, ...)
        self.width = w
        if not ok then error(err, 0) end
    end, TAG)
end

-------------------------------------------------------------------------
-- Listas de opciones (RadioButtonTable) y títulos (TitleBar) en hojas
-------------------------------------------------------------------------
local ok_rbt, RadioButtonTable = pcall(require, "ui/widget/radiobuttontable")
if ok_rbt and not RadioButtonTable._aire_sheet_patched then
    RadioButtonTable._aire_sheet_patched = true
    safeWrap(RadioButtonTable, "init", function(orig_rbt_init, self, ...)
        if sheetDepth() <= 0 then return orig_rbt_init(self, ...) end
        if rawget(self, "face") == nil then self.face = Font:getFace("cfont", 15) end
        if self.parent and self.parent.radio_buttons then
            self.width = sheetInnerWidth()
        end
        orig_rbt_init(self, ...)
        pcall(function()
            for _k, w in ipairs(self.container) do
                if isA(w, LineWidget) then w.background = WHITE end
                if isA(w, HorizontalGroup) then
                    for _m, x in ipairs(w) do
                        if isA(x, LineWidget) then x.background = WHITE end
                    end
                end
            end
        end)
    end, TAG)
end

if not TitleBar._aire_sheet_line_patched then
    TitleBar._aire_sheet_line_patched = true
    safeWrap(TitleBar, "init", function(orig_tb_init, self, ...)
        if sheetDepth() > 0 and not self.fullscreen then
            self.with_bottom_line = false
            if rawget(self, "title_top_padding") == nil and not self.left_icon and not self.right_icon then
                self.title_top_padding = 0
            end
            if rawget(self, "bottom_v_padding") == nil then self.bottom_v_padding = S_(8) end
            -- título alineado con los botones (que van a Size.padding.default)
            if rawget(self, "title_h_padding") == nil then self.title_h_padding = Size.padding.default end
            -- Mismas letras que el resto de hojas: título en negrita 15,
            -- texto de debajo normal 15
            if rawget(self, "title_face") == nil then self.title_face = Font:getFace("tfont", 15) end
            if rawget(self, "info_text_face") == nil then self.info_text_face = Font:getFace("cfont", package.loaded.aire_screen.SHEET.SUB_FONT) end
            if rawget(self, "subtitle_face") == nil then self.subtitle_face = Font:getFace("cfont", 13) end
        end
        return orig_tb_init(self, ...)
    end, TAG)
end
