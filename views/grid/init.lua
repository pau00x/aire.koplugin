--[[
    aire.koplugin/views/grid/init.lua
    Vistas de cuadrícula de la pantalla de inicio (pestañas del dock):
    Librería, Colecciones e Historial, todas con el mismo estilo.

      ● Librería ⌄                                 43%  [⏻]
      48 libros · 6 series · 12 terminados                   <- recuentos (gris)
      (Todos) (Leyendo) (Nuevos) (Terminados)   Inteligente ⌄ <- filtros + orden
      ┌──┐ ┌──┐ ┌──┐ ┌──┐
      │▤▤│ │  │ │  │ │  │   <- portadas; los grupos (series / colecciones)
      └──┘ └──┘ └──┘ └──┘      son una pila con su nº de libros y se abren
                 ● ○ ○                    <- páginas (deslizar)
      [Librería][Colecciones][Inicio][Historial][Estadísticas]

    Librería:    libros de la carpeta de inicio y subcarpetas; series (2+
                 libros) como mosaico 2×2 con las 4 primeras portadas. Filtros Todos/Leyendo/Nuevos/Terminados.
                 Orden Inteligente/Título/Autor/Recientes.
    Colecciones: cada colección es un mosaico 2×2 (vacía: pila con el nombre); al abrirla, sus libros con
                 filtros y orden (Colección/Inteligente/Título/Autor).
    Historial:   libros leídos (sin los borrados). Filtros Todos/Leyendo/
                 En pausa/Terminados. Orden Última lectura/Título/Autor.

    Series y colecciones: mosaico con el nombre arriba (letras blancas sobre
    franja oscurecida). Mantener: ficha de grupo
    (Continuar, Abrir, Marcar todo terminado / leyendo).
    Tocar libro: abrir. Mantener: ficha del libro (booksheet.lua), con
    "Quitar de la colección" / "Quitar del historial" donde toca.
    Título / autor / serie salen de la base de datos de CoverBrowser; los
    libros sin analizar se analizan en segundo plano y la vista se refresca.

    Se carga desde main.lua como "mixin": añade métodos a Aire.
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

local time = require("ui/time")
local _ = require("gettext")
local C_ = _.pgettext


local COLS = 4               -- columnas de la cuadrícula (más = portadas más pequeñas)
local COVER_RATIO = 1.5      -- alto / ancho de cada celda

local GRID_VIEWS = { library = true, collections = true, history = true, finished = true }

-- Filtros y órdenes ("short" es lo que se ve junto a los filtros)
local FILTERS_BOOKS = {
    { id = "all",      label = _("All") },
    { id = "reading",  label = C_("aire", "Reading") },
    { id = "new",      label = _("New") },
    { id = "complete", label = C_("aire", "Finished") },
}
local FILTERS_HISTORY = {
    { id = "all",       label = _("All") },
    { id = "reading",   label = C_("aire", "Reading") },
    { id = "abandoned", label = C_("aire", "On hold") },
    { id = "complete",  label = C_("aire", "Finished") },
}
local SORTS_LIBRARY = {
    { id = "smart",   label = _("Smart") },
    { id = "title",   label = _("Title") },
    { id = "author",  label = _("Author") },
    { id = "series",  label = _("Series") },
    { id = "percent", label = _("Progress") },
    { id = "recent",  label = _("Recently added"), short = _("Recent") },
}
local SORTS_COLLECTION = {
    { id = "manual",  label = _("Collection order"), short = _("Collection") },
    { id = "smart",   label = _("Smart") },
    { id = "title",   label = _("Title") },
    { id = "author",  label = _("Author") },
    { id = "series",  label = _("Series") },
    { id = "percent", label = _("Progress") },
}
-- Lista de colecciones: orden de KOReader, inteligente o por nombre
local SORTS_COLL_LIST = {
    { id = "manual", label = _("Collections order"), short = _("Collections") },
    { id = "smart",  label = _("Smart") },
    { id = "title",  label = _("Name") },
}
local SORTS_FINISHED = {
    { id = "recent", label = _("Date finished"), short = _("Date") },
    { id = "title",  label = _("Title") },
    { id = "author", label = _("Author") },
    { id = "series", label = _("Series") },
}
local SORTS_HISTORY = {
    { id = "recent",  label = _("Last read") },
    { id = "title",   label = _("Title") },
    { id = "author",  label = _("Author") },
    { id = "series",  label = _("Series") },
    { id = "percent", label = _("Progress") },
}


local GRID_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]*$") or "plugins/aire.koplugin/views/grid"
-- Datos (buscar, metadatos, ordenar, filtrar) y widgets (celda, puntos)
local Books = dofile(GRID_DIR .. "/books.lua")
local findOption, getBIM, loadMetadataUnder = Books.findOption, Books.getBIM, Books.loadMetadataUnder
local metaIn, makeBook, isAutoKey, groupRank = Books.metaIn, Books.makeBook, Books.isAutoKey, Books.groupRank
local lowerKey, byTitle, sortEntries, filterBooks = Books.lowerKey, Books.byTitle, Books.sortEntries, Books.filterBooks
local countDone, booksAndDone, RANK, AUTO = Books.countDone, Books.booksAndDone, Books.RANK, Books.AUTO
local Cell = dofile(GRID_DIR .. "/cell.lua")
local GridCell = Cell.GridCell
local Pager = package.loaded.aire_screen.Pager
-- Miniaturas de portadas en disco (ya escaladas a la celda), caché LRU y caché de Librería
local Thumbs = dofile(GRID_DIR .. "/thumbs.lua")
local Covers = dofile(GRID_DIR .. "/covers.lua")({ getBIM = getBIM, Thumbs = Thumbs })
local Library = dofile(GRID_DIR .. "/library.lua")({
    scanBooks = Books.scanBooks,
    loadMetadataUnder = loadMetadataUnder,
})
-- Herramientas de prueba (devtools.lua, opcional): las fija el mixin
local TEST = nil


---------------------------------------------------------------------------
-- Mixin
---------------------------------------------------------------------------
-- Las listas de filtros y orden van juntas en una tabla: la función de abajo
-- (el mixin) no puede usar más de 60 variables locales de fuera (límite de LuaJIT)
local LISTS = {
    COLS = COLS,
    COVER_RATIO = COVER_RATIO,
    GRID_VIEWS = GRID_VIEWS,
    RANK = RANK,
    AUTO = AUTO,
    FILTERS_BOOKS = FILTERS_BOOKS,
    FILTERS_HISTORY = FILTERS_HISTORY,
    SORTS_LIBRARY = SORTS_LIBRARY,
    SORTS_COLLECTION = SORTS_COLLECTION,
    SORTS_COLL_LIST = SORTS_COLL_LIST,
    SORTS_FINISHED = SORTS_FINISHED,
    SORTS_HISTORY = SORTS_HISTORY,
}

return function(Aire, ctx)
    -- Módulos que usa el mixin, declarados aquí dentro: así no cuentan como
    -- upvalues de esta función (LuaJIT admite 60). require devuelve el
    -- mismo módulo que arriba.
    local Blitbuffer = require("ffi/blitbuffer")
    local BookList = require("ui/widget/booklist")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Notification = require("ui/widget/notification")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local lfs = require("libs/libkoreader-lfs")
    local logger = require("logger")
    local _ = require("gettext")
    local N_ = _.ngettext
    local T = require("ffi/util").template
    local C_ = _.pgettext
    local Screen = require("device").screen
    local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

    local S, face, config, saveConfig = ctx.S, ctx.face, ctx.config, ctx.saveConfig
    GridCell.state.CONFIG = config
    do
        local test_file = (ctx.PLUGIN_DIR or "plugins/aire.koplugin") .. "/dev/devtools.lua"
        if lfs.attributes(test_file, "mode") == "file" then
            local ok, mod = pcall(dofile, test_file)
            if ok and type(mod) == "table" then
                TEST = mod
                GridCell.state.TEST = mod
            else
                logger.warn("Aire/Grid: error cargando devtools.lua:", mod)
            end
        end
    end

    function Aire:hasTestTools()
        return TEST ~= nil
    end

    function Aire:getTestTools()
        return TEST
    end


    -- Columnas de la cuadrícula (opción del menú; 4 por defecto)
    local function gridCols()
        return tonumber(config.grid_cols) == 3 and 3 or LISTS.COLS -- solo 3 o 4
    end

    local function state(self, kind)
        self._gv = self._gv or {}
        if not self._gv[kind] then
            self._gv[kind] = { page = 1, open = nil, cover_cache = Covers.new() }
        elseif not self._gv[kind].cover_cache then
            self._gv[kind].cover_cache = Covers.new()
        end
        return self._gv[kind]
    end

    local function libRoot()
        return (filemanagerutil.getHomeFolder():gsub("/+$", ""))
    end

    -- (Deben ir después de state(): si van antes, Lua busca un state global y fallan)
    -- Para los widgets de Inicio: libros terminados (con finished_year / finished_month)
    function Aire:getFinishedBooks()
        local L = state(self, "finished")
        if not L.loaded then self:loadGridView("finished") end
        return L.books or {}
    end

    -- Para los widgets de Inicio: libros de la Librería (se cargan si hace falta)
    function Aire:getLibraryBooks()
        local L = state(self, "library")
        if not L.loaded then self:loadGridView("library") end
        return L.books or {}, L.groups or {}
    end

    -- Para los widgets de Inicio: portada de un libro. Se guarda por ruta y se
    -- reutiliza en los redibujos de Inicio (wifi, luz, cargador…) hasta que se
    -- liberan todas con freeWidgetCovers (al vaciar la caché de los widgets o al
    -- cerrar). La lista es también el índice: la galería de pruebas pone una
    -- lista vacía propia y así nunca libera una portada de Inicio.
    function Aire:getWidgetCover(path)
        local list = self._widget_covers or {}
        self._widget_covers = list
        list.by_path = list.by_path or {}
        if not path then return nil end
        local cached = list.by_path[path]
        if cached then return cached end
        local BIM = getBIM()
        if not BIM then return nil end
        local ok, bi = pcall(BIM.getBookInfo, BIM, path, true)
        if ok and bi and bi.has_cover and bi.cover_bb then
            table.insert(list, bi.cover_bb)
            list.by_path[path] = bi.cover_bb
            return bi.cover_bb
        end
    end

    function Aire:freeWidgetCovers()
        for _i, bb in ipairs(self._widget_covers or {}) do pcall(bb.free, bb) end
        self._widget_covers = {}
    end

    -------------------------------------------------------------------------
    -- Proveedores: datos, nivel actual (lista / grupo abierto), acciones
    -- level() devuelve:
    --   entries, group (si hay uno abierto), counts (texto),
    --   filters = { list, key } o nil, sorts = { list, key } o nil, empty (texto)
    -------------------------------------------------------------------------
    local P = {}

    P.library = {
        load = function(self, L)
            local root = libRoot()
            local BIM = getBIM()
            local files, meta = Library.get(root, BIM)
            local books, by_series, missing = {}, {}, {}
            for _i, f in ipairs(files) do
                local m = meta[f.path]
                if not m then table.insert(missing, f.path) end
                local book = makeBook(f.path, m, f.mtime)
                table.insert(books, book)
                if book.series then
                    by_series[book.series] = by_series[book.series] or {}
                    table.insert(by_series[book.series], book)
                end
            end
            -- Series con 2 o más libros: una pila
            local groups = {}
            for name, list in pairs(by_series) do
                if #list >= 2 then
                    table.sort(list, function(a, b)
                        local ia, ib = a.series_index or math.huge, b.series_index or math.huge
                        if ia ~= ib then return ia < ib end
                        return byTitle(a, b)
                    end)
                    local mtime = 0
                    for _j, b in ipairs(list) do
                        b.in_group = true
                        if b.mtime > mtime then mtime = b.mtime end
                    end
                    table.insert(groups, {
                        is_group = true, key = name, title = name, sort_title = name,
                        author = list[1].author, books = list, mtime = mtime, rank = groupRank(list),
                    })
                end
            end
            L.books, L.groups = books, groups
            return missing
        end,
        level = function(self, L)
            if L.open then
                for _i, g in ipairs(L.groups) do
                    if g.key == L.open then
                        -- Serie: por número, sin filtros ni orden
                        return { entries = g.books, group = g, counts = booksAndDone(g.books),
                                 empty = _("Empty series") }
                    end
                end
                L.open = nil
            end
            local filter = config.lib_filter or "all"
            local entries
            if filter == "all" then
                entries = {}
                for _i, b in ipairs(L.books) do
                    if not b.in_group then table.insert(entries, b) end
                end
                for _i, g in ipairs(L.groups) do table.insert(entries, g) end
            else
                entries = filterBooks(L.books, filter)
            end
            sortEntries(entries, config.lib_sort or "smart", config.lib_sort_rev == true,
                filter == "all" and config.lib_mixed == false)
            local counts
            if filter == "all" then
                local parts = { T(N_("%1 book", "%1 books", #L.books), #L.books) }
                if #L.groups > 0 then table.insert(parts, T(N_("%1 series", "%1 series", #L.groups), #L.groups)) end
                do local done = countDone(L.books); table.insert(parts, T(N_("%1 finished", "%1 finished", done), done)) end
                counts = table.concat(parts, " · ")
            else
                counts = T(N_("%1 book", "%1 books", #entries), #entries)
            end
            return {
                entries = entries, counts = counts,
                filters = { list = LISTS.FILTERS_BOOKS, key = "lib_filter" },
                sorts = { list = LISTS.SORTS_LIBRARY, key = "lib_sort", default = "smart",
                          mixed_key = (filter == "all") and "lib_mixed" or nil },
                empty = filter == "all" and _("No books in home folder") or _("No books with this filter"),
            }
        end,
    }

    P.collections = {
        load = function(self, L)
            local ReadCollection = require("readcollection")
            pcall(ReadCollection._read, ReadCollection)
            local BIM = getBIM()
            local meta = loadMetadataUnder(BIM, nil)
            local missing, groups = {}, {}
            local default_title = (self.ui.collections and self.ui.collections.default_collection_title) or _("Favorites")
            for name, coll in pairs(ReadCollection.coll or {}) do
                local books = {}
                for path, item in pairs(coll) do
                    if lfs.attributes(path, "mode") == "file" then
                        local m = metaIn(meta, BIM, path)
                        if not m then table.insert(missing, path) end
                        local b = makeBook(path, m, lfs.attributes(path, "modification"))
                        b.order = item.order
                        table.insert(books, b)
                    end
                end
                sortEntries(books, "manual")
                local settings = ReadCollection.coll_settings and ReadCollection.coll_settings[name] or {}
                local title = name == ReadCollection.default_collection_name and default_title or name
                table.insert(groups, {
                    is_group = true, key = name, title = title, sort_title = title,
                    books = books, order = settings.order, mtime = 0, rank = groupRank(books),
                })
            end
            sortEntries(groups, "manual") -- mismo orden que la lista de colecciones de KOReader
            -- Automáticas por autor y por género (palabra clave): se calculan
            -- cada vez desde la Librería y no se guardan en KOReader.
            if config.coll_auto_author ~= false or config.coll_auto_genre or config.coll_auto_lang then
                local lib_books, lib_groups = self:getLibraryBooks()
                local all_books, seen_all = {}, {}
                local function collectBook(b)
                    if b.fake or seen_all[b.path] then return end
                    seen_all[b.path] = true
                    table.insert(all_books, b)
                end
                for _i, b in ipairs(lib_books or {}) do collectBook(b) end
                for _i, g in ipairs(lib_groups or {}) do
                    for _j, b in ipairs(g.books or {}) do collectBook(b) end
                end

                local function copyBook(b)
                    local copy = {}
                    for k, v in pairs(b) do copy[k] = v end
                    copy.order = nil
                    return copy
                end

                local Genres = package.loaded.aire_genres

                if config.coll_auto_author ~= false then
                    local by, labels, keys = {}, {}, {}
                    for _i, b in ipairs(all_books) do
                        if b.author and b.author ~= "" then
                            local ak = Genres and Genres.authorKey(b.author) or b.author
                            if ak ~= "" then
                                if not by[ak] then
                                    by[ak] = {}
                                    labels[ak] = b.author
                                    table.insert(keys, ak)
                                elseif Genres then
                                    labels[ak] = Genres.betterLabel(labels[ak], b.author)
                                end
                                table.insert(by[ak], copyBook(b))
                            end
                        end
                    end
                    table.sort(keys, function(a, b) return lowerKey(labels[a]) < lowerKey(labels[b]) end)
                    local n = 0
                    for _i, ak in ipairs(keys) do
                        local books = by[ak]
                        if #books >= LISTS.AUTO.MIN then
                            n = n + 1
                            local author = labels[ak]
                            sortEntries(books, "title")
                            table.insert(groups, {
                                is_group = true, auto = true, key = LISTS.AUTO.AUTHOR .. ak, title = author,
                                sort_title = author, books = books, order = 100000 + n, mtime = 0,
                                rank = groupRank(books),
                            })
                        end
                    end
                end

                if config.coll_auto_genre then
                    local by, labels, keys = {}, {}, {}
                    for _i, b in ipairs(all_books) do
                        if b.keywords and b.keywords ~= "" then
                            local extracted = Genres and Genres.extractGenres(b.keywords) or nil
                            if extracted then
                                for _j, g in ipairs(extracted) do
                                    if not by[g.key] then
                                        by[g.key] = {}
                                        labels[g.key] = g.label
                                        table.insert(keys, g.key)
                                    elseif not g.canonical then
                                        labels[g.key] = Genres.betterLabel(labels[g.key], g.label)
                                    end
                                    table.insert(by[g.key], copyBook(b))
                                end
                            else
                                local book_seen = {}
                                local sep = b.keywords:find("\n", 1, true) and "[^\n]+" or "[^,;]+"
                                for raw in b.keywords:gmatch(sep) do
                                    local kw = raw:match("^%s*(.-)%s*$")
                                    kw = kw and (kw:match("^(.-)%s*%-%-") or kw)
                                    if kw and kw ~= "" then
                                        local lk = kw:lower()
                                        if not book_seen[lk] then
                                            book_seen[lk] = true
                                            if not by[lk] then
                                                by[lk] = {}
                                                labels[lk] = kw
                                                table.insert(keys, lk)
                                            end
                                            table.insert(by[lk], copyBook(b))
                                        end
                                    end
                                end
                            end
                        end
                    end
                    table.sort(keys, function(a, b) return lowerKey(labels[a]) < lowerKey(labels[b]) end)
                    local n = 0
                    for _i, lk in ipairs(keys) do
                        local books = by[lk]
                        if #books >= LISTS.AUTO.MIN then
                            n = n + 1
                            local genre = labels[lk]
                            sortEntries(books, "title")
                            table.insert(groups, {
                                is_group = true, auto = true, key = LISTS.AUTO.GENRE .. lk, title = genre,
                                sort_title = genre, books = books, order = 200000 + n, mtime = 0,
                                rank = groupRank(books),
                            })
                        end
                    end
                end

                if config.coll_auto_lang and Genres and Genres.extractLanguages then
                    local by, labels, keys = {}, {}, {}
                    for _i, b in ipairs(all_books) do
                        if b.language and b.language ~= "" then
                            for _j, lang in ipairs(Genres.extractLanguages(b.language)) do
                                if not by[lang.key] then
                                    by[lang.key] = {}
                                    labels[lang.key] = lang.label
                                    table.insert(keys, lang.key)
                                end
                                table.insert(by[lang.key], copyBook(b))
                            end
                        end
                    end
                    table.sort(keys, function(a, b) return lowerKey(labels[a]) < lowerKey(labels[b]) end)
                    local n = 0
                    for _i, lk in ipairs(keys) do
                        local books = by[lk]
                        if #books >= LISTS.AUTO.MIN then
                            n = n + 1
                            local lang_label = labels[lk]
                            sortEntries(books, "title")
                            table.insert(groups, {
                                is_group = true, auto = true, key = LISTS.AUTO.LANG .. lk, title = lang_label,
                                sort_title = lang_label, books = books, order = 300000 + n, mtime = 0,
                                rank = groupRank(books),
                            })
                        end
                    end
                end
            end
            L.groups = groups
            return missing
        end,
        level = function(self, L)
            if L.open then
                for _i, g in ipairs(L.groups) do
                    if g.key == L.open then
                        local filter = config.coll_filter or "all"
                        local entries = filterBooks(g.books, filter)
                        sortEntries(entries, config.coll_sort or "manual", config.coll_sort_rev == true)
                        return {
                            entries = entries, group = g,
                            counts = filter == "all" and booksAndDone(g.books) or T(N_("%1 book", "%1 books", #entries), #entries),
                            filters = { list = LISTS.FILTERS_BOOKS, key = "coll_filter" },
                            sorts = { list = LISTS.SORTS_COLLECTION, key = "coll_sort", default = "manual" },
                            empty = filter == "all" and _("Empty collection") or _("No books with this filter"),
                        }
                    end
                end
                L.open = nil
            end
            -- Filtros por estado de la colección: Leyendo = empezada (algún
            -- libro leyéndose, o terminados algunos pero no todos); Nuevos = sin
            -- empezar; Terminados = todos terminados. Las vacías solo en Todos.
            local filter = config.coll_list_filter or "all"
            local want = ({ reading = 0, new = 2, complete = 3 })[filter]
            local entries, total = {}, 0
            for _i, g in ipairs(L.groups) do
                total = total + #g.books
                if filter == "all" or (#g.books > 0 and g.rank == want) then
                    table.insert(entries, g)
                end
            end
            sortEntries(entries, config.coll_list_sort or "manual", config.coll_list_sort_rev == true)
            local n_entries = #entries
            if filter == "all" or n_entries > 0 then
                table.insert(entries, 1, { is_action = true, action = "new_collection", title = _("New collection") })
            end
            return {
                entries = entries,
                counts = filter == "all"
                    and (T(N_("%1 collection", "%1 collections", #L.groups), #L.groups) .. " · " .. T(N_("%1 book", "%1 books", total), total))
                    or T(N_("%1 collection", "%1 collections", n_entries), n_entries),
                filters = { list = LISTS.FILTERS_BOOKS, key = "coll_list_filter" },
                sorts = { list = LISTS.SORTS_COLL_LIST, key = "coll_list_sort", default = "manual" },
                empty = filter == "all" and _("No collections") or _("No collections with this filter"),
            }
        end,
        remove = function(self, L, book)
            if isAutoKey(L.open) then return nil end -- automática: los libros se calculan
            return {
                text = C_("aire", "Remove from collection"),
                callback = function()
                    require("readcollection"):removeItem(book.path, L.open)
                    self:reloadGridView("collections")
                end,
            }
        end,
    }

    -- Terminados (se abre desde la casilla de Estadísticas): libros del
    -- historial marcados como terminados; fecha = summary.modified
    P.finished = {
        load = function(self, L)
            local ReadHistory = require("readhistory")
            local BIM = getBIM()
            local meta = loadMetadataUnder(BIM, nil)
            local missing, books = {}, {}
            -- Candidatos: el historial y también la Librería (libros marcados como
            -- terminados sin haberlos abierto no están en el historial)
            local candidates, seen = {}, {}
            -- Clave = ruta con /mnt/base-us -> /mnt/us (en el Kindle son la misma
            -- carpeta). Antes era solo el nombre del archivo: dos libros con el
            -- mismo nombre en carpetas distintas contaban como uno.
            local function add(path, time)
                local key = path and path:gsub("^/mnt/base%-us/", "/mnt/us/")
                if path and key and not seen[key] then
                    seen[key] = true
                    table.insert(candidates, { file = path, time = time })
                end
            end
            for _i, item in ipairs(ReadHistory.hist or {}) do
                if not item.dim then add(item.file, item.time) end
            end
            for _i, b in ipairs(self:getLibraryBooks()) do
                if not b.fake then add(b.path, b.mtime) end
            end
            for _i, item in ipairs(candidates) do
                if lfs.attributes(item.file, "mode") == "file" and BookList.getBookStatus(item.file) == "complete" then
                    local m = metaIn(meta, BIM, item.file)
                    if not m then table.insert(missing, item.file) end
                    local b = makeBook(item.file, m, item.time)
                    local ok_ds, ds = pcall(BookList.getDocSettings, item.file)
                    local summary = ok_ds and ds and ds:readSetting("summary")
                    local mod = summary and summary.modified
                    if type(mod) == "string" then
                        local y, mo, d = mod:match("^(%d+)-(%d+)-(%d+)")
                        if y then
                            b.mtime = os.time{ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = 12 }
                            b.finished_year = y
                            b.finished_month = tonumber(mo)
                        end
                    end
                    table.insert(books, b)
                end
            end
            L.books = books
            return missing
        end,
        level = function(self, L)
            local year = os.date("%Y")
            local month = tonumber(os.date("%m"))
            local filter = config.fin_filter or "year"
            local entries = {}
            for _i, b in ipairs(L.books) do
                if filter == "all" or (b.finished_year == year
                        and (filter == "year" or b.finished_month == month)) then
                    table.insert(entries, b)
                end
            end
            sortEntries(entries, config.fin_sort or "recent", config.fin_sort_rev == true)
            return {
                entries = entries,
                back = { title = _("Finished books"), action = function() self:goBack(function() self:showStatsView() end) end },
                counts = T(N_("%1 finished book", "%1 finished books", #entries), #entries),
                filters = { list = { { id = "month", label = require("datetime").longMonthTranslation[({ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" })[month]] }, { id = "year", label = year },
                                     { id = "all", label = _("Always") } },
                            key = "fin_filter", default = "year" },
                sorts = { list = LISTS.SORTS_FINISHED, key = "fin_sort", default = "recent" },
                empty = filter == "all" and _("You haven't finished any books yet")
                    or (filter == "month" and _("No books finished this month") or _("No books finished this year")),
            }
        end,
    }

    P.history = {
        load = function(self, L)
            local ReadHistory = require("readhistory")
            local BIM = getBIM()
            local meta = loadMetadataUnder(BIM, nil)
            local missing, books = {}, {}
            for _i, item in ipairs(ReadHistory.hist or {}) do
                if not item.dim and item.file then
                    local m = metaIn(meta, BIM, item.file)
                    if not m then table.insert(missing, item.file) end
                    local b = makeBook(item.file, m, item.time)
                    b.hist_item = item
                    table.insert(books, b)
                end
            end
            L.books = books
            return missing
        end,
        level = function(self, L)
            local filter = config.hist_filter or "all"
            local entries = filterBooks(L.books, filter)
            sortEntries(entries, config.hist_sort or "recent", config.hist_sort_rev == true)
            return {
                entries = entries,
                counts = filter == "all" and booksAndDone(L.books) or T(N_("%1 book", "%1 books", #entries), #entries),
                filters = { list = LISTS.FILTERS_HISTORY, key = "hist_filter" },
                sorts = { list = LISTS.SORTS_HISTORY, key = "hist_sort", default = "recent" },
                empty = filter == "all" and _("History is empty") or _("No books with this filter"),
            }
        end,
        remove = function(self, L, book)
            return {
                text = _("Remove from history"),
                callback = function()
                    -- Con el índice exacto: sin él, KOReader lo busca por hora y,
                    -- si no lo encuentra, table.remove(hist, nil) quita el ÚLTIMO
                    local item = book.hist_item
                    local RH = require("readhistory")
                    for idx, h in ipairs(RH.hist or {}) do
                        if h == item then RH:removeItem(item, idx) break end
                    end
                    self:reloadGridView("history")
                end,
            }
        end,
    }

    -------------------------------------------------------------------------
    -- Carga y análisis en segundo plano
    -------------------------------------------------------------------------
    function Aire:loadGridView(kind)
        local L = state(self, kind)
        local t0 = time.now()
        local ok, missing = pcall(P[kind].load, self, L)
        logger.dbg("Aire/Grid:", kind, "leído en", time.to_ms(time.since(t0)), "ms,",
            L.books and #L.books or 0, "libros")
        if not ok then
            logger.warn("Aire/Grid: error cargando", kind, missing)
            L.books, L.groups = {}, {}
            missing = {}
        end
        L.books = L.books or {}
        L.groups = L.groups or {}
        if config.demo and TEST and TEST.addDemoData then
            local ok_demo, err = pcall(TEST.addDemoData, kind, L, { RANK = LISTS.RANK, groupRank = groupRank })
            if not ok_demo then logger.warn("Aire/Grid: error en los datos de prueba:", err) end
        end
        L.loaded = true
        self:startGridExtraction(missing or {})
    end

    -- Libros ya mandados a analizar en esta sesión (no por FileManager): si
    -- CoverBrowser no puede con uno (fichero roto, formato sin soporte), no se
    -- vuelve a lanzar al volver de cada libro, y su fin de análisis no invalida
    -- otra vez la caché de Librería (views/grid/library.lua).
    local extract_tried = {}

    function Aire:startGridExtraction(missing)
        local BIM = getBIM()
        if not BIM or #missing == 0 then return end
        local gw = Screen:getWidth() - 2 * S(ctx.SIDE_PAD)
        local cols = gridCols()
        local cell_w = math.floor((gw - (cols - 1) * S(10)) / cols)
        local specs = { max_cover_w = cell_w, max_cover_h = math.floor(cell_w * LISTS.COVER_RATIO) }
        local files = {}
        for _i, p in ipairs(missing) do
            if not extract_tried[p] then
                extract_tried[p] = true
                table.insert(files, { filepath = p, cover_specs = specs })
            end
        end
        if #files == 0 then return end
        local ok, started = pcall(BIM.extractInBackground, BIM, files)
        if not ok or started == false then
            logger.warn("Aire/Grid: no se pudo lanzar el análisis:", started)
            return
        end
        logger.dbg("Aire/Grid: analizando", #files, "libros nuevos")
        if not self._gv_poll then
            self._gv_poll = function()
                local bim = getBIM()
                if bim and bim:isExtractingInBackground() then
                    UIManager:scheduleIn(2, self._gv_poll)
                    return
                end
                Library.invalidate()
                if self:isGridViewVisible() then self:reloadGridView(self.view) end
            end
        end
        UIManager:unschedule(self._gv_poll)
        UIManager:scheduleIn(2, self._gv_poll)
    end

    -- Caché de sesión de Librería caducada: la próxima carga vuelve a escanear.
    -- Si la pestaña Librería de este FileManager ya estaba cargada, se marca
    -- para volver a leerla al construirla (getLibraryBooks, buildGridView).
    function Aire:invalidateLibraryCache()
        Library.invalidate()
        local L = self._gv and self._gv.library
        if L then L.loaded = false end
    end

    -- Metadatos cambiados (Información del libro, en el lector o el explorador):
    -- KOReader lo avisa a todos los widgets. No se consume el evento.
    function Aire:onBookMetadataChanged()
        self:invalidateLibraryCache()
    end

    -- Borrar, renombrar o pegar (copiar / mover) desde el explorador de KOReader
    -- o desde las fichas (FileManager.showDeleteFileDialog → deleteFile): pueden
    -- cambiar subcarpetas, cuyo cambio no se ve en el mtime de la raíz.
    do
        local FileManager = require("apps/filemanager/filemanager")
        if not FileManager._aire_library_hooked then
            FileManager._aire_library_hooked = true
            local function invalidateAfter(...)
                pcall(function()
                    local inst = Aire._active_instance
                    if inst and inst.invalidateLibraryCache then
                        inst:invalidateLibraryCache()
                    else
                        Library.invalidate()
                    end
                end)
                return ...
            end
            for _i, name in ipairs({ "deleteFile", "deleteSelectedFiles", "renameFile", "pasteFileFromClipboard" }) do
                local orig = FileManager[name]
                if type(orig) == "function" then
                    FileManager[name] = function(...) return invalidateAfter(orig(...)) end
                end
            end
        end
    end

    -------------------------------------------------------------------------
    -- Acciones
    -------------------------------------------------------------------------
    function Aire:isGridViewVisible()
        return self:isOwnView() and LISTS.GRID_VIEWS[self.view] == true
    end

    function Aire:refreshGridView()
        if not self:isGridViewVisible() then return end
        self:apply()
        UIManager:setDirty(self.ui, "ui")
    end

    function Aire:reloadGridView(kind)
        if kind == "library" then Library.invalidate() end
        self:freeGridCovers(kind)
        self:loadGridView(kind)
        if self.view == kind then self:refreshGridView() end
    end

    function Aire:setGridOption(key, id)
        if config[key] == id then return end
        config[key] = id
        saveConfig()
        state(self, self.view).page = 1
        self:refreshGridView()
    end

    function Aire:showGridFilterSortMenu(filters, sorts)
        -- Hoja común para elegir (ui/sheet.lua): la opción actual, rellena
        local groups = {}
        local function addGroup(heading, spec)
            local current = config[spec.key] or spec.default
            local items = {}
            for _i, item in ipairs(spec.list) do
                local id, key = item.id, spec.key
                table.insert(items, { text = item.label, active = (item.id == current),
                    callback = function() self:setGridOption(key, id) end })
            end
            table.insert(groups, { heading = heading, items = items })
        end
        if filters then addGroup(_("FILTER"), filters) end
        if sorts then
            addGroup(_("SORT BY"), sorts)
            local rev_key = sorts.key .. "_rev"
            local rev = config[rev_key] == true
            local extras = {
                { text = _("Reverse sorting"), active = rev,
                  callback = function() self:setGridOption(rev_key, not rev) end },
            }
            local mixed_key = sorts.mixed_key
            if mixed_key then
                local mixed = config[mixed_key] ~= false
                table.insert(extras, { text = _("Mix series"), active = mixed,
                    callback = function() self:setGridOption(mixed_key, not mixed) end })
            end
            table.insert(groups, { items = extras })
        end
        package.loaded.aire_sheet.showChoices{
            title = (filters and sorts) and _("Filter and sort") or (filters and _("Filter") or _("Sort by")),
            groups = groups,
            style = ctx.selStyle and ctx.selStyle() or "black",
            lighten = ctx.lightened,
        }
    end

    function Aire:openGridGroup(key)
        local L = state(self, self.view)
        L.parent_page = L.page
        L.open = key
        L.page = 1
        self:refreshGridView()
    end

    function Aire:closeGridGroup()
        local L = state(self, self.view)
        L.open = nil
        L.page = L.parent_page or 1
        self:refreshGridView()
    end

    function Aire:gridPageTurn(delta)
        local L = state(self, self.view)
        local new_page = math.max(1, math.min(L.pages or 1, L.page + delta))
        if new_page ~= L.page then
            L.page = new_page
            self:refreshGridView()
        end
    end

    function Aire:onGridBookHold(book)
        local fm = self.ui
        local kind = self.view
        local L = state(self, kind)
        local path = book.path
        local reload = function()
            BookList.resetBookInfoCache(path)
            self:reloadGridView(kind)
        end
        local show = require("apps/filemanager/filemanager").aire_showBookSheetFor
        if show then
            local fc = fm.file_chooser
            local item = { path = path, is_file = true, text = path:match("([^/]+)$") }
            local ok, err = pcall(show, {
                owner = self,
                ui = fm,
                file = path,
                item = item,
                on_status = reload,
                on_refresh = reload,
                remove_btn = P[kind].remove and P[kind].remove(self, L, book) or nil,
                more = function()
                    if fc and fc._aire_orig_showFileDialog then
                        fc._aire_orig_showFileDialog(fc, item)
                    elseif fm.bookinfo then
                        fm.bookinfo:show(path)
                    end
                end,
            })
            if ok then return end
            logger.warn("Aire/Grid: error en la ficha del libro:", err)
        end
        if fm.bookinfo then fm.bookinfo:show(path) end
    end

    -------------------------------------------------------------------------
    -- Gestión de colecciones (crear, renombrar, eliminar, ordenar)
    -- Usa ReadCollection y el diálogo de nombre de KOReader; guarda con write().
    -------------------------------------------------------------------------
    local function RC() return require("readcollection") end

    local function editName(self, callback, old_name)
        local fmc = self.ui.collections
        if fmc and fmc.editCollectionName then
            fmc:editCollectionName(callback, old_name)
        end
    end

    function Aire:newCollection()
        editName(self, function(name)
            RC():addCollection(name)
            RC():write({ [name] = true })
            self:reloadGridView("collections")
        end)
    end

    function Aire:renameCollection(key)
        editName(self, function(name)
            RC():renameCollection(key, name)
            RC():write({ [name] = true })
            local L = state(self, "collections")
            if L.open == key then L.open = name end
            self:reloadGridView("collections")
        end, key)
    end

    function Aire:removeCollection(key, title)
        UIManager:show(require("ui/widget/confirmbox"):new{
            text = _("Delete the collection?") .. "\n\n" .. (title or key)
                .. "\n\n" .. _("Books are not deleted, only the collection."),
            ok_text = _("Delete"),
            ok_callback = function()
                RC():removeCollection(key)
                RC():write()
                local L = state(self, "collections")
                if L.open == key then L.open = nil end
                self:reloadGridView("collections")
            end,
        })
    end

    function Aire:sortCollections()
        local items = {}
        for _i, g in ipairs(state(self, "collections").groups or {}) do
            if not g.fake and not g.auto then table.insert(items, { text = g.title, name = g.key }) end
        end
        local sort_widget
        sort_widget = require("ui/widget/sortwidget"):new{
            title = _("Sort collections"),
            item_table = items,
            callback = function()
                RC():updateCollectionListOrder(sort_widget.item_table)
                RC():write({ [1] = true })
                config.coll_list_sort = "manual" -- para ver el orden que acabas de poner
                saveConfig()
                self:reloadGridView("collections")
            end,
        }
        UIManager:show(sort_widget)
    end

    -- Mantener una colección: la misma ficha que una serie (continuar, abrir,
    -- marcar todo) y debajo la gestión de colecciones
    function Aire:showCollectionOptions(group)
        if group.fake then return end
        local is_default = group.key == RC().default_collection_name -- Favoritos: no se renombra ni borra
        if group.auto then
            local auto_label = _("Automatic: books by this author")
            if type(group.key) == "string" then
                if group.key:sub(1, #LISTS.AUTO.GENRE) == LISTS.AUTO.GENRE then
                    auto_label = _("Automatic: books in this genre")
                elseif group.key:sub(1, #LISTS.AUTO.LANG) == LISTS.AUTO.LANG then
                    auto_label = _("Automatic: books in this language")
                end
            end
            return self:showGroupStatusSheet(group, {
                { { text = auto_label, enabled = false } },
                {
                    { text = _("New collection…"), callback = function() self:newCollection() end },
                    { text = _("Sort collections…"), callback = function() self:sortCollections() end },
                },
            })
        end
        self:showGroupStatusSheet(group, {
            {
                { text = _("Rename…"), enabled = not is_default,
                  callback = function() self:renameCollection(group.key) end },
                { text = _("Delete…"), enabled = not is_default,
                  callback = function() self:removeCollection(group.key, group.title) end },
            },
            {
                { text = _("New collection…"), callback = function() self:newCollection() end },
                { text = _("Sort collections…"), callback = function() self:sortCollections() end },
            },
        })
    end

    -- Mantener pulsada una serie o colección: ficha de grupo (booksheet.lua)
    function Aire:onGridGroupHold(group)
        if self.view == "collections" then return self:showCollectionOptions(group) end
        return self:showGroupStatusSheet(group)
    end

    function Aire:showGroupStatusSheet(group, extra_rows)
        if #group.books == 0 and not extra_rows then return end
        local fm = self.ui
        local kind = self.view
        local show = require("apps/filemanager/filemanager").aire_showSeriesSheet
        if not show then return end
        local items = {}
        for _i, b in ipairs(group.books) do
            table.insert(items, { path = b.path, text = b.title, _series_index = b.series_index })
        end
        local is_coll = kind == "collections"
        local ok, err = pcall(show, fm, { text = group.title, series_items = items }, {
            owner = self,
            open = function() self:openGridGroup(group.key) end,
            refresh = function()
                for _i, b in ipairs(group.books) do BookList.resetBookInfoCache(b.path) end
                self:reloadGridView(kind)
            end,
            open_text = is_coll and _("Open collection") or _("Open series"),
            all_done_text = is_coll and _("Mark entire collection as finished") or nil,
            all_reading_text = is_coll and _("Mark entire collection as reading") or nil,
            confirm_text = is_coll and _("Mark all books in collection \"%1\" as reading?") or nil,
            extra_rows = extra_rows,
        })
        if not ok then logger.warn("Aire/Grid: error en la ficha del grupo:", err) end
    end

    -------------------------------------------------------------------------
    -- Construcción
    -------------------------------------------------------------------------
    -- Portadas: caché LRU en views/grid/covers.lua (por pestaña). Las celdas
    -- no son dueñas de los buffers (image_disposable = false); se desalojan
    -- las menos recientes al superar el límite y se liberan todas al salir.
    function Aire:freeGridCovers(kind)
        local L = state(self, kind)
        if L.cover_cache then L.cover_cache:freeAll() end
    end

    local function cancelPrefetch(L)
        if not L then return end
        if L.prefetch_cb then
            UIManager:unschedule(L.prefetch_cb)
            L.prefetch_cb = nil
        end
        if L.prefetch_todo then
            for _i, c in ipairs(L.prefetch_todo) do pcall(c.free, c) end
            L.prefetch_todo = nil
        end
    end

    -- Con el Kindle en reposo, se preparan las miniaturas de la página
    -- siguiente (celdas fuera de pantalla, una cada poco), para que deslizar
    -- sea inmediato. No se repinta nada. Si se cambia de página o de pestaña,
    -- se para.
    function Aire:startPrefetch(kind, next_cells)
        local L = state(self, kind)
        cancelPrefetch(L)
        L.load_token = (L.load_token or 0) + 1
        local token = L.load_token
        if not next_cells then return end
        local function alive()
            return L.load_token == token and self.view == kind and self:isGridViewVisible()
        end
        local slow = function(path, w, h) return L.cover_cache:get(path, w, h, true, false) end
        local prefetch
        prefetch = function()
            L.prefetch_cb = nil
            local list = L.prefetch_todo
            if not alive() then
                cancelPrefetch(L)
                return
            end
            local c = list and table.remove(list, 1)
            if c then
                pcall(c.loadPending, c, slow)
                pcall(c.free, c)
                L.prefetch_cb = prefetch
                UIManager:scheduleIn(0.05, prefetch)
            else
                L.prefetch_todo = nil
                Thumbs.maybeTrim()
            end
        end
        local start_cb = function()
            L.prefetch_cb = nil
            if not alive() then return end
            local ok, list = pcall(next_cells)
            if ok and type(list) == "table" then
                local todo = {}
                for _i, c in ipairs(list) do
                    if c.pending then table.insert(todo, c) else pcall(c.free, c) end
                end
                L.prefetch_todo = todo
                prefetch()
            end
        end
        L.prefetch_cb = start_cb
        UIManager:scheduleIn(0.6, start_cb)
    end

    -- Texto del filtro y el orden actuales ("Todos · Recientes"); nil si la
    -- vista no tiene ninguno de los dos
    function Aire:gridFilterSortLabel(filters, sorts)
        if not (filters or sorts) then return nil end
        local parts = {}
        if filters then
            local fopt = findOption(filters.list, config[filters.key] or filters.default or "all")
            table.insert(parts, fopt.short or fopt.label)
        end
        if sorts then
            local sopt = findOption(sorts.list, config[sorts.key] or sorts.default)
            table.insert(parts, sopt.short or sopt.label)
        end
        return table.concat(parts, " · ")
    end

    function Aire:buildGrid(w, h, entries, empty_text, swipe_extra_h)
        local L = state(self, self.view)
        local gap = S(10)
        local COLS = gridCols() -- opción del menú (3 o 4)
        local cell_w = math.floor((w - (COLS - 1) * gap) / COLS)
        local rem_w = w - (COLS - 1) * gap - COLS * cell_w
        -- Filas que caben con la proporción ideal (COVER_RATIO); luego el alto de
        -- las celdas se estira o encoge para llenar todo el espacio, eligiendo el
        -- nº de filas cuya proporción quede más cerca de la ideal. Así no queda
        -- un hueco grande debajo donde no cabe otra fila.
        local ideal_h = cell_w * LISTS.COVER_RATIO
        local function heightFor(r) return math.floor((h - (r - 1) * gap) / r) end
        local r1 = math.max(1, math.floor((h + gap) / (ideal_h + gap)))
        local rows = r1
        local h1, h2 = heightFor(r1), heightFor(r1 + 1)
        if h2 > 0 and math.abs(h2 - ideal_h) < math.abs(h1 - ideal_h) then rows = r1 + 1 end
        local cell_h = heightFor(rows)
        local per_page = rows * COLS
        L.pages = math.max(1, math.ceil(#entries / per_page))
        L.page = math.max(1, math.min(L.page or 1, L.pages))

        local grid = InputContainer:new{
            dimen = Geom:new{ x = 0, y = 0, w = w, h = h },
        }
        grid.ges_events = {
            AireSwipe = { GestureRange:new{ ges = "swipe", range = function()
                -- también sobre la fila de puntos de página
                local d = grid.dimen
                return Geom:new{ x = d.x, y = d.y, w = d.w, h = d.h + (swipe_extra_h or 0) }
            end } },
        }
        grid.onAireSwipe = function(_self, _args, ges)
            local dir = ges and ges.direction
            if dir == "west" then
                self:gridPageTurn(1)
                return true
            elseif dir == "east" then
                self:gridPageTurn(-1)
                return true
            end
            return false
        end

        if #entries == 0 then
            grid[1] = CenterContainer:new{
                dimen = Geom:new{ w = w, h = h },
                TextWidget:new{ text = empty_text or "", face = face(false, 15), fgcolor = GRAY_TEXT, padding = 0 },
            }
            return grid
        end

        local on_tap = function(entry)
            if entry.is_action then
                if entry.action == "new_collection" then self:newCollection() end
            elseif entry.is_group then
                self:openGridGroup(entry.key)
            elseif entry.fake then
                Notification:notify(_("Test book"))
            else
                filemanagerutil.openFile(self.ui, entry.path)
            end
        end
        local on_hold = function(entry)
            if entry.fake or entry.is_action then return end
            if entry.is_group then
                self:onGridGroupHold(entry)
            else
                self:onGridBookHold(entry)
            end
        end

        local cache = L.cover_cache
        cache:clearPins()
        local RC = require("readcollection")
        local fast_pin = function(path, fw, fh) return cache:get(path, fw, fh, false, true) end
        local fast_prefetch = function(path, fw, fh) return cache:get(path, fw, fh, false, false) end
        local function makeCell(e, c, fast_fn)
            local cover_path, mosaic_paths
            if e.is_group then
                -- Series y colecciones (también vacías): mosaico con las
                -- portadas de los 4 primeros libros y el nombre arriba
                mosaic_paths = {}
                for i = 1, math.min(4, #e.books) do
                    local b = e.books[i]
                    mosaic_paths[i] = (not b.fake and b.path) or false
                end
            elseif not e.fake and not e.is_action then
                cover_path = e.path
            end
            local cw = cell_w + (c < rem_w and 1 or 0)
            return GridCell:new{
                    entry = e, width = cw, height = cell_h, cover_path = cover_path, mosaic_paths = mosaic_paths,
                    cover_fast = fast_fn or fast_pin,
                    scaled_cache = cache.aux,
                    series_badge = self.view == "library" and config.series_badge ~= false,
                    -- Marca de colección (KOReader: Configuración → Mostrar marca de
                    -- colección); no en Colecciones, donde ya se sabe
                    in_collection = self.view ~= "collections" and not e.is_group and not e.fake
                        and not e.is_action and RC:isFileInCollections(e.path),
                    show_mark = config.reading_mark ~= false,
                    show_finished = config.finished_gray ~= false,
                    rounded = config.rounded_covers == true,
                    tap_expand = math.floor(gap / 2),
                    on_tap = on_tap, on_hold = on_hold,
                }
        end
        local vg = VerticalGroup:new{ align = "left" }
        local first = (L.page - 1) * per_page + 1
        local cells = {}
        for r = 0, rows - 1 do
            local idx = first + r * COLS
            if idx > #entries then break end
            if r > 0 then table.insert(vg, VerticalSpan:new{ width = gap }) end
            local hg = HorizontalGroup:new{ align = "top" }
            for c = 0, COLS - 1 do
                local e = entries[idx + c]
                if not e then break end
                if c > 0 then table.insert(hg, HorizontalSpan:new{ width = gap }) end
                local cell = makeCell(e, c)
                table.insert(cells, cell)
                table.insert(hg, cell)
            end
            table.insert(vg, hg)
        end
        grid[1] = vg
        -- Portadas que no tienen miniatura todavía: se hacen ya, antes de
        -- enseñar la página (el usuario prefiere que no vayan apareciendo)
        local slow = function(path, fw, fh) return cache:get(path, fw, fh, true, true) end
        for _i, cell in ipairs(cells) do
            if cell.pending then pcall(cell.loadPending, cell, slow) end
        end
        -- Con el Kindle en reposo, miniaturas de la página siguiente
        local next_first = first + per_page
        local next_cells = next_first <= #entries and function()
            local list = {}
            for i = next_first, math.min(#entries, next_first + per_page - 1) do
                table.insert(list, makeCell(entries[i], (i - next_first) % COLS, fast_prefetch))
            end
            return list
        end or nil
        self:startPrefetch(self.view, next_cells)
        return grid
    end

    function Aire:buildGridView(kind)
        local L = state(self, kind)
        if not L.loaded then self:loadGridView(kind) end
        local t0 = time.now()
        local lvl = P[kind].level(self, L)

        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local side = S(ctx.SIDE_PAD)
        local w = sw - 2 * side

        local VIEW_TITLES = {
            library = _("Library"),
            collections = _("Collections"),
            history = _("History"),
        }
        -- Cabecera común (ui/screen.lua):
        --   pestaña (Librería…): "Título" y a la derecha el filtro·orden ▾
        --   subpágina (Terminados, una colección o serie): "‹ Título" y ≡ si
        --   tiene filtro u orden (el filtro·orden actual va en el subtítulo)
        local fs_label = self:gridFilterSortLabel(lvl.filters, lvl.sorts)
        local fs_open = fs_label and function() self:showGridFilterSortMenu(lvl.filters, lvl.sorts) end or nil
        local head, sub_txt = {}, lvl.counts or ""
        local back = lvl.back
            or (lvl.group and { title = lvl.group.title, action = function() self:closeGridGroup() end })
        if back then
            head = { title = back.title, on_back = back.action, menu_icon = fs_open and "aire.menu", on_menu = fs_open }
            if fs_label then sub_txt = sub_txt ~= "" and (sub_txt .. " · " .. fs_label) or fs_label end
        elseif VIEW_TITLES[kind] then
            head = { title = VIEW_TITLES[kind], menu_text = fs_label, on_menu = fs_open }
        end
        local content = self:buildScreenTop(w, head)
        -- Recuentos (y en subpáginas el filtro·orden) como subtítulo
        table.insert(content, (package.loaded.aire_screen.subtitle(w, sub_txt)))
        table.insert(content, VerticalSpan:new{ width = S(12) })
        content:resetLayout()
        local used_h = content:getSize().h

        local dock = self:buildNavBar(w)
        local dock_area = package.loaded.aire_screen.dockReserve(dock)
        local dots_gap = S(package.loaded.aire_screen.METRICS.DOTS_GAP)
        local dots_h = S(package.loaded.aire_screen.METRICS.DOTS_H)
        local grid_h = math.max(S(60), sh - used_h - dots_gap - dots_h - dock_area)

        table.insert(content, self:buildGrid(w, grid_h, lvl.entries, lvl.empty, dots_gap + dots_h))
        table.insert(content, VerticalSpan:new{ width = dots_gap })
        table.insert(content, Pager:new{ width = w, height = dots_h, page = L.page, pages = L.pages or 1 })
        content:resetLayout()
        logger.dbg("Aire/Grid:", kind, "construido en", time.to_ms(time.since(t0)), "ms")

        local view = package.loaded.aire_screen.root(HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            content,
        }, dock)
        -- Tiempo del primer pintado (escalar portadas, etc.) en el log
        local orig_paint = view.paintTo
        view.paintTo = function(v, bb, x, y)
            local tp = time.now()
            orig_paint(v, bb, x, y)
            if not v._aire_paint_logged then
                v._aire_paint_logged = true
                logger.dbg("Aire/Grid:", kind, "pintado en", time.to_ms(time.since(tp)), "ms")
            end
        end
        return view
    end

    -- Abrir una pestaña de cuadrícula desde el dock (o subvista "finished")
    function Aire:showGridView(kind)
        if kind == "finished" then
            if self.pushBack then self:pushBack("finished") end
        elseif not self._restoring_back and self.clearBackStack then
            self:clearBackStack()
        end
        local L = state(self, kind)
        if self.view ~= kind then
            if self.view == "stats" and self.closeStatsView then self:closeStatsView() end
            -- Al entrar: volver a leer (libros nuevos, estados al día)
            L.loaded = false
            L.open = nil
            L.page = 1
        elseif L.open then
            -- Tocar la pestaña dentro de un grupo: volver a la lista
            L.open = nil
            L.page = L.parent_page or 1
        end
        config.mode = "library"
        saveConfig()
        self.view = kind
        self:apply()
        UIManager:setDirty(self.ui, "flashui")
    end

    function Aire:isGridView(view)
        return LISTS.GRID_VIEWS[view] == true
    end

    -- Al salir de las vistas de cuadrícula o cerrar el FileManager.
    -- keep_covers (ir a Inicio / Estadísticas): las portadas se quedan para
    -- que volver a la pestaña sea rápido; se liberan al cerrar el explorador
    -- (abrir un libro). Mientras tanto, la caché LRU (covers.lua) desaloja las
    -- menos recientes al pasar de su límite.
    function Aire:closeGridViews(keep_covers)
        if self._gv_poll then UIManager:unschedule(self._gv_poll) end
        if self._gv then
            for kind in pairs(LISTS.GRID_VIEWS) do cancelPrefetch(self._gv[kind]) end
        end
        if keep_covers then return end
        for kind in pairs(LISTS.GRID_VIEWS) do
            if self._gv and self._gv[kind] then self:freeGridCovers(kind) end
        end
    end
end
