--[[
    aire.koplugin/views/widgets.lua
    Zona de widgets de Inicio (debajo de "Leyendo ahora").

    Cuadrícula de 4 columnas por fila; cada widget ocupa 1 celda (pequeño) o
    2 (grande, si la celda de la derecha está libre). El nº de filas depende del
    espacio entre la tarjeta y el dock (hasta MAX_ROWS); el alto se ajusta.

    Uso normal: tocar = acción rápida; mantener = abrir algo. Huecos vacíos
    invisibles.
    Modo edición (menú -> Pantalla de inicio -> Editar widgets de Inicio, o
    "Listo" para salir): cada celda libre sale con "+"; tocar un widget (o
    crearlo) abre sus opciones:
        Grande (si la derecha está libre), Colores invertidos,
        Mantener = tocar (solo si el widget no tiene acción al mantener),
        Intercambiar tocar y mantener (no se puede con la anterior),
        opciones propias (p. ej. periodo de Terminados), Cambiar, Quitar.
    Se guarda en config.home_widgets["fila:columna"] =
        { id, span, invert, swap, hold_tap, period }

    Se carga desde main.lua como "mixin". OJO: no usar "_" como variable.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local _ = require("gettext")

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

local COLS = 4
local MAX_ROWS = 3
local MIN_CELL_H = 84   -- por debajo de esto no se añade otra fila
local MAX_CELL_H = 150  -- las celdas no crecen más

-- Colores: normal y con "Colores invertidos"
local THEME_NORMAL = { bg = WHITE, fg = BLACK, fg2 = GRAY_TEXT, border = BLACK, inverted = false }
local THEME_INVERTED = { bg = BLACK, fg = WHITE, fg2 = Blitbuffer.COLOR_GRAY_B, border = BLACK, inverted = true }

local WIDGETS_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]*$") or "plugins/aire.koplugin/views"
-- Formatos, utilidades y piezas (hoja de opciones, hueco, celda)
local Parts = dofile(WIDGETS_DIR .. "/widgets/parts.lua")
local fmtDuration, fmtSize, fire, fileExists, powerd = Parts.fmtDuration, Parts.fmtSize, Parts.fire, Parts.fileExists, Parts.powerd
local themedIcon, OptionSheet, WidgetSlot, WidgetCell = Parts.themedIcon, Parts.OptionSheet, Parts.WidgetSlot, Parts.WidgetCell

return function(Aire, ctx)
    -- Módulos que usa el mixin, declarados aquí dentro: así no cuentan como
    -- upvalues de esta función (LuaJIT admite 60). require devuelve el
    -- mismo módulo que arriba.
    local Blitbuffer = require("ffi/blitbuffer")
    local BookList = require("ui/widget/booklist")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local ImageWidget = require("ui/widget/imagewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local NetworkMgr = require("ui/network/manager")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local logger = require("logger")
    local util = require("util")
    local _ = require("gettext")
    local N_ = _.ngettext
    local T = require("ffi/util").template
    local C_ = _.pgettext
    local Screen = Device.screen
    local BLACK = Blitbuffer.COLOR_BLACK
    local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

    local S, face, config, saveConfig, tappable = ctx.S, ctx.face, ctx.config, ctx.saveConfig, ctx.tappable

    function Aire:showOptionSheet(title, rows_fn, buttons, on_close, columns)
        local sheet = OptionSheet:new{
            title = title, rows_fn = rows_fn, buttons = buttons, columns = columns,
            S = S, face = face, tappable = tappable, on_close = on_close,
        }
        UIManager:show(sheet, "ui")
        return sheet
    end

    ---------------------------------------------------------------------
    -- Caché de los widgets costosos (cache = true: estadísticas, serie,
    -- historial) y de sus portadas. Inicio se redibuja a menudo (wifi,
    -- cargador, luz…) sin que esos datos cambien. La caché se vacía:
    --   · al volver a Inicio desde otra pestaña (showHome),
    --   · tras una acción que cambia datos (refreshSoon con invalidate),
    --   · al cambiar de día, y al volver de un libro (FileManager nuevo).
    ---------------------------------------------------------------------
    function Aire:invalidateWidgetData()
        self._w_cache = nil
        if self.freeWidgetCovers then self:freeWidgetCovers() end
    end

    local function widgetData(self, w, opts)
        if not w.cache then return pcall(w.data, self, opts) end
        local day = os.date("%Y-%m-%d")
        local c = self._w_cache
        if not c or c._day ~= day then
            c = { _day = day }
            self._w_cache = c
        end
        local key = w.id .. "|" .. tostring(opts.period or "") .. (config.demo_stats and "|demo" or "")
        if c[key] == nil then
            local ok, d = pcall(w.data, self, opts)
            if not ok then return false, d end -- los errores no se guardan: se reintenta
            c[key] = d or false
        end
        return true, c[key] or nil
    end

    -- Refrescar Inicio. invalidate = true tras una acción que cambia los datos
    -- (estado de un libro…); sin él (wifi, luz, cargador) se reutiliza la caché.
    local function refreshSoon(self, delay, invalidate)
        UIManager:scheduleIn(delay or 0.5, function()
            if self:isHomeVisible() then
                if invalidate then self:invalidateWidgetData() end
                self:apply()
                UIManager:setDirty(self.ui, "ui")
            end
        end)
    end

    local function docProps(self, file)
        local props = {}
        if self.ui.bookinfo and file then
            local ok, p = pcall(self.ui.bookinfo.getDocProps, self.ui.bookinfo, file, nil, true)
            if ok and type(p) == "table" then props = p end
        end
        props.title = props.display_title or props.title or (file and file:match("([^/]+)$")) or "?"
        return props
    end

    local function openBook(self, file)
        if fileExists(file) then filemanagerutil.openFile(self.ui, file) end
    end

    -- Ficha del libro (booksheet.lua) o, si no está, la información del libro
    local function bookSheet(self, file)
        if not fileExists(file) then return end
        local show = require("apps/filemanager/filemanager").aire_showBookSheetFor
        if show then
            local ok = pcall(show, {
                owner = self, ui = self.ui, file = file,
                item = { path = file, is_file = true, text = file:match("([^/]+)$") },
                on_status = function() refreshSoon(self, 0, true) end,
                on_refresh = function() refreshSoon(self, 0, true) end,
                -- "Más opciones…": el menú completo de KOReader (el del explorador)
                more = function()
                    local fc = self.ui.file_chooser
                    if fc and fc._aire_orig_showFileDialog then
                        fc._aire_orig_showFileDialog(fc, { path = file, is_file = true, text = file:match("([^/]+)$") })
                    elseif self.ui.bookinfo then
                        self.ui.bookinfo:show(file)
                    end
                end,
            })
            if ok then return end
        end
        if self.ui.bookinfo then self.ui.bookinfo:show(file) end
    end

    -- Menú del libro (el mismo que al mantener un libro en la Librería)
    function Aire:showBookMenu(file) return bookSheet(self, file) end

    -- Siguiente libro de la serie del libro actual, buscando en la base de
    -- datos de CoverBrowser por nombre de serie (no depende de la Librería).
    local function nextInSeries(self)
        local last = G_reader_settings:readSetting("lastfile")
        if not fileExists(last) then return nil, _("No current book") end
        local props = docProps(self, last)
        local series, idx = props.series, tonumber(props.series_index)
        if not series or series == "" then return nil, _("The current book is not part of a series") end
        local ok_b, BIM = pcall(require, "bookinfomanager")
        if not ok_b or type(BIM) ~= "table" then return nil, _("No CoverBrowser data") end
        local found = {}
        local stmt
        local ok, err = pcall(function()
            BIM:openDbConnection()
            stmt = BIM.db_conn:prepare("SELECT directory, filename, series_index, title FROM bookinfo "
                .. "WHERE series = ? AND (ignore_meta IS NULL OR ignore_meta != 'Y')")
            stmt:bind(series)
            local row = stmt:step()
            while row do
                table.insert(found, { dir = row[1], name = row[2], index = tonumber(row[3]), title = row[4] })
                row = stmt:step()
            end
        end)
        -- Cerrar también si falla a medias: la conexión de CoverBrowser es compartida
        if stmt then pcall(stmt.close, stmt) end
        if not ok then
            logger.warn("Aire/Widgets: error buscando la serie:", err)
            return nil, _("Could not read database")
        end
        -- Quitar duplicados (/mnt/us y /mnt/base-us son la misma carpeta):
        -- se queda una ruta que exista, preferiblemente en la carpeta del libro actual
        local last_dir = last:match("^(.*/)") or ""
        local last_name = last:match("([^/]+)$")
        local by_name = {}
        for _i, f in ipairs(found) do
            local path = (f.dir or "") .. (f.name or "")
            if f.name ~= last_name and fileExists(path) then
                if not by_name[f.name] or f.dir == last_dir then
                    by_name[f.name] = { path = path, index = f.index, title = f.title }
                end
            end
        end
        local best
        local candidates = 0
        for _name, b in pairs(by_name) do
            candidates = candidates + 1
            if BookList.getBookStatus(b.path) ~= "complete" and (not idx or not b.index or b.index > idx) then
                if not best or (b.index or math.huge) < (best.index or math.huge) then best = b end
            end
        end
        -- Al log solo cuando cambia el resultado (Inicio se redibuja a menudo)
        local summary = series .. "#" .. tostring(idx) .. ">" .. (best and best.path or "ninguno")
        if summary ~= self._w_series_logged then
            self._w_series_logged = summary
            logger.dbg("Aire/Widgets: siguiente de la serie «" .. series .. "» #" .. tostring(idx) .. ":",
                candidates, "libros más en la serie; elegido:", best and best.path or "ninguno")
        end
        if not best then return nil, _("No next unfinished book") end
        best.series = series
        return best
    end

    -- Terminados por periodo ("month" / "year" / "all"), del más reciente al más antiguo
    local function finishedBooks(self, period)
        local books = self.getFinishedBooks and self:getFinishedBooks() or {}
        local now = os.date("*t")
        local list = {}
        for _i, b in ipairs(books) do
            local match = period == "all"
                or (tonumber(b.finished_year) == now.year
                    and (period == "year" or b.finished_month == now.month))
            if match then table.insert(list, b) end
        end
        table.sort(list, function(a, b) return (a.mtime or 0) > (b.mtime or 0) end)
        return list
    end
    local PERIOD_LABEL = { month = _("this month"), year = _("this year"), all = _("in total") }

    ---------------------------------------------------------------------
    -- Widgets. data(self, opts) -> tabla para dibujar; tap / hold (opcional).
    -- needs_large: solo en grande. options(opts, set) -> filas extra de opciones.
    -- Regla: tap = acción rápida; hold = abrir algo.
    ---------------------------------------------------------------------
    local W, ORDER = {}, {}
    local function def(id, t)
        t.id = id
        W[id] = t
        table.insert(ORDER, id)
    end

    -- 1) Hoy / racha
    def("today", {
        title = _("Today and streak"), icon = "aire.widget.flame",
        cache = true, -- abre statistics.sqlite3
        data = function(self)
            local st = self.getQuickStats and self:getQuickStats() or nil
            if not st then return { value = "—", label = _("today") } end
            return {
                value = fmtDuration(st.today_secs), label = _("today"),
                sub = T(N_("streak %1 day", "streak %1 days", st.streak), st.streak) .. " · " .. T(_("%1 pp."), st.today_pages),
                small_sub = T(_("streak %1"), st.streak),
            }
        end,
        tap = function(self) if self.showCalendarView then self:showCalendarView() end end,
    })

    -- 2) Siguiente de la serie
    def("next_series", {
        title = _("Next in series"), icon = "aire.widget.next",
        cache = true, -- consulta la base de datos de CoverBrowser y el estado de cada libro
        data = function(self)
            local best, why = nextInSeries(self)
            if not best then return { label = _("NEXT"), value = "—", sub = why, small_sub = _("Next") } end
            local n = best.index
            local num = n and ((n == math.floor(n)) and ("#%d"):format(n) or ("#" .. n)) or ""
            local props = docProps(self, best.path)
            return { label = _("NEXT"), file = best.path, title = props.title or best.title,
                     sub = num ~= "" and (num .. " · " .. best.series) or best.series, value = num,
                     small_sub = num ~= "" and T(_("Next %1"), num) or _("Next") }
        end,
        hold = function(self, d) bookSheet(self, d.file) end, -- tocar: nada
    })

    -- 3) Libro anterior
    def("previous", {
        title = _("Previous book"), icon = "aire.widget.previous",
        cache = true, -- historial y metadatos del libro
        data = function(self)
            local ok, RH = pcall(require, "readhistory")
            local last = G_reader_settings:readSetting("lastfile")
            last = last and (require("ffi/util").realpath(last) or last)
            local prev = ok and RH:getPreviousFile(last) or nil
            if not fileExists(prev) then
                return { label = _("PREVIOUS"), value = "—", sub = _("No previous book"), small_sub = _("Previous") }
            end
            local props = docProps(self, prev)
            return { label = _("PREVIOUS"), file = prev, title = props.title,
                     sub = props.authors and props.authors:gsub("\n", ", ") or nil, small_sub = _("Previous") }
        end,
        hold = function(self, d) bookSheet(self, d.file) end, -- tocar: nada
    })

    -- 4) Libro al azar (sin empezar; cambia cada vez que vuelves a Inicio)
    def("random", {
        title = _("Random book"), icon = "aire.widget.shuffle",
        data = function(self)
            local books = self.getLibraryBooks and self:getLibraryBooks() or {}
            local pool = {}
            for _i, b in ipairs(books) do
                if b.status == "new" and not b.fake then table.insert(pool, b) end
            end
            if #pool == 0 then return { label = _("RANDOM"), value = "—", sub = _("No unstarted books"), small_sub = _("Random") } end
            local pick
            for _i, b in ipairs(pool) do if b.path == self._w_random then pick = b end end
            if not pick then
                pick = pool[math.random(#pool)]
                self._w_random = pick.path
            end
            return { label = _("RANDOM"), file = pick.path, title = pick.title, sub = pick.author, small_sub = _("Random") }
        end,
        hold = function(self, d) bookSheet(self, d.file) end, -- tocar: nada
    })

    -- 5) Añadido recientemente
    def("recent", {
        title = _("Recently added"), icon = "aire.widget.new",
        data = function(self)
            local books = self.getLibraryBooks and self:getLibraryBooks() or {}
            local best
            for _i, b in ipairs(books) do
                if not b.fake and (not best or b.mtime > best.mtime) then best = b end
            end
            if not best then return { label = _("NEW"), value = "—", sub = _("Library is empty"), small_sub = _("New") } end
            return { label = _("ADDED"), file = best.path, title = best.title, sub = best.author, small_sub = _("New") }
        end,
        hold = function(self, d) bookSheet(self, d.file) end, -- tocar: nada
    })

    -- 6) Cita del día (subrayado al azar de los libros del historial)
    local function pickQuote(self)
        local ok, RH = pcall(require, "readhistory")
        if not ok then return nil end
        local found = {}
        for i, item in ipairs(RH.hist or {}) do
            if i > 60 then break end
            if not item.dim and item.file then
                local ok_ds, ds = pcall(BookList.getDocSettings, item.file)
                local ann = ok_ds and ds and ds:readSetting("annotations")
                if type(ann) == "table" then
                    for _j, a in ipairs(ann) do
                        if type(a.text) == "string" and #a.text > 20 and #a.text < 400 then
                            table.insert(found, { text = a.text, file = item.file })
                        end
                    end
                end
            end
        end
        if #found == 0 then return nil end
        local q = found[math.random(#found)]
        q.text = q.text:gsub("%s+", " ")
        q.title = docProps(self, q.file).title
        return q
    end
    def("quote", {
        title = _("Quote of the day"), icon = "aire.widget.quote", needs_large = true,
        data = function(self)
            if not self._w_quote then self._w_quote = pickQuote(self) or false end
            local q = self._w_quote
            if not q then return { label = _("QUOTE"), value = "—", sub = _("You don't have any highlights yet") } end
            return { quote = q.text, sub = q.title, file = q.file }
        end,
        tap = function(self) self._w_quote = nil; refreshSoon(self, 0) end, -- otra cita
        hold = function(self, d) openBook(self, d.file) end,
    })

    -- 7) Favoritos
    def("favorites", {
        title = _("Favorites"), icon = "aire.widget.heart",
        data = function()
            local ok, RC = pcall(require, "readcollection")
            local coll = ok and RC.coll and RC.coll[RC.default_collection_name] or {}
            local n, files = 0, {}
            for path, item in pairs(coll) do
                n = n + 1
                table.insert(files, { path = path, order = item.order or 0 })
            end
            table.sort(files, function(a, b) return a.order < b.order end)
            return { value = tostring(n), label = _("favorites"), sub = N_("book", "books", n), covers = files }
        end,
        tap = function(self)
            if self.showGridView then
                self:showGridView("collections")
                local ok, RC = pcall(require, "readcollection")
                if ok and self.openGridGroup then self:openGridGroup(RC.default_collection_name) end
            end
        end,
    })

    -- 8) Terminados (periodo configurable: mes / año / siempre)
    def("finished", {
        title = C_("aire", "Finished"), icon = "aire.widget.done",
        data = function(self, opts)
            local period = opts.period or "year"
            local list = finishedBooks(self, period)
            local n = #list
            local covers = {}
            for i = 1, math.min(2, n) do covers[i] = list[i] end
            return { value = tostring(n), label = N_("finished book", "finished books", n),
                     sub = PERIOD_LABEL[period], small_sub = PERIOD_LABEL[period], covers = covers }
        end,
        tap = function(self, d, opts)
            config.fin_filter = opts.period or "year"
            saveConfig()
            if self.showGridView then self:showGridView("finished") end
        end,
        hold = function(self, d, opts)
            local period = opts.period or "year"
            if self.showRecapView then
                self:showRecapView(period == "month" and "month" or "year")
            elseif self.showStatsView then
                self:showStatsView()
            end
        end,
        options = function(opts, set)
            local rows = {}
            for _i, p in ipairs({ { "month", _("This month") }, { "year", _("This year") }, { "all", _("Always") } }) do
                table.insert(rows, { text = T(_("Count: %1"), p[2]), radio = true,
                    checked = (opts.period or "year") == p[1], callback = function(sheet) set("period", p[1], sheet) end })
            end
            return rows
        end,
    })

    -- 9) Luz
    def("light", {
        title = _("Light"), icon = "aire.widget.sun",
        cond = function() return Device:hasFrontlight() end,
        data = function()
            local p = powerd()
            local on = p:isFrontlightOn()
            return { value = on and tostring(p:frontlightIntensity()) or _("Off"), label = _("light"),
                     sub = on and _("On") or _("Off") }
        end,
        tap = function(self) fire("ToggleFrontlight"); refreshSoon(self) end,
        hold = function() fire("ShowFlDialog") end,
    })

    -- 11) Wi-Fi
    def("wifi", {
        title = _("Wi-Fi"), icon = "aire.widget.wifi",
        cond = function() return Device:hasWifiToggle() end,
        data = function()
            local on = NetworkMgr:isWifiOn()
            local connected = on and NetworkMgr:isConnected()
            return { value = connected and _("Connected") or (on and _("On") or _("Off")), label = _("wi-fi") }
        end,
        tap = function(self) fire("ToggleWifi"); refreshSoon(self, 2) end,
        hold = function() fire("ShowNetworkInfo") end,
    })

    -- 12) Modo noche
    def("night", {
        title = _("Night mode"), icon = "aire.widget.contrast",
        data = function()
            local on = G_reader_settings:isTrue("night_mode")
            return { value = on and _("Enabled") or _("Disabled"), label = _("night mode") }
        end,
        tap = function(self) fire("ToggleNightMode"); refreshSoon(self) end,
    })

    -- 14) Refresco completo
    def("refresh", {
        title = _("Full refresh"), icon = "aire.widget.refresh",
        data = function() return { value = _("Refresh"), label = _("screen") } end,
        tap = function() UIManager:setDirty(nil, "full") end,
    })

    -- 15) Captura de pantalla
    def("screenshot", {
        title = _("Screenshot"), icon = "aire.widget.camera",
        data = function() return { value = _("Capture"), label = _("screen") } end,
        tap = function() fire("Screenshot") end,
    })

    -- 16) Batería
    def("battery", {
        title = _("Battery"), icon = "aire.widget.battery",
        cond = function() return Device:hasBattery() end,
        data = function()
            local p = powerd()
            return { value = p:getCapacity() .. "%", label = _("battery"),
                     sub = p:isCharging() and _("Charging") or (p:isCharged() and _("Charged") or nil) }
        end,
        tap = function() fire("ShowBatteryStatistics") end,
    })

    -- 17) Almacenamiento (util.diskUsage ya devuelve bytes)
    def("storage", {
        title = _("Storage"), icon = "aire.widget.storage",
        data = function()
            local ok, du = pcall(util.diskUsage, filemanagerutil.getHomeFolder())
            local avail = ok and du and tonumber(du.available)
            if not avail then return { value = "—", label = _("free") } end
            local total = tonumber(du.total)
            return { value = fmtSize(avail), label = _("free"),
                     sub = total and T(_("of %1"), fmtSize(total)) or nil }
        end,
    })

    -- 19) Buscar
    def("search", {
        title = _("Search"), icon = "aire.search",
        data = function() return { value = _("Search"), label = _("files") } end,
        tap = function() fire("ShowFileSearch") end,
        hold = function() fire("ShowSearchResults") end, -- últimos resultados
    })

    -- 20) Diccionario
    def("dict", {
        title = _("Dictionary"), icon = "aire.widget.dict",
        data = function() return { value = _("Dictionary"), label = _("search word") } end,
        tap = function() fire("ShowDictionaryLookup") end,
    })

    -- 21) Wikipedia
    def("wiki", {
        title = _("Wikipedia"), icon = "aire.widget.globe",
        data = function() return { value = _("Wikipedia"), label = _("search") } end,
        tap = function() fire("ShowWikipediaLookup") end,
    })

    -- 22) Marcadores y subrayados
    def("bookmarks", {
        title = _("Bookmarks and highlights"), icon = "aire.widget.highlight",
        data = function() return { title = _("Bookmarks"), sub = _("and highlights"), small_sub = _("and highlights") } end,
        tap = function() fire("ShowBookmarkBrowser") end,
    })

    -- 23) Carpetas favoritas
    def("folders", {
        title = _("Favorite folders"), icon = "aire.folder",
        data = function() return { title = _("Folders"), sub = _("shortcuts"), small_sub = _("shortcuts") } end,
        tap = function() fire("ShowFolderShortcutsDialog") end,
    })

    -- Plugin: temporizador de lectura (readtimer)
    def("readtimer", {
        title = _("Read timer"), icon = "aire.widget.timer",
        cond = function(self) return self.ui.readtimer ~= nil end,
        data = function(self)
            local rt = self.ui.readtimer
            if rt and rt:scheduled() then
                return { value = fmtDuration(rt:remaining()), label = _("timer"), sub = _("Tap to stop") }
            end
            return { value = _("Start"), label = _("timer"), sub = _("Hold to configure") }
        end,
        tap = function(self)
            local rt = self.ui.readtimer
            if not rt then return end
            if rt:scheduled() then
                rt:onStopTimer()
            elseif rt.settings and rt.settings.remain_time_hours and rt.settings.remain_time_minutes then
                rt:onStartTimer()
            else
                rt:onShowTimer() -- aún no hay duración guardada: preguntarla
            end
            refreshSoon(self, 1)
        end,
        hold = function(self)
            local rt = self.ui.readtimer
            if rt then rt:onShowTimer() end
        end,
    })

    -- Plugin: servidor SSH
    def("ssh", {
        title = _("SSH server"), icon = "aire.widget.terminal",
        cond = function(self) return self.ui.SSH ~= nil end,
        data = function(self)
            local ssh = self.ui.SSH
            local on = ssh and ssh:isRunning()
            return { value = on and _("Active") or _("Off"), label = _("SSH"),
                     sub = ssh and T(_("port %1"), ssh.SSH_port) or nil }
        end,
        tap = function(self)
            if self.ui.SSH then self.ui.SSH:onToggleSSHServer() end
            refreshSoon(self, 1.5)
        end,
        hold = function(self)
            -- Ajustes del SSH: las mismas opciones de su menú, en una hoja
            local ssh = self.ui.SSH
            if not ssh then return end
            local tmp = {}
            pcall(ssh.addToMainMenu, ssh, tmp)
            local items = tmp.ssh and tmp.ssh.sub_item_table or {}
            local function textOf(it)
                if it.text_func then
                    local ok, t = pcall(it.text_func)
                    if ok and t then return t end
                end
                return it.text or "?"
            end
            self:showOptionSheet(_("SSH server"), function()
                local rows = {}
                for _i, it in ipairs(items) do
                    local checked
                    if it.checked_func then
                        local ok, c = pcall(it.checked_func)
                        checked = (ok and c) and true or false
                    end
                    local enabled = true
                    if it.enabled_func then
                        local ok, en = pcall(it.enabled_func)
                        enabled = (ok and en) and true or false
                    end
                    local cb = it.callback
                    table.insert(rows, {
                        text = textOf(it), checked = checked, enabled = enabled,
                        callback = cb and function(sheet)
                            -- "touchmenu_instance" falso: updateItems redibuja la hoja
                            local rebuilt = false
                            pcall(cb, {
                                updateItems = function() rebuilt = true; sheet:rebuild() end,
                                closeMenu = function() end,
                            })
                            if checked ~= nil and not rebuilt then
                                UIManager:scheduleIn(0.2, function()
                                    if not sheet._closed then sheet:rebuild() end
                                end)
                            end
                        end or nil,
                    })
                end
                return rows
            end, { { text = _("Close"), primary = true, callback = function(sheet) sheet:close() end } },
            function() refreshSoon(self, 0) end)
        end,
    })

    ---------------------------------------------------------------------
    -- Dibujo
    ---------------------------------------------------------------------
    local function coverThumb(self, path, max_w, max_h, bg)
        local bb = self.getWidgetCover and self:getWidgetCover(path)
        if not bb then return nil end
        local rounded = config.rounded_covers == true
        local border = Size.border.thin
        return FrameContainer:new{
            bordersize = border, color = Blitbuffer.COLOR_GRAY, padding = 0, margin = 0,
            radius = rounded and S(6) or 0, _aire_clip_corners = rounded,
            _aire_clip_bg = bg,
            ImageWidget:new{
                image = bb, image_disposable = false,
                scale_factor = math.min((max_w - 2 * border) / bb:getWidth(), (max_h - 2 * border) / bb:getHeight()),
            },
        }
    end

    local function buildContent(self, w, size, d, cw, ch, theme)
        local pad = S(10)
        local iw, ih = cw - 2 * pad, ch - 2 * pad
        -- Pequeño con libro: portada + etiqueta corta debajo
        if size == "S" and d.file then
            local lbl = TextWidget:new{ text = d.small_sub or d.label or "", face = face(false, 11),
                fgcolor = theme.fg2, max_width = iw, padding = 0 }
            local img_h = math.max(1, ih - lbl:getSize().h - S(4))
            local cover = coverThumb(self, d.file, iw, img_h, theme.bg) or TextBoxWidget:new{
                text = d.title or "?", face = face(true, 12), width = iw, alignment = "center",
                fgcolor = theme.fg, bgcolor = theme.bg,
                height = img_h, height_adjust = true, height_overflow_show_ellipsis = true,
            }
            return CenterContainer:new{
                dimen = Geom:new{ w = cw, h = ch },
                VerticalGroup:new{ align = "center", cover, VerticalSpan:new{ width = S(4) }, lbl },
            }
        end
        -- Pequeño: icono, valor y etiqueta
        if size == "S" then
            local vg = VerticalGroup:new{ align = "center" }
            table.insert(vg, themedIcon(theme, w.icon, S(24)))
            table.insert(vg, VerticalSpan:new{ width = S(4) })
            local main_s = d.value or d.title
            if main_s then
                table.insert(vg, TextWidget:new{ text = main_s, face = face(true, 14), fgcolor = theme.fg, max_width = iw, padding = 0 })
            end
            local lbl = d.small_sub or d.label
            if lbl then
                table.insert(vg, TextWidget:new{ text = lbl, face = face(false, 11), fgcolor = theme.fg2, max_width = iw, padding = 0 })
            end
            return CenterContainer:new{ dimen = Geom:new{ w = cw, h = ch }, vg }
        end
        -- Grande con cita
        if d.quote then
            local src = TextWidget:new{ text = "— " .. (d.sub or ""), face = face(false, 11), fgcolor = theme.fg2, max_width = iw, padding = 0 }
            local box = TextBoxWidget:new{
                text = "«" .. d.quote .. "»", face = Font:getFace("cfont", 13), width = iw,
                fgcolor = theme.fg, bgcolor = theme.bg,
                height = ih - src:getSize().h - S(4), height_overflow_show_ellipsis = true,
            }
            return CenterContainer:new{
                dimen = Geom:new{ w = cw, h = ch },
                VerticalGroup:new{ align = "left", box, VerticalSpan:new{ width = S(4) }, src },
            }
        end
        -- Grande: portada (libros) o icono, y textos a la derecha
        local left
        if d.file then left = coverThumb(self, d.file, math.floor(ih * 0.7), ih, theme.bg) end
        if not left and d.covers and #d.covers > 0 then
            local hg = HorizontalGroup:new{ align = "center" }
            for i = 1, math.min(3, #d.covers) do
                local th = coverThumb(self, d.covers[i].path, math.floor(ih * 0.5), math.floor(ih * 0.8), theme.bg)
                if th then
                    if #hg > 0 then table.insert(hg, HorizontalSpan:new{ width = S(4) }) end
                    table.insert(hg, th)
                end
            end
            if #hg > 0 then left = hg end
        end
        if not left then left = themedIcon(theme, w.icon, S(30)) end
        local tw = iw - left:getSize().w - S(10)
        local col = VerticalGroup:new{ align = "left" }
        if d.label then
            table.insert(col, TextWidget:new{ text = d.label:upper(), face = face(true, 10), fgcolor = theme.fg2, max_width = tw, padding = 0 })
            table.insert(col, VerticalSpan:new{ width = S(2) })
        end
        local main_text = d.title or d.value
        if main_text then
            table.insert(col, TextWidget:new{ text = main_text, face = face(true, d.title and 14 or 17), fgcolor = theme.fg, max_width = tw, padding = 0 })
        end
        if d.sub then
            table.insert(col, VerticalSpan:new{ width = S(2) })
            table.insert(col, TextWidget:new{ text = d.sub, face = face(false, 12), fgcolor = theme.fg2, max_width = tw, padding = 0 })
        end
        return LeftContainer:new{
            dimen = Geom:new{ w = cw, h = ch },
            HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad }, left, HorizontalSpan:new{ width = S(10) }, col },
        }
    end

    -- Acciones efectivas según las opciones (Mantener = tocar / Intercambiar)
    local function actionsFor(w, opts)
        local tap, hold = w.tap, w.hold
        if opts.hold_tap and not w.hold then hold = w.tap end
        if opts.swap and not opts.hold_tap then tap, hold = hold, tap end
        return tap, hold
    end

    function Aire:buildWidgetCell(opts, size, width, height, key)
        local w = W[opts.id]
        local ok, d = widgetData(self, w, opts)
        if not ok then
            logger.warn("Aire/Widgets: error en", opts.id, d)
            d = { value = "—", label = w.title }
        end
        -- Pruebas: datos inventados (devtools.lua, "Widgets de prueba")
        if self._demo_widget_data then
            local ok_f, fd = pcall(self._demo_widget_data, opts.id)
            if ok_f and fd then d = fd end
        end
        d = d or {}
        local theme = opts.invert and THEME_INVERTED or THEME_NORMAL
        local border = Size.border.thin
        local cw, ch = width - 2 * border, height - 2 * border
        local ok_c, content = pcall(buildContent, self, w, size, d, cw, ch, theme)
        if not ok_c then
            logger.warn("Aire/Widgets: error dibujando", opts.id, content)
            content = CenterContainer:new{ dimen = Geom:new{ w = cw, h = ch },
                TextWidget:new{ text = w.title, face = face(false, 12), fgcolor = theme.fg2, padding = 0 } }
        end
        local tap, hold = actionsFor(w, opts)
        local function run(fn, what)
            if not fn then return end
            local ok_t, err = pcall(fn, self, d, opts)
            if not ok_t then logger.warn("Aire/Widgets: error al", what, opts.id, err) end
        end
        local cell = WidgetCell:new{
            width = width, height = height,
            on_tap = function()
                if self._widgets_edit then return self:showWidgetOptions(key) end
                run(tap, "tocar")
            end,
            on_hold = function()
                if self._widgets_edit then return self:showWidgetOptions(key) end
                run(hold, "mantener")
            end,
        }
        cell[1] = FrameContainer:new{
            bordersize = border, color = theme.border, background = theme.bg,
            radius = S(12), padding = 0, margin = 0, width = width, height = height,
            content,
        }
        return cell
    end

    ---------------------------------------------------------------------
    -- Zona de widgets
    ---------------------------------------------------------------------
    -- Presets: combinaciones listas para Inicio (Aire → Inicio y widgets →
    -- Presets de widgets). "reader" se pone solo en la primera instalación.
    -- Claves "fila:columna" (4 columnas, hasta 3 filas: las que no quepan no se
    -- ven); los widgets que el dispositivo no tiene (luz, wifi…) se saltan solos.
    local L2 = function(id, extra)
        local t = { id = id, span = 2 }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    local S1 = function(id) return { id = id, span = 1 } end
    local PRESETS = {
        { id = "reader", name = _("Reader"), widgets = {
            ["1:1"] = L2("next_series"), ["1:3"] = S1("light"), ["1:4"] = S1("search"),
            ["2:1"] = S1("wifi"),        ["2:2"] = S1("ssh"),   ["2:3"] = L2("finished", { period = "year" }),
        } },
        { id = "progress", name = _("Progress"), widgets = {
            ["1:1"] = L2("today"),       ["1:3"] = L2("finished", { period = "month" }),
            ["2:1"] = L2("next_series"), ["2:3"] = L2("previous"),
            ["3:1"] = L2("quote"),       ["3:3"] = L2("random"),
        } },
        { id = "quick", name = C_("aire", "Quick actions"), widgets = {
            ["1:1"] = S1("light"),   ["1:2"] = S1("wifi"),    ["1:3"] = S1("night"),     ["1:4"] = S1("refresh"),
            ["2:1"] = S1("search"),  ["2:2"] = S1("dict"),    ["2:3"] = S1("wiki"),      ["2:4"] = S1("folders"),
            ["3:1"] = S1("battery"), ["3:2"] = S1("storage"), ["3:3"] = S1("bookmarks"), ["3:4"] = S1("screenshot"),
        } },
        { id = "minimal", name = C_("aire", "Minimal"), widgets = {
            ["1:1"] = L2("next_series"), ["1:3"] = S1("today"), ["1:4"] = S1("light"),
        } },
        { id = "empty", name = C_("aire", "Empty"), widgets = {} },
    }
    local DEFAULT_PRESET = "reader"

    local function presetWidgets(id)
        for _i, p in ipairs(PRESETS) do
            if p.id == id then
                local copy = {}
                for key, v in pairs(p.widgets) do
                    local w = {}
                    for k, x in pairs(v) do w[k] = x end
                    copy[key] = w
                end
                return copy
            end
        end
    end

    local function placed()
        if config.home_widgets == nil then
            -- Primera instalación: preset por defecto (se guarda para que no cambie)
            config.home_widgets = presetWidgets(DEFAULT_PRESET) or {}
            saveConfig()
        elseif type(config.home_widgets) ~= "table" then
            config.home_widgets = {}
        end
        return config.home_widgets
    end

    -- Para el menú (menu.lua): { id, name } de cada preset, en orden
    function Aire:getWidgetPresets()
        local list = {}
        for _i, p in ipairs(PRESETS) do table.insert(list, { id = p.id, name = p.name }) end
        return list
    end

    -- Sustituye los widgets de Inicio por los del preset
    function Aire:applyWidgetPreset(id)
        local w = presetWidgets(id)
        if not w then return false end
        config.home_widgets = w
        self._widgets_edit = nil
        if self.invalidateWidgetData then self:invalidateWidgetData() end
        saveConfig()
        if self.isOwnView and self:isOwnView() then
            self.view = "home"
            self:apply()
            UIManager:setDirty(self.ui, "ui")
        end
        return true
    end

    local function available(self, w)
        if w.cond and not w.cond(self) then return false end
        return true
    end

    -- Widgets disponibles en este dispositivo, en el orden del selector
    -- (lo usan los tests automáticos de dev/ para comprobar que salen todos)
    function Aire:getWidgetDefs()
        local list = {}
        for _i, id in ipairs(ORDER) do
            local w = W[id]
            if w and available(self, w) then
                table.insert(list, { id = id, title = w.title, icon = w.icon, needs_large = w.needs_large and true or false,
                    has_tap = w.tap ~= nil, has_hold = w.hold ~= nil, has_options = w.options ~= nil })
            end
        end
        return list
    end

    ---------------------------------------------------------------------
    -- Pruebas (galería de widgets, devtools.lua): cada widget en grande, en
    -- pequeño y en pequeño invertido, con datos inventados. Los toques no
    -- hacen nada (la galería no debe encender la wifi, la luz…).
    -- Devuelve las páginas como funciones que montan cada una.
    ---------------------------------------------------------------------
    function Aire:widgetGalleryPages()
        local ids = {}
        for _i, id in ipairs(ORDER) do
            if W[id] and available(self, W[id]) then table.insert(ids, id) end
        end
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local side = S(ctx.SIDE_PAD)
        local w = sw - 2 * side
        local gap = S(ctx.WIDGET_GAP or 14)
        local col_w = math.floor((w - (COLS - 1) * gap) / COLS)
        local large_w = 2 * col_w + gap
        local cell_h = S(112)
        local label_h = S(22)
        local head_h = S(70)
        local per_page = math.max(1, math.floor((sh - head_h - S(20)) / (label_h + cell_h + gap)))
        local pages = {}
        local n_pages = math.ceil(#ids / per_page)
        for pi = 1, n_pages do
            local from = (pi - 1) * per_page + 1
            local to = math.min(#ids, from + per_page - 1)
            table.insert(pages, {
                T(_("Widgets %1–%2"), from, to),
                function(covers_out)
                    local TEST = self.getTestTools and self:getTestTools()
                    local books = {}
                    for _i, b in ipairs(self.getLibraryBooks and self:getLibraryBooks() or {}) do
                        if not b.fake and #books < 6 then table.insert(books, b.path) end
                    end
                    -- Portadas de esta página: propias (no las libera Inicio al redibujarse)
                    local saved_covers = self._widget_covers
                    self._widget_covers = {}
                    self._demo_widget_data = (TEST and TEST.fakeWidgetData)
                        and function(id) return TEST.fakeWidgetData(id, books) end or nil
                    local content = VerticalGroup:new{ align = "left" }
                    table.insert(content, VerticalSpan:new{ width = S(16) })
                    table.insert(content, TextWidget:new{
                        text = T(_("Widget gallery · %1 / %2"), pi, n_pages),
                        face = face(true, 17), fgcolor = BLACK, padding = 0 })
                    table.insert(content, TextWidget:new{
                        text = _("Large · small · small inverted — swipe ← →, tap to exit"),
                        face = face(false, 12), fgcolor = GRAY_TEXT, max_width = w, padding = 0 })
                    table.insert(content, VerticalSpan:new{ width = S(14) })
                    local function cell(opts, size, width)
                        local c = self:buildWidgetCell(opts, size, width, cell_h, "gallery")
                        c.on_tap, c.on_hold = nil, nil
                        return c
                    end
                    for i = from, to do
                        local id = ids[i]
                        local wd = W[id]
                        table.insert(content, TextWidget:new{
                            text = ("%d · %s"):format(i, wd.title or id), face = face(true, 12),
                            fgcolor = GRAY_TEXT, max_width = w, padding = 0 })
                        table.insert(content, VerticalSpan:new{ width = S(4) })
                        local row = HorizontalGroup:new{ align = "top" }
                        table.insert(row, cell({ id = id, span = 2 }, "L", large_w))
                        table.insert(row, HorizontalSpan:new{ width = gap })
                        if wd.needs_large then
                            table.insert(row, cell({ id = id, span = 2, invert = true }, "L", large_w))
                        else
                            table.insert(row, cell({ id = id, span = 1 }, "S", col_w))
                            table.insert(row, HorizontalSpan:new{ width = gap })
                            table.insert(row, cell({ id = id, span = 1, invert = true }, "S", col_w))
                        end
                        table.insert(content, row)
                        table.insert(content, VerticalSpan:new{ width = gap })
                    end
                    self._demo_widget_data = nil
                    for _i, bb in ipairs(self._widget_covers) do table.insert(covers_out, bb) end
                    self._widget_covers = saved_covers
                    return HorizontalGroup:new{ HorizontalSpan:new{ width = side }, content }
                end,
            })
        end
        return pages
    end

    function Aire:buildWidgetArea(w, avail_h)
        -- (Las portadas no se liberan aquí: se reutilizan entre redibujos; ver
        -- invalidateWidgetData)
        local editing = self._widgets_edit
        local area = VerticalGroup:new{ align = "left" }
        if editing then
            local bar_h = S(30)
            local done = TextWidget:new{ text = _("Done"), face = face(true, 14), fgcolor = BLACK, padding = 0 }
            table.insert(area, OverlapGroup:new{
                dimen = Geom:new{ w = w, h = bar_h },
                LeftContainer:new{ dimen = Geom:new{ w = w, h = bar_h },
                    TextWidget:new{ text = _("EDITING WIDGETS"), face = face(true, 12), fgcolor = GRAY_TEXT, padding = 0 } },
                RightContainer:new{ dimen = Geom:new{ w = w, h = bar_h },
                    tappable(done, function() self:setWidgetsEdit(false) end, nil, { h = S(14), v = S(10) }) },
            })
            table.insert(area, VerticalSpan:new{ width = S(8) })
            avail_h = avail_h - bar_h - S(8)
        end
        local gap = S(ctx.WIDGET_GAP or 14)
        local col_w = math.floor((w - (COLS - 1) * gap) / COLS)
        local rem_w = w - (COLS - 1) * gap - COLS * col_w
        local function colWidth(col) return col_w + (col <= rem_w and 1 or 0) end
        local rows = math.min(MAX_ROWS, math.floor((avail_h + gap) / (S(MIN_CELL_H) + gap)))
        if rows < 1 then return nil end
        local cell_h = math.min(S(MAX_CELL_H), math.floor((avail_h - (rows - 1) * gap) / rows))

        local P = placed()
        -- Pruebas: rellenar las celdas libres con widgets (por tandas) y datos inventados
        self._demo_widget_data = nil
        local TEST = self.getTestTools and self:getTestTools()
        if config.demo_widgets and TEST and TEST.fakeWidgetData then
            local books = {}
            for _i, b in ipairs(self.getLibraryBooks and self:getLibraryBooks() or {}) do
                if not b.fake and #books < 6 then table.insert(books, b.path) end
            end
            self._demo_widget_data = function(id) return TEST.fakeWidgetData(id, books) end
            local ids = {}
            for _i, id in ipairs(ORDER) do
                if available(self, W[id]) then table.insert(ids, id) end
            end
            local n = #ids
            local next_i = ((config.demo_widgets_offset or 0) % math.max(1, n)) + 1
            local demo = {}
            for k, v in pairs(P) do demo[k] = v end
            for r = 1, rows do
                local c = 1
                while c <= COLS do
                    local key = r .. ":" .. c
                    local existing = demo[key]
                    if existing and W[existing.id] then
                        c = c + (((existing.span == 2 or W[existing.id].needs_large) and c < COLS) and 2 or 1)
                    else
                        local id = ids[next_i]
                        next_i = next_i % n + 1
                        local wd = W[id]
                        local free_right = c < COLS and not demo[r .. ":" .. (c + 1)]
                        if wd.needs_large and not free_right then
                            id = ids[next_i]; next_i = next_i % n + 1; wd = W[id]
                        end
                        -- alternar: en las filas pares, widgets grandes si caben
                        local span = (wd.needs_large or (r % 2 == 1 and free_right and c % 2 == 1)) and free_right and 2 or 1
                        demo[key] = { id = id, span = span }
                        c = c + span
                    end
                end
            end
            P = demo
        end
        for r = 1, rows do
            if r > 1 then table.insert(area, VerticalSpan:new{ width = gap }) end
            local row = HorizontalGroup:new{ align = "top" }
            local c = 1
            while c <= COLS do
                if c > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                local key = r .. ":" .. c
                local opts = P[key]
                local wdef = opts and W[opts.id]
                if wdef and available(self, wdef) then
                    local span = ((opts.span == 2 or wdef.needs_large) and c < COLS) and 2 or 1
                    local width = span == 2 and (colWidth(c) + colWidth(c + 1) + gap) or colWidth(c)
                    table.insert(row, self:buildWidgetCell(opts, span == 2 and "L" or "S", width, cell_h, key))
                    c = c + span
                else
                    local cw = colWidth(c)
                    if editing then
                        local k = key
                        table.insert(row, WidgetSlot:new{ width = cw, height = cell_h,
                            on_tap = function() self:showWidgetPicker(k) end })
                    else
                        table.insert(row, HorizontalSpan:new{ width = cw }) -- invisible
                    end
                    c = c + 1
                end
            end
            table.insert(area, row)
        end
        return area
    end

    ---------------------------------------------------------------------
    -- Edición: elegir, opciones, cambiar, quitar
    ---------------------------------------------------------------------
    local function redraw(self)
        saveConfig()
        self:apply()
        UIManager:setDirty(self.ui, "ui")
    end

    -- ¿Está libre la celda de la derecha de key?
    local function rightFree(key)
        local r, c = key:match("^(%d+):(%d+)$")
        r, c = tonumber(r), tonumber(c)
        if not r or c >= COLS then return false end
        local right = placed()[r .. ":" .. (c + 1)]
        return not (right and W[right.id])
    end

    -- Elegir widget: hoja en dos columnas con icono; al tocar uno se coloca
    -- directamente (sus opciones, tocándolo en edición)
    function Aire:showWidgetPicker(key)
        local can_large = rightFree(key)
        self:showOptionSheet(_("Add widget"), function()
            local rows = {}
            for _i, id in ipairs(ORDER) do
                local w = W[id]
                if available(self, w) and (not w.needs_large or can_large) then
                    table.insert(rows, {
                        text = w.title, icon = w.icon,
                        callback = function(sheet)
                            placed()[key] = { id = id, span = w.needs_large and 2 or 1 }
                            sheet:close()
                            redraw(self)
                        end,
                    })
                end
            end
            return rows
        end, { { text = _("Cancel"), callback = function(sheet) sheet:close() end } }, nil, 2)
    end

    function Aire:showWidgetOptions(key)
        local opts = placed()[key]
        if not opts or not W[opts.id] then return end
        local w = W[opts.id]
        local function set(field, value, sheet)
            opts[field] = value
            redraw(self)
            if sheet then sheet:rebuild() end
        end
        self:showOptionSheet(w.title, function()
            local rows = {}
            local is_large = opts.span == 2 or w.needs_large
            table.insert(rows, {
                text = _("Large (also occupies the right cell)"),
                checked = is_large and true or false,
                enabled = (not w.needs_large) and (is_large or rightFree(key)),
                callback = function(sheet) set("span", is_large and 1 or 2, sheet) end,
            })
            table.insert(rows, {
                text = _("Inverted colors"), checked = opts.invert and true or false,
                callback = function(sheet) set("invert", (not opts.invert) or nil, sheet) end,
            })
            if w.tap and not w.hold then
                table.insert(rows, {
                    text = _("Hold does the same as tap"), checked = opts.hold_tap and true or false,
                    callback = function(sheet)
                        opts.swap = nil -- no se puede con "Intercambiar"
                        set("hold_tap", (not opts.hold_tap) or nil, sheet)
                    end,
                })
            end
            if w.tap or w.hold then
                table.insert(rows, {
                    text = _("Swap tap and hold"), checked = opts.swap and true or false,
                    enabled = not opts.hold_tap,
                    callback = function(sheet) set("swap", (not opts.swap) or nil, sheet) end,
                })
            end
            if w.options then
                for _i, r in ipairs(w.options(opts, set)) do table.insert(rows, r) end
            end
            return rows
        end, {
            { text = _("Change"), callback = function(sheet) sheet:close(); self:showWidgetPicker(key) end },
            { text = C_("aire", "Remove"), callback = function(sheet)
                sheet:close()
                placed()[key] = nil
                redraw(self)
            end },
            { text = _("Done"), primary = true, callback = function(sheet) sheet:close() end },
        })
    end

    -- Entrar / salir del modo edición (se abre en Inicio)
    function Aire:setWidgetsEdit(on)
        self._widgets_edit = on and true or nil
        if self:isHomeVisible() then
            self:apply()
            UIManager:setDirty(self.ui, "ui")
        else
            self:showHome()
        end
    end

    -- La luz cambió (gesto, botón, diálogo): actualizar los widgets
    function Aire:refreshWidgets()
        if self:isHomeVisible() then refreshSoon(self, 0.3) end
    end
end
