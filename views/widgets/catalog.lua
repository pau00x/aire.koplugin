--[[
    aire.koplugin/views/widgets/catalog.lua
    Catálogo de definiciones de widgets de Inicio (W y ORDER) y sus helpers
    de datos exclusivos (nextInSeries, finishedBooks, pickQuote).

    Lo carga views/widgets/init.lua pasando las dependencias compartidas.
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

local BookList = require("ui/widget/booklist")
local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local C_ = _.pgettext

return function(deps)
    local config = deps.config
    local saveConfig = deps.saveConfig
    local Parts = deps.Parts
    local fmtDuration, fmtSize, fire, fileExists, powerd =
        Parts.fmtDuration, Parts.fmtSize, Parts.fire, Parts.fileExists, Parts.powerd
    local refreshSoon = deps.refreshSoon
    local docProps = deps.docProps
    local openBook = deps.openBook
    local bookSheet = deps.bookSheet

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

    -- Cita del día (subrayado al azar de los libros del historial)
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

    -- 6) Cita del día
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

    -- 8) Libros terminados (periodo configurable: mes / año / siempre)
    def("finished", {
        title = _("Finished books"), icon = "aire.widget.done",
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
                self:showRecapView(period == "month" and "month" or (period == "all" and "all" or "year"))
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

    -- 8b) Libros empezados (como Libros terminados, sin configuración de periodo)
    def("started", {
        title = _("Started books"), icon = "aire.book.opened",
        data = function(self)
            local list = self.getInProgressBooks and self:getInProgressBooks() or {}
            local n = #list
            local covers = {}
            for i = 1, math.min(2, n) do covers[i] = list[i] end
            return { value = tostring(n), label = N_("started book", "started books", n), covers = covers }
        end,
        tap = function(self)
            if self.showInProgressView then self:showInProgressView()
            elseif self.showStatsView then self:showStatsView() end
        end,
        hold = function(self)
            if self.showStatsView then self:showStatsView() end
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

    return { W = W, ORDER = ORDER }
end
