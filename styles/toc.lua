--[[
    aire.koplugin/styles/toc.lua
    Rediseño moderno (Opción C + tarjetas) de ReaderToc ("Índice"):
      - Tarjeta fija arriba con "CAPÍTULO ACTUAL · PÁG. X", título y progreso
      - Cada entrada del índice como tarjeta redondeada con sangría por nivel,
        botón de expandir/colapsar y píldora de página a la derecha
      - Capítulo actual resaltado en gris claro con píldora negra
--]]

local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderToc = require("apps/reader/modules/readertoc")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Toc"
local AireUI = package.loaded.aire_ui
local S, face, BLACK, WHITE, GRAY_DARK, GRAY_CARD, GRAY_BORDER, GRAY_LINE = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_CARD, AireUI.GRAY_BORDER, AireUI.GRAY_LINE

if ReaderToc._aire_toc_styled then return end
ReaderToc._aire_toc_styled = true



local function buildHeroCard(toc, avail_w, pad_h)
    local ui = toc.ui
    local cur_page = toc.pageno or (ui and ui.getCurrentPage and ui:getCurrentPage()) or 1
    local total_pages = (ui and ui.document and ui.document.getPageCount and ui.document:getPageCount()) or 1
    local pct = math.max(0, math.min(100, math.floor((cur_page / math.max(1, total_pages)) * 100 + 0.5)))
    local ch_title = (toc.getTocTitleByPage and toc:getTocTitleByPage(cur_page)) or ""
    if ch_title == "" then
        local props = ui and ui.doc_props
        ch_title = (props and (props.display_title or props.title)) or _("No chapter")
    end
    local left_pages = toc.getChapterPagesLeft and toc:getChapterPagesLeft(cur_page)
    local sub_txt = left_pages and string.format(_("%d %% of book · %d pp. left in chapter"), pct, left_pages)
        or string.format(_("%d %% of book"), pct)

    local card_w = avail_w - 2 * pad_h
    local pad = S(11)
    local in_w = card_w - 2 * pad - 2 * Size.border.thin

    local card = FrameContainer:new{
        width = card_w,
        bordersize = Size.border.thin,
        color = GRAY_BORDER,
        background = GRAY_CARD,
        radius = S(package.loaded.aire_screen.LIST.CARD_RADIUS), -- (tarjeta de lista: common/screen.lua)
        padding = pad,
        VerticalGroup:new{
            align = "left",
            TextWidget:new{
                text = string.format(_("CURRENT CHAPTER · PAGE %d"), cur_page),
                face = face(true, 10),
                fgcolor = GRAY_DARK,
                max_width = in_w,
                padding = 0,
            },
            VerticalSpan:new{ width = S(3) },
            TextWidget:new{
                text = ch_title,
                face = face(true, 14),
                fgcolor = BLACK,
                max_width = in_w,
                padding = 0,
            },
            VerticalSpan:new{ width = S(2) },
            TextWidget:new{
                text = sub_txt,
                face = face(false, 12),
                fgcolor = GRAY_DARK,
                max_width = in_w,
                padding = 0,
            },
        },
    }
    return FrameContainer:new{
        width = avail_w,
        bordersize = 0,
        padding = 0,
        padding_left = pad_h,
        padding_right = pad_h,
        padding_bottom = S(8),
        card,
    }
end

local function styleTocMenuItem(item, item_w, item_h, pad_h, cur_ch_title)
    local entry = item.entry
    if not entry or item._aire_toc_card_done then return end
    item._aire_toc_card_done = true

    local depth = math.max(0, (tonumber(entry.depth) or 1) - 1)
    local indent = math.min(S(48), depth * S(16))
    -- Ancho de la tarjeta y hueco de debajo: los comunes (common/list.lua)
    local card_w, _card_max_h, gap_b = package.loaded.aire_list.geometry(item_w, item_h, pad_h, { indent = indent })
    local card_h = math.max(S(32), item_h - gap_b)
    local is_cur = entry.bold == true or (cur_ch_title and cur_ch_title ~= "" and entry.text == cur_ch_title)

    local inner_pad_h = S(12)
    local in_w = card_w - 2 * inner_pad_h - 2 * Size.border.thin
    local page_str = entry.mandatory and tostring(entry.mandatory) or ""

    local pill_w = 0
    local pill_wgt
    if page_str ~= "" then
        local pw_txt = TextWidget:new{
            text = page_str,
            face = face(is_cur, 13),
            fgcolor = is_cur and BLACK or GRAY_DARK,
            padding = 0,
        }
        pill_w = pw_txt:getSize().w + S(10)
        pill_wgt = pw_txt
    end

    local state_str = ""
    -- En KOReader entry.state es un botón: "control.collapse" = desplegado
    local st = entry.state
    if st == "expanded" or (type(st) == "table" and st.icon == "control.collapse") then
        state_str = "▾ "
    elseif entry.state then
        state_str = "▸ "
    end
    local title_txt = (state_str .. (entry.text or "")):gsub("^%s+", "")
    local title_w = TextWidget:new{
        text = title_txt,
        face = face(is_cur, 14), -- (solo el capítulo actual en negrita)
        fgcolor = entry.dim and GRAY_DARK or BLACK,
        max_width = math.max(S(60), in_w - pill_w),
        padding = 0,
    }

    local row_h = card_h - 2 * Size.border.thin
    local og = OverlapGroup:new{
        dimen = Geom:new{ w = in_w, h = row_h },
        LeftContainer:new{ dimen = Geom:new{ w = in_w, h = row_h }, title_w },
    }
    if pill_wgt then
        table.insert(og, RightContainer:new{ dimen = Geom:new{ w = in_w, h = row_h }, pill_wgt })
    end

    local card = FrameContainer:new{
        width = card_w,
        height = card_h,
        bordersize = Size.border.thin,
        color = is_cur and GRAY_BORDER or GRAY_LINE,
        background = is_cur and GRAY_CARD or WHITE,
        radius = S(package.loaded.aire_screen.LIST.CARD_RADIUS), -- (tarjeta de lista: common/screen.lua)
        padding = 0,
        padding_left = inner_pad_h,
        padding_right = inner_pad_h,
        og,
    }

    -- La tarjeta en la fila, con su margen y el hueco de debajo (common/list.lua)
    package.loaded.aire_list.place(item, card, item_w, pad_h, { gap = gap_b, item_h = item_h, indent = indent })
end

safeWrap(ReaderToc, "onShowToc", function(orig_onShowToc, self)
    local res = orig_onShowToc(self)
    local tm = self.toc_menu
    if tm and not tm._aire_toc_hooked then
        tm._aire_toc_hooked = true
        tm.with_dots = false
        tm.is_borderless = true
        tm._toc_owner = self

        -- Mantener pulsado un capítulo: KOReader enseña el título completo en un
        -- aviso centrado con su letra. Aquí, solo el título completo, alineado
        -- a la izquierda con la letra de Aire.
        if Device:isTouchDevice() then
            tm.onMenuHold = function(_menu, item)
                if not item then return true end
                local InfoMessage = require("ui/widget/infomessage")
                local txt = tostring(item.text or ""):gsub("^%s+", "")
                UIManager:show(InfoMessage:new{
                    text = txt,
                    show_icon = false,
                    alignment = "left",
                    face = Font:getFace("cfont", 16),
                })
                return true
            end
        end

        -- Subtítulo: título · autor (cuando no hay búsqueda activa)
        if tm.title_bar and tm.title_bar.setSubTitle and (not self.search_string or self.search_string == "") then
            local sub = package.loaded.aire_ui.bookSubtitle(self.ui)
            if sub ~= "" then
                tm.title_bar._aire_default_subtitle = sub
                tm.title_bar:setSubTitle(sub, true)
            end
        end

        -- Ajustar _recalculateDimen para reservar el alto real de la tarjeta superior
        -- sin invadir el espacio del paginado inferior (DotPager)
        local sw = tm.dimen and tm.dimen.w or Screen:getWidth()
        local probe_w = (tm.inner_dimen and tm.inner_dimen.w) or sw
        local probe_pad = math.max(0, S(SIDE) - math.floor((sw - probe_w) / 2))
        local hero_h = buildHeroCard(self, probe_w, probe_pad):getSize().h
        local base_perpage = tm.items_per_page or tm.perpage or 10
        tm.items_per_page = math.max(4, base_perpage - 2)

        -- Reservar el alto de la tarjeta superior. Solo cuando Menu ha
        -- recalculado de verdad (si no, available_height ya está descontado y
        -- se encogería en cada llamada). Con "máx. líneas por elemento"
        -- (items_max_lines) las páginas se reparten con available_height, así
        -- que se vuelven a calcular con el alto ya descontado.
        safeWrap(tm, "_recalculateDimen", function(orig_recalc, self, ...)
            orig_recalc(self, ...)
            if not (self.available_height and self.perpage and self.perpage > 0 and self.item_dimen) then return end
            if self.available_height == self._aire_avail_adjusted then return end
            self.available_height = math.max(S(160), self.available_height - hero_h - S(8))
            self._aire_avail_adjusted = self.available_height
            if self.items_max_lines and self.setupItemHeights then
                self:setupItemHeights()
                self.page_num = self:getPageNumber(#self.item_table)
                if self.page > self.page_num then self.page = self.page_num end
            else
                self.item_dimen.h = math.floor(self.available_height / self.perpage)
            end
        end, TAG)
        tm._aire_avail_adjusted = nil
        tm:_recalculateDimen(false)
        -- Con menos elementos por página, la página que eligió KOReader para
        -- el capítulo actual ya no vale: recalcularla
        local cur_idx = self.collapsed_toc and self.collapsed_toc.current
        if cur_idx and cur_idx > 0 and tm.getPageNumber then
            tm.page = tm:getPageNumber(cur_idx)
        end

        safeWrap(tm, "updateItems", function(orig_update, self, select_number, ...)
            orig_update(self, select_number, ...)
            if not self.item_group then return end
            local owner = self._toc_owner
            local cp = owner and (owner.pageno or (owner.ui and owner.ui.getCurrentPage and owner.ui:getCurrentPage()))
            local cur_ch = owner and owner.getTocTitleByPage and cp and owner:getTocTitleByPage(cp)
            -- Filas con el margen común (common/list.lua); arriba, la tarjeta fija
            local avail_w, pad_h = package.loaded.aire_list.eachItem(self, function(child, aw, ih, ph)
                styleTocMenuItem(child, aw, ih, ph, cur_ch)
            end, S(52))
            local hero = buildHeroCard(owner, avail_w, pad_h)
            table.insert(self.item_group, 1, hero)
            self.item_group:resetLayout()
        end, TAG)
        tm:updateItems(1)
        UIManager:setDirty(tm, "ui")
    end
    return res
end, TAG)

logger.dbg("Aire/Toc: aplicado desde el plugin")
