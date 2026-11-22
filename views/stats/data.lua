--[[
    aire.koplugin/views/stats/data.lua
    Datos de la pestaña Estadísticas (views/stats/init.lua): lectura de la base de
    datos de KOReader (statistics.sqlite3), resúmenes, mes, día, recapitulación,
    géneros más leídos, hábitos horarios/semanales y caché de sesión. Sin widgets.
    state.FAKE: estadísticas de prueba (devtools.lua); lo fija el mixin.
--]]

local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local DB_FILE = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local BOOKINFO_DB = DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3"
local state = { FAKE = nil }

-- Caché de sesión: se invalida sola si cambia statistics.sqlite3,
-- bookinfo_cache.sqlite3, el día, el idioma o el modo de prueba.
local cache = {
    stats_key = nil, stats = nil,
    kw_key = nil, kw_map = nil,
    months = {},
    recaps = {},
}

local function invalidateCache()
    cache.stats_key, cache.stats = nil, nil
    cache.kw_key, cache.kw_map = nil, nil
    cache.months = {}
    cache.recaps = {}
end


---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
local function fmtDuration(secs)
    secs = math.floor(tonumber(secs) or 0)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return ("%d h %02d min"):format(h, m) end
    return ("%d min"):format(m)
end

local function fmtDelta(pct)
    if pct == nil then return nil end
    if pct > 0 then return ("+%d%%"):format(pct) end
    return ("%d%%"):format(pct)
end

local function calcSpeed(pages, secs)
    if not secs or secs < 60 or not pages or pages <= 0 then return 0 end
    return math.floor(pages / (secs / 3600) + 0.5)
end

local function calcDelta(cur, prev)
    if not prev or prev <= 0 then return nil end
    return math.floor(((cur or 0) - prev) / prev * 100 + 0.5)
end

-- Abre statistics.sqlite3, ejecuta fn(conn) y cierra SIEMPRE la conexión
-- (también si fn falla: así no quedan la base ni sentencias abiertas).
local function withDB(fn)
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(DB_FILE)
    local ok, err = pcall(fn, conn)
    pcall(conn.close, conn)
    if not ok then error(err, 0) end
end

-- Abre bookinfo_cache.sqlite3 en solo lectura para cruzar géneros (keywords)
local function withBookinfoDB(fn)
    if lfs.attributes(BOOKINFO_DB, "mode") ~= "file" then return false end
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(BOOKINFO_DB, "ro")
    local ok, err = pcall(fn, conn)
    pcall(conn.close, conn)
    if not ok then error(err, 0) end
    return true
end

local function dayStart(t)
    local d = os.date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d)
end

local function fileSig(path)
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then return "0:0" end
    return tostring(attr.modification or 0) .. ":" .. tostring(attr.size or 0)
end

local function cacheKey(extra)
    local lang = G_reader_settings and G_reader_settings:readSetting("language") or ""
    local fake = state.FAKE and "1" or "0"
    local day = os.date("%Y-%m-%d")
    return table.concat({ fake, day, lang, fileSig(DB_FILE), fileSig(BOOKINFO_DB), extra or "" }, "|")
end


---------------------------------------------------------------------------
-- Géneros, autores y rachas
---------------------------------------------------------------------------
local function getGenresMod()
    return package.loaded.aire_genres
end

-- Mapa title/authors normalizados -> keywords desde bookinfo_cache.sqlite3
local function getBookKeywordsMap()
    local key = fileSig(BOOKINFO_DB)
    if cache.kw_key == key and cache.kw_map then return cache.kw_map end
    local map = { by_ta = {}, by_t = {} }
    local Genres = getGenresMod()
    local norm = Genres and Genres.normalize or function(s) return (s or ""):lower():match("^%s*(.-)%s*$") or "" end
    local akey = Genres and Genres.authorKey or norm

    local ok, err = pcall(withBookinfoDB, function(conn)
        local stmt = conn:prepare(
            "SELECT title, authors, keywords FROM bookinfo "
            .. "WHERE keywords IS NOT NULL AND keywords != '' AND (in_progress = 0 OR in_progress IS NULL)"
        )
        local row = stmt:step()
        while row do
            local title, authors, kw = row[1], row[2], row[3]
            if title and title ~= "" and kw and kw ~= "" then
                local tk = norm(title)
                if tk ~= "" then
                    if authors and authors ~= "" then
                        local ak = akey(authors)
                        if ak ~= "" then map.by_ta[tk .. "\0" .. ak] = kw end
                    end
                    if not map.by_t[tk] then map.by_t[tk] = kw end
                end
            end
            row = stmt:step()
        end
        stmt:close()
    end)
    if not ok then logger.warn("Aire/Stats: error leyendo bookinfo_cache.sqlite3:", err) end

    cache.kw_key, cache.kw_map = key, map
    return map
end

local function lookupKeywords(kw_map, title, authors)
    if not kw_map or not title or title == "" then return nil end
    local Genres = getGenresMod()
    local norm = Genres and Genres.normalize or function(s) return (s or ""):lower():match("^%s*(.-)%s*$") or "" end
    local akey = Genres and Genres.authorKey or norm
    local tk = norm(title)
    if tk == "" then return nil end
    if authors and authors ~= "" then
        local ak = akey(authors)
        if ak ~= "" and kw_map.by_ta[tk .. "\0" .. ak] then
            return kw_map.by_ta[tk .. "\0" .. ak]
        end
    end
    return kw_map.by_t[tk]
end

-- Calcula top géneros a partir de una lista de libros { title, authors, secs, pages }
local function computeTopGenres(books_rows, kw_map, limit)
    local Genres = getGenresMod()
    if not Genres or not books_rows or #books_rows == 0 then return {} end
    local by, list = {}, {}
    local total_secs = 0
    for _i, b in ipairs(books_rows) do
        local kw = b.keywords or lookupKeywords(kw_map, b.title, b.authors)
        if kw and kw ~= "" then
            local extracted = Genres.extractGenres(kw)
            if extracted and #extracted > 0 then
                for _j, g in ipairs(extracted) do
                    local entry = by[g.key]
                    if not entry then
                        entry = {
                            key = g.key, label = g.label, canonical = g.canonical,
                            secs = 0, pages = 0, books = 0,
                        }
                        by[g.key] = entry
                        table.insert(list, entry)
                    elseif not g.canonical then
                        entry.label = Genres.betterLabel(entry.label, g.label)
                    end
                    entry.secs = entry.secs + (b.secs or 0)
                    entry.pages = entry.pages + (b.pages or 0)
                    entry.books = entry.books + 1
                    total_secs = total_secs + (b.secs or 0)
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.secs ~= b.secs then return a.secs > b.secs end
        if a.books ~= b.books then return a.books > b.books end
        return a.label < b.label
    end)
    local out = {}
    local cap = math.min(limit or 5, #list)
    for i = 1, cap do
        local g = list[i]
        table.insert(out, {
            key = g.key,
            label = g.label,
            secs = g.secs,
            pages = g.pages,
            books = g.books,
            pct = total_secs > 0 and math.floor(g.secs / total_secs * 100 + 0.5) or 0,
        })
    end
    return out
end

-- Agrupa autores normalizados (sin separar por mayúsculas, tildes ni coautores en líneas)
local function computeTopAuthor(books_rows)
    if not books_rows or #books_rows == 0 then return nil end
    local Genres = getGenresMod()
    local by = {}
    for _i, b in ipairs(books_rows) do
        if b.authors and b.authors ~= "" then
            local seen = {}
            for raw in b.authors:gmatch("[^\n]+") do
                local name = raw:match("^%s*(.-)%s*$")
                if name and name ~= "" then
                    local ak = Genres and Genres.authorKey(name) or name:lower()
                    if ak ~= "" and not seen[ak] then
                        seen[ak] = true
                        local entry = by[ak]
                        if not entry then
                            entry = { name = name, secs = 0, books = 0 }
                            by[ak] = entry
                        elseif Genres then
                            entry.name = Genres.betterLabel(entry.name, name)
                        end
                        entry.secs = entry.secs + (b.secs or 0)
                        entry.books = entry.books + 1
                    end
                end
            end
        end
    end
    local best
    for _k, entry in pairs(by) do
        if not best or entry.secs > best.secs then best = entry end
    end
    return best
end

-- Mejor racha (días consecutivos) a partir de una lista ordenada de "YYYY-MM-DD"
local function computeBestStreak(sorted_days)
    local best, run, prev = 0, 0, nil
    for _i, ds in ipairs(sorted_days) do
        local y, m, d = ds:match("^(%d+)%-(%d+)%-(%d+)$")
        if y then
            local num = math.floor(os.time{
                year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12,
            } / 86400 + 0.5)
            if prev and num == prev + 1 then
                run = run + 1
            else
                run = 1
            end
            if run > best then best = run end
            prev = num
        end
    end
    return best
end


---------------------------------------------------------------------------
-- Consultas compartidas de hábitos y libros en un rango [t0, t1)
---------------------------------------------------------------------------
local SLOT_IDS = { "morning", "afternoon", "evening", "night" }

-- Franjas horarias: morning (06-11), afternoon (12-17), evening (18-23), night (00-05)
local function queryTimeSlots(conn, t0, t1)
    local totals = { morning = 0, afternoon = 0, evening = 0, night = 0 }
    local stmt = conn:prepare(
        "SELECT CAST(strftime('%H', start_time, 'unixepoch', 'localtime') AS INTEGER) AS h, sum(duration) "
        .. "FROM page_stat_data WHERE start_time >= ? AND start_time < ? GROUP BY h"
    )
    stmt:bind(t0, t1)
    local row = stmt:step()
    local grand = 0
    while row do
        local h = tonumber(row[1]) or 0
        local secs = tonumber(row[2]) or 0
        local id
        if h >= 6 and h < 12 then id = "morning"
        elseif h >= 12 and h < 18 then id = "afternoon"
        elseif h >= 18 then id = "evening"
        else id = "night" end
        totals[id] = totals[id] + secs
        grand = grand + secs
        row = stmt:step()
    end
    stmt:close()

    local slots, fav, fav_s = {}, nil, 0
    for _i, id in ipairs(SLOT_IDS) do
        local secs = totals[id]
        if secs > fav_s then fav, fav_s = id, secs end
        table.insert(slots, {
            id = id,
            secs = secs,
            pct = grand > 0 and math.floor(secs / grand * 100 + 0.5) or 0,
        })
    end
    return slots, fav
end

-- Distribución por día de la semana (1 = lunes .. 7 = domingo)
local function queryWeekdays(conn, t0, t1)
    local totals = { 0, 0, 0, 0, 0, 0, 0 }
    local stmt = conn:prepare(
        "SELECT CAST(strftime('%w', start_time, 'unixepoch', 'localtime') AS INTEGER) AS w, sum(duration) "
        .. "FROM page_stat_data WHERE start_time >= ? AND start_time < ? GROUP BY w"
    )
    stmt:bind(t0, t1)
    local row = stmt:step()
    local grand = 0
    while row do
        local w = tonumber(row[1]) or 0 -- SQLite: 0=domingo .. 6=sábado
        local idx = (w == 0) and 7 or w -- 1=lunes .. 7=domingo
        local secs = tonumber(row[2]) or 0
        totals[idx] = totals[idx] + secs
        grand = grand + secs
        row = stmt:step()
    end
    stmt:close()

    local dayLetter = package.loaded.aire_ui and package.loaded.aire_ui.dayLetter
    local days, fav, fav_s = {}, nil, 0
    for i = 1, 7 do
        local secs = totals[i]
        if secs > fav_s then fav, fav_s = i, secs end
        local lua_wday = (i % 7) + 1 -- 1=domingo, 2=lunes .. 7=sábado
        table.insert(days, {
            wday = i,
            letter = dayLetter and dayLetter(lua_wday) or tostring(i),
            secs = secs,
            pct = grand > 0 and math.floor(secs / grand * 100 + 0.5) or 0,
        })
    end
    return days, fav
end

-- Todos los libros leídos en [t0, t1), ordenados por tiempo descendente
local function queryBooksInRange(conn, t0, t1)
    local list = {}
    local stmt = conn:prepare(
        "SELECT p.id_book, book.title, book.authors, sum(p.duration) AS s, count(DISTINCT p.page) "
        .. "FROM page_stat_data AS p JOIN book ON book.id = p.id_book "
        .. "WHERE p.start_time >= ? AND p.start_time < ? GROUP BY p.id_book ORDER BY s DESC"
    )
    stmt:bind(t0, t1)
    local row = stmt:step()
    while row do
        table.insert(list, {
            id_book = tonumber(row[1]),
            title = row[2] or "?",
            authors = row[3],
            secs = tonumber(row[4]) or 0,
            pages = tonumber(row[5]) or 0,
        })
        row = stmt:step()
    end
    stmt:close()
    return list
end

local function queryTotalSecs(conn, t0, t1)
    local stmt = conn:prepare("SELECT sum(duration) FROM page_stat_data WHERE start_time >= ? AND start_time < ?")
    stmt:bind(t0, t1)
    local row = stmt:step()
    local secs = row and tonumber(row[1]) or 0
    stmt:close()
    return secs
end


---------------------------------------------------------------------------
-- Calendario: utilidades de meses/días (se definen aquí para usarlas en stats y recap)
---------------------------------------------------------------------------
local MONTHS, WEEKDAYS_LONG = {}, {}
do
    local dt = require("datetime")
    for i, m in ipairs({ "January", "February", "March", "April", "May", "June", "July",
                         "August", "September", "October", "November", "December" }) do
        MONTHS[i] = dt.longMonthTranslation[m] or m
    end
    for i, d in ipairs(dt.weekDays) do
        WEEKDAYS_LONG[i] = dt.shortDayOfWeekToLongTranslation[d] or d
    end
end

local function monthRange(year, month)
    local t0 = os.time{ year = year, month = month, day = 1, hour = 0 }
    local ny, nm = year, month + 1
    if nm > 12 then ny, nm = year + 1, 1 end
    local t1 = os.time{ year = ny, month = nm, day = 1, hour = 0 }
    local ndays = tonumber(os.date("%d", t1 - 12 * 3600))
    return t0, t1, ndays
end


---------------------------------------------------------------------------
-- Resumen principal (pestaña Estadísticas + widgets de inicio)
---------------------------------------------------------------------------
local function loadStats()
    local lastfile = G_reader_settings and G_reader_settings:readSetting("lastfile") or ""
    local ckey = cacheKey("stats:" .. lastfile)
    if cache.stats_key == ckey and cache.stats then
        return cache.stats
    end

    local now = os.time()
    local now_t = os.date("*t", now)
    local today0 = dayStart(now)
    local st = {
        today_secs = 0, today_pages = 0,
        week = {}, week_total = 0, prev_week_total = 0, week_delta_pct = nil,
        streak = 0, best_streak = 0,
        month_secs = 0, month_pages = 0, month_read_days = 0,
        month_avg_secs = 0, month_speed = 0, prev_month_secs = 0, month_delta_pct = nil,
        year_secs = 0, year_pages = 0, year_speed = 0,
        all_secs = 0, all_pages = 0,
        finished_year = 0,
        top_genres = {},
        time_slots = {}, fav_slot = nil,
        weekdays = {}, fav_weekday = nil,
        current = nil,
        year = os.date("%Y", now),
        ok = false,
    }

    -- Días de la semana: de hace 6 días a hoy
    for i = 6, 0, -1 do
        local t = today0 - i * 86400 + 3600 * 12 -- mediodía, para no pisar cambios de hora
        table.insert(st.week, {
            key = os.date("%Y-%m-%d", t),
            letter = package.loaded.aire_ui.dayLetter(os.date("*t", t).wday),
            secs = 0,
        })
    end

    -- Pruebas: datos inventados (devtools.lua, opción "Estadísticas de prueba")
    if state.FAKE and state.FAKE.fakeStats then
        local ok_f, res = pcall(state.FAKE.fakeStats, st)
        if ok_f and res then
            cache.stats_key, cache.stats = ckey, res
            return res
        end
        logger.warn("Aire/Stats: error en las estadísticas de prueba:", res)
    end

    if lfs.attributes(DB_FILE, "mode") == "file" then
        local year_books
        local ok, err = pcall(withDB, function(conn)
            -- Hoy, este mes y este año: tiempo y páginas distintas
            local q_period = "SELECT count(*), sum(d) FROM (SELECT id_book, page, sum(duration) AS d "
                .. "FROM page_stat_data WHERE start_time >= %d GROUP BY id_book, page)"
            local tp, ts = conn:rowexec(q_period:format(today0))
            st.today_pages, st.today_secs = tonumber(tp) or 0, tonumber(ts) or 0

            local month0 = os.time{ year = now_t.year, month = now_t.month, day = 1, hour = 0 }
            local mp, ms = conn:rowexec(q_period:format(month0))
            st.month_pages, st.month_secs = tonumber(mp) or 0, tonumber(ms) or 0

            local year0 = os.time{ year = now_t.year, month = 1, day = 1, hour = 0 }
            local yp, ys = conn:rowexec(q_period:format(year0))
            st.year_pages, st.year_secs = tonumber(yp) or 0, tonumber(ys) or 0

            local ap, as_ = conn:rowexec(q_period:format(0))
            st.all_pages, st.all_secs = tonumber(ap) or 0, tonumber(as_) or 0

            -- Días leídos este mes (para media diaria)
            local mrd = conn:rowexec(string.format(
                "SELECT count(DISTINCT date(start_time, 'unixepoch', 'localtime')) "
                .. "FROM page_stat_data WHERE start_time >= %d AND duration > 0", month0))
            st.month_read_days = tonumber(mrd) or 0
            st.month_avg_secs = st.month_read_days > 0 and math.floor(st.month_secs / st.month_read_days) or 0
            st.month_speed = calcSpeed(st.month_pages, st.month_secs)
            st.year_speed = calcSpeed(st.year_pages, st.year_secs)

            -- Comparativa mes anterior (mismos días transcurridos del mes anterior)
            local py, pm = now_t.year, now_t.month - 1
            if pm < 1 then py, pm = py - 1, 12 end
            local pm0, pm1, p_ndays = monthRange(py, pm)
            if now_t.day < p_ndays then
                pm1 = os.time{ year = py, month = pm, day = now_t.day + 1, hour = 0 }
            end
            st.prev_month_secs = queryTotalSecs(conn, pm0, pm1)
            st.month_delta_pct = calcDelta(st.month_secs, st.prev_month_secs)

            -- Últimos 7 días, por día + semana anterior para comparativa
            local by_day = {}
            local week0 = today0 - 6 * 86400
            local stmt = conn:prepare("SELECT date(start_time, 'unixepoch', 'localtime') AS day, sum(duration) "
                .. "FROM page_stat_data WHERE start_time >= ? GROUP BY day")
            stmt:bind(week0)
            local row = stmt:step()
            while row do
                by_day[row[1]] = tonumber(row[2]) or 0
                row = stmt:step()
            end
            stmt:close()
            for _i, d in ipairs(st.week) do
                d.secs = by_day[d.key] or 0
                st.week_total = st.week_total + d.secs
            end
            st.prev_week_total = queryTotalSecs(conn, week0 - 7 * 86400, week0)
            st.week_delta_pct = calcDelta(st.week_total, st.prev_week_total)

            -- Racha actual y mejor racha histórica
            local days_set, sorted_days = {}, {}
            stmt = conn:prepare("SELECT DISTINCT date(start_time, 'unixepoch', 'localtime') "
                .. "FROM page_stat_data WHERE duration > 0 ORDER BY 1 ASC")
            row = stmt:step()
            while row do
                if row[1] then
                    days_set[row[1]] = true
                    table.insert(sorted_days, row[1])
                end
                row = stmt:step()
            end
            stmt:close()
            local t = today0 + 3600 * 12
            if not days_set[os.date("%Y-%m-%d", t)] then t = t - 86400 end
            while days_set[os.date("%Y-%m-%d", t)] do
                st.streak = st.streak + 1
                t = t - 86400
            end
            st.best_streak = computeBestStreak(sorted_days)

            -- Hábitos del año en curso (franjas horarias, días de la semana, géneros)
            local now_end = now + 1
            st.time_slots, st.fav_slot = queryTimeSlots(conn, year0, now_end)
            st.weekdays, st.fav_weekday = queryWeekdays(conn, year0, now_end)
            year_books = queryBooksInRange(conn, year0, now_end)
            -- Si este año aún no hay lectura, caemos al histórico completo para hábitos/géneros
            if #year_books == 0 then
                st.time_slots, st.fav_slot = queryTimeSlots(conn, 0, now_end)
                st.weekdays, st.fav_weekday = queryWeekdays(conn, 0, now_end)
                year_books = queryBooksInRange(conn, 0, now_end)
            end

            -- Libro actual: tiempo leído y velocidad en ese libro
            if lastfile ~= "" and lfs.attributes(lastfile, "mode") == "file" then
                local md5 = util.partialMD5(lastfile)
                if md5 then
                    local s2 = conn:prepare("SELECT total_read_time, total_read_pages FROM book WHERE md5 = ?")
                    s2:bind(md5)
                    local r2 = s2:step()
                    if r2 then
                        st.current = {
                            file = lastfile,
                            read_secs = tonumber(r2[1]) or 0,
                            read_pages = tonumber(r2[2]) or 0,
                        }
                    end
                    s2:close()
                end
            end
        end)
        if ok then
            st.ok = true
            if year_books and #year_books > 0 then
                st.top_genres = computeTopGenres(year_books, getBookKeywordsMap(), 5)
            end
        else
            logger.warn("Aire/Stats: error leyendo statistics.sqlite3:", err)
        end
    end

    cache.stats_key, cache.stats = ckey, st
    return st
end

-- Respaldo de countFinishedYear: libros del historial con estado terminado
-- y fecha de "summary.modified" de este año (lee los .sdr: solo si hace falta)
local function historyFinishedYear(year)
    local n = 0
    local ok_h, ReadHistory = pcall(require, "readhistory")
    if not ok_h then return n end
    for _i, item in ipairs(ReadHistory.hist or {}) do
        if not item.dim and item.file and BookList.getBookStatus(item.file) == "complete" then
            local ok_ds, ds = pcall(BookList.getDocSettings, item.file)
            local summary = ok_ds and ds and ds:readSetting("summary")
            local modified = summary and summary.modified
            if type(modified) == "string" and modified:sub(1, 4) == year then
                n = n + 1
            end
        end
    end
    return n
end


---------------------------------------------------------------------------
-- Calendario: datos de un mes y de un día
---------------------------------------------------------------------------
-- days[d] = { secs, pages }, más totales del mes
local function loadMonth(year, month)
    local ckey = cacheKey("m:" .. year .. ":" .. month)
    if cache.months[ckey] then return cache.months[ckey] end

    if state.FAKE and state.FAKE.fakeMonth then
        local ok_f, fres = pcall(state.FAKE.fakeMonth, year, month)
        if ok_f and fres then
            cache.months[ckey] = fres
            return fres
        end
    end
    local res = { days = {}, secs = 0, pages = 0, read_days = 0, max = 0 }
    if lfs.attributes(DB_FILE, "mode") ~= "file" then return res end
    local t0, t1 = monthRange(year, month)
    local ok, err = pcall(withDB, function(conn)
        local stmt = conn:prepare("SELECT day, sum(d), count(*) FROM ("
            .. "SELECT date(start_time, 'unixepoch', 'localtime') AS day, id_book, page, sum(duration) AS d "
            .. "FROM page_stat_data WHERE start_time >= ? AND start_time < ? GROUP BY day, id_book, page"
            .. ") GROUP BY day")
        stmt:bind(t0, t1)
        local row = stmt:step()
        while row do
            local d = tonumber((row[1] or ""):match("%-(%d+)$"))
            if d then
                local secs, pages = tonumber(row[2]) or 0, tonumber(row[3]) or 0
                res.days[d] = { secs = secs, pages = pages }
                res.secs = res.secs + secs
                res.pages = res.pages + pages
                if secs > 0 then res.read_days = res.read_days + 1 end
                if secs > res.max then res.max = secs end
            end
            row = stmt:step()
        end
        stmt:close()
    end)
    if not ok then logger.warn("Aire/Stats: error leyendo el mes:", err) end
    cache.months[ckey] = res
    return res
end

-- Libros leídos un día: { id_book, title, secs, pages }, de más a menos tiempo
local function loadDay(year, month, day)
    if state.FAKE and state.FAKE.fakeDay then
        local ok_f, flist = pcall(state.FAKE.fakeDay, year, month, day)
        if ok_f and flist then return flist end
    end
    local list = {}
    if lfs.attributes(DB_FILE, "mode") ~= "file" then return list end
    local t0 = os.time{ year = year, month = month, day = day, hour = 0 }
    local t1 = os.time{ year = year, month = month, day = day + 1, hour = 0 }
    local ok, err = pcall(withDB, function(conn)
        local stmt = conn:prepare("SELECT p.id_book, book.title, sum(p.duration), count(DISTINCT p.page) "
            .. "FROM page_stat_data AS p JOIN book ON book.id = p.id_book "
            .. "WHERE p.start_time >= ? AND p.start_time < ? GROUP BY p.id_book ORDER BY 3 DESC")
        stmt:bind(t0, t1)
        local row = stmt:step()
        while row do
            table.insert(list, {
                id_book = tonumber(row[1]),
                title = row[2] or "?",
                secs = tonumber(row[3]) or 0,
                pages = tonumber(row[4]) or 0,
            })
            row = stmt:step()
        end
        stmt:close()
    end)
    if not ok then logger.warn("Aire/Stats: error leyendo el día:", err) end
    return list
end


---------------------------------------------------------------------------
-- Recapitulación mensual o anual
---------------------------------------------------------------------------
local function loadRecap(self, mode, year, month)
    local ckey = cacheKey("r:" .. mode .. ":" .. year .. ":" .. (month or 0))
    if cache.recaps[ckey] then return cache.recaps[ckey] end

    if state.FAKE and state.FAKE.fakeRecap then
        local ok_f, fres = pcall(state.FAKE.fakeRecap, mode, year, month)
        if ok_f and fres then
            cache.recaps[ckey] = fres
            return fres
        end
    end

    local now = os.time()
    local now_t = os.date("*t", now)
    local t0, t1, ndays, pt0, pt1
    if mode == "all" then
        t0, t1, ndays = 0, now + 1, 0
    elseif mode == "month" then
        t0, t1, ndays = monthRange(year, month)
        local py, pm = year, month - 1
        if pm < 1 then py, pm = py - 1, 12 end
        local p_ndays
        pt0, pt1, p_ndays = monthRange(py, pm)
        if year == now_t.year and month == now_t.month and now_t.day < p_ndays then
            pt1 = os.time{ year = py, month = pm, day = now_t.day + 1, hour = 0 }
        end
    else
        t0 = os.time{ year = year, month = 1, day = 1, hour = 0 }
        t1 = os.time{ year = year + 1, month = 1, day = 1, hour = 0 }
        ndays = math.floor((t1 - t0) / 86400 + 0.5)
        pt0 = os.time{ year = year - 1, month = 1, day = 1, hour = 0 }
        pt1 = (year == now_t.year) and (pt0 + math.max(0, now - t0)) or t0
    end

    local res = {
        mode = mode, year = year, month = month,
        total_secs = 0, total_pages = 0, read_days = 0, total_days = ndays,
        avg_secs = 0, speed = 0, best_streak = 0,
        prev_secs = 0, delta_pct = nil,
        bars = {}, best_day = nil, best_month = nil, best_year = nil,
        top_books = {}, top_author = nil, top_genres = {},
        time_slots = {}, fav_slot = nil,
        weekdays = {}, fav_weekday = nil,
        finished_books = {},
    }

    local by_day, by_month, by_year, sorted_days = {}, {}, {}, {}
    local period_books = {}
    if lfs.attributes(DB_FILE, "mode") == "file" then
        local ok, err = pcall(withDB, function(conn)
            local stmt = conn:prepare("SELECT day, sum(d), count(*) FROM ("
                .. "SELECT date(start_time, 'unixepoch', 'localtime') AS day, id_book, page, sum(duration) AS d "
                .. "FROM page_stat_data WHERE start_time >= ? AND start_time < ? GROUP BY day, id_book, page"
                .. ") GROUP BY day ORDER BY day ASC")
            stmt:bind(t0, t1)
            local row = stmt:step()
            while row do
                local day_str = row[1] or ""
                local secs, pages = tonumber(row[2]) or 0, tonumber(row[3]) or 0
                if secs > 0 then
                    res.total_secs = res.total_secs + secs
                    res.total_pages = res.total_pages + pages
                    res.read_days = res.read_days + 1
                    table.insert(sorted_days, day_str)
                    local ym_y, ym_m, ym_d = day_str:match("^(%d+)%-(%d+)%-(%d+)$")
                    local y_num, m_num, d_num = tonumber(ym_y), tonumber(ym_m), tonumber(ym_d)
                    if y_num then by_year[y_num] = (by_year[y_num] or 0) + secs end
                    if m_num then by_month[m_num] = (by_month[m_num] or 0) + secs end
                    if d_num then by_day[d_num] = (by_day[d_num] or 0) + secs end
                    if not res.best_day or secs > res.best_day.secs then
                        res.best_day = { year = y_num, month = m_num, day = d_num, secs = secs }
                    end
                end
                row = stmt:step()
            end
            stmt:close()

            period_books = queryBooksInRange(conn, t0, t1)
            if pt0 and pt1 then
                res.prev_secs = queryTotalSecs(conn, pt0, pt1)
            end
            res.time_slots, res.fav_slot = queryTimeSlots(conn, t0, t1)
            res.weekdays, res.fav_weekday = queryWeekdays(conn, t0, t1)
        end)
        if not ok then logger.warn("Aire/Stats: error leyendo el recap:", err) end
    end

    res.avg_secs = res.read_days > 0 and math.floor(res.total_secs / res.read_days) or 0
    res.speed = calcSpeed(res.total_pages, res.total_secs)
    res.best_streak = computeBestStreak(sorted_days)
    res.delta_pct = (pt0 and pt1) and calcDelta(res.total_secs, res.prev_secs) or nil

    for i = 1, math.min(3, #period_books) do
        table.insert(res.top_books, period_books[i])
    end
    res.top_author = computeTopAuthor(period_books)
    if #period_books > 0 then
        res.top_genres = computeTopGenres(period_books, getBookKeywordsMap(), 5)
    end

    if mode == "all" then
        local years = {}
        local best_y, best_s = nil, 0
        for y, s in pairs(by_year) do
            table.insert(years, y)
            if s > best_s then best_y, best_s = y, s end
        end
        table.sort(years)
        if best_y then res.best_year = { year = best_y, secs = best_s } end
        if #years > 1 then
            for _i, y in ipairs(years) do
                table.insert(res.bars, { label = tostring(y), secs = by_year[y] or 0, highlight = (y == best_y) })
            end
        else
            local best_m, best_ms = nil, 0
            for m = 1, 12 do
                local s = by_month[m] or 0
                if s > best_ms then best_m, best_ms = m, s end
            end
            if best_m then res.best_month = { month = best_m, secs = best_ms } end
            for m = 1, 12 do
                local initial = (MONTHS[m] or ""):match("[%z\1-\127\194-\244][\128-\191]*") or tostring(m)
                table.insert(res.bars, { label = initial:upper(), secs = by_month[m] or 0, highlight = (m == best_m) })
            end
        end
    elseif mode == "month" then
        local best_d = res.best_day and res.best_day.day
        for d = 1, ndays do
            local lbl = (d == 1 or d % 5 == 0 or d == ndays) and tostring(d) or ""
            table.insert(res.bars, { label = lbl, secs = by_day[d] or 0, highlight = (d == best_d) })
        end
    else
        local best_m, best_s = nil, 0
        for m = 1, 12 do
            local s = by_month[m] or 0
            if s > best_s then best_m, best_s = m, s end
        end
        if best_m then res.best_month = { month = best_m, secs = best_s } end
        for m = 1, 12 do
            local initial = (MONTHS[m] or ""):match("[%z\1-\127\194-\244][\128-\191]*") or tostring(m)
            table.insert(res.bars, { label = initial:upper(), secs = by_month[m] or 0, highlight = (m == best_m) })
        end
    end

    local ok_fb, books = false, nil
    if self.getFinishedBooks then ok_fb, books = pcall(self.getFinishedBooks, self) end
    if ok_fb and type(books) == "table" then
        for _i, b in ipairs(books) do
            if mode == "all"
                or (tonumber(b.finished_year) == year and (mode == "year" or tonumber(b.finished_month) == month)) then
                table.insert(res.finished_books, b)
            end
        end
        table.sort(res.finished_books, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
    end

    cache.recaps[ckey] = res
    return res
end


---------------------------------------------------------------------------
-- Borrar registros y terminados del año
---------------------------------------------------------------------------
-- Borrar registros de lectura de un libro (solo de un día o de todos)
-- y restaurar su posición en ReadHistory según el último registro restante
local function deleteBookStats(id_book, year, month, day)
    if not id_book or lfs.attributes(DB_FILE, "mode") ~= "file" then return false end
    local md5, prev_time
    id_book = tonumber(id_book)
    if not id_book then return false end
    local ok, err = pcall(withDB, function(conn)
        -- Todo en una transacción: o se borra y se recalcula todo, o nada
        conn:exec("BEGIN IMMEDIATE;")
        local ok_tx, err_tx = pcall(function()
            local stmt
            if year and month and day then
                local t0 = os.time{ year = year, month = month, day = day, hour = 0 }
                local t1 = os.time{ year = year, month = month, day = day + 1, hour = 0 }
                stmt = conn:prepare("DELETE FROM page_stat_data WHERE id_book = ? AND start_time >= ? AND start_time < ?")
                stmt:bind(id_book, t0, t1)
            else
                stmt = conn:prepare("DELETE FROM page_stat_data WHERE id_book = ?")
                stmt:bind(id_book)
            end
            stmt:step()
            stmt:close()

            local q1 = conn:prepare("SELECT md5 FROM book WHERE id = ?")
            local r1 = q1:bind(id_book):step()
            if r1 then md5 = r1[1] end
            q1:close()

            local q2 = conn:prepare("SELECT max(start_time + duration) FROM page_stat_data WHERE id_book = ?")
            local r2 = q2:bind(id_book):step()
            prev_time = r2 and tonumber(r2[1]) or nil
            q2:close()

            -- Totales del libro como los calcula el plugin de Estadísticas
            -- (si no, "tiempo leído" y la estimación de lo que queda
            -- seguirían contando lo borrado hasta volver a abrir el libro)
            local pages, secs = conn:rowexec(string.format(
                "SELECT count(DISTINCT page), sum(duration) FROM page_stat WHERE id_book = %d;", id_book))
            local u1 = conn:prepare("UPDATE book SET last_open = ?, total_read_time = ?, total_read_pages = ? WHERE id = ?")
            u1:bind(prev_time or 0, tonumber(secs) or 0, tonumber(pages) or 0, id_book):step()
            u1:close()
        end)
        if ok_tx then
            conn:exec("COMMIT;")
        else
            pcall(conn.exec, conn, "ROLLBACK;")
            error(err_tx, 0)
        end
    end)
    if not ok then
        logger.warn("Aire/Stats: error borrando registros:", err)
        return false
    end
    invalidateCache()
    if md5 then
        pcall(function()
            local ReadHistory = require("readhistory")
            for idx, item in ipairs(ReadHistory.hist or {}) do
                if item.file then
                    local ok_m, f_md5 = pcall(util.partialMD5, item.file)
                    if ok_m and f_md5 == md5 then
                        if prev_time and prev_time > 0 then
                            ReadHistory:addItem(item.file, prev_time)
                        else
                            -- índice exacto (sin él KOReader puede quitar otro libro)
                            ReadHistory:removeItem(item, idx)
                        end
                        break
                    end
                end
            end
        end)
    end
    return true
end

-- Terminados del año con la misma fuente que la vista Terminados
-- (historial + Librería), salvo con estadísticas de prueba
local function countFinishedYear(self, st)
    if state.FAKE then return end -- las de prueba ya traen su número
    local ok, books = false, nil
    if self.getFinishedBooks then ok, books = pcall(self.getFinishedBooks, self) end
    if not ok or type(books) ~= "table" then
        st.finished_year = historyFinishedYear(st.year or os.date("%Y"))
        return
    end
    local year = tonumber(os.date("%Y"))
    local n = 0
    for _i, b in ipairs(books) do
        if tonumber(b.finished_year) == year then n = n + 1 end
    end
    st.finished_year = n
end


-- Libros empezados (estado "reading" en ReadHistory), más tiempo y páginas desde statistics.sqlite3
local function loadInProgressBooks()
    local list = {}
    local seen = {}
    local ok_h, ReadHistory = pcall(require, "readhistory")
    if ok_h and ReadHistory and ReadHistory.hist then
        for _i, item in ipairs(ReadHistory.hist) do
            local f = item and not item.dim and item.file
            if f and not seen[f] and lfs.attributes(f, "mode") == "file" then
                if BookList.getBookStatus(f) == "reading" then
                    seen[f] = true
                    table.insert(list, { file = f, read_secs = 0, read_pages = 0 })
                    if #list >= 24 then break end
                end
            end
        end
    end
    -- Si no salió ninguno pero hay lastfile activo sin terminar, incluirlo
    if #list == 0 then
        local lf = G_reader_settings and G_reader_settings:readSetting("lastfile")
        if lf and lfs.attributes(lf, "mode") == "file" and BookList.getBookStatus(lf) ~= "complete" then
            table.insert(list, { file = lf, read_secs = 0, read_pages = 0 })
        end
    end
    if #list > 0 and lfs.attributes(DB_FILE, "mode") == "file" then
        pcall(withDB, function(conn)
            local stmt = conn:prepare("SELECT total_read_time, total_read_pages FROM book WHERE md5 = ?")
            for _i, b in ipairs(list) do
                local ok_m, md5 = pcall(util.partialMD5, b.file)
                if ok_m and md5 then
                    stmt:reset()
                    stmt:bind(md5)
                    local r = stmt:step()
                    if r then
                        b.read_secs = tonumber(r[1]) or 0
                        b.read_pages = tonumber(r[2]) or 0
                    end
                end
            end
            stmt:close()
        end)
    end
    return list
end


return {
    state = state,
    invalidateCache = invalidateCache,
    fmtDuration = fmtDuration,
    fmtDelta = fmtDelta,
    calcSpeed = calcSpeed,
    calcDelta = calcDelta,
    withDB = withDB,
    dayStart = dayStart,
    loadStats = loadStats,
    loadInProgressBooks = loadInProgressBooks,
    historyFinishedYear = historyFinishedYear,
    MONTHS = MONTHS,
    WEEKDAYS_LONG = WEEKDAYS_LONG,
    monthRange = monthRange,
    loadMonth = loadMonth,
    loadDay = loadDay,
    loadRecap = loadRecap,
    deleteBookStats = deleteBookStats,
    countFinishedYear = countFinishedYear,
}
