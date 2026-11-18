--[[
    aire.koplugin/styles/ui/lightsheet.lua
    Hoja propia de Iluminación (diseño 1B): escalones de brillo y calidez (el icono del sol enciende y apaga); sustituye Device.showLightDialog.
    Lo carga styles/ui.lua en su orden (recibe la tabla de styles/ui/base.lua
    y lo que exporta styles/ui/sheets.lua).
--]]

local B = ...
local uiOpt = B.uiOpt
local liveRect = B.liveRect
local SHEET_MARGIN = B.SHEET_MARGIN
local SHEET_RADIUS = B.SHEET_RADIUS
local S_ = B.S_
local SHEET_PAD = B.SHEET_PAD
local SHEET_BTN_H = B.SHEET_BTN_H
local SHEET_BTN_RADIUS = B.SHEET_BTN_RADIUS
local SHEET_BTN_GAP = B.SHEET_BTN_GAP
local SHEET_BTN_FONT = B.SHEET_BTN_FONT
local sheetInnerWidth = B.sheetInnerWidth
local Tap = B.Tap
local StepBar = B.StepBar
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local WHITE, BLACK = Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK

if not uiOpt("sheets") then return end

-------------------------------------------------------------------------
-- Iluminación (diseño 1B): escalones de brillo y de calidez,
-- − Brillo / + Brillo y Listo
-------------------------------------------------------------------------
local LightSheet = InputContainer:extend{}

function LightSheet:init()
    self.powerd = Device:getPowerDevice()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        AireOutside = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
    self:build()
end

function LightSheet:flSteps()
    local p = self.powerd
    local min, max = p.fl_min or 0, p.fl_max or 24
    local stride = math.max(1, math.ceil((max - min + 1) / 25))
    return min, max, stride, math.ceil((max - min) / stride)
end

function LightSheet:setBrightness(v)
    local p = self.powerd
    local min, max = self:flSteps()
    v = math.max(min, math.min(max, v))
    if v <= min then
        if p:isFrontlightOn() then p:turnOffFrontlight() end
    else
        p:setIntensity(v)
    end
    if p.updateResumeFrontlightState then p:updateResumeFrontlightState() end
    self:refresh()
end

function LightSheet:setWarmth(v)
    local p = self.powerd
    v = math.max(p.fl_warmth_min, math.min(p.fl_warmth_max, v))
    p:setWarmth(p:fromNativeWarmth(v))
    self:refresh()
end

function LightSheet:build()
    local p = self.powerd
    local margin, pad, border = S_(SHEET_MARGIN), S_(SHEET_PAD), Size.border.thin
    local inner = sheetInnerWidth()
    local face_t = Font:getFace("tfont", 15)
    local face = Font:getFace("cfont", 15)
    local on = p:isFrontlightOn()
    local min, _max, stride, steps = self:flSteps()
    local cur = on and p:frontlightIntensity() or min

    local content = VerticalGroup:new{ align = "left" }
    -- Título (sin interruptor: el icono del sol apaga y vuelve a encender)
    table.insert(content, TextWidget:new{ text = _("Frontlight"), face = face_t, fgcolor = BLACK,
        max_width = inner, padding = 0 })
    table.insert(content, VerticalSpan:new{ width = S_(10) })

    local icon_d, val_w, gap = S_(40), S_(44), S_(10)
    local bar_w = inner - icon_d - val_w - 2 * gap
    local function stepRow(icon, n, k, value_text, on_step, on_icon)
        local bar = StepBar:new{ width = bar_w, height = S_(30), n = n, k = k }
        local ic = FrameContainer:new{ bordersize = border, radius = math.floor(icon_d / 2), padding = 0,
            width = icon_d, height = icon_d,
            CenterContainer:new{ dimen = Geom:new{ w = icon_d - 2 * border, h = icon_d - 2 * border },
                IconWidget:new{ icon = icon, width = S_(22), height = S_(22), alpha = true } } }
        local val = CenterContainer:new{ dimen = Geom:new{ w = val_w, h = icon_d },
            TextWidget:new{ text = value_text, face = face, fgcolor = BLACK, padding = 0 } }
        -- Tocar el icono: la barra a 0
        return HorizontalGroup:new{ align = "center",
            Tap:new{ callback = function() on_icon() end, ic }, HorizontalSpan:new{ width = gap },
            Tap:new{ callback = function(ges)
                local i = ges and ges.pos and bar:stepAt(ges.pos.x)
                if i then on_step(i) end
            end, bar },
            HorizontalSpan:new{ width = gap }, val }
    end
    table.insert(content, stepRow("aire.widget.sun", steps, on and math.floor((cur - min) / stride + 0.5) or 0,
        tostring(cur), function(i)
            local target = min + i * stride
            -- tocar el último escalón encendido lo apaga (baja uno)
            if on and target == cur then target = target - stride end
            self:setBrightness(target)
        end, function()
            -- Icono: a 0 y, si se vuelve a tocar, al valor de antes
            if on and cur > min then
                self._prev_fl = cur
                self:setBrightness(min)
            elseif self._prev_fl then
                local v = self._prev_fl
                self._prev_fl = nil
                self:setBrightness(v)
            else
                -- apagada al abrir la hoja: encender con el último brillo que recuerde KOReader
                p:toggleFrontlight()
                if p.updateResumeFrontlightState then p:updateResumeFrontlightState() end
                self:refresh()
            end
        end))
    if Device:hasNaturalLight() and p.fl_warmth_max then
        local wmin, wmax = p.fl_warmth_min or 0, p.fl_warmth_max
        local wcur = p:toNativeWarmth(p:frontlightWarmth())
        local wstride = math.max(1, math.ceil((wmax - wmin + 1) / 25))
        local wsteps = math.ceil((wmax - wmin) / wstride)
        table.insert(content, VerticalSpan:new{ width = S_(12) })
        table.insert(content, stepRow("aire.widget.warmth", wsteps, math.floor((wcur - wmin) / wstride + 0.5),
            tostring(wcur), function(i)
                local target = wmin + i * wstride
                if target == wcur then target = target - wstride end
                self:setWarmth(target)
            end, function()
                if wcur > wmin then
                    self._prev_nl = wcur
                    self:setWarmth(wmin)
                elseif self._prev_nl then
                    local v = self._prev_nl
                    self._prev_nl = nil
                    self:setWarmth(v)
                end
            end))
    end
    table.insert(content, VerticalSpan:new{ width = S_(16) })

    -- Botones como la hoja
    local function sheetButton(text, primary, w, cb)
        local bh = S_(SHEET_BTN_H)
        return Tap:new{ callback = cb, FrameContainer:new{
            bordersize = border, color = BLACK, background = primary and BLACK or WHITE,
            radius = S_(SHEET_BTN_RADIUS), padding = 0, width = w, height = bh,
            CenterContainer:new{ dimen = Geom:new{ w = w - 2 * border, h = bh - 2 * border },
                TextWidget:new{ text = text, face = Font:getFace("cfont", SHEET_BTN_FONT),
                    fgcolor = primary and WHITE or BLACK, padding = 0 } } } }
    end
    local bgap = S_(SHEET_BTN_GAP)
    local half = math.floor((inner - bgap) / 2)
    table.insert(content, HorizontalGroup:new{ align = "center",
        sheetButton(_("− Brightness"), false, half, function() self:setBrightness((on and cur or min) - stride) end),
        HorizontalSpan:new{ width = bgap },
        sheetButton(_("+ Brightness"), false, inner - half - bgap, function() self:setBrightness((on and cur or min) + stride) end) })

    self.sheet = FrameContainer:new{ bordersize = border, color = BLACK, background = WHITE,
        radius = S_(SHEET_RADIUS), padding = pad, content }
    self[1] = BottomContainer:new{ dimen = Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.dimen.h - margin },
        self.sheet }
end

function LightSheet:refresh()
    local old = self.sheet and self.sheet.dimen
    self:build()
    UIManager:setDirty(self, function()
        return "ui", old or self.sheet.dimen
    end)
end

function LightSheet:onAireOutside(_args, ges)
    local sd = self.sheet and liveRect(self.sheet)
    if ges and ges.pos and sd and sd.x and ges.pos:intersectWith(sd) then return true end
    return self:onClose()
end

function LightSheet:onClose()
    UIManager:close(self, "ui")
    return true
end

function LightSheet:onCloseWidget()
    UIManager:nextTick(function() UIManager:broadcastEvent(Event:new("HomeWidgetsRefresh")) end)
end

if Device:hasFrontlight() then
    Device.showLightDialog = function() UIManager:show(LightSheet:new{}, "ui") end
end
