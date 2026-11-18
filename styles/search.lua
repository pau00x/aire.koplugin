--[[
    aire.koplugin/styles/search.lua
    Rediseño moderno (Opción A + resumen arriba) de ReaderSearch ("Resultados de búsqueda"):
      - Tarjeta fija superior "BÚSQUEDA ACTIVA" con el término y total de coincidencias
      - Cada resultado en tarjeta blanca redondeada con "COINCIDENCIA N", página limpia
        a la derecha y fragmento de texto debajo
      - Subtítulo con Título · Autor
--]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderSearch = require("apps/reader/modules/readersearch")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Search"
local AireUI = package.loaded.aire_ui
local S, face, BLACK, WHITE, GRAY_DARK, GRAY_CARD, GRAY_BORDER, GRAY_LINE = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_CARD, AireUI.GRAY_BORDER, AireUI.GRAY_LINE

if ReaderSearch._aire_search_styled then return end
ReaderSearch._aire_search_styled = true



local function buildSummaryCard(rs, avail_w, pad_h)
    local query = rs.last_search_text or ""
    local total = rs.findall_results and #rs.findall_results or 0
    local card_w = avail_w - 2 * pad_h
    local pad = S(11)
    local in_w = card_w - 2 * pad - 2 * Size.border.thin

    local card = FrameContainer:new{
        width = card_w,
        bordersize = Size.border.thin,
        color = GRAY_BORDER,
        background = GRAY_CARD,
        radius = S(10),
        padding = pad,
        VerticalGroup:new{
            align = "left",
            TextWidget:new{
                text = _("ACTIVE SEARCH"),
                face = face(true, 10),
                fgcolor = GRAY_DARK,
                max_width = in_w,
                padding = 0,
            },
            VerticalSpan:new{ width = S(3) },
            TextWidget:new{
                text = T(N_("\"%1\" · %2 match", "\"%1\" · %2 matches", total), query, total),
                face = face(true, 14),
                fgcolor = BLACK,
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

-- Tarjeta con el alto de su contenido (fragmento hasta 3 líneas, sin pasar de
-- item_h): el MenuItem se encoge a ese alto (su dimen es también la zona táctil)
local function styleSearchItem(item, item_w, item_h, pad_h)
    local entry = item.entry
    if not entry or item._aire_search_card_done then return end
    item._aire_search_card_done = true

    local card_w = math.max(S(120), item_w - 2 * pad_h)
    local gap_b = S(8)
    local max_card_h = math.max(S(44), item_h - gap_b)
    local inner_pad = S(11)  -- igual que la tarjeta de resumen: textos alineados
    local in_w = card_w - 2 * inner_pad - 2 * Size.border.thin

    local dim = false
    if type(entry.mandatory_dim_func) == "function" then
        local ok, v = pcall(entry.mandatory_dim_func)
        dim = ok and v or false
    end
    local page_str = entry.mandatory and tostring(entry.mandatory) or ""
    local page_w = page_str ~= "" and TextWidget:new{
        text = page_str,
        face = face(false, 12),
        fgcolor = dim and GRAY_DARK or BLACK,
        padding = 0,
    } or nil
    local page_reserve = page_w and (page_w:getSize().w + S(8)) or 0
    local idx_lbl = entry.idx and string.format(_("MATCH %d"), entry.idx) or _("MATCH")
    local meta_w = TextWidget:new{
        text = idx_lbl,
        face = face(true, 10),
        fgcolor = GRAY_DARK,
        max_width = math.max(S(60), in_w - page_reserve),
        padding = 0,
    }
    local top_h = math.max(meta_w:getSize().h, page_w and page_w:getSize().h or 0)
    local top_og = OverlapGroup:new{
        dimen = Geom:new{ w = in_w, h = top_h },
        LeftContainer:new{ dimen = Geom:new{ w = in_w, h = top_h }, meta_w },
    }
    if page_w then
        table.insert(top_og, RightContainer:new{ dimen = Geom:new{ w = in_w, h = top_h }, page_w })
    end

    -- Fragmento (con la palabra buscada en negrita: KOReader lo da en "Poor Text Formatting")
    local text_face = face(false, 13)
    local text = entry.text or ""
    local tb = TextBoxWidget:new{ text = text, face = text_face, fgcolor = BLACK, width = in_w, padding = 0 }
    local lh = tb.line_height_px or S(18)
    local body_h = max_card_h - 2 * inner_pad - 2 * Size.border.thin - top_h - S(4)
    local max_lines = math.max(1, math.min(3, math.floor(body_h / lh)))
    if tb:getSize().h > max_lines * lh then
        tb:free()
        tb = TextBoxWidget:new{
            text = text, face = text_face, fgcolor = BLACK, width = in_w, padding = 0,
            height = max_lines * lh, height_overflow_show_ellipsis = true,
        }
    end

    local card = FrameContainer:new{
        width = card_w,
        bordersize = Size.border.thin,
        color = GRAY_LINE,
        background = WHITE,
        radius = S(10),
        padding = inner_pad,
        VerticalGroup:new{
            align = "left",
            top_og,
            VerticalSpan:new{ width = S(4) },
            tb,
        },
    }
    local card_h = math.min(max_card_h, card:getSize().h)

    item[1] = FrameContainer:new{
        width = item_w,
        height = card_h + gap_b,
        bordersize = 0,
        padding = 0,
        padding_left = pad_h,
        padding_right = pad_h,
        padding_bottom = gap_b,
        card,
    }
    if item.dimen then item.dimen.h = card_h + gap_b end
end

safeWrap(ReaderSearch, "onShowFindAllResults", function(orig_show, self, not_cached)
    local res = orig_show(self, not_cached)
    local rm = self.result_menu
    if rm and not rm._aire_search_hooked then
        rm._aire_search_hooked = true
        rm.with_dots = false
        rm.is_borderless = true
        rm._search_owner = self

        if rm.title_bar and rm.title_bar.setSubTitle then
            local sub = package.loaded.aire_ui.bookSubtitle(self.ui)
            if sub ~= "" then
                rm.title_bar._aire_default_subtitle = sub
                rm.title_bar:setSubTitle(sub, true)
            end
        end

        local sw = rm.dimen and rm.dimen.w or Screen:getWidth()
        local probe_w = (rm.inner_dimen and rm.inner_dimen.w) or sw
        local probe_pad = math.max(0, S(SIDE) - math.floor((sw - probe_w) / 2))
        local hero_h = buildSummaryCard(self, probe_w, probe_pad):getSize().h
        rm.items_per_page = 7
        rm.items_max_lines = nil

        -- Reservar el alto de la tarjeta superior. Solo cuando Menu ha
        -- recalculado de verdad (si no, available_height ya está descontado y
        -- se encogería en cada llamada). Con "máx. líneas por elemento"
        -- (items_max_lines) las páginas se reparten con available_height, así
        -- que se vuelven a calcular con el alto ya descontado.
        safeWrap(rm, "_recalculateDimen", function(orig_recalc, self, ...)
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
        rm._aire_avail_adjusted = nil
        rm:_recalculateDimen(false)

        safeWrap(rm, "updateItems", function(orig_update, self, select_number, ...)
            orig_update(self, select_number, ...)
            if not self.item_group then return end
            self.item_group.align = "left"
            local w = self.dimen and self.dimen.w or Screen:getWidth()
            local first_item = self.item_group[1]
            local avail_w = (first_item and first_item.dimen and first_item.dimen.w)
                or (self.inner_dimen and self.inner_dimen.w)
                or w
            local outer_pad = math.floor((w - avail_w) / 2)
            local pad_h = math.max(0, S(SIDE) - outer_pad)
            for _, child in ipairs(self.item_group) do
                if child and child.entry then
                    local ih = (child.dimen and child.dimen.h) or S(84)
                    styleSearchItem(child, avail_w, ih, pad_h)
                end
            end
            if self.item_table and #self.item_table > 0 then
                local hero = buildSummaryCard(self._search_owner, avail_w, pad_h)
                table.insert(self.item_group, 1, hero)
            end
            self.item_group:resetLayout()
        end, TAG)
        rm:updateItems(1)
        UIManager:setDirty(rm, "ui")
    end
    return res
end, TAG)

logger.dbg("Aire/Search: aplicado desde el plugin")
