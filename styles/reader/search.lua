--[[
    aire.koplugin/styles/reader/search.lua
    Rediseño moderno (Opción A + resumen arriba) de ReaderSearch ("Resultados de búsqueda"):
      - Tarjeta fija superior "BÚSQUEDA ACTIVA" con el término y total de coincidencias
      - Cada resultado en tarjeta blanca redondeada con "COINCIDENCIA N", página limpia
        a la derecha y fragmento de texto debajo
      - Subtítulo con Título · Autor
--]]

local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local ReaderSearch = require("apps/reader/modules/readersearch")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (ui/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Search"
local AireUI = package.loaded.aire_ui
local S, face, BLACK, GRAY_DARK, GRAY_CARD, GRAY_BORDER = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.GRAY_DARK, AireUI.GRAY_CARD, AireUI.GRAY_BORDER

if ReaderSearch._aire_search_styled then return end
ReaderSearch._aire_search_styled = true



local function buildSummaryCard(rs, avail_w, pad_h)
    local query = rs.last_search_text or ""
    local total = rs.findall_results and #rs.findall_results or 0
    local card_w = avail_w - 2 * pad_h
    local pad = S(package.loaded.aire_screen.LIST.CARD_PAD) -- (como las tarjetas de la lista)
    local in_w = card_w - 2 * pad - 2 * Size.border.thin

    local card = FrameContainer:new{
        width = card_w,
        bordersize = Size.border.thin,
        color = GRAY_BORDER,
        background = GRAY_CARD,
        radius = S(package.loaded.aire_screen.LIST.CARD_RADIUS), -- (tarjeta de lista: ui/screen.lua)
        padding = pad,
        VerticalGroup:new{
            align = "left",
            TextWidget:new{
                text = _("ACTIVE SEARCH"),
                face = face(true, package.loaded.aire_screen.LIST.META),
                fgcolor = GRAY_DARK,
                max_width = in_w,
                padding = 0,
            },
            VerticalSpan:new{ width = S(3) },
            TextWidget:new{
                text = T(N_("\"%1\" · %2 match", "\"%1\" · %2 matches", total), query, total),
                face = face(true, package.loaded.aire_screen.LIST.TITLE),
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
    -- Tarjeta común (ui/list.lua): "COINCIDENCIA N" arriba con la página a
    -- la derecha y el fragmento (hasta 3 líneas, normal: es un elemento final;
    -- KOReader da la palabra buscada en negrita) con el alto que necesite
    local Lst = package.loaded.aire_list
    local card_w, max_card_h, gap_b = Lst.geometry(item_w, item_h, pad_h)
    local dim = false
    if type(entry.mandatory_dim_func) == "function" then
        local ok, v = pcall(entry.mandatory_dim_func)
        dim = ok and v or false
    end
    local page_str = entry.mandatory and tostring(entry.mandatory) or ""
    local card = Lst.card({
        meta = entry.idx and string.format(_("MATCH %d"), entry.idx) or _("MATCH"),
        right = page_str ~= "" and { text = page_str, strong = not dim } or nil,
        title = entry.text or "", title_lines = "fill", title_max = 3,
        h = max_card_h, fit = true,
    }, card_w)
    Lst.place(item, card, item_w, pad_h, { gap = gap_b, fit = true, max_h = max_card_h })
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
            -- Filas con el margen común (ui/list.lua); arriba, la tarjeta fija
            local avail_w, pad_h = package.loaded.aire_list.eachItem(self, function(child, aw, ih, ph)
                styleSearchItem(child, aw, ih, ph)
            end, S(84))
            if self.item_table and #self.item_table > 0 then
                local hero = buildSummaryCard(self._search_owner, avail_w, pad_h)
                table.insert(self.item_group, 1, hero)
                self.item_group:resetLayout()
            end
        end, TAG)
        rm:updateItems(1)
        UIManager:setDirty(rm, "ui")
    end
    return res
end, TAG)

logger.dbg("Aire/Search: aplicado desde el plugin")
