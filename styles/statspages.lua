--[[
    aire.koplugin/styles/statspages.lua
    Pantallas del plugin Estadísticas rehechas con las piezas de common/pages.lua
    (mismos datos y mismas acciones que KOReader; si algo falla, la de KOReader):

      Estadísticas libro actual (opción A): tarjeta de progreso con barra y
        fecha estimada, 4 casillas (tiempo leído, por página, días, páginas de
        hoy) y debajo el resto de datos en filas.
      Intervalo de tiempo (opción A): tres tarjetas con su resumen (todo / esta
        semana / este mes); cada lista (libros, semanas, meses) en tarjetas con
        una barra proporcional.
      Línea de tiempo de hoy (opción A): horas seguidas de la primera a la
        última lectura, los libros en una tarjeta-leyenda y flechas para
        cambiar de día.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local datetime = require("datetime")
local logger = require("logger")
local userpatch = require("userpatch")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Stats"

-- Pantallas comunes (common/pages.lua, cargado una vez en main.lua)
local function getP() return package.loaded.aire_pages end

local function durationFmt() return G_reader_settings:readSetting("duration_format", "classic") end
local function fmtDuration(secs) return datetime.secondsToClockDuration(durationFmt(), tonumber(secs) or 0, false) end

-- Segundos aproximados de un texto de duración de KOReader ("1:05:00", "1h 05m", "1 h 05 min"…)
local function parseDuration(str)
    str = tostring(str or "")
    local h, m, s = str:match("(%d+):(%d+):(%d+)")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) end
    h, m = str:match("^%s*(%d+):(%d+)")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 end
    local total, found = 0, false
    for num, unit in str:gmatch("(%d+)%s*(%a)") do
        local n = tonumber(num)
        unit = unit:lower()
        if unit == "d" then total = total + n * 86400; found = true
        elseif unit == "h" then total = total + n * 3600; found = true
        elseif unit == "m" then total = total + n * 60; found = true
        elseif unit == "s" then total = total + n; found = true end
    end
    return found and total or nil
end

-- Quita "▸", "◂" y "ⓘ" del final de las claves de KOReader
local function plainKey(k)
    return (tostring(k or ""):gsub("%s*[\226][\150\151][\130\182\184]%s*$", ""):gsub("%s*\226\147\152%s*$", ""))
end

--===========================================================================
-- Estadísticas libro actual
--===========================================================================
local CUR = {
    session_time = _("Time spent reading this session"), session_pages = _("Pages read this session"),
    today_time = _("Time spent reading today"), today_pages = _("Pages read today"),
    total_time = _("Total time spent on this book"), read_time = _("Time spent reading"),
    left = _("Estimated reading time left"), days = _("Days reading this book"),
    avg_day = _("Average time per day"), start = _("Book start date"),
    finish = _("Estimated finish date"), finished = _("Book marked as finished"),
    current = _("Current page/Total pages"), pages_read = _("Pages read"),
    avg_page = _("Average time per page"),
}

local function buildCurrentStats(kv_pairs)
    local P = getP()
    local S = P.S
    local by, order = {}, {}
    for _i, e in ipairs(kv_pairs) do
        if type(e) == "table" then
            local k = plainKey(e[1])
            local id
            for name, txt in pairs(CUR) do if txt == k then id = name end end
            e._key = k
            if id then by[id] = e end
            table.insert(order, { id = id, e = e })
        end
    end
    local RUI = package.loaded["apps/reader/readerui"]
    local props = RUI and RUI.instance and RUI.instance.doc_props
    local title = props and (props.display_title or props.title) or nil

    return P.Page:new{
        title = _("Current statistics"),
        subtitle = title,
        in_reader = true,
        build = function(_page, w, h)
            local widgets = {}
            -- Progreso
            local cur = by.current and tostring(by.current[2]) or ""
            local pct = tonumber(cur:match("%((%d+)%%%)")) or 0
            local pages_txt = cur:gsub("%s*%(.-%)%s*$", "")
            local fin = by.finish or by.finished
            local fin_txt = fin and tostring(fin[2]):gsub("^%s*%(.-%)%s*", "") or nil
            local in_w = P.cardInner(w)
            local sub = pages_txt
            if fin_txt and fin_txt ~= "" then sub = sub .. " · " .. fin_txt end
            table.insert(widgets, P.tappable(P.card(VerticalGroup:new{
                align = "left",
                P.label(_("Progress")),
                VerticalSpan:new{ width = S(4) },
                TextWidget:new{ text = pct .. " %", face = P.face(true, 22), fgcolor = P.BLACK, padding = 0 },
                VerticalSpan:new{ width = S(6) },
                P.bar(in_w, pct / 100, S(7)),
                VerticalSpan:new{ width = S(6) },
                TextWidget:new{ text = sub, face = P.face(false, 12), fgcolor = P.GRAY_DARK, max_width = in_w, padding = 0 },
            }, w, { gray = true }), fin and fin.callback))
            -- 4 casillas
            local gap = S(P.GAP)
            local tw = math.floor((w - gap) / 2)
            local function tile(id)
                local e = by[id]
                return P.tile(e and e[2] or "—", e and e._key or CUR[id], tw, e and e.callback)
            end
            table.insert(widgets, HorizontalGroup:new{ align = "top", tile("read_time"), HorizontalSpan:new{ width = gap }, tile("avg_page") })
            table.insert(widgets, HorizontalGroup:new{ align = "top", tile("days"), HorizontalSpan:new{ width = gap }, tile("today_pages") })
            -- Resto, en filas
            local used = { current = true, read_time = true, avg_page = true, days = true, today_pages = true,
                finish = true, finished = true }
            -- (una a una: si no, todas juntas pasaban a la página siguiente)
            local first_row = true
            for _i, o in ipairs(order) do
                if not (o.id and used[o.id]) then
                    local r = P.row(o.e._key, o.e[2], w, o.e.callback)
                    if first_row then
                        first_row = false
                    else
                        r._aire_gap = 0
                    end
                    table.insert(widgets, r)
                end
            end
            return P.packPages(widgets, h)
        end,
    }
end

--===========================================================================
-- Intervalo de tiempo
--===========================================================================
local function dbSummary(stats)
    pcall(stats.insertDB, stats)
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(DataStorage:getSettingsDir() .. "/statistics.sqlite3")
    local res = {}
    local ok, err = pcall(function()
        local total, books = conn:rowexec("SELECT sum(duration), count(DISTINCT id_book) FROM page_stat;")
        res.total, res.books = tonumber(total) or 0, tonumber(books) or 0
        local t = os.date("*t")
        local wday = (t.wday + 5) % 7 -- lunes = 0
        local week_start = os.time{ year = t.year, month = t.month, day = t.day - wday, hour = 0 }
        local month_start = os.time{ year = t.year, month = t.month, day = 1, hour = 0 }
        res.week = tonumber(conn:rowexec(string.format("SELECT sum(duration) FROM page_stat WHERE start_time >= %d;", week_start))) or 0
        res.month = tonumber(conn:rowexec(string.format("SELECT sum(duration) FROM page_stat WHERE start_time >= %d;", month_start))) or 0
    end)
    conn:close()
    if not ok then logger.warn("Aire/Stats: resumen:", err) end
    return res
end

-- Lista en tarjetas con barra (semanas, meses, libros)
local function showListPage(stats, title, subtitle, kv_pairs, metric)
    local P = getP()
    local S = P.S
    local page
    page = P.Page:new{
        title = title,
        subtitle = subtitle,
        build = function(_pg, w, h)
            local maxv = 0
            for _i, e in ipairs(kv_pairs) do
                local v = metric(e) or 0
                if v > maxv then maxv = v end
            end
            local widgets = {}
            local in_w = P.cardInner(w)
            for _i, e in ipairs(kv_pairs) do
                if type(e) == "table" and e[1] then
                    local val = TextWidget:new{ text = tostring(e[2] or ""), face = P.face(false, 12),
                        fgcolor = P.GRAY_DARK, padding = 0, max_width = math.floor(in_w * 0.55) }
                    local name = TextWidget:new{ text = tostring(e[1]), face = P.face(true, 14), fgcolor = P.BLACK,
                        padding = 0, max_width = in_w - val:getSize().w - S(8) }
                    local lh = math.max(name:getSize().h, val:getSize().h)
                    local v = metric(e) or 0
                    local content = VerticalGroup:new{
                        align = "left",
                        OverlapGroup:new{
                            dimen = Geom:new{ w = in_w, h = lh },
                            LeftContainer:new{ dimen = Geom:new{ w = in_w, h = lh }, name },
                            RightContainer:new{ dimen = Geom:new{ w = in_w, h = lh }, val },
                        },
                        VerticalSpan:new{ width = S(6) },
                        P.bar(in_w, maxv > 0 and v / maxv or 0),
                    }
                    local cb = e.callback
                    table.insert(widgets, P.tappable(P.card(content, w), cb and function()
                        stats.kv = page
                        cb()
                    end))
                end
            end
            return P.packPages(widgets, h)
        end,
    }
    stats.kv = page
    page:show()
end

local function pagesOf(e) return tonumber(tostring(e[2] or ""):match("%((%d+)")) end
local function secondsOf(e) return parseDuration(e[2]) end

local function showTimeRange(stats)
    local P = getP()
    local S = P.S
    local sum = dbSummary(stats)
    local main
    main = P.Page:new{
        title = _("Time range statistics"),
        build = function(_pg, w, h)
            local in_w = P.cardInner(w)
            local function navCard(title, sub, on_tap)
                local chevron = TextWidget:new{ text = "›", face = P.face(false, 18), fgcolor = P.GRAY_DARK, padding = 0 }
                local t = TextWidget:new{ text = title, face = P.face(true, 15), fgcolor = P.BLACK, padding = 0,
                    max_width = in_w - chevron:getSize().w - S(8) }
                local s = TextWidget:new{ text = sub or "", face = P.face(false, 12), fgcolor = P.GRAY_DARK,
                    padding = 0, max_width = in_w - chevron:getSize().w - S(8) }
                local vg = VerticalGroup:new{ align = "left", t, VerticalSpan:new{ width = S(3) }, s }
                local hh = vg:getSize().h
                return P.tappable(P.card(OverlapGroup:new{
                    dimen = Geom:new{ w = in_w, h = hh },
                    LeftContainer:new{ dimen = Geom:new{ w = in_w, h = hh }, vg },
                    RightContainer:new{ dimen = Geom:new{ w = in_w, h = hh }, chevron },
                }, w, { padding = S(12) }), on_tap)
            end
            local widgets = {
                navCard(_("All books"), fmtDuration(sum.total) .. " · " .. T(N_("%1 book", "%1 books", sum.books or 0), sum.books or 0),
                    function()
                        local total_msg, kv = stats:getTotalStats()
                        showListPage(stats, _("All books"), total_msg, kv, secondsOf)
                    end),
                navCard(_("Books by week"), T(_("This week: %1"), fmtDuration(sum.week)), function()
                    showListPage(stats, _("Books by week"), nil, stats:getDatesFromAll(0, "weekly", true), pagesOf)
                end),
                navCard(_("Books by month"), T(_("This month: %1"), fmtDuration(sum.month)), function()
                    showListPage(stats, _("Books by month"), nil, stats:getDatesFromAll(0, "monthly", true), pagesOf)
                end),
            }
            return P.packPages(widgets, h)
        end,
        close_callback = function() stats.kv = nil end,
    }
    stats.kv = main
    main:show()
end

--===========================================================================
-- Línea de tiempo de hoy
--===========================================================================
local SHADES = { 0x00, 0x66, 0x99, 0x33, 0xBB, 0x55 }
local function shade(i) return Blitbuffer.Color8(SHADES[((i - 1) % #SHADES) + 1]) end

-- Pista de una hora: línea fina y los ratos de lectura como barras redondeadas
local HourTrack = Widget:extend{ width = 0, height = 0, spans = nil }
function HourTrack:getSize() return Geom:new{ w = self.width, h = self.height } end
function HourTrack:paintTo(bb, x, y)
    local h = self.height
    bb:paintRect(x, y + math.floor(h / 2), self.width, 1, Blitbuffer.COLOR_LIGHT_GRAY)
    local bh = math.max(4, math.floor(h * 0.55))
    local by = y + math.floor((h - bh) / 2)
    for _i, sp in ipairs(self.spans or {}) do
        local sx = x + math.floor(self.width * sp.a)
        local sw = math.max(bh, math.floor(self.width * (sp.b - sp.a)))
        bb:paintRoundedRect(sx, by, sw, bh, sp.color, math.floor(bh / 2))
    end
end

local function showTimeline(stats, day_offset)
    local P = getP()
    local S = P.S
    local settings = stats.settings or {}
    local start_h, start_m = settings.calendar_day_start_hour or 0, settings.calendar_day_start_minute or 0
    local now = os.time()
    local d = os.date("*t", now)
    if d.hour * 3600 + d.min * 60 + d.sec < start_h * 3600 + start_m * 60 then
        d = os.date("*t", now - 86400 + 10800)
    end
    local day_ts = os.time{ year = d.year, month = d.month, day = d.day + (day_offset or 0), hour = start_h, min = start_m }
    local books = stats:getBooksFromPeriod(day_ts, day_ts + 86400) or {}
    local secs = stats:getReadingDurationBySecond(day_ts) or {}
    table.sort(books, function(a, b) return (a.duration or 0) > (b.duration or 0) end)
    local total = 0
    for _i, b in ipairs(books) do total = total + (tonumber(b.duration) or 0) end
    local date_txt = datetime.secondsToDate(day_ts, true)

    local page
    page = P.Page:new{
        title = (day_offset or 0) == 0 and _("Today's timeline") or date_txt,
        subtitle = ((day_offset or 0) == 0 and date_txt .. " · " or "") .. fmtDuration(total),
        build = function(_pg, w, h)
            local widgets = {}
            local colors = {}
            for i, b in ipairs(books) do colors[b.book_id] = shade(i) end
            -- Horas seguidas, de la primera a la última con lectura
            local by_hour, first_h, last_h = {}, nil, nil
            for hr = 0, 23 do
                local a0, a1 = hr * 3600, (hr + 1) * 3600
                local spans = {}
                for book_id, v in pairs(secs) do
                    for _j, p in ipairs(v.periods or {}) do
                        local s0, s1 = math.max(a0, p.start or 0), math.min(a1, p.finish or 0)
                        if s1 > s0 then
                            table.insert(spans, { a = (s0 - a0) / 3600, b = (s1 - a0) / 3600, color = colors[book_id] or P.BLACK })
                        end
                    end
                end
                if #spans > 0 then
                    by_hour[hr] = spans
                    first_h = first_h or hr
                    last_h = hr
                end
            end
            -- (las filas se montan al final: su alto depende de lo que quede libre)
            local build_rows
            if first_h then
              build_rows = function(hh)
                local label_w = S(56)
                local track_w = w - label_w
                local rows = VerticalGroup:new{ align = "left" }
                for hr = first_h, last_h do
                    local lbl = string.format("%02d:%02d", (hr + start_h) % 24, start_m)
                    table.insert(rows, HorizontalGroup:new{
                        align = "center",
                        LeftContainer:new{ dimen = Geom:new{ w = label_w, h = hh },
                            TextWidget:new{ text = lbl, face = P.face(false, 13),
                                fgcolor = by_hour[hr] and P.BLACK or P.GRAY_DARK, padding = 0 } },
                        HourTrack:new{ width = track_w, height = hh, spans = by_hour[hr] or {} },
                    })
                end
                return rows
              end
            else
                table.insert(widgets, CenterContainer:new{ dimen = Geom:new{ w = w, h = S(160) },
                    TextWidget:new{ text = _("No reading activity in this period"), face = P.face(false, 14),
                        fgcolor = P.GRAY_DARK, padding = 0 } })
            end
            -- Libros del día: leyenda en una tarjeta (tono, título, tiempo)
            if #books > 0 then
                local in_w = P.cardInner(w)
                local list = VerticalGroup:new{ align = "left" }
                for i, b in ipairs(books) do
                    local sq = S(14)
                    local Sq = Widget:extend{}
                    local color = shade(i)
                    function Sq:getSize() return Geom:new{ w = sq, h = sq } end
                    function Sq:paintTo(bb, x, y) bb:paintRoundedRect(x, y, sq, sq, color, math.floor(sq / 3)) end
                    local tm = TextWidget:new{ text = tostring(b[2] or ""), face = P.face(false, 13),
                        fgcolor = P.GRAY_DARK, padding = 0 }
                    local name_w = in_w - sq - S(10) - tm:getSize().w - S(10)
                    local name = TextWidget:new{ text = tostring(b[1] or ""), face = P.face(true, 14),
                        fgcolor = P.BLACK, padding = 0, max_width = math.max(S(40), name_w) }
                    local lh = S(34)
                    if i > 1 then table.insert(list, P.line(in_w)) end
                    table.insert(list, OverlapGroup:new{
                        dimen = Geom:new{ w = in_w, h = lh },
                        LeftContainer:new{ dimen = Geom:new{ w = in_w, h = lh },
                            HorizontalGroup:new{ align = "center", Sq:new{}, HorizontalSpan:new{ width = S(10) }, name } },
                        RightContainer:new{ dimen = Geom:new{ w = in_w, h = lh }, tm },
                    })
                end
                table.insert(widgets, P.card(list, w))
            end
            -- Cambiar de día (flechas como iconos)
            local bw = math.floor((w - S(P.GAP)) / 2)
            local function navBtn(icon, on_tap, disabled)
                local bh = S(48)
                local frame = FrameContainer:new{
                    width = bw, height = bh, bordersize = Size.border.thin,
                    color = Blitbuffer.COLOR_GRAY, background = P.WHITE, radius = S(10), padding = 0,
                    CenterContainer:new{ dimen = Geom:new{ w = bw - 2 * Size.border.thin, h = bh - 2 * Size.border.thin },
                        IconWidget:new{ icon = icon, width = S(28), height = S(28), alpha = true,
                            dim = disabled or nil } },
                }
                if disabled then return frame end
                return P.tappable(frame, on_tap)
            end
            table.insert(widgets, HorizontalGroup:new{
                align = "center",
                navBtn("chevron.left", function() page:onClose(); showTimeline(stats, (day_offset or 0) - 1) end),
                HorizontalSpan:new{ width = S(P.GAP) },
                navBtn("chevron.right", function() page:onClose(); showTimeline(stats, (day_offset or 0) + 1) end,
                    (day_offset or 0) >= 0),
            })
            if build_rows then
                -- Filas de 40 si caben; si no, más bajas (mín. 24) para que la
                -- leyenda y las flechas sigan en la misma página
                local others = 0
                for _i, wd in ipairs(widgets) do others = others + wd:getSize().h + S(P.GAP) end
                local n = last_h - first_h + 1
                local hh = math.max(S(24), math.min(S(40), math.floor((h - others) / n)))
                table.insert(widgets, 1, build_rows(hh))
            end
            return P.packPages(widgets, h)
        end,
    }
    page:show()
    return page
end

--===========================================================================
-- Enganches
--===========================================================================
local function patchStats(ReaderStatistics)
    if not ReaderStatistics or ReaderStatistics._aire_stat_pages then return end
    ReaderStatistics._aire_stat_pages = true

    -- Estadísticas libro actual: KOReader crea un KeyValuePage con este título
    -- (desde el menú y desde la acción de gestos): se devuelve la pantalla de Aire
    if not KeyValuePage._aire_current_stats then
        KeyValuePage._aire_current_stats = true
        local title_cur = _("Current statistics")
        local base_new = KeyValuePage.new
        KeyValuePage.new = function(cls, o)
            if cls == KeyValuePage and type(o) == "table" and o.title == title_cur and type(o.kv_pairs) == "table" then
                local ok, page = pcall(buildCurrentStats, o.kv_pairs)
                if ok and page then return page end
                logger.warn("Aire/Stats: libro actual:", page)
            end
            return base_new(cls, o)
        end
    end

    safeWrap(ReaderStatistics, "onShowTimeRange", function(orig_range, self, ...)
        local ok, err = pcall(showTimeRange, self)
        if ok then return true end
        logger.warn("Aire/Stats: intervalo de tiempo:", err)
        return orig_range(self, ...)
    end, TAG)

    local ok_cv, CalendarView = pcall(require, "calendarview")
    if ok_cv and type(CalendarView) == "table" and CalendarView.showCalendarDayView and not CalendarView._aire_timeline_page then
        CalendarView._aire_timeline_page = true
        local orig_day = CalendarView.showCalendarDayView
        CalendarView.showCalendarDayView = function(cv, reader_statistics, ...)
            local ok, err = pcall(showTimeline, reader_statistics, 0)
            if ok then return end
            logger.warn("Aire/Stats: línea de tiempo:", err)
            return orig_day(cv, reader_statistics, ...)
        end
    end
end

-- Protegido: los parches de plugins se ejecutan dentro de FileManager:init
userpatch.registerPatchPluginFunc("statistics", function(plugin)
    local ok, err = pcall(patchStats, plugin)
    if not ok then logger.warn("Aire/Stats: no se pudo aplicar:", err) end
end)

logger.dbg("Aire/StatsPages: aplicado desde el plugin")
