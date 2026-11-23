--[[
    aire.koplugin/styles/reader/footer.lua
    Barra de estado inferior del lector (ReaderFooter). Se carga una vez desde main.lua.

      - En «Mostrar todos a la vez» con la barra de progreso en línea (alongside),
        aplica la distribución en 1 línea de Aire (Propuesta 2):
          Izquierda: contexto del capítulo (en gris) · páginas restantes (en negro)
          Centro:    barra cápsula flexible de Aire como separador natural
          Derecha:   progreso del libro (en gris) + hora e iconos de sistema (en negro)
      - En los modos «Iconos» y «Elementos compactos», sustituye inline batería
        (píldora fina con relleno gris claro y número dentro), luz, Wi-Fi (con
        intensidad de señal) y memoria por los iconos vectoriales de Aire.
      - Si la barra de progreso está oculta o arriba/abajo, mantiene los iconos
        inline de Aire y suaviza los separadores «|» en gris claro.
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local NetworkMgr = require("ui/network/manager")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local logger = require("logger")

local Screen = Device.screen
local AireUI = package.loaded.aire_ui
local AireScreen = package.loaded.aire_screen
local S = AireUI.S
local safeWrap = AireUI.safeWrap
local TAG = "Aire/Footer"

local map = ReaderFooter.textGeneratorMap
if type(map) ~= "table" or type(map.battery) ~= "function" or map._aire_patched then
    if type(map) ~= "table" then logger.warn("Aire/Footer: no se encontró textGeneratorMap") end
    return
end
map._aire_patched = true

local function isIconMode(footer)
    local p = footer and footer.settings and footer.settings.item_prefix
    return p == "icons" or p == "compact_items"
end

local function isSplitMode(footer)
    local st = footer and footer.settings
    return st ~= nil
        and st.all_at_once == true
        and st.progress_bar_position == "alongside"
        and not st.disable_progress_bar
end

--===========================================================================
-- 1) Generadores con marcadores inline (\1...\2) en modos con iconos
--===========================================================================
local orig_battery = map.battery
map.battery = function(footer, ...)
    local text, merge = orig_battery(footer, ...)
    if not isIconMode(footer) or type(text) ~= "string" or text == "" or not Device:hasBattery() then
        return text, merge
    end
    local ok, lvl, chg = pcall(function()
        local powerd = Device:getPowerDevice()
        local l = powerd:getCapacity()
        local c = powerd:isCharging() == true
        if Device:hasAuxBattery() and powerd:isAuxBatteryConnected() then
            l = l + powerd:getAuxCapacity()
            c = powerd:isAuxCharging() == true
        end
        return l, c
    end)
    if ok and lvl then
        return ("\1B:%d:%d\2"):format(lvl, chg and 1 or 0), merge
    end
    return text, merge
end

if type(map.frontlight) == "function" then
    local orig_frontlight = map.frontlight
    map.frontlight = function(footer, ...)
        local text, merge = orig_frontlight(footer, ...)
        if not isIconMode(footer) or type(text) ~= "string" or text == "" or not Device:hasFrontlight() then
            return text, merge
        end
        local ok, on, intensity = pcall(function()
            local p = Device:getPowerDevice()
            return p:isFrontlightOn(), p:frontlightIntensity()
        end)
        if not ok then return text, merge end
        if on then
            local suffix = (Device:isCervantes() or Device:isKobo()) and "%" or ""
            return ("\1L\2%d%s"):format(intensity, suffix), merge
        end
        return "\1L\2" .. _("Off"), merge
    end
end

if type(map.mem_usage) == "function" then
    local orig_mem = map.mem_usage
    map.mem_usage = function(footer, ...)
        local text, merge = orig_mem(footer, ...)
        if not isIconMode(footer) or type(text) ~= "string" or text == "" then
            return text, merge
        end
        local val = text:match("(%d+%.?%d*%s*[KMGT]?[iI]?[Bb]?)$") or text:match("(%d+%s*M)$")
        if val and val ~= "" then
            return "\1M\2" .. val, merge
        end
        return text, merge
    end
end

if type(map.wifi_status) == "function" then
    local orig_wifi = map.wifi_status
    map.wifi_status = function(footer, ...)
        local text, merge = orig_wifi(footer, ...)
        if not isIconMode(footer) or type(text) ~= "string" or text == "" then
            return text, merge
        end
        return (NetworkMgr:isWifiOn() and "\1W\2" or "\1W0\2"), merge
    end
end

if type(map.pages_left) == "function" then
    local orig_pages_left = map.pages_left
    map.pages_left = function(footer, ...)
        local text, merge = orig_pages_left(footer, ...)
        if isIconMode(footer) and type(text) == "string" then
            local num = text:match("(%d+)%s*$")
            if num then
                local arrow = BD.mirroredUILayout() and "‹" or "›"
                return num .. " " .. arrow, merge
            end
            text = text:gsub("⇒", BD.mirroredUILayout() and "‹" or "›"):gsub("⇐", "‹")
        end
        return text, merge
    end
end

--===========================================================================
-- 2) Widget de texto con iconos vectoriales inline, grises y separadores
--===========================================================================
local AireFooterText = WidgetContainer:extend{
    text = "",
    face = nil,
    bold = false,
    max_width = nil,
    height = 0,
    footer = nil,
}

function AireFooterText:init()
    self._built_key = nil
    self._line_h = nil
    self:_rebuild()
end

function AireFooterText:_measureLineH()
    if self._line_h then return self._line_h end
    local tmp = TextWidget:new{ text = "88%", face = self.face, bold = self.bold, padding = 0 }
    local h = tmp:getSize().h
    tmp:free()
    self._line_h = math.max(S(10), h or S(14))
    return self._line_h
end

local function appendPlain(row, text_widgets, chunk, face, bold, soft_bar)
    if chunk == "" then return end
    if soft_bar and chunk:find(" | ", 1, true) then
        local pos = 1
        while pos <= #chunk do
            local s, e = chunk:find(" | ", pos, true)
            if not s then
                local tail = chunk:sub(pos)
                if tail ~= "" then
                    local tw = TextWidget:new{ text = tail, face = face, bold = bold, fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 }
                    table.insert(row, tw)
                    table.insert(text_widgets, tw)
                end
                break
            end
            local before = chunk:sub(pos, s - 1)
            if before ~= "" then
                local tw = TextWidget:new{ text = before, face = face, bold = bold, fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 }
                table.insert(row, tw)
                table.insert(text_widgets, tw)
            end
            table.insert(row, TextWidget:new{
                text = " | ",
                face = face,
                bold = false,
                fgcolor = Blitbuffer.COLOR_GRAY_9,
                padding = 0,
            })
            pos = e + 1
        end
    else
        local tw = TextWidget:new{ text = chunk, face = face, bold = bold, fgcolor = Blitbuffer.COLOR_BLACK, padding = 0 }
        table.insert(row, tw)
        table.insert(text_widgets, tw)
    end
end

local wifi_icon_cache = { icon = "", at = 0 }
local function cachedWifiStatusIcon()
    local now = os.time()
    if wifi_icon_cache.icon == "" or (now - wifi_icon_cache.at) >= 10 then
        wifi_icon_cache.icon = AireScreen.wifiStatusIcon()
        wifi_icon_cache.at = now
    end
    return wifi_icon_cache.icon
end

function AireFooterText:_rebuild()
    local text = type(self.text) == "string" and self.text or ""
    local sep_mode = self.footer and self.footer.settings and self.footer.settings.items_separator or ""
    local soft_bar = sep_mode == "bar"
    local wifi_icon = text:find("\1W\2", 1, true) and cachedWifiStatusIcon() or ""
    local key = text .. "\0" .. tostring(self.max_width or "") .. "\0" .. tostring(sep_mode) .. "\0" .. wifi_icon
    if key == self._built_key then return end
    self._built_key = key

    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    if text == "" then
        self.height = 0
        return
    end

    local line_h = self:_measureLineH()
    local icon_sz = math.max(S(11), math.floor(line_h * 0.88 + 0.5))
    local bat_h = math.max(S(11), math.floor(line_h * 0.82 + 0.5))
    local row = HorizontalGroup:new{ align = "center" }
    local text_widgets = {}

    local pos = 1
    while pos <= #text do
        local s, e, tok = text:find("\1([^\2]+)\2", pos)
        if not s then
            appendPlain(row, text_widgets, text:sub(pos), self.face, self.bold, soft_bar)
            break
        end
        if s > pos then
            appendPlain(row, text_widgets, text:sub(pos, s - 1), self.face, self.bold, soft_bar)
        end
        local bat_lvl, bat_chg = tok:match("^B:(%d+):(%d)$")
        if bat_lvl then
            table.insert(row, AireScreen.BatteryGlyph:new{
                level = tonumber(bat_lvl) or 0,
                charging = bat_chg == "1",
                height = bat_h,
            })
        elseif tok == "L" then
            table.insert(row, IconWidget:new{ icon = "aire.status.sun", width = icon_sz, height = icon_sz, alpha = true })
            table.insert(row, HorizontalSpan:new{ width = S(2) })
        elseif tok == "M" then
            table.insert(row, IconWidget:new{ icon = "aire.status.memory", width = icon_sz, height = icon_sz, alpha = true })
            table.insert(row, HorizontalSpan:new{ width = S(2) })
        elseif tok == "W" then
            table.insert(row, IconWidget:new{ icon = wifi_icon, width = icon_sz, height = icon_sz, alpha = true })
        elseif tok == "W0" then
            table.insert(row, IconWidget:new{ icon = "aire.status.wifi.0", width = icon_sz, height = icon_sz, alpha = true })
        elseif tok == "S" then
            table.insert(row, HorizontalSpan:new{ width = S(8) })
        elseif tok:sub(1, 1) == "P" then
            local sep_str = tok:sub(2)
            if sep_str ~= "" then
                table.insert(row, TextWidget:new{
                    text = sep_str,
                    face = self.face,
                    bold = false,
                    fgcolor = Blitbuffer.COLOR_GRAY_9,
                    padding = 0,
                })
            end
        elseif tok:sub(1, 1) == "G" then
            local muted = tok:sub(2)
            if muted ~= "" then
                local tw = TextWidget:new{
                    text = muted,
                    face = self.face,
                    bold = self.bold,
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    padding = 0,
                }
                table.insert(row, tw)
                table.insert(text_widgets, tw)
            end
        end
        pos = e + 1
    end

    -- Si supera max_width, acortar el bloque de texto más ancho (normalmente el capítulo)
    if self.max_width and self.max_width > 0 then
        local total_w = row:getSize().w
        if total_w > self.max_width and #text_widgets > 0 then
            local widest, widest_w = nil, 0
            for _i, tw in ipairs(text_widgets) do
                local tw_w = tw:getSize().w
                if tw_w > widest_w then
                    widest, widest_w = tw, tw_w
                end
            end
            if widest and widest_w > 0 then
                local excess = total_w - self.max_width
                widest:setMaxWidth(math.max(S(24), widest_w - excess))
                row:resetLayout()
            end
        end
    end

    self[1] = row
    self.height = row:getSize().h
end

function AireFooterText:setContent(text, max_w)
    self.text = text or ""
    if max_w ~= nil then self.max_width = max_w end
    self:_rebuild()
end

function AireFooterText:setText(text)
    self.text = text or ""
    self:_rebuild()
end

function AireFooterText:setMaxWidth(max_w)
    if self.max_width == max_w then return end
    self.max_width = max_w
    self:_rebuild()
end

function AireFooterText:getSize()
    if self[1] then
        local sz = self[1]:getSize()
        return Geom:new{ w = sz.w, h = sz.h }
    end
    return Geom:new{ w = 0, h = 0 }
end

function AireFooterText:paintTo(bb, x, y)
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

function AireFooterText:free()
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    self._built_key = nil
end

--===========================================================================
-- 3) Propuesta 2: Izquierda (capítulo) — Barra central — Derecha (sistema)
--===========================================================================
local LEFT_KEYS = {
    book_chapter = true,
    book_title = true,
    book_author = true,
    pages_left = true,
    chapter_progress = true,
    chapter_time_to_read = true,
    bookmark_count = true,
}

local MUTED_KEYS = {
    book_chapter = true,
    book_title = true,
    book_author = true,
    chapter_time_to_read = true,
    bookmark_count = true,
    page_progress = true,
    pages_left_book = true,
    percentage = true,
    book_time_to_read = true,
    custom_text = true,
}

local function safeGen(footer, key)
    local fn = map[key]
    if type(fn) ~= "function" then return nil end
    local ok, val = pcall(fn, footer)
    if not ok or type(val) ~= "string" or val == "" then return nil end
    return val
end

local function buildSplitStrings(footer)
    local left_parts, right_parts = {}, {}
    local order = footer.settings and footer.settings.order
    local seen = {}
    local keys = {}
    if type(order) == "table" then
        for i = 1, #order do
            local k = order[i]
            if type(k) == "string" and k ~= "off" and k ~= "dynamic_filler" and not seen[k] then
                seen[k] = true
                table.insert(keys, k)
            end
        end
    end
    if type(footer.mode_index) == "table" then
        for _i, k in pairs(footer.mode_index) do
            if type(k) == "string" and k ~= "off" and k ~= "dynamic_filler" and not seen[k] then
                seen[k] = true
                table.insert(keys, k)
            end
        end
    end

    for _i, key in ipairs(keys) do
        if footer.settings[key] then
            local val = safeGen(footer, key)
            if val then
                if MUTED_KEYS[key] and not val:find("\1", 1, true) then
                    val = "\1G" .. val .. "\2"
                end
                if LEFT_KEYS[key] then
                    table.insert(left_parts, val)
                else
                    table.insert(right_parts, val)
                end
            end
        end
    end

    local add = safeGen(footer, "additional_content")
    if add then
        table.insert(right_parts, add)
    end

    local sep_mode = footer.settings and footer.settings.items_separator
    local sep_tok = "\1S\2"
    if sep_mode == "bar" then
        sep_tok = "\1P | \2"
    elseif sep_mode == "bullet" then
        sep_tok = "\1P • \2"
    elseif sep_mode == "dot" then
        sep_tok = "\1P · \2"
    end

    return table.concat(left_parts, sep_tok), table.concat(right_parts, sep_tok)
end

local function newFooterText(footer, text)
    local w = AireFooterText:new{
        text = text or "",
        face = footer.footer_text_face,
        bold = footer.settings and footer.settings.text_font_bold or false,
        footer = footer,
    }
    w._aire_footer_text = true
    return w
end

local function installFooterWidget(footer, force)
    if not footer or not footer.text_container then return end
    local cur = footer.footer_text
    if force or not (cur and cur._aire_footer_text) then
        local cur_text = cur and cur.text or ""
        if cur and cur.free then cur:free() end
        local w = newFooterText(footer, cur_text)
        footer.footer_text = w
        footer.text_container[1] = w
    end
    if footer._aire_left_box then
        local lcur = footer._aire_left_text
        if force or not (lcur and lcur._aire_footer_text) then
            local ltext = lcur and lcur.text or ""
            if lcur and lcur.free then lcur:free() end
            local lw = newFooterText(footer, ltext)
            footer._aire_left_text = lw
            footer._aire_left_box[1] = lw
        end
    end
end

local function installSplitContainer(footer)
    if footer and footer._aire_left_text and footer._aire_left_text.free then
        footer._aire_left_text:free()
    end
    if not footer or not footer.horizontal_group or not isSplitMode(footer) then
        footer._aire_left_box = nil
        footer._aire_left_text = nil
        footer._aire_left_gap = nil
        footer._aire_right_gap = nil
        return
    end
    local margin_span = footer.horizontal_group[1]
    local lw = newFooterText(footer, "")
    local lbox = LeftContainer:new{
        dimen = Geom:new{ w = 0, h = footer.height or S(18) },
        lw,
    }
    local lgap = HorizontalSpan:new{ width = 0 }
    local rgap = HorizontalSpan:new{ width = 0 }
    footer._aire_left_text = lw
    footer._aire_left_box = lbox
    footer._aire_left_gap = lgap
    footer._aire_right_gap = rgap

    footer.horizontal_group = HorizontalGroup:new{
        margin_span,
        lbox,
        lgap,
        footer.progress_bar,
        rgap,
        footer.text_container,
        margin_span,
    }
    if footer.footer_container then
        footer.footer_container[1] = footer.horizontal_group
    end
end

local function applySplitLayout(footer)
    if not isSplitMode(footer) or not footer._aire_left_text or not footer._aire_left_box then
        return false
    end
    local left_str, right_str = buildSplitStrings(footer)
    local sw = footer._saved_screen_width or Screen:getWidth()
    local margins_w = 2 * Screen:scaleBySize(footer.settings.progress_margin_width or 10)
    local avail = math.max(S(80), sw - margins_w)
    local gap = S(10)

    -- 1) Derecha (progreso + hora + batería): ancho completo sin truncar salvo extremo
    footer.footer_text:setContent(right_str, math.floor(avail * 0.65))
    local right_w = right_str ~= "" and footer.footer_text:getSize().w or 0
    local right_gap = right_w > 0 and gap or 0

    -- 2) Izquierda (capítulo · páginas restantes): cede espacio si hace falta para la barra
    local min_bar = math.max(S(32), math.floor(avail * (footer.settings.progress_bar_min_width_pct or 20) / 100))
    local left_gap = left_str ~= "" and gap or 0
    local max_left = math.max(S(36), avail - right_w - right_gap - left_gap - min_bar)
    footer._aire_left_text:setContent(left_str, max_left)
    local left_w = left_str ~= "" and footer._aire_left_text:getSize().w or 0
    if left_w == 0 then left_gap = 0 end

    -- 3) Barra central: ocupa exactamente el hueco libre restante
    local bar_w = math.max(S(24), math.floor(avail - left_w - left_gap - right_gap - right_w))
    footer._aire_left_box.dimen.w = left_w
    footer._aire_left_box.dimen.h = footer.height or footer.text_container.dimen.h
    footer._aire_left_gap.width = left_gap
    footer._aire_right_gap.width = right_gap
    footer.progress_bar.width = bar_w
    footer.text_container.dimen.w = right_w
    footer.text_width = left_w + left_gap + right_gap + right_w
    footer.footer_text.height = math.max(footer.footer_text:getSize().h, footer._aire_left_text:getSize().h)

    if footer.separator_line then
        footer.separator_line.dimen.w = sw - 2 * footer.horizontal_margin
    end
    footer.horizontal_group:resetLayout()
    return true
end

safeWrap(ReaderFooter, "init", function(orig, self, ...)
    local res = orig(self, ...)
    installFooterWidget(self)
    return res
end, TAG)

safeWrap(ReaderFooter, "updateFooterContainer", function(orig, self, ...)
    local res = orig(self, ...)
    installSplitContainer(self)
    installFooterWidget(self)
    return res
end, TAG)

safeWrap(ReaderFooter, "updateFooterFont", function(orig, self, ...)
    local res = orig(self, ...)
    installFooterWidget(self, true)
    return res
end, TAG)

safeWrap(ReaderFooter, "resetLayout", function(orig, self, force_reset)
    local res = orig(self, force_reset)
    if isSplitMode(self) and self.view and self.view.footer_visible and self.pageno then
        applySplitLayout(self)
    end
    return res
end, TAG)

safeWrap(ReaderFooter, "_updateFooterText", function(orig, self, force_repaint, full_repaint)
    if not isSplitMode(self) or not self.view or not self.view.footer_visible then
        return orig(self, force_repaint, full_repaint)
    end
    if not self._aire_left_text then
        installSplitContainer(self)
    end
    if not applySplitLayout(self) then
        return orig(self, force_repaint, full_repaint)
    end
    if force_repaint then
        if self.visibility_change then
            self.visibility_change = nil
            self.ui:handleEvent(Event:new("ReaderFooterVisibilityChange"))
        end
        local refresh_dim = self.footer_content.dimen
        if not full_repaint then
            UIManager:widgetRepaint(self.view.footer, 0, 0)
            UIManager:setDirty(nil, function()
                return self.view.currently_scrolling and "fast" or "ui", self.footer_content.dimen
            end)
        else
            UIManager:setDirty(self.view.dialog, function()
                return self.view.currently_scrolling and "fast" or "ui", refresh_dim
            end)
        end
    end
end, TAG)

logger.dbg("Aire/Footer: aplicado desde el plugin")
