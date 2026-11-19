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

local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local Menu = require("ui/widget/menu")
local logger = require("logger")
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Collections"
local AireUI = package.loaded.aire_ui
local S = AireUI.S

if FileManagerCollection._aire_coll_styled then return end
FileManagerCollection._aire_coll_styled = true

local ITEMS_PER_PAGE = 8


local function styleCollItem(item, item_w, item_h, pad_h, selected)
    local entry = item.entry
    if not entry or item._aire_coll_done then return end
    item._aire_coll_done = true
    -- Tarjeta común (common/list.lua): nombre en negrita (abre una lista) y, a
    -- la derecha, la casilla al elegir o el recuento; las elegidas, en gris
    local Lst = package.loaded.aire_list
    local card_w, card_h, gap_b = Lst.geometry(item_w, item_h, pad_h)
    local is_sel = selected ~= nil and selected[entry.name] ~= nil
    local right
    if selected then
        right = { check = is_sel }
    elseif entry.mandatory ~= nil and tostring(entry.mandatory) ~= "" then
        right = { text = tostring(entry.mandatory) }
    end
    local card = Lst.card({
        title = entry.text or "", bold = true,
        right = right,
        state = is_sel and "selected" or nil,
        h = card_h,
    }, card_w)
    Lst.place(item, card, item_w, pad_h, { gap = gap_b, item_h = item_h })
    item.onTapSelect = Lst.onTapFlash
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
            -- Filas con el margen común (common/list.lua)
            package.loaded.aire_list.eachItem(self, function(child, avail_w, ih, pad_h)
                styleCollItem(child, avail_w, ih, pad_h, manager.selected_collections)
            end, S(56))
        end, TAG)
        menu:updateItems(1)
    end)
    if not ok then logger.warn("Aire/Collections:", err) end
    return res
end, TAG)

logger.dbg("Aire/Collections: aplicado desde el plugin")
