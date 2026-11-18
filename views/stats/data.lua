--[[
    aire.koplugin/views/stats/data.lua
    Datos de la pestaña Estadísticas (views/stats.lua): lectura de la base de
    datos de KOReader (statistics.sqlite3), resúmenes, mes, día, recapitulación
    y borrar estadísticas de un libro. Sin widgets.
    state.FAKE: estadísticas de prueba (devtools.lua); lo fija el mixin.
--]]

local BookList = require("ui/widget/booklist")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")

local DB_FILE = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
local state = { FAKE = nil }


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

-- Abre statistics.sqlite3, ejecuta fn(conn) y cierra SIEMPRE la conexión
-- (también si fn falla: así no quedan la base ni sentencias abiertas).
-- conn:close() de ljsqlite3 cierra además las sentencias que queden.
local function withDB(fn)
    local SQ3 = require("lua-ljsqlite3/init")
    local conn = SQ3.open(DB_FILE)
    local ok, err = pcall(fn, conn)
    pcall(conn.close, conn)
    if not ok then error(err, 0) end
end

local function dayStart(t)
    local d = os.date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d)
end

---------------------------------------------------------------------------
-- Datos
---------------------------------------------------------------------------
local function loadStats()
    local st = {
        today_secs = 0, today_pages = 0,
        week = {}, week_total = 0,
        streak = 0,
        month_secs = 0, month_pages = 0,
        year_secs = 0, year_pages = 0,
        finished_year = 0,
        current = nil,
        ok = false,
    }
    local now = os.time()
    local today0 = dayStart(now)
    -- Días de la semana: de hace 6 días a hoy
    for i = 6, 0, -1 do
        local t = today0 - i * 86400 + 3600 * 12 -- mediodía, para no pisar cambios de hora
        table.insert(st.week, { key = os.date("%Y-%m-%d", t), letter = package.loaded.aire_ui.dayLetter(os.date("*t", t).wday), secs = 0 })
    end

    -- Pruebas: datos inventados (devtools.lua, opción "Estadísticas de prueba")
    if state.FAKE and state.FAKE.fakeStats then
        st.year = os.date("%Y", now)
        local ok_f, res = pcall(state.FAKE.fakeStats, st)
        if ok_f and res then return res end
        logger.warn("Aire/Stats: error en las estadísticas de prueba:", res)
    end

    if lfs.attributes(DB_FILE, "mode") == "file" then
        local ok, err = pcall(withDB, function(conn)
            -- Hoy y este mes: tiempo y páginas distintas
            local q_period = "SELECT count(*), sum(d) FROM (SELECT id_book, page, sum(duration) AS d "
                .. "FROM page_stat_data WHERE start_time >= %d GROUP BY id_book, page)"
            local tp, ts = conn:rowexec(q_period:format(today0))
            st.today_pages, st.today_secs = tonumber(tp) or 0, tonumber(ts) or 0
            local m = os.date("*t", now)
            m.day, m.hour, m.min, m.sec = 1, 0, 0, 0
            local mp, ms = conn:rowexec(q_period:format(os.time(m)))
            st.month_pages, st.month_secs = tonumber(mp) or 0, tonumber(ms) or 0
            m.month = 1
            local yp, ys = conn:rowexec(q_period:format(os.time(m)))
            st.year_pages, st.year_secs = tonumber(yp) or 0, tonumber(ys) or 0

            -- Últimos 7 días, por día
            local by_day = {}
            local stmt = conn:prepare("SELECT date(start_time, 'unixepoch', 'localtime') AS day, sum(duration) "
                .. "FROM page_stat_data WHERE start_time >= ? GROUP BY day")
            stmt:bind(today0 - 6 * 86400)
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

            -- Racha: días seguidos con lectura, contando desde hoy (o desde ayer)
            local days = {}
            stmt = conn:prepare("SELECT DISTINCT date(start_time, 'unixepoch', 'localtime') "
                .. "FROM page_stat_data WHERE start_time >= ?")
            stmt:bind(today0 - 400 * 86400)
            row = stmt:step()
            while row do
                days[row[1]] = true
                row = stmt:step()
            end
            stmt:close()
            local t = today0 + 3600 * 12
            if not days[os.date("%Y-%m-%d", t)] then t = t - 86400 end
            while days[os.date("%Y-%m-%d", t)] do
                st.streak = st.streak + 1
                t = t - 86400
            end

            -- Libro actual: tiempo leído y velocidad en ese libro
            local file = G_reader_settings:readSetting("lastfile")
            if file and lfs.attributes(file, "mode") == "file" then
                local md5 = util.partialMD5(file)
                if md5 then
                    local s2 = conn:prepare("SELECT total_read_time, total_read_pages FROM book WHERE md5 = ?")
                    s2:bind(md5)
                    local r2 = s2:step()
                    if r2 then
                        st.current = {
                            file = file,
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
        else
            logger.warn("Aire/Stats: error leyendo statistics.sqlite3:", err)
        end
    end

    -- Los terminados del año los rellena countFinishedYear (una sola pasada)
    st.year = os.date("%Y", now)
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
-- Meses y días traducidos por KOReader (datetime.lua)
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

-- days[d] = { secs, pages }, más totales del mes
local function loadMonth(year, month)
    if state.FAKE and state.FAKE.fakeMonth then
        local ok_f, fres = pcall(state.FAKE.fakeMonth, year, month)
        if ok_f and fres then return fres end
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
    return res
end

-- Libros leídos un día: { title, secs, pages }, de más a menos tiempo
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

-- Datos del recap mensual o anual
local function loadRecap(self, mode, year, month)
    if state.FAKE and state.FAKE.fakeRecap then
        local ok_f, fres = pcall(state.FAKE.fakeRecap, mode, year, month)
        if ok_f and fres then return fres end
    end
    local t0, t1, ndays
    if mode == "month" then
        t0, t1, ndays = monthRange(year, month)
    else
        t0 = os.time{ year = year, month = 1, day = 1, hour = 0 }
        t1 = os.time{ year = year + 1, month = 1, day = 1, hour = 0 }
        ndays = math.floor((t1 - t0) / 86400 + 0.5)
    end
    local res = {
        mode = mode, year = year, month = month,
        total_secs = 0, total_pages = 0, read_days = 0, total_days = ndays,
        bars = {}, best_day = nil, best_month = nil,
        top_books = {}, top_author = nil, finished_books = {},
    }
    local by_day, by_month = {}, {}
    if lfs.attributes(DB_FILE, "mode") == "file" then
        local ok, err = pcall(withDB, function(conn)
            local stmt = conn:prepare("SELECT day, sum(d), count(*) FROM ("
                .. "SELECT date(start_time, 'unixepoch', 'localtime') AS day, id_book, page, sum(duration) AS d "
                .. "FROM page_stat_data WHERE start_time >= ? AND start_time < ? GROUP BY day, id_book, page"
                .. ") GROUP BY day")
            stmt:bind(t0, t1)
            local row = stmt:step()
            while row do
                local day_str = row[1] or ""
                local secs, pages = tonumber(row[2]) or 0, tonumber(row[3]) or 0
                if secs > 0 then
                    res.total_secs = res.total_secs + secs
                    res.total_pages = res.total_pages + pages
                    res.read_days = res.read_days + 1
                    local ym_m, ym_d = day_str:match("^%d+%-(%d+)%-(%d+)$")
                    local m_num, d_num = tonumber(ym_m), tonumber(ym_d)
                    if m_num then by_month[m_num] = (by_month[m_num] or 0) + secs end
                    if d_num then by_day[d_num] = (by_day[d_num] or 0) + secs end
                    if not res.best_day or secs > res.best_day.secs then
                        res.best_day = { month = m_num, day = d_num, secs = secs }
                    end
                end
                row = stmt:step()
            end
            stmt:close()

            local sb = conn:prepare("SELECT p.id_book, book.title, book.authors, sum(p.duration) AS s, count(DISTINCT p.page) "
                .. "FROM page_stat_data AS p JOIN book ON book.id = p.id_book "
                .. "WHERE p.start_time >= ? AND p.start_time < ? GROUP BY p.id_book ORDER BY s DESC LIMIT 3")
            sb:bind(t0, t1)
            local rb = sb:step()
            while rb do
                table.insert(res.top_books, {
                    id_book = tonumber(rb[1]),
                    title = rb[2] or "?",
                    authors = rb[3],
                    secs = tonumber(rb[4]) or 0,
                    pages = tonumber(rb[5]) or 0,
                })
                rb = sb:step()
            end
            sb:close()

            local sa = conn:prepare("SELECT book.authors, sum(p.duration) AS s "
                .. "FROM page_stat_data AS p JOIN book ON book.id = p.id_book "
                .. "WHERE p.start_time >= ? AND p.start_time < ? AND book.authors IS NOT NULL AND book.authors != '' "
                .. "GROUP BY book.authors ORDER BY s DESC LIMIT 1")
            sa:bind(t0, t1)
            local ra = sa:step()
            if ra and ra[1] and ra[1] ~= "" then
                res.top_author = { name = ra[1]:gsub("\n", ", "), secs = tonumber(ra[2]) or 0 }
            end
            sa:close()
        end)
        if not ok then logger.warn("Aire/Stats: error leyendo el recap:", err) end
    end

    if mode == "month" then
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
            if tonumber(b.finished_year) == year and (mode == "year" or tonumber(b.finished_month) == month) then
                table.insert(res.finished_books, b)
            end
        end
        table.sort(res.finished_books, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
    end
    return res
end

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


return {
    state = state,
    fmtDuration = fmtDuration,
    withDB = withDB,
    dayStart = dayStart,
    loadStats = loadStats,
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
