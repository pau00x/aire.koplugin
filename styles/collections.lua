--[[
    aire.koplugin/styles/collections.lua
    Lista de colecciones de KOReader (FileManagerCollection:onShowCollList),
    la que se abre con "Colecciones…" en la ficha de un libro (elegir en qué
    colecciones está) y desde el menú de KOReader. Se carga una vez desde main.lua.

      - Cada colección en una tarjeta redondeada, como Índice o Marcadores.
      - Al elegir: casilla redonda de Aire a la derecha; las marcadas, en gris.
        Arriba, las tres rayas (en KOReader un ✓) abren el menú de siempre
        (nueva colección, seleccionar todo / nada, aplicar selección).
      - Lista normal: nº de libros (y marcas de KOReader) en gris a la derecha.
      - Al tocar una colección, la tarjeta se pone gris un momento (KOReader
        invertía todo el rectángulo en negro, con las esquinas cuadradas).
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Menu = require("ui/widget/menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = Device.screen
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Collections"
local AireUI = package.loaded.aire_ui
local S, BLACK, WHITE, GRAY_DARK, GRAY_CARD, GRAY_BORDER, GRAY_LINE = AireUI.S, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_CARD, AireUI.GRAY_BORDER, AireUI.GRAY_LINE

if FileManagerCollection._aire_coll_styled then return end
FileManagerCollection._aire_coll_styled = true

local ITEMS_PER_PAGE = 8


-- Toque: la tarjeta en gris un momento y luego lo de KOReader
local function onTapCard(item, _arg, ges)
    if not item[1] or not item[1].dimen then return end
    local pos = item:getGesPosition(ges)
    local card = item._aire_card
    if card and G_reader_settings:nilOrTrue("flash_ui") then
        local old = card.background
        card.background = Blitbuffer.COLOR_LIGHT_GRAY
        UIManager:widgetRepaint(item[1], item[1].dimen.x, item[1].dimen.y)
        UIManager:setDirty(nil, "fast", item[1].dimen)
        UIManager:forceRePaint()
        card.background = old
    end
    item.menu:onMenuSelect(item.entry, pos)
    return true
end

local function styleCollItem(item, item_w, item_h, pad_h, selected)
    local entry = item.entry
    if not entry or item._aire_coll_done then return end
    item._aire_coll_done = true

    local gap_b = S(8)
    local card_w = math.max(S(120), item_w - 2 * pad_h)
    local card_h = math.max(S(36), item_h - gap_b)
    local inner_pad = S(14)
    local in_w = card_w - 2 * inner_pad - 2 * Size.border.thin
    local row_h = card_h - 2 * Size.border.thin
    local is_sel = selected ~= nil and selected[entry.name] ~= nil

    local right
    if selected then
        local sz = S(24)
        right = IconWidget:new{ icon = is_sel and "aire.checkbox.on" or "aire.checkbox.off",
            width = sz, height = sz, alpha = true }
    elseif entry.mandatory ~= nil and tostring(entry.mandatory) ~= "" then
        right = TextWidget:new{ text = tostring(entry.mandatory), face = Font:getFace("cfont", 14),
            fgcolor = GRAY_DARK, padding = 0 }
    end
    local right_w = right and (right:getSize().w + S(10)) or 0
    local title = TextWidget:new{
        text = entry.text or "",
        face = Font:getFace("tfont", 15),
        fgcolor = BLACK,
        max_width = math.max(S(60), in_w - right_w),
        padding = 0,
    }
    local og = OverlapGroup:new{
        dimen = Geom:new{ w = in_w, h = row_h },
        LeftContainer:new{ dimen = Geom:new{ w = in_w, h = row_h }, title },
    }
    if right then
        table.insert(og, RightContainer:new{ dimen = Geom:new{ w = in_w, h = row_h }, right })
    end
    local card = FrameContainer:new{
        width = card_w,
        height = card_h,
        bordersize = Size.border.thin,
        color = is_sel and GRAY_BORDER or GRAY_LINE,
        background = is_sel and GRAY_CARD or WHITE,
        radius = S(10),
        padding = 0,
        padding_left = inner_pad,
        padding_right = inner_pad,
        og,
    }
    item._aire_card = card
    item.onTapSelect = onTapCard
    item[1] = FrameContainer:new{
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

safeWrap(FileManagerCollection, "onShowCollList", function(orig_show, self, ...)
    -- Tres rayas en vez del ✓ (se cambia al crear la lista: la barra de título
    -- de Aire ya está montada cuando KOReader la enseña)
    local own_new = rawget(Menu, "new")
    local base_new = Menu.new
    rawset(Menu, "new", function(cls, o)
        if type(o) == "table" and o.title_bar_left_icon == "check" then
            o.title_bar_left_icon = "appbar.menu"
        end
        return base_new(cls, o)
    end)
    local ok_s, res = pcall(orig_show, self, ...)
    rawset(Menu, "new", own_new)
    if not ok_s then error(res, 0) end

    local menu = self.coll_list
    if not menu or menu._aire_coll_hooked then return res end
    menu._aire_coll_hooked = true
    local manager = self
    local ok, err = pcall(function()
        menu.items_per_page = ITEMS_PER_PAGE
        menu.items_max_lines = nil
        if menu._recalculateDimen then menu:_recalculateDimen(false) end
        safeWrap(menu, "updateItems", function(orig_update, self, select_number, ...)
            orig_update(self, select_number, ...)
            if not self.item_group then return end
            self.item_group.align = "left"
            local w = self.dimen and self.dimen.w or Screen:getWidth()
            local first = self.item_group[1]
            local avail_w = (first and first.dimen and first.dimen.w) or (self.inner_dimen and self.inner_dimen.w) or w
            local pad_h = math.max(0, S(16) - math.floor((w - avail_w) / 2))
            for _i, child in ipairs(self.item_group) do
                if child and child.entry then
                    styleCollItem(child, avail_w, (child.dimen and child.dimen.h) or S(56), pad_h,
                        manager.selected_collections)
                end
            end
            self.item_group:resetLayout()
        end, TAG)
        menu:updateItems(1)
    end)
    if not ok then logger.warn("Aire/Collections:", err) end
    return res
end, TAG)

logger.dbg("Aire/Collections: aplicado desde el plugin")
