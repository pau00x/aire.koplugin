--[[
    aire.koplugin/styles/bookmap.lua
    Rediseño moderno (Opción A) de BookMapWidget ("Mapa del libro"):
      - Cabecera unificada de pantalla completa (barra de estado + ‹ Mapa del libro + subtítulo)
      - Tarjeta resumen del capítulo actual (título, páginas restantes, marcadores)
      - Mapa de capítulos/páginas debajo con el ancho y separación del plugin
--]]

local Blitbuffer = require("ffi/blitbuffer")
local BookMapWidget = require("ui/widget/bookmapwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/BookMap"
local AireUI = package.loaded.aire_ui
local S = AireUI.S

if BookMapWidget._aire_styled then return end
BookMapWidget._aire_styled = true


do
    local BookMapRow = package.loaded.aire_ui.getUpValue(BookMapWidget.init, "BookMapRow")
    if BookMapRow and BookMapRow.init and not BookMapRow._aire_ind_patched then
        BookMapRow._aire_ind_patched = true
        BookMapRow.pages_frame_border = Size.border.thin
        BookMapRow.toc_span_border = Size.border.thin
        safeWrap(BookMapRow, "init", function(orig_row_init, self, ...)
            orig_row_init(self, ...)
            -- Cajas de capítulos y marco de páginas siempre redondeados y con bordes suaves
            if self.pages_frame then
                self.pages_frame.radius = S(6)
                self.pages_frame.color = Blitbuffer.COLOR_GRAY
                self.pages_frame._aire_clip_corners = true
                for _i, ch in ipairs(self.pages_frame) do
                    if type(ch) == "table" and ch.bordersize and ch.bordersize > 0 then
                        ch.radius = S(5)
                        ch.color = Blitbuffer.COLOR_GRAY
                        ch.background = Blitbuffer.COLOR_GRAY_E
                    end
                end
            end
            if type(self.indicators) == "table" and #self.indicators > 1 then
                local cur_idx
                for i, ind in ipairs(self.indicators) do
                    if ind.c == 0x25B2 then cur_idx = i break end
                end
                if cur_idx then
                    local cur = self.indicators[cur_idx]
                    for i, ind in ipairs(self.indicators) do
                        if i ~= cur_idx and math.abs(ind.x - cur.x) <= 2 then
                            cur.y = cur.y + math.floor((self.span_height or S(18)) * 0.45)
                            break
                        end
                    end
                end
            end
        end, TAG)
    end
end

local function buildCurrentChapterCard(bm)
    local sw = Screen:getWidth()
    local side = S(SIDE)
    local dock_w = sw - 2 * side
    local pad = S(10)
    local in_w = math.max(10, dock_w - 2 * (pad + Size.border.thin))

    local cur_page = bm.cur_page or (bm.ui and bm.ui.toc and bm.ui.toc.pageno) or 1
    local ch_title = (bm.ui and bm.ui.toc and bm.ui.toc.getTocTitleByPage
        and bm.ui.toc:getTocTitleByPage(cur_page)) or ""
    if ch_title == "" then ch_title = _("No chapter") end

    local left_pages = bm.ui and bm.ui.toc and bm.ui.toc.getChapterPagesLeft
        and bm.ui.toc:getChapterPagesLeft(cur_page)
    local anns = bm.ui and bm.ui.annotation and bm.ui.annotation.annotations
    local nb_marks = type(anns) == "table" and #anns or 0

    local sub_parts = {}
    if left_pages then
        table.insert(sub_parts, T(N_("%1 page left", "%1 pages left", left_pages), left_pages))
    end
    table.insert(sub_parts, T(N_("%1 bookmark", "%1 bookmarks", nb_marks), nb_marks))

    local vg = VerticalGroup:new{
        align = "left",
        TextWidget:new{
            text = _("CURRENT CHAPTER"),
            face = Font:getFace("cfont", 11),
            bold = true,
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            padding = 0,
        },
        VerticalSpan:new{ width = S(3) },
        TextBoxWidget:new{
            text = ch_title,
            face = Font:getFace("cfont", 15),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
            bgcolor = Blitbuffer.COLOR_GRAY_E,
            width = in_w,
        },
        VerticalSpan:new{ width = S(2) },
        TextWidget:new{
            text = table.concat(sub_parts, " · "),
            face = Font:getFace("cfont", 12),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            max_width = in_w,
            padding = 0,
        },
    }

    return CenterContainer:new{
        dimen = Geom:new{ w = sw, h = vg:getSize().h + 2 * (pad + Size.border.thin) },
        FrameContainer:new{
            width = dock_w,
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_GRAY,
            background = Blitbuffer.COLOR_GRAY_E,
            radius = S(10),
            padding = pad,
            LeftContainer:new{
                dimen = Geom:new{ w = in_w, h = vg:getSize().h },
                vg,
            },
        },
    }
end

safeWrap(BookMapWidget, "init", function(orig_init, self)
    local cur = self.ui and self.ui.toc and self.ui.toc.pageno or 1
    local total = self.ui and self.ui.document and self.ui.document:getPageCount() or 1
    local pct = total > 0 and math.floor(cur * 100 / total + 0.5) or 0
    local title_str = self.ui and self.ui.doc_props and self.ui.doc_props.display_title or ""
    local sub = title_str ~= ""
        and string.format("%s · %d %% (%d / %d)", title_str, pct, cur, total)
        or string.format("%d %% (%d / %d)", pct, cur, total)

    local own_tb_new, orig_tb_new = rawget(TitleBar, "new"), TitleBar.new
    TitleBar.new = function(cls, o)
        if type(o) == "table" and o.fullscreen then
            o.left_icon = "chevron.left"
            o.left_icon_tap_callback = function() self:onClose() end
            o.left_icon_hold_callback = function() self:onClose(true) end
            o.right_icon = "appbar.menu"
            o.right_icon_tap_callback = function() self:onShowBookMapMenu() end
            o.right_icon_hold_callback = not self.overview_mode and function() self:toggleDefaultSettings() end or nil
            o.close_callback = nil
            o.close_hold_callback = nil
            TitleBar._aire_pending_subtitle = sub
        end
        local res = orig_tb_new(cls, o)
        TitleBar._aire_pending_subtitle = nil
        return res
    end
    -- KOReader termina init() construyendo todo el mapa (update). Se aplaza
    -- hasta tener el alto y el ancho de Aire, para construirlo una sola vez.
    local had_own_update = rawget(self, "update")
    self.update = function() end
    local ok, err = pcall(orig_init, self)
    self.update = had_own_update
    rawset(TitleBar, "new", own_tb_new)
    if not ok then error(err) end

    local ok_c, card = pcall(buildCurrentChapterCard, self)
    if ok_c and card and self[1] and self[1][1] and self.cropping_widget then
        local sw = Screen:getWidth()
        local side = S(SIDE)
        local dock_w = sw - 2 * side
        local gap = S(10)
        local extra_h = card:getSize().h + gap
        local sb_w = self.scrollbar_width or 0
        self.crop_height = math.max(S(100), (self.crop_height or self.dimen.h) - extra_h)
        self.row_width = dock_w
        self.row_left_spacing = 0
        self.cropping_widget.dimen.w = dock_w + sb_w
        self.cropping_widget.dimen.h = self.crop_height
        if self.cropping_widget.resetLayout then self.cropping_widget:resetLayout() end
        -- Alinear row_width con dock_w (deja la scrollbar fuera, en el margen derecho)
        local vg_main = self[1][1]
        for i, child in ipairs(vg_main) do
            if child == self.cropping_widget then
                vg_main[i] = HorizontalGroup:new{
                    align = "top",
                    HorizontalSpan:new{ width = side },
                    self.cropping_widget,
                }
                break
            end
        end
        table.insert(vg_main, 2, card)
        table.insert(vg_main, 3, VerticalSpan:new{ width = gap })
        if vg_main.resetLayout then vg_main:resetLayout() end
    elseif not ok_c then
        logger.warn("Aire/BookMap:", card)
    end
    -- La única construcción del mapa (con o sin la tarjeta de Aire)
    self:update()
end, TAG)

-- Ocultar barras indicadoras de swipe lateral e inferior en Mapa del libro
function BookMapWidget:paintBottomHorizontalSwipeHint() end
function BookMapWidget:paintLeftVerticalSwipeHint() end

-- Corregir onTap para usar la posición real de cropping_widget (desplazada por la tarjeta y márgenes)
safeWrap(BookMapWidget, "onTap", function(_orig, self, arg, ges)
    if not self.cropping_widget or not self.cropping_widget.dimen or ges.pos:notIntersectWith(self.cropping_widget.dimen) then
        return true
    end
    local BD = require("ui/bidi")
    local Event = require("ui/event")
    local UIManager = require("ui/uimanager")
    local x = ges.pos.x - self.cropping_widget.dimen.x
    local y = ges.pos.y - self.cropping_widget.dimen.y
    local row = self:getVGroupRowAtY(y)
    if not row then return true end
    local page = row.toc_item_page
    if not page and row.start_page then
        if BD.mirroredUILayout() then
            x = x - (self.scrollbar_width or 0)
        end
        page = row:getPageAtX(x, true)
    end
    if page then
        if (self.overview_mode and G_reader_settings:isFalse("book_map_overview_tap_to_page_browser"))
                or (not self.overview_mode and G_reader_settings:isFalse("book_map_tap_to_page_browser")) then
            self:onClose(true)
            self.ui.link:addCurrentLocationToStack()
            self.ui:handleEvent(Event:new("GotoPage", page))
            return true
        end
        local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
        UIManager:show(PageBrowserWidget:new{
            launcher = self,
            ui = self.ui,
            focus_page = page,
        })
    end
    return true
end, TAG)

-- Convertir el menú flotante del mapa en bottom sheet unificada
safeWrap(BookMapWidget, "onShowBookMapMenu", function(orig_bm_menu, self)
    local ButtonDialog = require("ui/widget/buttondialog")
    local own_bd_new, orig_bd_new = rawget(ButtonDialog, "new"), ButtonDialog.new
    ButtonDialog.new = function(cls, o)
        if type(o) == "table" and o.anchor then
            o.anchor = nil
            o.shrink_unneeded_width = nil
            o.width = nil
            o.title = o.title or _("Book map")
            o.title_align = "left"
        end
        return orig_bd_new(cls, o)
    end
    local ok, err = pcall(orig_bm_menu, self)
    rawset(ButtonDialog, "new", own_bd_new)
    if not ok then error(err) end
end, TAG)

logger.dbg("Aire/BookMap: aplicado desde el plugin")
