--[[
    aire.koplugin/styles/ui/pagination.lua
    Paginación por puntos en todo KOReader (Menu, KeyValuePage, TouchMenu, calendario, vocabulario) y aviso gris en listas vacías.
    Lo carga styles/ui.lua en su orden (recibe la tabla de styles/ui/base.lua).
--]]

local B = ...
local uiOpt = B.uiOpt
local getUpValue = B.getUpValue
local safePluginPatch = B.safePluginPatch
local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TouchMenu = require("ui/widget/touchmenu")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"

-- stylua: ignore start
local DOT_PAGINATION            = uiOpt("dots")   -- activar paginación por puntos global
local TOUCHMENU_DOTS            = 6      -- máximo de puntos en el pie del menú desplegable
local BAR_HEIGHT                = package.loaded.aire_screen.METRICS.DOTS_H -- alto del indicador
local EMPTY_LIST_MESSAGE        = true   -- aviso gris centrado en listas vacías (Historial, colecciones…)
-- stylua: ignore end

--===========================================================================
-- 2) PAGINACIÓN POR PUNTOS GLOBAL (SIN ZONAS TÁCTILES)
--===========================================================================
if DOT_PAGINATION and not Menu._dot_pagination_patched then
    Menu._dot_pagination_patched = true

    -- Puntos de página: la pieza común (common/screen.lua), la misma que usan
    -- la cuadrícula de la Librería y common/pages.lua
    local DotPager = package.loaded.aire_screen.Pager
    Menu._aire_dot_pager_cls = DotPager

    -- Pie de los puntos (common/screen.lua): las pantallas completas sin dock
    -- (en el lector…) dejan debajo el mismo hueco que hay hasta el dock
    local AireScreen = package.loaded.aire_screen
    local function wantsBottomGap(w)
        if w._aire_has_dock or w.is_popout or w.name == "filemanager" then return false end
        return w.covers_fullscreen or (w.dimen and w.dimen.h and w.dimen.h >= Screen:getHeight()) or false
    end
    local function dotsFooter(w)
        if not w._dot_footer then w._dot_footer = AireScreen.pagerFooter(w._dot_pager, not wantsBottomGap(w)) end
        -- El ancho de los puntos cambia con el nº de páginas: volver a medir
        if w._dot_footer ~= w._dot_pager and w._dot_footer.resetLayout then w._dot_footer:resetLayout() end
        return w._dot_footer
    end

    local function replaceGroupWithDots(group, pager)
        if not group then return end
        for i = #group, 1, -1 do
            group[i] = nil
        end
        group[1] = pager
        if group.resetLayout then group:resetLayout() end
    end

    -- 2.1) Menu (Explorador, Historial, Colecciones, TOC, Marcadores, Búsqueda…)
    local function installMenuDots(menu)
        if not menu or not menu.page_info then return end
        if not menu._dot_pager then
            local h = Screen:scaleBySize(BAR_HEIGHT)
            menu._dot_pager = DotPager:new{
                height = h,
                get_state = function()
                    if not menu.item_table or #menu.item_table == 0 then return 1, 1 end
                    return menu.page or 1, menu.page_num or 1
                end,
            }
        end
        local footer = dotsFooter(menu)
        if menu.page_info[1] ~= footer or #menu.page_info > 1 then
            replaceGroupWithDots(menu.page_info, footer)
        else
            menu.page_info:resetLayout()
        end
    end

    -- Con los puntos ya no se ve el "No items" de serie: en una lista vacía se
    -- muestra un aviso gris en el centro del área de la lista.
    local function emptyListText(menu)
        if menu.empty_text then return menu.empty_text end
        if menu.name == "history" then
            local m = menu._manager
            if m and (m.search_string or m.selected_collections or (m.filter and m.filter ~= "all")) then
                return _("No book matches the filter")
            end
            return _("You have not opened any book yet")
        elseif menu.name == "collections" then
            return _("This collection is empty")
        elseif menu.genItemTableFromPath then -- FileChooser
            return _("Empty folder")
        end
        return _("No items")
    end

    local function showEmptyMessage(menu)
        if menu.item_table and #menu.item_table > 0 then return end
        local group = menu.item_group
        if not group or #group > 0 then return end -- ya hay algo (o ya está el aviso)
        local w = (menu.item_dimen and menu.item_dimen.w) or (menu.inner_dimen and menu.inner_dimen.w)
        local h = menu.available_height
        if not h and menu.inner_dimen then
            -- Modos de portadas (CoverBrowser) no rellenan available_height
            h = menu.inner_dimen.h
                - ((menu.title_bar and not menu.no_title) and menu.title_bar:getHeight() or 0)
                - (menu.page_return_arrow and menu.page_return_arrow:getSize().h or 0)
        end
        if not w or not h or h <= 0 then return end
        table.insert(group, CenterContainer:new{
            dimen = Geom:new{ w = w, h = h },
            TextBoxWidget:new{
                text = emptyListText(menu),
                face = Font:getFace("cfont", 15),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                alignment = "center",
                width = math.floor(w * 0.8),
            },
        })
        group:resetLayout()
        if menu.content_group and menu.content_group.resetLayout then
            menu.content_group:resetLayout()
        end
    end

    safeWrap(Menu, "init", function(orig_Menu_init, self, ...)
        orig_Menu_init(self, ...)
        installMenuDots(self)
    end, TAG)

    local function stylePlainExplorerItems(menu)
        if menu.name ~= "filemanager" or not menu.item_group or #menu.item_group == 0 then return end
        local pad_h = Screen:scaleBySize(SIDE)
        local inner_pad = Screen:scaleBySize(14)
        local changed = false
        for _i, child in ipairs(menu.item_group) do
            if type(child) == "table" and child.entry and child._underline_container
               and child.do_cover_image == nil and child.do_filename_only == nil
               and not child._aire_fc_card_done then
                child._aire_fc_card_done = true
                changed = true
                local item_w = (child.dimen and child.dimen.w) or (menu.item_dimen and menu.item_dimen.w) or menu.width or Screen:getWidth()
                local item_h = (child.dimen and child.dimen.h) or (menu.item_dimen and menu.item_dimen.h) or Screen:scaleBySize(48)
                local gap_b = Screen:scaleBySize(8)
                local card_w = math.max(Screen:scaleBySize(120), item_w - 2 * pad_h)
                local card_h = math.max(Screen:scaleBySize(28), item_h - gap_b)
                local inner_w = math.max(Screen:scaleBySize(80), card_w - 2 * inner_pad - 2 * Size.border.thin)
                local inner_h = math.max(Screen:scaleBySize(20), card_h - 2 * Size.border.thin)
                local is_dir = child.entry.is_file == false or (not child.entry.is_file and not child.entry.file)
                local title_txt = child.text or child.entry.text or ""
                local mand_txt = child.mandatory or child.entry.mandatory or ""

                local mand_w
                local mand_used = 0
                if mand_txt ~= "" then
                    mand_w = TextWidget:new{
                        text = mand_txt,
                        face = Font:getFace("infont", 13),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                        padding = 0,
                    }
                    mand_used = mand_w:getSize().w + Screen:scaleBySize(8)
                end

                local text_w = math.max(Screen:scaleBySize(80), inner_w - mand_used)
                local title_w = TextWidget:new{
                    text = title_txt,
                    face = Font:getFace(is_dir and "tfont" or "cfont", 15),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    bold = is_dir,
                    max_width = text_w,
                    padding = 0,
                }

                local left_hg = HorizontalGroup:new{ align = "center", title_w }

                local row
                if mand_w then
                    row = OverlapGroup:new{
                        dimen = Geom:new{ w = inner_w, h = inner_h },
                        LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, left_hg },
                        RightContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, mand_w },
                    }
                else
                    row = LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, left_hg }
                end

                local card = FrameContainer:new{
                    width = card_w,
                    height = card_h,
                    bordersize = Size.border.thin,
                    color = Blitbuffer.COLOR_GRAY_D,
                    background = Blitbuffer.COLOR_WHITE,
                    radius = Screen:scaleBySize(10),
                    padding = 0,
                    padding_left = inner_pad,
                    padding_right = inner_pad,
                    row,
                }
                child[1] = FrameContainer:new{
                    width = item_w,
                    height = item_h,
                    bordersize = 0,
                    padding = 0,
                    padding_left = pad_h,
                    padding_right = pad_h,
                    padding_bottom = gap_b,
                    card,
                }
            end
        end
        if changed and menu.item_group.resetLayout then menu.item_group:resetLayout() end
    end

    -- Tanto Menu:updateItems como CoverMenu:updateItems (mosaico/lista con
    -- portadas) llaman a updatePageInfo justo después de rellenar item_group.
    safeWrap(Menu, "updatePageInfo", function(orig_Menu_updatePageInfo, self, select_number)
        orig_Menu_updatePageInfo(self, select_number)
        installMenuDots(self)
        pcall(stylePlainExplorerItems, self)
        if EMPTY_LIST_MESSAGE then
            local ok, err = pcall(showEmptyMessage, self)
            if not ok then logger.warn("Aire/UI: aviso de lista vacía:", err) end
        end
    end, TAG)

    -- 2.2) KeyValuePage (Información del libro, Estadísticas, Estado del sistema…)
    local function installKeyValueDots(kvp)
        if not kvp or not kvp.page_info then return end
        if not kvp._dot_pager then
            -- Mismo alto que en el resto (antes, el del pie de KOReader, más
            -- alto: los puntos quedaban más arriba)
            kvp._dot_pager = DotPager:new{
                height = Screen:scaleBySize(BAR_HEIGHT),
                get_state = function()
                    return kvp.show_page or 1, kvp.pages or 1
                end,
            }
        end
        local footer = dotsFooter(kvp)
        if kvp.page_info[1] ~= footer or #kvp.page_info > 1 then
            replaceGroupWithDots(kvp.page_info, footer)
        else
            kvp.page_info:resetLayout()
        end
    end

    safeWrap(KeyValuePage, "_populateItems", function(orig_KeyValuePage_populateItems, self, ...)
        orig_KeyValuePage_populateItems(self, ...)
        installKeyValueDots(self)
    end, TAG)

    -- 2.3) TouchMenu (menús desplegables superiores con más de 1 página)
    safeWrap(TouchMenu, "updateItems", function(orig_TouchMenu_updateItems, self, target_page, target_item_id)
        orig_TouchMenu_updateItems(self, target_page, target_item_id)
        if not self.page_info then return end
        if not self._dot_pager then
            local h = (self.footer and self.footer:getSize().h) or Screen:scaleBySize(BAR_HEIGHT)
            self._dot_pager = DotPager:new{
                height = h,
                max_dots = TOUCHMENU_DOTS,
                get_state = function()
                    return self.page or 1, self.page_num or 1
                end,
            }
        end
        if self.page_info[1] ~= self._dot_pager or #self.page_info > 1 then
            replaceGroupWithDots(self.page_info, self._dot_pager)
        else
            self.page_info:resetLayout()
        end
    end, TAG)

    -- 2.4) Plugins: Calendario (vista diaria) y Constructor de vocabulario
    safePluginPatch("statistics", function()
        local ok, CalendarView = pcall(require, "calendarview")
        if not ok or type(CalendarView) ~= "table" then return end
        -- CalendarDayView es local en calendarview.lua; se usa en showCalendarDayView
        local CalendarDayView = getUpValue(CalendarView.showCalendarDayView, "CalendarDayView")
        if not CalendarDayView or CalendarDayView._dot_pager_patched then return end
        CalendarDayView._dot_pager_patched = true

        safeWrap(CalendarDayView, "_populateBooks", function(orig_populateBooks, self, ...)
            orig_populateBooks(self, ...)
            if not self.page_info then return end
            if not self._dot_pager then
                self._dot_pager = DotPager:new{
                    height = self.footer_height or Screen:scaleBySize(BAR_HEIGHT),
                    get_state = function()
                        return self.show_page or 1, self.pages or 1
                    end,
                }
            end
            replaceGroupWithDots(self.page_info, self._dot_pager)
        end, TAG)
    end)

    -- Se exporta en Menu: styles/vocabbuilder.lua lo aplica a la clase cuando la
    -- encuentra (al cargar el plugin o, si no, al abrir el vocabulario)
    local function patchVocabFooter(VocabularyBuilderWidget)
        if type(VocabularyBuilderWidget) ~= "table" or VocabularyBuilderWidget._dot_pager_patched then return end
        VocabularyBuilderWidget._dot_pager_patched = true

        safeWrap(VocabularyBuilderWidget, "refreshFooter", function(orig_refreshFooter, self, ...)
            orig_refreshFooter(self, ...)
            if not self.page_info or #self.page_info < 7 then return end
            local center_w = 4 * (self.footer_button_width or 0) + (self.footer_center_width or 0)
            local first_item = self.page_info[1]
            local last_item = self.page_info[#self.page_info]
            -- Mismo alto que en las demás listas; más solo si están los botones
            -- de sincronizar o buscar (si no, en los lados hay huecos de alto 0)
            local h = Screen:scaleBySize(BAR_HEIGHT)
            for _i, side in ipairs({ first_item, last_item }) do
                local ok, sz = pcall(side.getSize, side)
                if ok and sz and sz.h > h then h = sz.h end
            end
            if not self._dot_pager then
                self._dot_pager = DotPager:new{
                    height = h,
                    get_state = function()
                        return self.show_page or 1, self.pages or 1
                    end,
                }
            else
                self._dot_pager.height = h
            end
            for i = #self.page_info, 1, -1 do
                self.page_info[i] = nil
            end
            self.page_info[1] = first_item
            self.page_info[2] = CenterContainer:new{
                dimen = Geom:new{ w = center_w, h = h },
                self._dot_pager,
            }
            self.page_info[3] = last_item
            self.page_info:resetLayout()
        end, TAG)
    end
    Menu._aire_patch_vocab_footer = patchVocabFooter

    safePluginPatch("vocabbuilder", function(plugin)
        local orig = plugin and (plugin._aire_orig_onShowVocabBuilder or plugin.onShowVocabBuilder)
        patchVocabFooter(getUpValue(orig, "VocabularyBuilderWidget"))
    end)
end
