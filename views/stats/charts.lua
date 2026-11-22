--[[
    aire.koplugin/views/stats/charts.lua
    Gráficos de la pestaña Estadísticas (views/stats/init.lua): barras de la semana,
    barras horizontales (géneros), barras por día de la semana, barras de la
    recapitulación y la cuadrícula del calendario del mes.
    Uso: dofile(".../charts.lua")(Data)  (Data = views/stats/data.lua ya cargado)
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local Widget = require("ui/widget/widget")
local Screen = require("device").screen

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

-- Pinta una barra vertical con esquinas superiores redondeadas y base recta
local function paintTopRoundedBar(bb, x, y, w, h, color, r)
    if h <= 0 or w <= 0 then return end
    r = math.min(r or 0, math.floor(w / 2), math.floor(h / 2))
    if r >= 2 and h > r then
        bb:paintRoundedRect(x, y, w, h, color, r)
        bb:paintRect(x, y + h - r, w, r, color)
    else
        bb:paintRect(x, y, w, h, color)
    end
end

return function(Data)
local monthRange = Data.monthRange

---------------------------------------------------------------------------
-- Barras de la semana (con línea de media diaria opcional)
---------------------------------------------------------------------------
local WeekBars = Widget:extend{
    width = nil, height = nil, days = nil,
    avg_secs = nil, avg_label = nil,
}

function WeekBars:init()
    self.labels = {}
    for i, d in ipairs(self.days) do
        self.labels[i] = TextWidget:new{
            text = d.letter, face = Font:getFace(i == #self.days and "tfont" or "cfont", 12),
            fgcolor = i == #self.days and BLACK or GRAY_TEXT, padding = 0,
        }
    end
    self.label_h = self.labels[1]:getSize().h
    if self.avg_label and self.avg_secs and self.avg_secs > 0 then
        self.avg_widget = TextWidget:new{
            text = self.avg_label, face = Font:getFace("cfont", 10),
            fgcolor = GRAY_TEXT, padding = 0,
        }
    end
end

function WeekBars:getSize() return Geom:new{ w = self.width, h = self.height } end

function WeekBars:paintTo(bb, x, y)
    local n = #self.days
    local gap = Screen:scaleBySize(10)
    local bw = math.floor((self.width - (n - 1) * gap) / n)
    local label_gap = Screen:scaleBySize(5)
    local top_pad = self.avg_widget and Screen:scaleBySize(4) or 0
    local chart_h = self.height - self.label_h - label_gap - top_pad
    local base_y = y + top_pad + chart_h
    local max = 0
    for _i, d in ipairs(self.days) do if d.secs > max then max = d.secs end end
    if self.avg_secs and self.avg_secs > max then max = self.avg_secs end
    local bar_r = Screen:scaleBySize(3)
    local stub_h = Screen:scaleBySize(2)

    -- Línea discontinua de referencia (media diaria o meta diaria) detrás de las barras
    if self.avg_secs and self.avg_secs > 0 and max > 0 then
        local avg_h = math.floor(chart_h * self.avg_secs / max)
        local ay = base_y - avg_h
        local dash = Screen:scaleBySize(4)
        local step = dash * 2
        local dx = x
        while dx < x + self.width do
            local dw = math.min(dash, x + self.width - dx)
            bb:paintRect(dx, ay, dw, Size.line.thin, Blitbuffer.COLOR_GRAY)
            dx = dx + step
        end
    end

    for i, d in ipairs(self.days) do
        local bx = x + (i - 1) * (bw + gap)
        if d.secs > 0 and max > 0 then
            local h = math.max(Screen:scaleBySize(4), math.floor(chart_h * d.secs / max))
            local col = (i == n) and BLACK or Blitbuffer.COLOR_DARK_GRAY
            paintTopRoundedBar(bb, bx, base_y - h, bw, h, col, bar_r)
        else
            bb:paintRect(bx, base_y - stub_h, bw, stub_h, Blitbuffer.COLOR_GRAY_D)
        end
        local ls = self.labels[i]:getSize()
        self.labels[i]:paintTo(bb, bx + math.floor((bw - ls.w) / 2), base_y + label_gap)
    end

    -- Etiqueta de la línea de referencia (encima, a la derecha, con fondo blanco limpio)
    if self.avg_widget and self.avg_secs and self.avg_secs > 0 and max > 0 then
        local avg_h = math.floor(chart_h * self.avg_secs / max)
        local as = self.avg_widget:getSize()
        local pad_x = Screen:scaleBySize(4)
        local ax = x + self.width - as.w - pad_x
        local ay = math.max(y, base_y - avg_h - as.h - Screen:scaleBySize(2))
        bb:paintRect(ax - pad_x, ay, as.w + 2 * pad_x, as.h, WHITE)
        self.avg_widget:paintTo(bb, ax, ay)
    end

    -- Línea base
    bb:paintRect(x, base_y, self.width, Size.border.thin, BLACK)
end

function WeekBars:free()
    for _i, l in ipairs(self.labels or {}) do l:free() end
    if self.avg_widget then self.avg_widget:free() end
end

---------------------------------------------------------------------------
-- Barras horizontales (géneros más leídos, reutilizable en Hábitos y Recaps)
---------------------------------------------------------------------------
local HorizontalBars = Widget:extend{
    width = nil, items = nil, compact = false,
}

function HorizontalBars:init()
    self.rows = {}
    local f_lbl = self.compact and 12 or 13
    local f_det = self.compact and 11 or 12
    self.bar_h = Screen:scaleBySize(self.compact and 5 or 7)
    self.bar_gap = Screen:scaleBySize(self.compact and 3 or 4)
    self.row_gap = Screen:scaleBySize(self.compact and 7 or 10)
    local total_h = 0
    for i, item in ipairs(self.items or {}) do
        local det_w = TextWidget:new{
            text = item.detail or "", face = Font:getFace("cfont", f_det),
            fgcolor = GRAY_TEXT, padding = 0,
        }
        local lbl_max = math.max(Screen:scaleBySize(60), self.width - det_w:getSize().w - Screen:scaleBySize(10))
        local lbl_w = TextWidget:new{
            text = item.label or "", face = Font:getFace("tfont", f_lbl),
            fgcolor = BLACK, max_width = lbl_max, padding = 0,
        }
        local text_h = math.max(lbl_w:getSize().h, det_w:getSize().h)
        local row_h = text_h + self.bar_gap + self.bar_h
        table.insert(self.rows, {
            lbl = lbl_w, det = det_w, text_h = text_h, row_h = row_h,
            ratio = math.max(0, math.min(1, item.ratio or 0)),
            rank = i,
        })
        total_h = total_h + row_h + (i > 1 and self.row_gap or 0)
    end
    self.height = total_h
end

function HorizontalBars:getSize() return Geom:new{ w = self.width, h = self.height } end

function HorizontalBars:paintTo(bb, x, y)
    local cy = y
    local r = math.floor(self.bar_h / 2)
    for _i, row in ipairs(self.rows) do
        row.lbl:paintTo(bb, x, cy)
        local ds = row.det:getSize()
        row.det:paintTo(bb, x + self.width - ds.w, cy + math.floor((row.text_h - ds.h) / 2))
        local by = cy + row.text_h + self.bar_gap
        bb:paintRoundedRect(x, by, self.width, self.bar_h, Blitbuffer.COLOR_GRAY_D, r)
        local fill_w = math.max(row.ratio > 0 and self.bar_h or 0, math.floor(self.width * row.ratio))
        if fill_w > 0 then
            local col = row.rank == 1 and BLACK
                or (row.rank <= 3 and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY)
            bb:paintRoundedRect(x, by, fill_w, self.bar_h, col, r)
        end
        cy = cy + row.row_h + self.row_gap
    end
end

function HorizontalBars:free()
    for _i, row in ipairs(self.rows or {}) do
        row.lbl:free()
        row.det:free()
    end
end

---------------------------------------------------------------------------
-- Barras por día de la semana (L-D, destacando el día favorito)
---------------------------------------------------------------------------
local WeekdayBars = Widget:extend{
    width = nil, height = nil, days = nil, fav = nil,
}

function WeekdayBars:init()
    self.labels = {}
    for i, d in ipairs(self.days or {}) do
        local is_fav = (d.wday == self.fav)
        self.labels[i] = TextWidget:new{
            text = d.letter or "",
            face = Font:getFace(is_fav and "tfont" or "cfont", 12),
            fgcolor = is_fav and BLACK or GRAY_TEXT,
            padding = 0,
        }
    end
    self.label_h = self.labels[1] and self.labels[1]:getSize().h or Screen:scaleBySize(14)
end

function WeekdayBars:getSize() return Geom:new{ w = self.width, h = self.height } end

function WeekdayBars:paintTo(bb, x, y)
    local n = #(self.days or {})
    if n == 0 then return end
    local gap = Screen:scaleBySize(10)
    local bw = math.floor((self.width - (n - 1) * gap) / n)
    local label_gap = Screen:scaleBySize(5)
    local chart_h = self.height - self.label_h - label_gap
    local base_y = y + chart_h
    local max = 0
    for _i, d in ipairs(self.days) do if d.secs > max then max = d.secs end end
    local bar_r = Screen:scaleBySize(3)
    local stub_h = Screen:scaleBySize(2)
    for i, d in ipairs(self.days) do
        local bx = x + (i - 1) * (bw + gap)
        if d.secs > 0 and max > 0 then
            local h = math.max(Screen:scaleBySize(4), math.floor(chart_h * d.secs / max))
            local col = (d.wday == self.fav) and BLACK or Blitbuffer.COLOR_DARK_GRAY
            paintTopRoundedBar(bb, bx, base_y - h, bw, h, col, bar_r)
        else
            bb:paintRect(bx, base_y - stub_h, bw, stub_h, Blitbuffer.COLOR_GRAY_D)
        end
        local ls = self.labels[i]:getSize()
        self.labels[i]:paintTo(bb, bx + math.floor((bw - ls.w) / 2), base_y + label_gap)
    end
    bb:paintRect(x, base_y, self.width, Size.border.thin, BLACK)
end

function WeekdayBars:free()
    for _i, l in ipairs(self.labels or {}) do l:free() end
end

---------------------------------------------------------------------------
-- Barras de ritmo del recap (mensual: días del mes; anual: 12 meses)
---------------------------------------------------------------------------
local RecapBars = Widget:extend{ width = nil, height = nil, bars = nil }

function RecapBars:init()
    self.labels = {}
    for i, b in ipairs(self.bars or {}) do
        if b.label and b.label ~= "" then
            self.labels[i] = TextWidget:new{
                text = b.label,
                face = Font:getFace(b.highlight and "tfont" or "cfont", 11),
                fgcolor = b.highlight and BLACK or GRAY_TEXT,
                padding = 0,
            }
        end
    end
    local sample = TextWidget:new{ text = "M", face = Font:getFace("cfont", 11), padding = 0 }
    self.label_h = sample:getSize().h
    sample:free()
end

function RecapBars:getSize() return Geom:new{ w = self.width, h = self.height } end

function RecapBars:paintTo(bb, x, y)
    local n = #(self.bars or {})
    if n == 0 then return end
    local gap = n > 15 and Screen:scaleBySize(3) or Screen:scaleBySize(8)
    local bw = math.max(Screen:scaleBySize(3), math.floor((self.width - (n - 1) * gap) / n))
    local total_w = n * bw + (n - 1) * gap
    local start_x = x + math.floor((self.width - total_w) / 2)
    local label_gap = Screen:scaleBySize(4)
    local chart_h = self.height - self.label_h - label_gap
    local base_y = y + chart_h
    local max = 0
    for _i, b in ipairs(self.bars) do if b.secs > max then max = b.secs end end
    local bar_r = n > 15 and Screen:scaleBySize(1) or Screen:scaleBySize(3)
    for i, b in ipairs(self.bars) do
        local bx = start_x + (i - 1) * (bw + gap)
        if b.secs > 0 and max > 0 then
            local h = math.max(Screen:scaleBySize(3), math.floor(chart_h * b.secs / max))
            paintTopRoundedBar(bb, bx, base_y - h, bw, h,
                b.highlight and BLACK or Blitbuffer.COLOR_DARK_GRAY, bar_r)
        end
        local lw = self.labels[i]
        if lw then
            local ls = lw:getSize()
            lw:paintTo(bb, bx + math.floor((bw - ls.w) / 2), base_y + label_gap)
        end
    end
    bb:paintRect(x, base_y, self.width, Size.border.thin, BLACK)
end

function RecapBars:free()
    for _i, l in pairs(self.labels or {}) do l:free() end
end

-- Cuadrícula del mes: días más o menos oscuros según el tiempo leído.
-- Tocar un día lo selecciona; deslizar cambia de mes.
local LEVEL_COLORS = { Blitbuffer.COLOR_GRAY_D, Blitbuffer.COLOR_GRAY, Blitbuffer.COLOR_DARK_GRAY, BLACK }

local CalendarGrid = InputContainer:extend{
    width = nil, max_height = nil, year = nil, month = nil, data = nil, selected = nil,
    on_select = nil, on_swipe = nil,
}

function CalendarGrid:init()
    local t0, _t1, ndays = monthRange(self.year, self.month)
    self.ndays = ndays
    -- Lunes = primera columna
    self.first_col = (tonumber(os.date("%w", t0)) + 6) % 7
    self.rows = math.ceil((self.first_col + ndays) / 7)
    self.gap = Screen:scaleBySize(5)
    self.cell = math.floor((self.width - 6 * self.gap) / 7)
    -- Alto de las casillas: como mucho 0,82 del ancho, y menos si no cabe en
    -- max_height (así queda sitio para el detalle del día)
    self.cell_h = math.floor(self.cell * 0.82)
    if self.max_height then
        local fit = math.floor((self.max_height - (self.rows - 1) * self.gap) / self.rows)
        self.cell_h = math.max(Screen:scaleBySize(28), math.min(self.cell_h, fit))
    end
    self.height = self.rows * self.cell_h + (self.rows - 1) * self.gap
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    local now = os.date("*t")
    self.today = (now.year == self.year and now.month == self.month) and now.day or nil
    -- Días que aún no han llegado (solo en el mes actual)
    self.first_future = self.today and (self.today + 1) or nil
    self.nums = {}
    for d = 1, ndays do
        local info = self.data.days[d]
        local lvl = 0
        if info and info.secs > 0 and self.data.max > 0 then
            lvl = math.max(1, math.min(4, math.ceil(4 * info.secs / self.data.max)))
        end
        self.nums[d] = {
            lvl = lvl,
            w = TextWidget:new{
                text = tostring(d),
                face = Font:getFace(d == self.today and "tfont" or "cfont", 13),
                fgcolor = lvl >= 3 and WHITE
                    or ((self.first_future and d >= self.first_future) and Blitbuffer.COLOR_GRAY or BLACK),
                padding = 0,
            },
        }
    end
    local range = function() return self.dimen end
    self.ges_events = {
        AireTap = { GestureRange:new{ ges = "tap", range = range } },
        AireSwipe = { GestureRange:new{ ges = "swipe", range = range } },
    }
end

function CalendarGrid:getSize() return Geom:new{ w = self.width, h = self.height } end

function CalendarGrid:cellPos(d)
    local idx = self.first_col + d - 1
    local col, row = idx % 7, math.floor(idx / 7)
    return col * (self.cell + self.gap), row * (self.cell_h + self.gap)
end

function CalendarGrid:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local r = Screen:scaleBySize(4)
    for d = 1, self.ndays do
        local cx, cy = self:cellPos(d)
        cx, cy = x + cx, y + cy
        local n = self.nums[d]
        if n.lvl > 0 then
            bb:paintRoundedRect(cx, cy, self.cell, self.cell_h, LEVEL_COLORS[n.lvl], r)
        end
        local future = self.first_future and d >= self.first_future
        -- Futuros: borde gris claro; el resto: borde fino negro
        bb:paintBorder(cx, cy, self.cell, self.cell_h, Size.border.thin,
            future and Blitbuffer.COLOR_LIGHT_GRAY or BLACK, r)
        -- Seleccionado: anillo por fuera de la casilla (se ve también en las negras)
        if d == self.selected then
            local o = math.max(Screen:scaleBySize(2), math.floor(self.gap / 2))
            bb:paintBorder(cx - o, cy - o, self.cell + 2 * o, self.cell_h + 2 * o,
                Size.border.thick, BLACK, r + o)
        end
        local s = n.w:getSize()
        n.w:paintTo(bb, cx + math.floor((self.cell - s.w) / 2), cy + math.floor((self.cell_h - s.h) / 2))
    end
end

function CalendarGrid:onAireTap(_args, ges)
    if not (ges and ges.pos) then return true end
    local px, py = ges.pos.x - self.dimen.x, ges.pos.y - self.dimen.y
    local col = math.floor(px / (self.cell + self.gap))
    local row = math.floor(py / (self.cell_h + self.gap))
    local d = row * 7 + col - self.first_col + 1
    if self.first_future and d >= self.first_future then return true end -- futuros: nada que ver
    if col >= 0 and col < 7 and d >= 1 and d <= self.ndays and self.on_select then
        self.on_select(d)
    end
    return true
end

function CalendarGrid:onAireSwipe(_args, ges)
    local dir = ges and ges.direction
    if self.on_swipe and (dir == "west" or dir == "east") then
        self.on_swipe(dir == "west" and 1 or -1)
        return true
    end
    return false
end

function CalendarGrid:free()
    for _d, n in pairs(self.nums or {}) do n.w:free() end
end


return {
    WeekBars = WeekBars,
    HorizontalBars = HorizontalBars,
    WeekdayBars = WeekdayBars,
    RecapBars = RecapBars,
    CalendarGrid = CalendarGrid,
}
end
