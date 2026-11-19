--[[
    aire.koplugin/ui/list.lua
    Listas de contenido de Aire (las de KOReader que Aire pasa a tarjetas:
    Índice, Marcadores, Búsqueda, Atajos, Colecciones, explorador en lista…):
    lo que comparten, en un solo sitio. Medidas en ui/screen.lua (LIST).

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

--===========================================================================
-- card(spec, w): tarjeta estándar de una lista. Todo opcional salvo title.
--   title, bold          título (LIST.TITLE); negrita si abre otra lista o es
--                        el elemento actual
--   title_lines          1 (por defecto) | n | "fill" (las que quepan en el alto,
--                        como mucho title_max)
--   dim                  título en gris
--   sub, sub_lines       subtítulo en gris (LIST.SUB)
--   meta                 etiqueta pequeña arriba (LIST.META, mayúsculas); con
--                        ella, lo de la derecha va en su fila
--   left  = { icon = "…" } | { check = bool [, radio = true] }
--   right = { text = "…", strong = bool } | { check = bool } | { chevron = true }
--   body  = function(inner_w) -> widget   (debajo del texto: la nota…)
--   state = "current" | "selected" | nil  (gris claro, borde gris)
--   h                    alto fijo (contenido centrado) o, con fit, el máximo
--   fit                  el alto es el del contenido (hasta h)
--===========================================================================
local function face(bold, size) return package.loaded.aire_ui.face(bold, size) end

local function accessory(a)
    if not a then return nil end
    local L = LM()
    if a.icon or a.check ~= nil then
        local IconWidget = require("ui/widget/iconwidget")
        local icon = a.icon
        if a.check ~= nil then
            icon = a.radio and (a.check and "aire.radio.on" or "aire.radio.off")
                or (a.check and "aire.checkbox.on" or "aire.checkbox.off")
        end
        return IconWidget:new{ icon = icon, width = S(L.ICON), height = S(L.ICON), alpha = true }
    end
    if a.chevron then
        local TextWidget = require("ui/widget/textwidget")
        return TextWidget:new{ text = "›", face = face(false, L.TITLE), fgcolor = Blitbuffer.COLOR_DARK_GRAY, padding = 0 }
    end
    if a.text and a.text ~= "" then
        local TextWidget = require("ui/widget/textwidget")
        return TextWidget:new{ text = a.text, face = face(a.strong == true, L.VALUE),
            fgcolor = a.strong and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY, padding = 0 }
    end
end

-- Texto en varias líneas (como mucho lines, con … si no cabe)
local function textBox(text, fc, color, w, lines)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local tb = TextBoxWidget:new{ text = text, face = fc, fgcolor = color, width = w, padding = 0 }
    local lh = tb.line_height_px or tb:getLineHeight()
    if lines and tb:getSize().h > lines * lh then
        tb:free()
        tb = TextBoxWidget:new{ text = text, face = fc, fgcolor = color, width = w, padding = 0,
            height = lines * lh, height_overflow_show_ellipsis = true }
    end
    return tb
end

local function lineHeight(fc, w)
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local probe = TextBoxWidget:new{ text = "X", face = fc, width = w, padding = 0 }
    local lh = probe.line_height_px or probe:getLineHeight()
    probe:free()
    return lh
end

function M.card(spec, w)
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Geom = require("ui/geometry")
    local L = LM()
    local pad = S(L.CARD_PAD)
    local border = Size.border.thin
    local inner_w = w - 2 * (pad + border)
    local left = accessory(spec.left)
    local right = accessory(spec.right)
    local lead = left and (left:getSize().w + S(L.ICON_GAP)) or 0
    local title_face = face(spec.bold == true, L.TITLE)
    local title_color = spec.dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK

    -- Etiqueta de arriba (y lo de la derecha en su fila)
    local top
    if spec.meta and spec.meta ~= "" then
        local P = package.loaded.aire_pages
        local meta_txt = P and P.upper and P.upper(spec.meta) or spec.meta:upper()
        local rw = right and (right:getSize().w + S(8)) or 0
        local meta_w = TextWidget:new{ text = meta_txt, face = face(true, L.META),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = math.max(S(60), inner_w - rw), padding = 0 }
        local th = math.max(meta_w:getSize().h, right and right:getSize().h or 0)
        top = OverlapGroup:new{
            dimen = Geom:new{ w = inner_w, h = th },
            LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = th }, meta_w },
        }
        if right then table.insert(top, RightContainer:new{ dimen = Geom:new{ w = inner_w, h = th }, right }) end
        right = nil
    end

    local text_w = inner_w - lead - (right and (right:getSize().w + S(10)) or 0)
    local body = spec.body and spec.body(inner_w) or nil

    -- Título: una línea, n líneas o las que quepan en el alto
    local lines = spec.title_lines or 1
    -- (con "fill", siempre en un TextBoxWidget aunque quepa una línea: entiende
    -- el formato de KOReader, p. ej. la palabra buscada en negrita)
    local boxed = lines ~= 1
    if lines == "fill" then
        local used = 2 * (pad + border) + (top and (top:getSize().h + S(L.META_GAP)) or 0)
            + (body and (body:getSize().h + S(6)) or 0)
        lines = math.max(1, math.floor(((spec.h or S(200)) - used) / lineHeight(title_face, text_w)))
        if spec.title_max then lines = math.min(lines, spec.title_max) end
    end
    local col = VerticalGroup:new{ align = "left" }
    if not boxed then
        table.insert(col, TextWidget:new{ text = spec.title or "", face = title_face, fgcolor = title_color,
            max_width = math.max(S(40), text_w), padding = 0 })
    else
        table.insert(col, textBox(spec.title or "", title_face, title_color, math.max(S(40), text_w), lines))
    end
    if spec.sub and spec.sub ~= "" then
        table.insert(col, VerticalSpan:new{ width = S(2) })
        if (spec.sub_lines or 1) == 1 then
            table.insert(col, TextWidget:new{ text = spec.sub, face = face(false, L.SUB),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = math.max(S(40), text_w), padding = 0 })
        else
            table.insert(col, textBox(spec.sub, face(false, L.SUB), Blitbuffer.COLOR_DARK_GRAY,
                math.max(S(40), text_w), spec.sub_lines))
        end
    end
    local row = HorizontalGroup:new{ align = "center" }
    if left then
        table.insert(row, left)
        table.insert(row, HorizontalSpan:new{ width = S(L.ICON_GAP) })
    end
    table.insert(row, col)

    if spec.fit then
        -- Alto del contenido: etiqueta, texto y lo de debajo, con el relleno alrededor
        local vg = VerticalGroup:new{ align = "left" }
        if top then
            table.insert(vg, top)
            table.insert(vg, VerticalSpan:new{ width = S(L.META_GAP) })
        end
        table.insert(vg, row)
        if body then
            table.insert(vg, VerticalSpan:new{ width = S(6) })
            table.insert(vg, body)
        end
        return M.cardFrame(vg, w, nil, { pad = pad, state = spec.state })
    end
    -- Alto fijo: todo centrado en vertical; lo de la derecha, a la derecha
    local inner_h = (spec.h or S(48)) - 2 * border
    local og = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = inner_h },
        LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h },
            top and VerticalGroup:new{ align = "left", top, VerticalSpan:new{ width = S(L.META_GAP) }, row } or row },
    }
    if right then table.insert(og, RightContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, right }) end
    return M.cardFrame(og, w, spec.h, { pad_h = pad, state = spec.state })
end

--===========================================================================
-- row(r, w): fila clave / valor (alto LIST.ROW_H, línea fina debajo)
--   key                  a la izquierda: gris (LIST.SUB) si hay valor; si no,
--                        en negro (y negrita con chevron: abre otra página)
--   key_main             la clave es el elemento (un libro…): en negro, normal
--   value, strong        a la derecha (LIST.VALUE), negro; negrita si strong
--   chevron              "›" a la derecha (abre algo); por defecto si hay
--                        callback y no hay valor
--   callback, hold_callback
--   line                 false: sin la línea de debajo
--===========================================================================
function M.row(r, w)
    local Geom = require("ui/geometry")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local L = LM()
    local h = S(L.ROW_H)
    local has_value = r.value ~= nil and tostring(r.value) ~= "" and tostring(r.value) ~= " "
    local chevron = r.chevron
    if chevron == nil then chevron = (r.callback ~= nil) and not has_value end
    local right
    if has_value then
        right = TextWidget:new{ text = tostring(r.value), face = face(r.strong == true, L.VALUE),
            fgcolor = Blitbuffer.COLOR_BLACK, max_width = math.floor(w * 0.65), padding = 0 }
    elseif chevron then
        right = TextWidget:new{ text = "›", face = face(false, L.TITLE),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY, padding = 0 }
    end
    local key_black = r.key_main or not has_value
    local left = TextWidget:new{ text = tostring(r.key or ""),
        face = face((not has_value) and chevron, L.SUB),
        fgcolor = key_black and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
        max_width = math.max(S(40), w - (right and (right:getSize().w + S(12)) or 0)), padding = 0 }
    local og = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = h },
        LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, left },
    }
    if right then table.insert(og, RightContainer:new{ dimen = Geom:new{ w = w, h = h }, right }) end
    local vg = VerticalGroup:new{ align = "left", og }
    if r.line ~= false then
        local LineWidget = require("ui/widget/linewidget")
        table.insert(vg, LineWidget:new{ dimen = Geom:new{ w = w, h = Size.line.thin },
            background = Blitbuffer.COLOR_LIGHT_GRAY })
    end
    if not (r.callback or r.hold_callback) then return vg end
    local AireUI = package.loaded.aire_ui
    local ic = AireUI.tappable(vg, r.callback, r.hold_callback)
    if not r.callback and ic.ges_events then ic.ges_events.AireTap = nil end
    return ic
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
