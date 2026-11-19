--[[
    aire.koplugin/common/list.lua
    Listas de contenido de Aire (las de KOReader que Aire pasa a tarjetas:
    Índice, Marcadores, Búsqueda, Atajos, Colecciones, explorador en lista…):
    lo que comparten, en un solo sitio. Medidas en common/screen.lua (LIST).

      eachItem(menu, fn, default_h)  recorre las filas de un Menu con el margen
                                     común: fn(item, item_w, item_h, pad_h)
      geometry(item_w, item_h, pad_h, opts)  ancho de la tarjeta, alto máximo y
                                     hueco de debajo
      cardFrame(content, w, h, opts) marco de la tarjeta (radio, borde, colores
                                     de "actual" y "seleccionada")
      place(item, card, item_w, pad_h, opts)  coloca la tarjeta en la fila, con
                                     su margen y el hueco de debajo
      onTapFlash                     tocar: la tarjeta en gris un momento

    Cada lista monta el contenido de su tarjeta; esto es lo que tienen igual.
    Se carga una vez desde main.lua en package.loaded.aire_list.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local AireScreen = package.loaded.aire_screen

local M = {}

local function S(n) return Screen:scaleBySize(n) end
local function LM() return AireScreen.LIST end

-- Recorre las filas (MenuItem) de un Menu. KOReader ya deja un margen a los
-- lados de item_group: pad_h es lo que falta para llegar al margen común
-- (METRICS.SIDE). Al terminar, vuelve a medir item_group. Devuelve el ancho
-- de las filas y pad_h (para lo que se añada aparte, p. ej. una tarjeta fija).
function M.eachItem(menu, fn, default_h)
    if not (menu and menu.item_group) then return end
    menu.item_group.align = "left"
    local w = menu.dimen and menu.dimen.w or Screen:getWidth()
    local first = menu.item_group[1]
    local avail_w = (first and first.dimen and first.dimen.w)
        or (menu.inner_dimen and menu.inner_dimen.w)
        or w
    local pad_h = math.max(0, S(AireScreen.METRICS.SIDE) - math.floor((w - avail_w) / 2))
    for _i, child in ipairs(menu.item_group) do
        if child and child.entry then
            local ih = (child.dimen and child.dimen.h) or default_h or S(52)
            fn(child, avail_w, ih, pad_h)
        end
    end
    if menu.item_group.resetLayout then menu.item_group:resetLayout() end
    return avail_w, pad_h
end

-- Ancho de la tarjeta, alto máximo (el de la fila menos el hueco) y hueco
--   opts.indent  sangría a la izquierda (Índice)
--   opts.min_h   alto mínimo de la tarjeta
function M.geometry(item_w, item_h, pad_h, opts)
    opts = opts or {}
    local gap = S(LM().CARD_GAP)
    local card_w = math.max(S(LM().CARD_MIN_W), item_w - 2 * pad_h - (opts.indent or 0))
    local card_h = math.max(opts.min_h or S(28), item_h - gap)
    return card_w, card_h, gap
end

-- Marco de la tarjeta
--   opts.state   "current" (gris claro, borde gris) | "selected" (igual) | nil
--   opts.pad     relleno en los cuatro lados; o pad_h / pad_v por separado
function M.cardFrame(content, w, h, opts)
    opts = opts or {}
    local marked = opts.state == "current" or opts.state == "selected"
    local f = FrameContainer:new{
        width = w,
        height = h,
        bordersize = Size.border.thin,
        color = marked and Blitbuffer.COLOR_GRAY_B or Blitbuffer.COLOR_GRAY_D,
        background = marked and Blitbuffer.COLOR_GRAY_E or Blitbuffer.COLOR_WHITE,
        radius = S(LM().CARD_RADIUS),
        padding = opts.pad or 0,
        content,
    }
    if not opts.pad then
        f.padding_left, f.padding_right = opts.pad_h or 0, opts.pad_h or 0
        f.padding_top, f.padding_bottom = opts.pad_v or 0, opts.pad_v or 0
    end
    return f
end

-- Coloca la tarjeta en la fila (MenuItem)
--   opts.gap     hueco de debajo (el de geometry)
--   opts.indent  sangría a la izquierda
--   opts.fit     la fila mide lo que la tarjeta (+ hueco), como mucho
--                opts.max_h (+ hueco); si no, item_h
--   opts.item_h  alto de la fila (sin fit)
-- item._aire_card: la tarjeta (mantener pulsado la pone en negro, styles/ui/titlebar.lua)
function M.place(item, card, item_w, pad_h, opts)
    opts = opts or {}
    local gap = opts.gap or S(LM().CARD_GAP)
    local h = opts.item_h
    if opts.fit then
        local ch = card:getSize().h
        if opts.max_h then ch = math.min(ch, opts.max_h) end
        h = ch + gap
    end
    item[1] = FrameContainer:new{
        width = item_w,
        height = h,
        bordersize = 0,
        padding = 0,
        padding_left = pad_h + (opts.indent or 0),
        padding_right = pad_h,
        padding_bottom = gap,
        card,
    }
    if opts.fit and item.dimen then item.dimen.h = h end
    item._aire_card = card
end

-- Tocar una tarjeta: gris un momento y después lo de KOReader (onMenuSelect)
function M.onTapFlash(item, _arg, ges)
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

return M
