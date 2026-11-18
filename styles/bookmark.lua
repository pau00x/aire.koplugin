--[[
    aire.koplugin/styles/bookmark.lua
    Rediseño moderno (Opción C sin píldora) de ReaderBookmark ("Marcadores y notas"):
      - Cada marcador en tarjeta blanca redondeada (radius S(10), borde gris fino)
        con el alto de su contenido (hasta 6 por página)
      - Cabecera superior: TIPO · CAPÍTULO · FECHA (traducida) a la izquierda y página (sin píldora) a la derecha
      - Cita en negrita y bloque gris interior si tiene nota personal
      - Subtítulo con Título · Autor cuando no hay filtro activo
--]]

local datetime = require("datetime")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ReaderBookmark = require("apps/reader/modules/readerbookmark")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local METRICS = package.loaded.aire_screen.METRICS -- medidas comunes (common/screen.lua)
local SIDE = METRICS.SIDE
local AireUI = package.loaded.aire_ui
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Bookmark"
local S, face, BLACK, WHITE, GRAY_DARK, GRAY_CARD, GRAY_LINE = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_CARD, AireUI.GRAY_LINE

if ReaderBookmark._aire_bm_styled then return end
ReaderBookmark._aire_bm_styled = true



local TYPE_LABELS = {
    note = _("NOTE"),
    highlight = _("HIGHLIGHT"),
    bookmark = _("BOOKMARK"),
}

-- "2026-11-17 18:43:00" -> fecha corta traducida por KOReader (día de la semana, mes, día, año)
local function shortDate(dt)
    local y, m, d = dt:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if not y then return dt:sub(1, 10) end
    local secs = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    local ok, str = pcall(datetime.secondsToDate, secs, true)
    return ok and str or dt:sub(1, 10)
end

-- Mantener pulsado: la tarjeta en negro un momento y los detalles. KOReader
-- invertía un rectángulo que ya no coincide con la tarjeta (franja negra) y no
-- hacía nada si aún no tenía su posición; en el Kindle no se abrían.
local function onHoldCard(item, _arg, ges)
    -- Solo la tarjeta en negro (común a las listas: styles/ui/titlebar.lua)
    local flash = require("ui/widget/menu")._aire_flashCard
    if flash then pcall(flash, item._aire_bm_card) end
    local ok, err = pcall(item.menu.onMenuHold, item.menu, item.entry, item:getGesPosition(ges))
    if not ok then logger.warn("Aire/Bookmark: mantener pulsado:", err) end
    return true
end

-- Tarjeta con el alto de su contenido (hasta item_h): KOReader reparte el alto
-- de la página entre items_per_page y las tarjetas cortas dejaban mucho hueco.
-- El MenuItem se encoge al alto de la tarjeta (su dimen es también la zona táctil).
local function styleBookmarkItem(item, item_w, item_h, pad_h)
    local entry = item.entry
    if not entry or item._aire_bm_card_done then return end
    item._aire_bm_card_done = true

    local card_w = math.max(S(120), item_w - 2 * pad_h)
    local gap_b = S(8)
    local max_card_h = math.max(S(44), item_h - gap_b)
    local inner_pad = S(11)
    local in_w = card_w - 2 * inner_pad - 2 * Size.border.thin

    local btype = entry.type
    local type_lbl = TYPE_LABELS[btype] or (entry.note and TYPE_LABELS.note) or TYPE_LABELS.bookmark
    local meta_parts = { type_lbl }
    if type(entry.chapter) == "string" and entry.chapter ~= "" then table.insert(meta_parts, entry.chapter) end
    if type(entry.datetime) == "string" and entry.datetime ~= "" then
        table.insert(meta_parts, shortDate(entry.datetime))
    end

    local page_str = entry.mandatory and tostring(entry.mandatory) or ""
    local page_w = page_str ~= "" and TextWidget:new{
        text = page_str,
        face = face(entry.bold, 12),
        fgcolor = entry.bold and BLACK or GRAY_DARK,
        padding = 0,
    } or nil
    local page_reserve = page_w and (page_w:getSize().w + S(8)) or 0
    local meta_w = TextWidget:new{
        text = table.concat(meta_parts, " · "),
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

    -- Texto principal: el subrayado sin el icono ni la nota que KOReader le añade
    -- (entry.text); la nota va solo en el recuadro gris
    local main_txt = entry.text_orig
    if type(main_txt) ~= "string" or main_txt == "" then main_txt = entry.text or "" end
    local note_txt = type(entry.note) == "string" and entry.note ~= "" and entry.note or nil

    local function textBox(text, fc, color, w, lines, bg)
        local tb = TextBoxWidget:new{ text = text, face = fc, fgcolor = color, bgcolor = bg, width = w, padding = 0 }
        local lh = tb.line_height_px or S(16)
        if lines and tb:getSize().h > lines * lh then
            tb:free()
            tb = TextBoxWidget:new{
                text = text, face = fc, fgcolor = color, bgcolor = bg, width = w, padding = 0,
                height = lines * lh, height_overflow_show_ellipsis = true,
            }
        end
        return tb, lh
    end

    -- Alto disponible bajo la cabecera, repartido: nota hasta 2 líneas, el resto para el subrayado
    local body_h = max_card_h - 2 * inner_pad - 2 * Size.border.thin - top_h - S(4)
    local note_box
    if note_txt then
        local note_pad = S(6)
        local probe = TextBoxWidget:new{ text = "X", face = face(false, 12), width = in_w, padding = 0 }
        local nlh = probe.line_height_px or S(16)
        probe:free()
        local note_lines = (body_h - S(6) - 2 * note_pad >= 4 * nlh) and 2 or 1
        local note_tb = textBox(note_txt, face(false, 12), GRAY_DARK, in_w - 2 * note_pad, note_lines, GRAY_CARD)
        note_box = FrameContainer:new{
            width = in_w,
            bordersize = 0,
            background = GRAY_CARD,
            radius = S(6),
            padding = note_pad,
            note_tb,
        }
        body_h = body_h - note_box:getSize().h - S(6)
    end
    local main_face = face(true, 13)
    local probe = TextBoxWidget:new{ text = "X", face = main_face, width = in_w, padding = 0 }
    local mlh = probe.line_height_px or S(18)
    probe:free()
    local main_tb = textBox(main_txt, main_face, entry.mandatory_dim and GRAY_DARK or BLACK, in_w,
        math.max(1, math.floor(body_h / mlh)))

    local body_vg = VerticalGroup:new{
        align = "left",
        top_og,
        VerticalSpan:new{ width = S(4) },
        main_tb,
    }
    if note_box then
        table.insert(body_vg, VerticalSpan:new{ width = S(6) })
        table.insert(body_vg, note_box)
    end

    local card = FrameContainer:new{
        width = card_w,
        bordersize = Size.border.thin,
        color = GRAY_LINE,
        background = WHITE,
        radius = S(10),
        padding = inner_pad,
        body_vg,
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
    item._aire_bm_card = card
    item.onHoldSelect = onHoldCard
end

safeWrap(ReaderBookmark, "onShowBookmark", function(orig_onShowBookmark, self, ...)
    local res = orig_onShowBookmark(self, ...)
    local bm_menu = self.bookmark_menu and self.bookmark_menu[1]
    if bm_menu and not bm_menu._aire_bm_hooked then
        bm_menu._aire_bm_hooked = true
        bm_menu.with_dots = false
        bm_menu.is_borderless = true
        bm_menu.items_per_page = 6
        bm_menu.items_max_lines = nil
        if bm_menu._recalculateDimen then bm_menu:_recalculateDimen(false) end

        if bm_menu.title_bar and bm_menu.title_bar.setSubTitle then
            local sub = package.loaded.aire_ui.bookSubtitle(self.ui)
            if sub ~= "" then
                bm_menu.title_bar._aire_default_subtitle = sub
                if not bm_menu.subtitle or bm_menu.subtitle == "" then
                    bm_menu.title_bar:setSubTitle(sub, true)
                end
            end
        end

        safeWrap(bm_menu, "updateItems", function(orig_update, self, select_number, ...)
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
                    styleBookmarkItem(child, avail_w, ih, pad_h)
                end
            end
            self.item_group:resetLayout()
        end, TAG)
        bm_menu:updateItems(1)
        UIManager:setDirty(bm_menu, "ui")
    end
    return res
end, TAG)

--===========================================================================
-- Detalles de un marcador (mantener pulsado en la lista, o desde el lector):
-- hoja inferior con la misma tarjeta que la lista (tipo · capítulo · fecha,
-- página, texto y nota en gris), acciones en píldoras ("Ir al marcador" en
-- negro) y los puntos de página abajo: deslizar a los lados cambia de
-- marcador. Mismas acciones y mismas actualizaciones que el TextViewer de KOReader.
--===========================================================================
local BottomContainer = require("ui/widget/container/bottomcontainer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")

-- Pantallas comunes (common/pages.lua, cargado una vez en main.lua)
local function getP() return package.loaded.aire_pages end

local DetailsSheet = InputContainer:extend{ modal = true }

function DetailsSheet:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        AireTapOut = { GestureRange:new{ ges = "tap", range = self.dimen } },
        AireSwipe = { GestureRange:new{ ges = "swipe", range = self.dimen } },
    }
    if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
end
function DetailsSheet:onAireTapOut(_arg, ges)
    if self.frame and self.frame.dimen and ges and ges.pos and not ges.pos:intersectWith(self.frame.dimen) then
        self:onClose()
    end
    return true
end
function DetailsSheet:onAireSwipe(_arg, ges)
    local dir = ges and ges.direction
    if dir == "west" and self.on_next then self.on_next() return true end
    if dir == "east" and self.on_prev then self.on_prev() return true end
    if dir == "south" then self:onClose() return true end
    return true
end
-- Al mostrarse, pedir refresco de pantalla: UIManager:show sin tipo solo la
-- pinta en memoria y en el Kindle no aparecía (en las capturas sí)
function DetailsSheet:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame and self.frame.dimen end)
end
function DetailsSheet:onClose()
    UIManager:close(self)
    if self.close_callback then self.close_callback() end
    return true
end
function DetailsSheet:onCloseWidget()
    UIManager:setDirty(nil, function() return "ui", self.frame and self.frame.dimen end)
end

local function showDetailsSheet(bookmark, item_or_index)
    local P = getP()
    local bm_menu = bookmark.bookmark_menu and bookmark.bookmark_menu[1]
    local item_table, item, item_idx
    if bm_menu then
        item_table = bm_menu.item_table
        item = item_or_index
        item_idx = item.idx
    else
        item_table = bookmark.ui.annotation.annotations
        item_idx = item_or_index
        item = item_table[item_idx]
    end
    if not item then return false end
    local items_nb = #item_table
    local not_select_mode = not (bm_menu and bm_menu.select_count) and not bookmark.ui.highlight.select_mode

    local sheet
    local function reopen(idx)
        UIManager:close(sheet)
        if bm_menu then
            bookmark:updateBookmarkList(nil, idx)
            bookmark:showBookmarkDetails(item_table[idx])
        else
            bookmark:showBookmarkDetails(idx)
        end
    end
    local function edit_details_callback()
        bookmark.details_updated = true
        UIManager:close(sheet)
        bookmark:showBookmarkDetails(item_or_index)
    end
    local function close_callback()
        if bookmark.details_updated then
            bookmark.details_updated = nil
            if bm_menu then
                if bookmark.show_edited_only then
                    for i = items_nb, 1, -1 do
                        if not item_table[i].text_edited then table.remove(item_table, i) end
                    end
                end
                bookmark:updateBookmarkList(item_table, -1)
            elseif bookmark.view.highlight.note_mark then
                UIManager:setDirty(bookmark.dialog, "ui")
            end
        end
    end

    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local style = ButtonDialog.aire_sheet_style or { margin = 6, radius = 14, pad = 14 }
    local sheet_w = ButtonDialog.aire_sheetWidth and ButtonDialog.aire_sheetWidth() or (sw - 2 * S(6))
    local pad = S(style.pad or 14)
    local in_w = sheet_w - 2 * pad - 2 * Size.border.thin

    -- Cabecera: TIPO · capítulo · fecha y la página a la derecha
    local btype = ReaderBookmark.getBookmarkType(item)
    local meta = { TYPE_LABELS[btype] or TYPE_LABELS.bookmark }
    if type(item.chapter) == "string" and item.chapter ~= "" then table.insert(meta, item.chapter) end
    if type(item.datetime) == "string" and item.datetime ~= "" then table.insert(meta, shortDate(item.datetime)) end
    local page_str = item.mandatory or (bookmark.getBookmarkPageString and bookmark:getBookmarkPageString(item.page)) or ""
    local page_w = TextWidget:new{ text = tostring(page_str), face = face(false, 12), fgcolor = GRAY_DARK, padding = 0 }
    local meta_w = TextWidget:new{ text = table.concat(meta, " · "), face = face(true, 10), fgcolor = GRAY_DARK,
        max_width = in_w - page_w:getSize().w - S(8), padding = 0 }
    local top_h = math.max(meta_w:getSize().h, page_w:getSize().h)
    local text = item.text_orig or item.text or ""
    local note = type(item.note) == "string" and item.note ~= "" and item.note or nil

    local content = VerticalGroup:new{
        align = "left",
        OverlapGroup:new{
            dimen = Geom:new{ w = in_w, h = top_h },
            LeftContainer:new{ dimen = Geom:new{ w = in_w, h = top_h }, meta_w },
            RightContainer:new{ dimen = Geom:new{ w = in_w, h = top_h }, page_w },
        },
        VerticalSpan:new{ width = S(6) },
        P.text(text, in_w, { bold = true, size = 14, max_lines = 8 }),
    }
    if note then
        local npad = S(8)
        table.insert(content, VerticalSpan:new{ width = S(8) })
        table.insert(content, FrameContainer:new{
            width = in_w, bordersize = 0, background = GRAY_CARD, radius = S(8), padding = npad,
            P.text(note, in_w - 2 * npad, { size = 13, color = GRAY_DARK, bgcolor = GRAY_CARD, max_lines = 5 }),
        })
    end
    -- Acciones
    local gap = S(8)
    local half = math.floor((in_w - gap) / 2)
    table.insert(content, VerticalSpan:new{ width = S(14) })
    table.insert(content, HorizontalGroup:new{
        align = "center",
        P.pill(note and _("Edit note") or _("Add note"), half, function()
            bookmark:setBookmarkNote(item_or_index, nil, nil, edit_details_callback)
        end, { disabled = not not_select_mode }),
        HorizontalSpan:new{ width = gap },
        P.pill(_("Edit text"), half, function()
            bookmark:editHighlightedText(item_or_index, edit_details_callback)
        end, { disabled = not (item.drawer and not_select_mode),
               on_hold = item.text_edited and not_select_mode and function()
                   bookmark:setHighlightedText(item_or_index, nil, edit_details_callback)
               end or nil }),
    })
    table.insert(content, VerticalSpan:new{ width = gap })
    table.insert(content, HorizontalGroup:new{
        align = "center",
        P.pill(_("Remove bookmark"), half, function()
            UIManager:show(ConfirmBox:new{
                text = _("Remove this bookmark?"),
                ok_text = _("Remove"),
                ok_callback = function()
                    UIManager:close(sheet)
                    bookmark:removeItem(item, not bm_menu and item_idx)
                    if bm_menu then
                        table.remove(item_table, item_idx)
                        bookmark:updateBookmarkList(item_table, -1)
                    end
                end,
            })
        end, { disabled = not not_select_mode }),
        HorizontalSpan:new{ width = gap },
        P.pill(_("Go to bookmark"), half, function()
            UIManager:close(sheet)
            close_callback()
            bookmark.ui.link:addCurrentLocationToStack()
            bookmark:gotoBookmark(item.page, item.pos0)
            if bm_menu then bm_menu.close_callback() end
        end, { primary = true, disabled = bm_menu and bm_menu.select_count ~= nil }),
    })
    -- Puntos de página (deslizar para cambiar de marcador)
    local DotPager = require("ui/widget/menu")._aire_dot_pager_cls
    if DotPager and items_nb > 1 then
        table.insert(content, VerticalSpan:new{ width = S(8) })
        table.insert(content, CenterContainer:new{
            dimen = Geom:new{ w = in_w, h = S(METRICS.DOTS_H) },
            DotPager:new{ height = S(METRICS.DOTS_H), get_state = function() return item_idx, items_nb end },
        })
    end

    sheet = DetailsSheet:new{
        close_callback = close_callback,
        on_prev = item_idx > 1 and function() reopen(item_idx - 1) end or nil,
        on_next = item_idx < items_nb and function() reopen(item_idx + 1) end or nil,
    }
    sheet.frame = FrameContainer:new{
        width = sheet_w, bordersize = Size.border.thin, color = BLACK, background = WHITE,
        radius = S(style.radius or 14), padding = pad, content,
    }
    sheet[1] = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh - S(style.margin or 6) },
        sheet.frame,
    }
    UIManager:show(sheet)
    return true
end

safeWrap(ReaderBookmark, "showBookmarkDetails", function(orig_details, self, item_or_index, ...)
    local ok, res = pcall(showDetailsSheet, self, item_or_index)
    if ok and res then return true end
    if not ok then logger.warn("Aire/Bookmark: detalles:", res) end
    return orig_details(self, item_or_index, ...)
end, TAG)

logger.dbg("Aire/Bookmark: aplicado desde el plugin")
