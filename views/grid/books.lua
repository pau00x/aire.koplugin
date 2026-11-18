--[[
    aire.koplugin/views/grid/books.lua
    Datos de las vistas de cuadrícula (views/grid.lua): buscar libros en la
    carpeta de inicio, leer sus metadatos de CoverBrowser, agrupar, ordenar y
    filtrar. Sin widgets.
--]]

local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local MAX_DEPTH = 8          -- profundidad máxima de subcarpetas (Librería)

local function findOption(list, id)
    for _i, o in ipairs(list) do
        if o.id == id then return o end
    end
    return list[1]
end

---------------------------------------------------------------------------
-- Datos comunes
---------------------------------------------------------------------------
local function getBIM()
    local ok, BIM = pcall(require, "bookinfomanager")
    if ok and type(BIM) == "table" then return BIM end
end

local function scanBooks(dir, out, depth)
    if depth > MAX_DEPTH then return end
    local ok, iter, dir_obj = pcall(lfs.dir, dir)
    if not ok or not iter then return end
    for name in iter, dir_obj do
        if name ~= "." and name ~= ".." and name:sub(1, 1) ~= "." then
            local path = dir .. "/" .. name
            local attr = lfs.attributes(path)
            if attr then
                if attr.mode == "directory" then
                    if not name:match("%.sdr$") then scanBooks(path, out, depth + 1) end
                elseif attr.mode == "file" and DocumentRegistry:hasProvider(path) then
                    table.insert(out, { path = path, mtime = attr.modification or 0 })
                end
            end
        end
    end
end

-- Metadatos de todos los libros bajo root (o de todos si root es nil) en una
-- sola consulta y sin la columna de la portada (BIM:getBookInfo lee la fila
-- entera, portada incluida, aunque no se pida: un libro a la vez era lento)
local function loadMetadataUnder(BIM, root)
    local meta = {}
    if not BIM then return meta end
    local stmt
    local ok, err = pcall(function()
        BIM:openDbConnection()
        -- (keywords: las colecciones automáticas por género salen de aquí)
        local sql = "SELECT directory, filename, title, authors, series, series_index, ignore_meta, keywords FROM bookinfo"
        if root then
            -- instr y no LIKE: en LIKE "_" y "%" son comodines (carpetas como
            -- "mis_libros" casaban con otras) y además no distingue mayúsculas
            stmt = BIM.db_conn:prepare(sql .. " WHERE instr(directory, ?) = 1")
            stmt:bind(root .. "/")
        else
            stmt = BIM.db_conn:prepare(sql)
        end
        local row = stmt:step()
        while row do
            local dir, fname = row[1], row[2]
            if dir and fname then
                meta[dir .. fname] = {
                    title = row[3], authors = row[4], series = row[5],
                    series_index = tonumber(row[6]), ignore_meta = row[7] == "Y",
                    keywords = row[8],
                }
            end
            row = stmt:step()
        end
    end)
    -- Cerrar también si falla a medias: la conexión de CoverBrowser es compartida
    if stmt then pcall(stmt.close, stmt) end
    if not ok then logger.warn("Aire/Grid: error leyendo la base de datos:", err) end
    return meta
end

-- Metadatos de un libro suelto (Historial / Colecciones: pueden estar en cualquier carpeta)
local function metaFor(BIM, path)
    if not BIM then return nil end
    local ok, bi = pcall(BIM.getBookInfo, BIM, path, false)
    if not ok or not bi then return nil end
    return {
        title = bi.title, authors = bi.authors, series = bi.series,
        series_index = tonumber(bi.series_index), ignore_meta = bi.ignore_meta == "Y",
        keywords = bi.keywords,
    }
end

-- Metadatos ya leídos con loadMetadataUnder; si no está (otra ruta, aún sin
-- analizar, formato sin lector), se pregunta a CoverBrowser solo por ese libro
local function metaIn(meta, BIM, path)
    return meta[path] or metaFor(BIM, path)
end

local function firstAuthor(authors)
    if type(authors) ~= "string" or authors == "" then return nil end
    return authors:match("^([^\n]+)") or authors
end

-- Rango para el orden inteligente
local RANK = { reading = 0, abandoned = 1, new = 2, complete = 3 }

local function makeBook(path, m, mtime)
    if m and m.ignore_meta then m = nil end
    local name = path:match("([^/]+)$") or path
    local title = (m and m.title and m.title ~= "") and m.title or filemanagerutil.splitFileNameType(name)
    local bi = BookList.getBookInfo(path) or {}
    local status = bi.been_opened and bi.status or "new"
    local percent = bi.percent_finished or (status == "complete" and 1 or 0)
    return {
        path = path,
        mtime = mtime or 0,
        title = title,
        sort_title = title,
        author = firstAuthor(m and m.authors),
        keywords = (m and m.keywords and m.keywords ~= "") and m.keywords or nil,
        series = (m and m.series and m.series ~= "") and m.series or nil,
        series_index = m and m.series_index,
        status = status,
        percent = percent,
        rank = RANK[status] or 2,
    }
end

-- Colecciones automáticas por autor y por género (palabra clave)
local AUTO = { MIN = 2, AUTHOR = "\1autor:", GENRE = "\1genero:" }
local function isAutoKey(key)
    return type(key) == "string"
        and (key:sub(1, #AUTO.AUTHOR) == AUTO.AUTHOR or key:sub(1, #AUTO.GENRE) == AUTO.GENRE)
end

local function groupRank(books)
    local reading, abandoned, complete = false, false, 0
    for _i, b in ipairs(books) do
        if b.status == "reading" then reading = true
        elseif b.status == "abandoned" then abandoned = true
        elseif b.status == "complete" then complete = complete + 1 end
    end
    if reading or (complete > 0 and complete < #books) then return 0 end
    if abandoned then return 1 end
    if #books > 0 and complete == #books then return 3 end
    return 2
end

-- Clave de orden: minúsculas y sin tildes (string.lower solo entiende ASCII,
-- y strcoll no sirve en el Kindle sin locales: "Él" iba detrás de "Zafiro").
-- La ñ va entre la n y la o ("n~": '~' es mayor que cualquier letra).
local FOLD = {}
do
    local base = { "a", "a", "a", "a", "a", "a", "ae", "c", "e", "e", "e", "e", "i", "i", "i", "i",
                   "d", "n~", "o", "o", "o", "o", "o", false, "o", "u", "u", "u", "u", "y", "th", "ss" }
    for i, v in ipairs(base) do
        if v then
            FOLD["\195" .. string.char(0x80 + i - 1)] = v -- mayúsculas U+00C0..U+00DF
            FOLD["\195" .. string.char(0xA0 + i - 1)] = v -- minúsculas U+00E0..U+00FF
        end
    end
    FOLD["\195\191"] = "y" -- ÿ
end
local key_cache, key_cache_n = {}, 0
local function lowerKey(s)
    s = s or ""
    local k = key_cache[s]
    if k then return k end
    k = s:lower():gsub("\195[\128-\191]", FOLD)
    if key_cache_n > 4000 then key_cache, key_cache_n = {}, 0 end
    key_cache[s] = k
    key_cache_n = key_cache_n + 1
    return k
end

local function byTitle(a, b) return lowerKey(a.sort_title) < lowerKey(b.sort_title) end

local function sortEntries(list, sort_id, reverse, separate_groups)
    local cmp
    if sort_id == "title" then
        cmp = byTitle
    elseif sort_id == "author" then
        cmp = function(a, b)
            local aa, ab = lowerKey(a.author), lowerKey(b.author)
            if aa ~= ab then
                if aa == "" then return false end
                if ab == "" then return true end
                return aa < ab
            end
            return byTitle(a, b)
        end
    elseif sort_id == "series" then
        cmp = function(a, b)
            local sa = lowerKey(a.series or (a.is_group and a.sort_title or ""))
            local sb = lowerKey(b.series or (b.is_group and b.sort_title or ""))
            if sa ~= sb then
                if sa == "" then return false end
                if sb == "" then return true end
                return sa < sb
            end
            local ia, ib = a.series_index or math.huge, b.series_index or math.huge
            if ia ~= ib then return ia < ib end
            return byTitle(a, b)
        end
    elseif sort_id == "percent" then
        cmp = function(a, b)
            local pa, pb = a.percent or 0, b.percent or 0
            if pa ~= pb then return pa > pb end
            return byTitle(a, b)
        end
    elseif sort_id == "recent" then
        cmp = function(a, b)
            if a.mtime ~= b.mtime then return a.mtime > b.mtime end
            return byTitle(a, b)
        end
    elseif sort_id == "manual" then
        cmp = function(a, b)
            local oa, ob = a.order or math.huge, b.order or math.huge
            if oa ~= ob then return oa < ob end
            return byTitle(a, b)
        end
    else -- smart
        -- Primero el libro que estás leyendo ahora (el último abierto), o la
        -- serie / colección que lo contiene; después por estado y título
        local current = G_reader_settings:readSetting("lastfile")
        for _i, e in ipairs(list) do
            local is_current = false
            if current then
                if e.is_group then
                    for _j, b in ipairs(e.books) do
                        if b.path == current then is_current = true break end
                    end
                else
                    is_current = e.path == current
                end
            end
            e._current = is_current
        end
        cmp = function(a, b)
            if a._current ~= b._current then return a._current end
            if a.rank ~= b.rank then return a.rank < b.rank end
            return byTitle(a, b)
        end
    end
    local function sortAndRev(arr)
        table.sort(arr, cmp)
        if reverse then
            local n = #arr
            for i = 1, math.floor(n / 2) do
                arr[i], arr[n - i + 1] = arr[n - i + 1], arr[i]
            end
        end
    end
    if separate_groups then
        local groups, singles = {}, {}
        for _i, e in ipairs(list) do
            if e.is_group then table.insert(groups, e) else table.insert(singles, e) end
        end
        sortAndRev(groups)
        sortAndRev(singles)
        for i = 1, #list do list[i] = nil end
        for _i, e in ipairs(groups) do table.insert(list, e) end
        for _i, e in ipairs(singles) do table.insert(list, e) end
    else
        sortAndRev(list)
    end
end

local function filterBooks(books, filter)
    local out = {}
    for _i, b in ipairs(books) do
        if not filter or filter == "all" or b.status == filter then table.insert(out, b) end
    end
    return out
end

local function countDone(books)
    local n = 0
    for _i, b in ipairs(books) do
        if b.status == "complete" then n = n + 1 end
    end
    return n
end

local function booksAndDone(books)
    local done = countDone(books)
    return T(N_("%1 book", "%1 books", #books), #books) .. " · " .. T(N_("%1 finished", "%1 finished", done), done)
end

return {
    findOption = findOption,
    getBIM = getBIM,
    scanBooks = scanBooks,
    loadMetadataUnder = loadMetadataUnder,
    metaIn = metaIn,
    makeBook = makeBook,
    isAutoKey = isAutoKey,
    groupRank = groupRank,
    lowerKey = lowerKey,
    byTitle = byTitle,
    sortEntries = sortEntries,
    filterBooks = filterBooks,
    countDone = countDone,
    booksAndDone = booksAndDone,
    RANK = RANK,
    AUTO = AUTO,
}
