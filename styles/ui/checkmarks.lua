--[[
    aire.koplugin/styles/ui/checkmarks.lua
    Casillas (CheckMark) y opciones (RadioMark) con los iconos SVG aire.checkbox.* y aire.radio.*.
    Lo carga styles/ui/init.lua en su orden (recibe la tabla de styles/ui/base.lua).
--]]

local B = ...

-- Letra de las casillas y opciones (búsqueda, ordenar, pickers…): la de las
-- filas de las hojas (ui/screen.lua, ROW_FONT). Si quien las crea pasa su
-- propia letra (p. ej. el selector de fuentes, que enseña cada una), se respeta.
do
    local Font_ = require("ui/font")
    local row_face = Font_:getFace("cfont", package.loaded.aire_screen.SHEET.ROW_FONT)
    local ok_cb, CheckButton_ = pcall(require, "ui/widget/checkbutton")
    if ok_cb and type(CheckButton_) == "table" then
        CheckButton_.face = row_face
        CheckButton_.checkmark_face = row_face
    end
    local ok_rt, RadioButtonTable_ = pcall(require, "ui/widget/radiobuttontable")
    if ok_rt and type(RadioButtonTable_) == "table" then RadioButtonTable_.face = row_face end
end
local uiOpt = B.uiOpt
local Device = require("device")
local BD = require("ui/bidi")
local CheckMark = require("ui/widget/checkmark")
local DataStorage = require("datastorage")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RadioMark = require("ui/widget/radiomark")
local TextWidget = require("ui/widget/textwidget")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"

-- stylua: ignore start
local MODERN_CHECKMARKS         = uiOpt("checkmarks")   -- usar aire.checkbox.* y aire.radio.*
local CHECKMARK_ICON_SCALE      = 0.68   -- tamaño del icono respecto al alto de línea
-- stylua: ignore end

--===========================================================================
-- 4) CASILLAS Y BOTONES DE OPCIÓN MODERNOS (SVG)
--===========================================================================
if MODERN_CHECKMARKS and not CheckMark._modern_checkmarks then
    CheckMark._modern_checkmarks = true

    -- Vienen con el plugin (icons/); también valen los de koreader/icons/ del usuario
    local icons_dir = DataStorage:getDataDir() .. "/icons/"
    local function iconExists(name)
        if IconWidget._aire_icon_path then
            return IconWidget._aire_icon_path(name) ~= nil
        end
        return lfs.attributes(icons_dir .. name .. ".svg", "mode") == "file"
    end

    local available = {}
    for _, n in ipairs({ "aire.checkbox.off", "aire.checkbox.on", "aire.radio.off", "aire.radio.on", "aire.check" }) do
        available[n] = iconExists(n)
        if not available[n] then logger.warn("Aire/UI: falta el icono", n) end
    end

    local metrics_cache = setmetatable({}, { __mode = "k" })
    local function getMetrics(face, sample)
        local by_face = metrics_cache[face]
        if not by_face then
            by_face = {}
            metrics_cache[face] = by_face
        end
        local key = sample .. (BD.mirroredUILayout() and "|rtl" or "|ltr")
        local m = by_face[key]
        if not m then
            local tw = TextWidget:new{
                text = sample,
                face = face,
                para_direction_rtl = BD.mirroredUILayout(),
            }
            local sz = tw:getSize()
            m = { w = sz.w, h = sz.h, baseline = tw:getBaseline() }
            tw:free()
            by_face[key] = m
        end
        return m
    end

    local function initWithIcon(widget, icon_name, sample)
        local m = getMetrics(widget.face, sample)
        local size = math.max(Screen:scaleBySize(12), math.floor(m.h * CHECKMARK_ICON_SCALE))
        local gap = math.max(Screen:scaleBySize(10), math.floor(size * 0.45))
        local total_w = math.max(m.w, size + gap)
        widget.baseline = m.baseline
        widget.dimen = Geom:new{ w = total_w, h = m.h }
        if not widget.checkable then
            widget[1] = WidgetContainer:new{ dimen = Geom:new{ w = 0, h = 0 } }
            return true
        end
        if not available[icon_name] then
            return false
        end
        widget[1] = LeftContainer:new{
            dimen = Geom:new{ w = total_w, h = m.h },
            IconWidget:new{
                icon = icon_name,
                width = size,
                height = size,
                alpha = true,
                dim = not widget.enabled or nil,
            },
        }
        return true
    end

    safeWrap(CheckMark, "init", function(orig_CheckMark_init, self)
        local icon = self.checked and "aire.checkbox.on" or "aire.checkbox.off"
        if not initWithIcon(self, icon, "▢ ") then
            orig_CheckMark_init(self)
        end
    end, TAG)

    safeWrap(RadioMark, "init", function(orig_RadioMark_init, self)
        local icon = self.checked and "aire.radio.on" or "aire.radio.off"
        if not initWithIcon(self, icon, "◯ ") then
            orig_RadioMark_init(self)
        end
    end, TAG)

    -- Botones marcados con ✓ (tanto los de checked_func como los que pegan
    -- "  ✓" al final del texto, p. ej. Leyendo / En pausa / Terminado en
    -- filemanagerutil.genStatusButtonsRow): sustituye el ✓ Unicode por aire.check.
    if available["aire.check"] then
        local Button = require("ui/widget/button")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan = require("ui/widget/horizontalspan")
        local TRAILING_CHECK = "^(.-)%s+\u{2713}$"
        safeWrap(Button, "init", function(orig_Button_init, self)
            if type(self.text) ~= "string" then
                return orig_Button_init(self)
            end
            local via_func = self.checked_func ~= nil and self.checkmark == Button.checkmark
            local stripped = not via_func and self.text:match(TRAILING_CHECK) or nil
            if not via_func and not stripped then
                return orig_Button_init(self)
            end
            local checked
            local orig_text = self.text
            local had_own_cm = rawget(self, "checkmark")
            if via_func then
                local ok_c, is_checked = pcall(self.checked_func)
                checked = ok_c and is_checked and true or false
                self.checkmark = ""
            else
                checked = true
                self.text = stripped
            end
            local ok_init, err = pcall(orig_Button_init, self)
            if via_func then
                rawset(self, "checkmark", had_own_cm)
            else
                self.text = orig_text
            end
            if not ok_init then error(err) end
            if not (self.label_container and self.label_widget) then return end
            local lw_sz = self.label_widget:getSize()
            local icon_sz = math.max(Screen:scaleBySize(12), math.floor((lw_sz.h or Screen:scaleBySize(20)) * 0.65))
            local gap = Screen:scaleBySize(6)
            if self._min_needed_width then
                self._min_needed_width = self._min_needed_width + gap + icon_sz
            end
            if not checked then return end
            local lc_w = self.label_container.dimen and self.label_container.dimen.w
            if lc_w and lw_sz.w + gap + icon_sz > lc_w and self.label_widget.setMaxWidth then
                self.label_widget:setMaxWidth(math.max(1, lc_w - gap - icon_sz))
            end
            local check_icon = IconWidget:new{
                icon = "aire.check",
                width = icon_sz,
                height = icon_sz,
                alpha = true,
                dim = not self.enabled or nil,
            }
            local span = HorizontalSpan:new{ width = gap }
            if BD.mirroredUILayout() then
                self.label_container[1] = HorizontalGroup:new{ align = "center", check_icon, span, self.label_widget }
            else
                self.label_container[1] = HorizontalGroup:new{ align = "center", self.label_widget, span, check_icon }
            end
        end, TAG)
    end
end
