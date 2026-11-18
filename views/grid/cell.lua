--[[
    aire.koplugin/views/grid/cell.lua
    Widgets de las vistas de cuadrícula (views/grid.lua): la celda de una
    portada o de un grupo (GridCell) y los puntos de página (PageDots).
    GridCell.state = { TEST, CONFIG }: lo rellena el mixin de grid.lua
    (herramientas de prueba de devtools.lua, opcionales).
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local RenderImage = require("ui/renderimage")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY
local MAX_DOTS = 9           -- con más páginas se muestra "3 / 12"

-- Herramientas de prueba (devtools.lua, opcional): datos falsos y medidas.
-- Las fija el mixin si el archivo existe.
local state = { TEST = nil, CONFIG = nil }

-- Parte un texto en como mucho 2 líneas de TextWidget (letras sin fondo, para
-- poder pintarlas encima de una zona oscurecida). La 2ª acaba en "…" si no cabe.
local function twoLineText(text, face, max_w, fgcolor)
    local function width(str)
        local t = TextWidget:new{ text = str, face = face, padding = 0 }
        local w = t:getSize().w
        t:free()
        return w
    end
    local words = {}
    for word in (text or "?"):gmatch("%S+") do table.insert(words, word) end
    local lines, cur, i = {}, "", 1
    while i <= #words do
        local cand = cur == "" and words[i] or (cur .. " " .. words[i])
        if cur ~= "" and width(cand) > max_w then
            table.insert(lines, cur)
            cur = table.concat(words, " ", i) -- el resto va a la 2ª línea
            break
        end
        cur = cand
        i = i + 1
    end
    if cur ~= "" then table.insert(lines, cur) end
    local widgets = {}
    for _i, line in ipairs(lines) do
        table.insert(widgets, TextWidget:new{
            text = line, face = face, fgcolor = fgcolor, max_width = max_w, padding = 0,
        })
    end
    return widgets
end

---------------------------------------------------------------------------
-- Celda de la cuadrícula (libro o pila de grupo)
---------------------------------------------------------------------------
local function maskRoundedCorners(bb, x, y, w, h, r, skip_br)
    if r <= 0 then return end
    for dy = 0, r - 1 do
        local dx = r - math.floor(math.sqrt(r * r - (r - dy - 0.5) ^ 2) + 0.5)
        if dx > 0 then
            bb:paintRect(x, y + dy, dx, 1, WHITE)
            bb:paintRect(x + w - dx, y + dy, dx, 1, WHITE)
            bb:paintRect(x, y + h - 1 - dy, dx, 1, WHITE)
            if not skip_br then
                bb:paintRect(x + w - dx, y + h - 1 - dy, dx, 1, WHITE)
            end
        end
    end
end

local GridCell = InputContainer:extend{
    entry = nil,
    width = nil,
    height = nil,
    cover_bb = nil,
    mosaic_bbs = nil,     -- grupos en mosaico 2×2: portadas de los 4 primeros (false = sin portada)
    -- Portadas por ruta (Librería, Colecciones, Historial): cover_fast(ruta, w, h)
    -- devuelve la miniatura ya escalada si está en memoria o en disco; si no,
    -- la portada queda en self.pending y grid.lua llama a loadPending antes de
    -- enseñar la página (o, para la página siguiente, en reposo).
    cover_path = nil,
    mosaic_paths = nil,   -- como mosaic_bbs, con rutas (false = sin libro / falso)
    cover_fast = nil,
    series_badge = false, -- nº de serie en la esquina (solo Librería)
    in_collection = false, -- marca de colección arriba a la izquierda (opción de KOReader)
    show_mark = true,     -- esquina doblada en los empezados / en pausa (opción del menú)
    show_finished = true, -- terminados en gris (opción del menú)
    rounded = false,      -- esquinas redondeadas (opción del menú)
    tap_expand = 0,       -- px extra alrededor que responden al toque
    on_tap = nil,
    on_hold = nil,
}

function GridCell:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    local e = self.entry
    if e.is_action then
        -- Celda de acción (p. ej. "Nueva colección")
        self.action_icon = IconWidget:new{ icon = e.icon or "aire.plus", width = Screen:scaleBySize(26),
            height = Screen:scaleBySize(26), alpha = true }
        self.action_text = TextBoxWidget:new{
            text = e.title or "", face = Font:getFace("cfont", 12), alignment = "center",
            width = self.width - 2 * Screen:scaleBySize(8), fgcolor = GRAY_TEXT,
        }
        local range = function() return self.dimen end
        self.ges_events = {
            AireTap = { GestureRange:new{ ges = "tap", range = range } },
            AireHold = { GestureRange:new{ ges = "hold", range = range } },
        }
        return
    end
    -- (antes de decidir si es pila: con rutas también es mosaico)
    self.pending = nil
    if self.mosaic_paths and not self.mosaic_bbs then self.mosaic_bbs = {} end
    self.off = (e.is_group and not self.mosaic_bbs) and Screen:scaleBySize(5) or 0
    self.box_w = self.width - 2 * self.off
    self.box_h = self.height - 2 * self.off
    if self.mosaic_bbs then
        -- Nombre arriba, superpuesto al mosaico: letras blancas sobre una
        -- franja oscurecida (hasta 2 líneas, centrado)
        self.name_pad = Screen:scaleBySize(4)
        self.name_lines = twoLineText(e.title, Font:getFace("tfont", 11),
            self.box_w - 2 * self.name_pad, WHITE)
        local lines_h = 0
        for _i, tw in ipairs(self.name_lines) do lines_h = lines_h + tw:getSize().h end
        self.name_h = lines_h + 2 * self.name_pad
        -- Mosaico 2×2 en toda la celda: cada miniatura cabe en su cuarto
        self.mos_pad = Screen:scaleBySize(4)
        self.mos_gap = Screen:scaleBySize(3)
        self.slot_w = math.floor((self.box_w - 2 * self.mos_pad - self.mos_gap) / 2)
        self.slot_h = math.floor((self.box_h - 2 * self.mos_pad - self.mos_gap) / 2)
        self.mosaic = {}
        for i = 1, 4 do
            local cbb = self.mosaic_bbs[i]
            local slot = { has_book = e.books[i] ~= nil }
            local mpath = self.mosaic_paths and self.mosaic_paths[i]
            if cbb then
                slot.img = self:coverImage(cbb, self.slot_w, self.slot_h)
            elseif mpath then
                local sbb = self.cover_fast and self.cover_fast(mpath, self.slot_w, self.slot_h)
                if sbb then
                    slot.img = ImageWidget:new{ image = sbb, image_disposable = false, scale_factor = 1 }
                else
                    self.pending = self.pending or {}
                    table.insert(self.pending, { path = mpath, slot = i, w = self.slot_w, h = self.slot_h })
                end
            end
            self.mosaic[i] = slot
        end
    elseif self.cover_bb then
        self.img = self:coverImage(self.cover_bb, self.box_w, self.box_h)
    elseif self.cover_path and self.cover_fast
            and self.cover_fast(self.cover_path, self.box_w, self.box_h) then
        self.img = ImageWidget:new{ image = self.cover_fast(self.cover_path, self.box_w, self.box_h),
            image_disposable = false, scale_factor = 1 }
    else
        if self.cover_path then
            self.pending = { { path = self.cover_path, w = self.box_w, h = self.box_h } }
        end
        local pad = Screen:scaleBySize(8)
        self.placeholder = TextBoxWidget:new{
            text = e.title or "?",
            face = Font:getFace(e.is_group and "tfont" or "cfont", 12),
            alignment = "center",
            width = self.box_w - 2 * pad,
            height = self.box_h - 2 * pad,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
    end
    if e.is_group then
        self.count_w = TextWidget:new{
            text = tostring(#e.books),
            face = Font:getFace("tfont", 12),
            fgcolor = WHITE,
            padding = 0,
        }
    end
    -- Estado: leyendo = esquina doblada blanca; en pausa = esquina doblada gris;
    -- terminado = en gris. En grupos: empezado (algún libro leyéndose, o
    -- terminados algunos pero no todos) = leyendo; solo en pausa = en pausa;
    -- todos terminados = en gris.
    if e.is_group then
        self.reading = e.rank == 0
        self.paused = e.rank == 1
        self.finished = #e.books > 0 and e.rank == 3
    else
        self.reading = e.status == "reading"
        self.paused = e.status == "abandoned"
        self.finished = e.status == "complete"
    end
    if not self.show_mark then self.reading, self.paused = false, false end
    if not self.show_finished then self.finished = false end
    -- Nº de serie (solo Librería): triángulo negro arriba a la derecha con el número en blanco
    -- Marca de colección: estrella blanca (la misma de KOReader) en un
    -- triángulo negro arriba a la izquierda
    if self.in_collection then
        -- Mismo tamaño que el triángulo del nº de serie con un número de 1 cifra
        local probe = TextWidget:new{ text = "8", face = Font:getFace("tfont", 11), padding = 0 }
        local ps = probe:getSize()
        probe:free()
        self.coll_side = math.max(Screen:scaleBySize(26), math.ceil(1.5 * (ps.w + ps.h)))
        local isz = math.max(Screen:scaleBySize(10), ps.h)
        self.coll_icon = IconWidget:new{ icon = "star.white", width = isz, height = isz, alpha = true }
    end
    if self.series_badge and not e.is_group and e.series_index then
        local n = tonumber(e.series_index)
        self.badge_w = TextWidget:new{
            text = (n and n == math.floor(n)) and ("%d"):format(n) or tostring(e.series_index),
            face = Font:getFace("tfont", 11),
            fgcolor = WHITE,
            padding = 0,
        }
    end
    if self.reading or self.paused then
        self.mark_size = math.floor(self.box_w / 6)
    end
    -- La mitad del hueco entre portadas también responde
    local e2 = self.tap_expand or 0
    local range = function()
        local d = self.dimen
        return Geom:new{ x = d.x - e2, y = d.y - e2, w = d.w + 2 * e2, h = d.h + 2 * e2 }
    end
    self.ges_events = {
        AireTap = { GestureRange:new{ ges = "tap", range = range } },
        AireHold = { GestureRange:new{ ges = "hold", range = range } },
    }
end

-- Portada encajada en max_w × max_h. Con scaled_cache (tabla de la pestaña) la
-- versión escalada se guarda y se reutiliza: escalar ~16 portadas cada vez que
-- se construía la vista era lo que más tardaba al abrir Librería / Historial.
-- Ni la celda ni el ImageWidget son dueños de los buffers (los libera
-- freeGridCovers).
function GridCell:coverImage(cbb, max_w, max_h)
    local iw, ih = cbb:getWidth(), cbb:getHeight()
    local s = math.min(max_w / iw, max_h / ih)
    local cache = self.scaled_cache
    if cache then
        local key = tostring(cbb) .. "|" .. max_w .. "x" .. max_h
        local sbb = cache[key]
        if not sbb then
            local ok, res = pcall(RenderImage.scaleBlitBuffer, RenderImage, cbb,
                math.max(1, math.floor(iw * s + 0.5)), math.max(1, math.floor(ih * s + 0.5)), false)
            sbb = ok and res or nil
            if sbb then cache[key] = sbb end
        end
        if sbb then
            return ImageWidget:new{ image = sbb, image_disposable = false, scale_factor = 1 }
        end
    end
    return ImageWidget:new{ image = cbb, image_disposable = false, scale_factor = s }
end

-- slow(ruta, w, h) hace la miniatura (leer, escalar,
-- guardar). Devuelve true si la celda ha cambiado y hay que repintarla.
function GridCell:loadPending(slow)
    if not self.pending then return false end
    local changed = false
    for _i, p in ipairs(self.pending) do
        local sbb = slow(p.path, p.w, p.h)
        if sbb then
            local img = ImageWidget:new{ image = sbb, image_disposable = false, scale_factor = 1 }
            if p.slot then
                self.mosaic[p.slot].img = img
            else
                self.img = img
                if self.placeholder then self.placeholder:free(); self.placeholder = nil end
            end
            changed = true
        end
    end
    self.pending = nil
    return changed
end

function GridCell:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function GridCell:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    if self.entry.is_action then
        bb:paintBorder(x, y, self.width, self.height, Size.border.thin, Blitbuffer.COLOR_LIGHT_GRAY,
            Screen:scaleBySize(8))
        local is = self.action_icon:getSize()
        local ts = self.action_text:getSize()
        local gap = Screen:scaleBySize(6)
        local top = y + math.floor((self.height - is.h - gap - ts.h) / 2)
        self.action_icon:paintTo(bb, x + math.floor((self.width - is.w) / 2), top)
        self.action_text:paintTo(bb, x + math.floor((self.width - ts.w) / 2), top + is.h + gap)
        return
    end
    local off = self.off
    local bw, bh = self.box_w, self.box_h
    -- Portada pegada abajo (como en una estantería) y centrada
    local rw, rh = bw, bh
    if self.img then
        local s = self.img:getSize()
        rw, rh = s.w, s.h
    end
    local rx = x + math.floor((bw - rw) / 2)
    local ry = y + 2 * off + (bh - rh)
    local border = Size.border.thin
    local r = self.rounded and Screen:scaleBySize(8) or 0

    if self.mosaic then
        -- Mosaico 2×2 dentro de un marco del tamaño de la celda
        bb:paintRect(rx, ry, rw, rh, WHITE)
        for i, slot in ipairs(self.mosaic) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local sx = rx + self.mos_pad + col * (self.slot_w + self.mos_gap)
            local sy = ry + self.mos_pad + row * (self.slot_h + self.mos_gap)
            if slot.img then
                local s = slot.img:getSize()
                local ix = sx + math.floor((self.slot_w - s.w) / 2)
                local iy = sy + math.floor((self.slot_h - s.h) / 2)
                slot.img:paintTo(bb, ix, iy)
                bb:paintBorder(ix, iy, s.w, s.h, border, BLACK, 0)
            elseif slot.has_book then
                -- Libro sin portada: hueco gris claro
                bb:paintRect(sx, sy, self.slot_w, self.slot_h, Blitbuffer.COLOR_GRAY_E)
                bb:paintBorder(sx, sy, self.slot_w, self.slot_h, border, BLACK, 0)
            else
                -- Hueco sin libro (grupo con menos de 4, o vacío): solo el contorno en gris
                bb:paintBorder(sx, sy, self.slot_w, self.slot_h, border, Blitbuffer.COLOR_LIGHT_GRAY, 0)
            end
        end
        -- Nombre arriba: oscurecer la franja y pintar las letras en blanco encima
        bb:darkenRect(rx, ry, rw, self.name_h, 0.7)
        local ly = ry + self.name_pad
        for _i, tw in ipairs(self.name_lines) do
            local ts = tw:getSize()
            tw:paintTo(bb, rx + math.floor((rw - ts.w) / 2), ly)
            ly = ly + ts.h
        end
        maskRoundedCorners(bb, rx, ry, rw, rh, r, self.mark_size ~= nil)
        bb:paintBorder(rx, ry, rw, rh, border, BLACK, r)
    end

    -- Pila: dos portadas "detrás", desplazadas hacia arriba a la derecha
    if off > 0 then
        for k = 2, 1, -1 do
            local lx, ly = rx + k * off, ry - k * off
            bb:paintRoundedRect(lx, ly, rw, rh, WHITE, r)
            bb:paintBorder(lx, ly, rw, rh, border, BLACK, r)
        end
    end

    if not self.mosaic then
        bb:paintRoundedRect(rx, ry, rw, rh, WHITE, r)
        if self.img then
            self.img:paintTo(bb, rx, ry)
            maskRoundedCorners(bb, rx, ry, rw, rh, r, self.mark_size ~= nil)
        else
            local ps = self.placeholder:getSize()
            self.placeholder:paintTo(bb, rx + math.floor((rw - ps.w) / 2), ry + math.floor((rh - ps.h) / 2))
        end
        bb:paintBorder(rx, ry, rw, rh, border, BLACK, r)
    end

    if self.coll_icon then
        local is = self.coll_icon:getSize()
        local side = math.min(self.coll_side or Screen:scaleBySize(26), math.floor(math.min(rw, rh) / 2))
        for i = 0, side - 1 do
            bb:paintRect(rx, ry + i, side - i, 1, BLACK)
        end
        if r > 0 then
            for dy = 0, r - 1 do
                local dx = r - math.floor(math.sqrt(r * r - (r - dy - 0.5) ^ 2) + 0.5)
                if dx > 0 then bb:paintRect(rx, ry + dy, dx, 1, WHITE) end
            end
        end
        self.coll_icon:paintTo(bb, rx + math.floor(side / 3 - is.w / 2) + 1, ry + math.floor(side / 3 - is.h / 2) + 1)
    end

    -- Nº de serie: triángulo negro en la esquina superior derecha; el número va
    -- centrado en el tercio del triángulo pegado a la esquina
    if self.badge_w then
        local ts = self.badge_w:getSize()
        local side = math.max(Screen:scaleBySize(26), math.ceil(1.5 * (ts.w + ts.h)))
        side = math.min(side, math.floor(math.min(rw, rh) / 2))
        for i = 0, side - 1 do
            local len = side - i
            bb:paintRect(rx + rw - len, ry + i, len, 1, BLACK)
        end
        if r > 0 then
            for dy = 0, r - 1 do
                local dx = r - math.floor(math.sqrt(r * r - (r - dy - 0.5) ^ 2) + 0.5)
                if dx > 0 then
                    bb:paintRect(rx + rw - dx, ry + dy, dx, 1, WHITE)
                end
            end
        end
        local cx = rx + rw - math.floor(side / 3)
        local cy = ry + math.floor(side / 3)
        self.badge_w:paintTo(bb, cx - math.floor(ts.w / 2), cy - math.floor(ts.h / 2))
    end

    -- Leyendo / en pausa: esquina doblada (cuadrada) abajo a la derecha de la
    -- portada, con el mismo grosor de línea que el borde de la portada.
    -- La solapa es blanca (leyendo) o gris (en pausa).
    if self.mark_size then
        local sz, t = self.mark_size, border
        local flap = self.paused and Blitbuffer.COLOR_DARK_GRAY or WHITE
        local X, Y = rx + rw - sz, ry + rh - sz
        if r > 0 then
            local rf = math.min(r, math.floor(sz * 0.35))
            -- Usar paintRoundedRect + paintBorder nativos para una esquina superior-izquierda suave
            bb:paintRoundedRect(X, Y, sz, sz, flap, rf)
            bb:paintBorder(X, Y, sz, sz, t, BLACK, rf, true)
            -- Borrar las curvas sobrantes de arriba-derecha y abajo-izquierda y trazar los bordes rectos
            bb:paintRect(X + sz - rf, Y, rf, rf, flap)
            bb:paintRect(X, Y + sz - rf, rf, rf, flap)
            bb:paintRect(X + rf, Y, sz - rf, t, BLACK)
            bb:paintRect(X, Y + rf, t, sz - rf, BLACK)
            for i = 0, sz - 1 do
                -- triángulo de abajo a la derecha: la esquina "cortada" (fondo)
                bb:paintRect(X + sz - 1 - i, Y + i, i + 1, 1, WHITE)
                -- diagonal del pliegue
                bb:paintRect(math.max(X, X + sz - i - t), Y + i, t, 1, BLACK)
            end
        else
            for i = 0, sz - 1 do
                -- triángulo de abajo a la derecha: la esquina "cortada" (fondo)
                bb:paintRect(X + sz - 1 - i, Y + i, i + 1, 1, WHITE)
                -- triángulo de arriba a la izquierda: la solapa doblada
                bb:paintRect(X, Y + i, sz - 1 - i, 1, flap)
                -- diagonal del pliegue
                bb:paintRect(math.max(X, X + sz - i - t), Y + i, t, 1, BLACK)
            end
            bb:paintRect(X, Y, sz, t, BLACK) -- lado de arriba de la solapa
            bb:paintRect(X, Y, t, sz, BLACK) -- lado izquierdo de la solapa
        end
    end

    -- Nº de libros del grupo (píldora negra abajo a la izquierda)
    if self.count_w then
        local cs = self.count_w:getSize()
        local pad_h = Screen:scaleBySize(7)
        local pw, ph = cs.w + 2 * pad_h, cs.h + Screen:scaleBySize(4)
        local m = Screen:scaleBySize(6)
        local px, py = rx + m, ry + rh - ph - m
        bb:paintRoundedRect(px, py, pw, ph, BLACK, math.floor(ph / 2))
        self.count_w:paintTo(bb, px + pad_h, py + math.floor((ph - cs.h) / 2))
    end

    -- Terminado: todo en gris (lo último, como en el explorador antes)
    if self.finished then
        bb:lightenRect(x, y, self.width, self.height, 0.5)
    end

    -- Pruebas: medidas encima de la celda
    if state.TEST and state.CONFIG and state.CONFIG.debug_sizes then
        pcall(state.TEST.paintCellInfo, self, bb, x, y, rx, ry, rw, rh)
    end
end

function GridCell:onAireTap()
    if self.on_tap then self.on_tap(self.entry) end
    return true
end

function GridCell:onAireHold()
    if self.on_hold then self.on_hold(self.entry) end
    return true
end

function GridCell:free()
    if self.img then self.img:free() end
    if self.placeholder then self.placeholder:free() end
    if self.count_w then self.count_w:free() end
    if self.badge_w then self.badge_w:free() end
    if self.coll_icon then self.coll_icon:free() end
    for _i, slot in ipairs(self.mosaic or {}) do
        if slot.img then slot.img:free() end
    end
    for _i, tw in ipairs(self.name_lines or {}) do tw:free() end
end

-- Indicador de páginas: puntos (● activo alargado) o "3 / 12"
local PageDots = Widget:extend{ width = nil, height = nil, page = 1, pages = 1 }

function PageDots:getSize() return Geom:new{ w = self.width, h = self.height } end

function PageDots:paintTo(bb, x, y)
    if self.pages <= 1 then return end
    if self.pages > MAX_DOTS then
        if not self._text then
            self._text = TextWidget:new{
                text = ("%d / %d"):format(self.page, self.pages),
                face = Font:getFace("cfont", 13), fgcolor = GRAY_TEXT, padding = 0,
            }
        end
        local s = self._text:getSize()
        self._text:paintTo(bb, x + math.floor((self.width - s.w) / 2), y + math.floor((self.height - s.h) / 2))
        return
    end
    -- Página actual: raya negra; las demás: puntos con borde fino (como las
    -- portadas y el dock), en blanco
    local d = Screen:scaleBySize(7)          -- diámetro de los puntos / alto de la raya
    local active_w = Screen:scaleBySize(28)  -- largo de la raya
    local gap = Screen:scaleBySize(9)
    local t = Size.border.thin
    local total = (self.pages - 1) * d + active_w + (self.pages - 1) * gap
    local cx = x + math.floor((self.width - total) / 2)
    local cy = y + math.floor((self.height - d) / 2)
    local r = math.floor(d / 2)
    for i = 1, self.pages do
        if i == self.page then
            bb:paintRoundedRect(cx, cy, active_w, d, BLACK, r)
            cx = cx + active_w + gap
        else
            bb:paintRoundedRect(cx, cy, d, d, BLACK, r)
            bb:paintRoundedRect(cx + t, cy + t, d - 2 * t, d - 2 * t, WHITE, math.max(0, r - t))
            cx = cx + d + gap
        end
    end
end

function PageDots:free()
    if self._text then self._text:free() end
end

GridCell.state = state

return { GridCell = GridCell, PageDots = PageDots }
