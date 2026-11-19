--[[
    aire.koplugin/styles/ui/titlebar.lua
    Barras de título y pantallas completas: barra de estado, dock, cabecera unificada y ventanas emergentes coherentes.
    Lo carga styles/ui/init.lua en su orden (recibe la tabla de styles/ui/base.lua).
--]]

local B = ...
local isA = B.isA
local getUpValue = B.getUpValue
local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderUI = require("apps/reader/readerui")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (ui/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"

-- stylua: ignore start
local CLEAN_POPUPS_AND_TITLES   = true   -- líneas de TitleBar finas en gris y radio unificado
-- stylua: ignore end

--===========================================================================
-- 9) BARRAS DE TÍTULO Y VENTANAS FLOTANTES COHERENTES
--===========================================================================
if CLEAN_POPUPS_AND_TITLES and not TitleBar._clean_line_patched then
    TitleBar._clean_line_patched = true

    safeWrap(TitleBar, "init", function(orig_TitleBar_init, self)
        if self.fullscreen then
            self.with_bottom_line = false
            self.title_top_padding = Screen:scaleBySize(3)
            self.bottom_v_padding = Screen:scaleBySize(3)
            self.title_h_padding = Screen:scaleBySize(SIDE)
            if rawget(self, "title_face") == nil then self.title_face = Font:getFace("tfont", 17) end
            -- Si trae icono de menú/acción a la izquierda (p. ej. "appbar.menu") y botón de cerrar,
            -- movemos ese icono a la derecha y dejamos volver (‹) a la izquierda.
            if self.left_icon and self.left_icon ~= "chevron.left" and self.left_icon ~= "triangle" and not self.right_icon then
                self.right_icon = self.left_icon
                self.right_icon_tap_callback = self.left_icon_tap_callback
                self.right_icon_hold_callback = self.left_icon_hold_callback
                self.right_icon_allow_flash = self.left_icon_allow_flash
                self.left_icon = nil
                self.left_icon_tap_callback = nil
                self.left_icon_hold_callback = nil
                self._aire_moved_left_to_right = true
            end
            -- Vistas a pantalla completa: cerrar volviendo atrás (‹), nunca con X
            if self.close_callback then
                if not self.left_icon then
                    self.left_icon = "chevron.left"
                    self.left_icon_tap_callback = self.close_callback
                    self.left_icon_hold_callback = self.close_hold_callback
                    self.left_icon_allow_flash = false
                end
                self.close_callback = nil
                self.close_hold_callback = nil
            end
            if self.right_icon == "close" or self.right_icon == "exit" then
                self.right_icon = nil
                self.right_icon_tap_callback = nil
                self.right_icon_hold_callback = nil
            end
        end
        -- rawequal: los colores son cdata y "color == nil" llama a su __eq, que
        -- revienta con nil (crash al abrir Información del libro).
        if self.with_bottom_line and rawequal(self.bottom_line_color, nil) then
            self.bottom_line_color = Blitbuffer.COLOR_LIGHT_GRAY
        end
        orig_TitleBar_init(self)
        if self.with_bottom_line then
            for _, child in ipairs(self) do
                if isA(child, HorizontalGroup) or type(child) == "table" then
                    for _, sub in ipairs(child) do
                        if isA(sub, LineWidget) and sub.dimen then
                            sub.dimen.h = Size.line.thin
                        elseif isA(sub, HorizontalGroup) then
                            for _, inner in ipairs(sub) do
                                if isA(inner, LineWidget) and inner.dimen then
                                    inner.dimen.h = Size.line.thin
                                end
                            end
                        end
                    end
                end
            end
        end
        -- Barra de estado del plugin arriba en vistas a pantalla completa
        if self.fullscreen and TitleBar._aire_build_status_bar and not self._aire_no_status_bar and self.dimen and #self > 0 then
            local bar = TitleBar._aire_build_status_bar(self, self.width)
            local og
            local back_cb = (self.left_icon == "chevron.left") and self.left_icon_tap_callback
            local AireScreen = package.loaded.aire_screen
            local side = Screen:scaleBySize(SIDE)
            local in_w = self.width - 2 * side
            if back_cb then
                -- Cabecera común (ui/screen.lua): la misma que Librería, Explorador…
                local header, parts = AireScreen.header(in_w, {
                    title = self.title,
                    on_back = back_cb,
                    menu_icon = self.right_icon,
                    on_menu = function()
                        if self.right_icon_tap_callback then self.right_icon_tap_callback() end
                    end,
                    on_menu_hold = self.right_icon_hold_callback and function()
                        self.right_icon_hold_callback()
                    end or nil,
                    tap_left = side, -- el margen izquierdo también vuelve atrás
                    tap_v = 0,
                })
                self._aire_title_w = parts.title
                self._aire_right_icon_w = parts.menu_icon
                for i = #self, 1, -1 do self[i] = nil end
                og = FrameContainer:new{
                    bordersize = 0, padding = 0, padding_left = side, padding_right = side,
                    header,
                }
                self._aire_custom_bar = true
            else
                og = OverlapGroup:new{ dimen = Geom:new{ w = self.width, h = self.dimen.h } }
                for i = 1, #self do
                    table.insert(og, self[i])
                    self[i] = nil
                end
            end
            local gap_top = Screen:scaleBySize(AireScreen.METRICS.HEADER_GAP)
            -- Subtítulo: el que pasa Aire (_aire_subtitle, ver withTitleBar en
            -- ui/screen.lua), el de KOReader o, en el lector, el título del libro
            local doc_props = ReaderUI and ReaderUI.instance and ReaderUI.instance.doc_props
            local book_title = doc_props and (doc_props.display_title or doc_props.title)
            local sub_txt = self._aire_subtitle
            if not sub_txt or sub_txt == "" then
                if self.subtitle and self.subtitle ~= "" then
                    sub_txt = self.subtitle
                elseif self.info_text and self.info_text ~= "" then
                    sub_txt = self.info_text
                else
                    sub_txt = book_title
                end
            end
            self._aire_default_subtitle = book_title
            local vg_tb = VerticalGroup:new{ align = "left", bar, VerticalSpan:new{ width = gap_top }, og }
            if (sub_txt and sub_txt ~= "") or self.subtitle ~= nil then
                local sub_row, sub_w = AireScreen.subtitle(in_w, sub_txt)
                self._aire_subtitle_w = sub_w
                table.insert(vg_tb, VerticalSpan:new{ width = Screen:scaleBySize(AireScreen.METRICS.SUB_GAP) })
                table.insert(vg_tb, FrameContainer:new{
                    bordersize = 0, padding = 0, padding_left = side, padding_right = side,
                    sub_row,
                })
                table.insert(vg_tb, VerticalSpan:new{ width = Screen:scaleBySize(AireScreen.METRICS.CONTENT_GAP) })
            end
            self[1] = vg_tb
            self.titlebar_height = vg_tb:getSize().h
            self.dimen.h = self.titlebar_height
            self._size = nil
        end
    end, TAG)

    local UIManager = require("ui/uimanager")
    safeWrap(TitleBar, "setTitle", function(orig_TitleBar_setTitle, self, title, no_refresh)
        if self._aire_custom_bar and self._aire_title_w then
            self.title = title
            self._aire_title_w:setText(title or "")
            if not no_refresh and self.show_parent then
                UIManager:setDirty(self.show_parent, "ui", self.dimen)
            end
            return
        end
        return orig_TitleBar_setTitle(self, title, no_refresh)
    end, TAG)

    safeWrap(TitleBar, "setSubTitle", function(orig_TitleBar_setSubTitle, self, subtitle, no_refresh)
        if self._aire_custom_bar and self._aire_subtitle_w then
            self.subtitle = subtitle
            local txt = (subtitle and subtitle ~= "") and subtitle or (self._aire_default_subtitle or "")
            self._aire_subtitle_w:setText(txt)
            if not no_refresh and self.show_parent then
                UIManager:setDirty(self.show_parent, "ui", self.dimen)
            end
            return
        end
        return orig_TitleBar_setSubTitle(self, subtitle, no_refresh)
    end, TAG)

    safeWrap(TitleBar, "setLeftIcon", function(orig_TitleBar_setLeftIcon, self, icon)
        if self._aire_custom_bar and self._aire_moved_left_to_right and self._aire_right_icon_w and icon then
            self._aire_right_icon_w:free()
            self._aire_right_icon_w.icon = package.loaded.aire_screen.menuIcon(icon)
            self._aire_right_icon_w:init()
            if self.show_parent then
                UIManager:setDirty(self.show_parent, "ui", self.dimen)
            end
            return
        end
        return orig_TitleBar_setLeftIcon(self, icon)
    end, TAG)

    local VerticalScrollBar = require("ui/widget/verticalscrollbar")
    if VerticalScrollBar and not VerticalScrollBar._aire_rounded_patched then
        VerticalScrollBar._aire_rounded_patched = true
        safeWrap(VerticalScrollBar, "paintTo", function(_orig, self, bb, x, y)
            if not self.enable then return end
            self.touch_dimen = Geom:new{
                x = x - self.extra_touch_on_side,
                y = y,
                w = self.width + 2 * self.extra_touch_on_side,
                h = self.height,
            }
            local bar_w = math.min(self.width, Screen:scaleBySize(4))
            local bx = x + math.floor((self.width - bar_w) / 2)
            local r = math.floor(bar_w / 2)
            bb:paintRoundedRect(bx, y, bar_w, self.height, Blitbuffer.COLOR_GRAY_E, r)
            local th = math.max(bar_w, math.floor(self.height * (self.high - self.low)))
            local ty = y + math.min(self.height - th, math.floor(self.low * self.height))
            bb:paintRoundedRect(bx, ty, bar_w, th, Blitbuffer.COLOR_GRAY, r)
        end, TAG)
    end

    local ok_aireb, HorizontalScrollBar = pcall(require, "ui/widget/horizontalscrollbar")
    if ok_aireb and HorizontalScrollBar and not HorizontalScrollBar._aire_rounded_patched then
        HorizontalScrollBar._aire_rounded_patched = true
        safeWrap(HorizontalScrollBar, "paintTo", function(_orig, self, bb, x, y)
            if not self.enable then return end
            self.touch_dimen = Geom:new{
                x = x,
                y = y - (self.extra_touch_on_side or 0),
                w = self.width,
                h = self.height + 2 * (self.extra_touch_on_side or 0),
            }
            local bar_h = math.min(self.height, Screen:scaleBySize(4))
            local by = y + math.floor((self.height - bar_h) / 2)
            local r = math.floor(bar_h / 2)
            bb:paintRoundedRect(x, by, self.width, bar_h, Blitbuffer.COLOR_GRAY_E, r)
            local tw = math.max(bar_h, math.floor(self.width * (self.high - self.low)))
            local tx = x + math.min(self.width - tw, math.floor(self.low * self.width))
            bb:paintRoundedRect(tx, by, tw, bar_h, Blitbuffer.COLOR_GRAY, r)
        end, TAG)
    end

    safeWrap(Menu, "init", function(prev_Menu_init, self, ...)
        prev_Menu_init(self, ...)
        if self.is_popout and self[1] then
            self[1].bordersize = Size.border.thin
            if self[1].radius and self[1].radius > 0 then
                self[1].radius = Size.radius.window
            end
        end
    end, TAG)

    -- Dock inferior del plugin en pantallas completas (sin pestaña seleccionada)
    local function attachFullscreenDock(cls)
        local orig = cls.init
        if not orig or cls._aire_dock_patched then return end
        cls._aire_dock_patched = true
        local AireScreen = package.loaded.aire_screen
        function cls:init(...)
            local sw, sh = Screen:getWidth(), Screen:getHeight()
            local is_fs = self.covers_fullscreen
                or ((self.width == nil or self.width == sw) and (self.height == nil or self.height == sh))
            -- Cuándo hay dock lo decide ui/screen.lua (no en el lector, no
            -- con la pantalla de inicio desactivada…); aquí, solo pantallas completas
            local dock, reserve
            if is_fs and not self.is_popout and self.name ~= "filemanager" then
                dock, reserve = AireScreen.fullscreenDock(self)
            end
            if dock then
                self.covers_fullscreen = true
                self.height = (self.height or sh) - reserve
                self._aire_has_dock = true -- (pagination.lua: sin hueco extra bajo los puntos)
            end
            orig(self, ...)
            if dock and self[1] then
                self.covers_fullscreen = true
                self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
                self[1] = AireScreen.root(self[1], dock)
            end
        end
    end
    attachFullscreenDock(KeyValuePage)
    attachFullscreenDock(Menu)

    -- Separadores de filas en listas (Menu / FileChooser): línea fina gris claro
    local MenuItem = getUpValue(Menu.updateItems, "MenuItem")
    if MenuItem and not MenuItem._aire_clean_line_patched then
        MenuItem._aire_clean_line_patched = true
        safeWrap(MenuItem, "init", function(orig_mi_init, self, ...)
            if self.menu and self.menu.name == "filemanager" then
                self.linesize = 0
                self.line_color = Blitbuffer.COLOR_WHITE
            else
                self.linesize = Size.line.thin
                self.line_color = Blitbuffer.COLOR_LIGHT_GRAY
            end
            return orig_mi_init(self, ...)
        end, TAG)
        -- Mantener pulsado (común a todas las listas): si la fila es una
        -- tarjeta de Aire (marco redondeado), se pone negra solo la tarjeta,
        -- respetando sus esquinas. KOReader invertía el rectángulo entero de
        -- la fila (márgenes incluidos) con esquinas cuadradas.
        local function findCard(w, depth)
            if type(w) ~= "table" or depth > 3 then return end
            if isA(w, FrameContainer) and (w.radius or 0) > 0 and (w.bordersize or 0) > 0 then return w end
            for _k, c in ipairs(w) do
                local f = findCard(c, depth + 1)
                if f then return f end
            end
        end
        local function invertRounded(bb, x, y, w, h, r)
            r = math.min(r, math.floor(h / 2), math.floor(w / 2))
            for row = 0, h - 1 do
                local dx = 0
                local dy = (row < r) and (r - row - 0.5) or ((row >= h - r) and (row - (h - r) + 0.5) or nil)
                if dy then dx = math.ceil(r - math.sqrt(math.max(0, r * r - dy * dy))) end
                if w - 2 * dx > 0 then bb:invertRect(x + dx, y + row, w - 2 * dx, 1) end
            end
        end
        -- Destello de una tarjeta (lo usan también Marcadores y otras listas)
        local function flashCard(card)
            local d = card and card.dimen
            if not (d and d.w and d.w > 0) or not G_reader_settings:nilOrTrue("flash_ui") then return end
            local UIManager = require("ui/uimanager")
            UIManager:widgetRepaint(card, d.x, d.y)
            local m = card.margin or 0
            invertRounded(Screen.bb, d.x + m, d.y + m, d.w - 2 * m, d.h - 2 * m, card.radius or 0)
            UIManager:setDirty(nil, "fast", d)
            UIManager:forceRePaint()
            UIManager:yieldToEPDC()
            UIManager:widgetRepaint(card, d.x, d.y)
            UIManager:setDirty(nil, "ui", d)
        end
        Menu._aire_flashCard = flashCard
        Menu._aire_findCard = findCard
        safeWrap(MenuItem, "onHoldSelect", function(orig_mi_hold, self, arg, ges)
            local card = self._aire_card or findCard(self[1], 0)
            if not (card and card.dimen) then return orig_mi_hold(self, arg, ges) end
            flashCard(card)
            self.menu:onMenuHold(self.entry, self:getGesPosition(ges))
            return true
        end, TAG)

        safeWrap(MenuItem, "onFocus", function(orig_mi_focus, self, ...)
            if self.menu and self.menu.name == "filemanager" then
                if self._underline_container then
                    self._underline_container.color = Blitbuffer.COLOR_WHITE
                end
                return true
            end
            return orig_mi_focus(self, ...)
        end, TAG)
    end

    local ok_it, InputText = pcall(require, "ui/widget/inputtext")
    if ok_it and type(InputText) == "table" and not InputText._aire_rounded_patched then
        InputText._aire_rounded_patched = true
        safeWrap(InputText, "initTextBox", function(orig_it_init_tb, self, text, char_added)
            orig_it_init_tb(self, text, char_added)
            if self._frame_textwidget and self._frame_textwidget.bordersize and self._frame_textwidget.bordersize > 0 then
                self._frame_textwidget.radius = Screen:scaleBySize(10)
                self._frame_textwidget.bordersize = Size.border.thin
            end
        end, TAG)
    end

    -- Popups con cuadro de texto (InputDialog / MultiInputDialog / Buscar):
    -- borde fino y título limpio como las hojas
    local ok_id, InputDialog = pcall(require, "ui/widget/inputdialog")
    if ok_id and type(InputDialog) == "table" and not InputDialog._aire_popup_patched then
        InputDialog._aire_popup_patched = true
        safeWrap(InputDialog, "init", function(orig_id_init, self, ...)
            if not self.fullscreen and rawget(self, "border_size") == nil then
                self.border_size = Size.border.thin
            end
            orig_id_init(self, ...)
            if not self.fullscreen and self.dialog_frame then
                self.dialog_frame.bordersize = Size.border.thin
                self.dialog_frame.radius = Size.radius.window
            end
            if not self.fullscreen and self.title_bar then
                local tb = self.title_bar
                tb.with_bottom_line = false
                tb.title_face = Font:getFace("tfont", 15)
                tb.info_text_face = Font:getFace("cfont", package.loaded.aire_screen.SHEET.SUB_FONT)
                tb.subtitle_face = Font:getFace("cfont", 13)
                tb.title_h_padding = Screen:scaleBySize(14)
                tb.title_top_padding = Screen:scaleBySize(14)
                tb.bottom_v_padding = Screen:scaleBySize(8)
                if tb.clear then
                    tb:clear()
                    tb:init()
                end
            end
        end, TAG)
    end
end

--===========================================================================
-- 16) RESTO DE VISTAS A PANTALLA COMPLETA CON TÍTULO + SUBTÍTULO + STATUS BAR
--===========================================================================
do
    -- Interceptor común de las barras de título (ui/screen.lua): solo la
    -- primera que se cree, siempre a pantalla completa
    local function withFullscreenTitleBar(fn, opts)
        return package.loaded.aire_screen.withTitleBar({
            once = true,
            fullscreen = true,
            subtitle = opts.subtitle,
            clear = opts.clear_info_text and { "info_text" } or nil,
            close_fallback = opts.close_callback,
        }, fn)
    end

    local ok_id, InputDialog = pcall(require, "ui/widget/inputdialog")
    if ok_id and type(InputDialog) == "table" and not InputDialog._aire_fs_titlebar_patched then
        InputDialog._aire_fs_titlebar_patched = true
        safeWrap(InputDialog, "init", function(orig_InputDialog_init, self)
            if not self.fullscreen then
                return orig_InputDialog_init(self)
            end
            return withFullscreenTitleBar(function()
                return orig_InputDialog_init(self)
            end, {
                subtitle = self.description,
                clear_info_text = true,
                close_callback = self.cancel_callback or function() self:onClose() end,
            })
        end, TAG)
    end

    -- Ordenar listas (colecciones, acciones de gestos…): la única pantalla
    -- completa de KOReader que creaba su TitleBar sin "fullscreen"
    local ok_sw, SortWidget = pcall(require, "ui/widget/sortwidget")
    if ok_sw and type(SortWidget) == "table" and not SortWidget._aire_fs_titlebar_patched then
        SortWidget._aire_fs_titlebar_patched = true
        safeWrap(SortWidget, "init", function(orig_SortWidget_init, self)
            return withFullscreenTitleBar(function()
                return orig_SortWidget_init(self)
            end, {})
        end, TAG)
    end

    local ok_up, userpatch = pcall(require, "userpatch")
    if ok_up and userpatch and userpatch.registerPatchPluginFunc then
        B.safePluginPatch("vocabbuilder", function(VocabBuilder)
            if VocabBuilder and VocabBuilder.onShowVocabBuilder and not VocabBuilder._aire_titlebar_patched then
                VocabBuilder._aire_titlebar_patched = true
                safeWrap(VocabBuilder, "onShowVocabBuilder", function(orig_show_vb, self)
                    return withFullscreenTitleBar(function()
                        return orig_show_vb(self)
                    end, {
                        subtitle = _("Vocabulary review"),
                    })
                end, TAG)
            end
        end)
    end
end
