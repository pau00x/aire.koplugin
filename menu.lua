--[[
    aire.koplugin/menu.lua
    Menú del plugin (primera pestaña del explorador) y limpieza de los
    menús de KOReader (opciones que no sirven con Aire, orden de las entradas).
    Se carga desde main.lua como "mixin" (añade métodos a Aire).
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

return function(Aire, ctx)
    -- Módulos y valores compartidos declarados aquí dentro: así no cuentan
    -- como upvalues de esta función (LuaJIT admite 60).
    local Device = require("device")
    local FileChooser = require("ui/widget/filechooser")
    local FileManager = require("apps/filemanager/filemanager")
    local UIManager = require("ui/uimanager")
    local logger = require("logger")
    local _ = require("gettext")
    local T = require("ffi/util").template
    local Screen = Device.screen
    local S = ctx.S
    local config = ctx.config
    local saveConfig = ctx.saveConfig
    local SIDE_PAD = ctx.SIDE_PAD
    local PLUGIN_DIR = ctx.PLUGIN_DIR
    local STATUS_ORDER = ctx.STATUS_ORDER
    local STATUS_LABELS = ctx.STATUS_LABELS

    -- Opciones de menú que no sirven con la Pantalla de inicio activa (se quitan
    -- del menú del explorador). Registro en dev/notas/opciones-quitadas.md.
    local OBSOLETE_MENU_KEYS = {
        "start_with",          -- "Iniciar con…": siempre se abre Inicio / Librería
        "filemanager_display_mode", -- "Modo de visualización": el plugin usa siempre su propio diseño
        -- (show_filter, sort_by, reverse_sorting y sort_mixed NO se quitan aquí: el
        -- envoltorio de MenuSorter.sort las mueve a Aire → Explorador. Si se
        -- borraran antes, ese traslado no las encontraría y desaparecerían.)
        "history",             -- "Historial": pestaña Historial del dock
        "favorites",           -- "Favoritos": pestaña Colecciones del dock
        "collections",         -- "Colecciones": pestaña Colecciones del dock
        "exit_menu",           -- "Salir": ya está en PowerSheet
        "exit",                -- "Salir" (huérfano si exit_menu no está)
        "restart_koreader",    -- "Reiniciar KOReader"
        "sleep",               -- "Entrar en reposo"
        "reboot",              -- "Reiniciar dispositivo"
        "poweroff",            -- "Apagar"
        "open_last_document",  -- "Abrir el último documento": tarjeta "Leyendo ahora"
        "quickstart_guide",    -- Ayuda → "Guía de inicio rápido": explica la interfaz clásica
    }
    local OBSOLETE_MENU_TEXTS = {
        _("Show progress in mosaic mode"), -- CoverBrowser: el plugin oculta esa barra en el mosaico
        _("Show parent folder"),            -- Explorador: siempre se usa la flecha en cabecera
        _("Show all files from subfolders"), -- Explorador: rompe el modo carpeta (Aire tiene Librería)
        _("Show filename in Open last/previous menu items"), -- "Abrir el último documento" ya no está
        _("Show collection mark"),          -- Explorador → Configuración: va en Librería y portadas
    }

    local function removeObsoleteMenuItems(menu_items)
        for _i, key in ipairs(OBSOLETE_MENU_KEYS) do menu_items[key] = nil end
        local wanted = {}
        for _i, t in ipairs(OBSOLETE_MENU_TEXTS) do wanted[t] = true end
        local function prune(list, depth)
            if type(list) ~= "table" or depth > 6 then return end
            for i = #list, 1, -1 do
                local it = list[i]
                if type(it) == "table" then
                    if it.text and wanted[it.text] then
                        table.remove(list, i)
                    elseif it.sub_item_table then
                        prune(it.sub_item_table, depth + 1)
                    end
                end
            end
        end
        for _key, item in pairs(menu_items) do
            if type(item) == "table" and item.sub_item_table then prune(item.sub_item_table, 1) end
        end
    end

    -- Galerías de prueba (devtools.lua): las cuatro, con datos falsos. "owner" es
    -- la Pantalla de inicio. Van en Avanzado → Pruebas.
    local function galleryMenu(owner)
        local function run(fn_name)
            return function()
                local TEST = Aire.getTestTools and Aire.getTestTools(Aire)
                local fn = TEST and TEST[fn_name]
                if fn then UIManager:nextTick(function() fn(owner) end) end
            end
        end
        return {
            text = _("Test galleries"),
            help_text = _("Everything drawn by the plugin, with mock data. Swipe ← → to turn pages; tap outside or on the page to exit."),
            sub_item_table = {
                { text = _("Home widgets"), callback = run("showWidgetGallery") },
                { text = _("Floating windows"), callback = run("showFloatingGallery") },
                { text = _("Bottom menus (sheets)"), callback = run("showSheetGallery") },
                { text = _("Full screens"), callback = run("showFullscreenGallery") },
            },
        }
    end
    -- Entradas del plugin en la primera pestaña del explorador, en este orden
    local MENU_IDS = { "aire_home", "aire_topbar", "aire_library", "aire_explorer", "aire_dock", "aire_advanced" }

    -- Menú ☰ del lector: opciones que open/abren las listas de KOReader (el plugin
    -- tiene las suyas en el dock) o que están repetidas (Salir: botón de
    -- encendido del pie del menú). Elegidas por el usuario (2026-11-16).
    -- En el lector este plugin no registra su menú, así que se quitan justo antes
    -- de que KOReader ordene el menú (sin la clave, MenuSorter las omite).
    local READER_REMOVED_MENU_KEYS = {
        "history",                -- Historial
        "open_previous_document", -- Abrir documento anterior
        "favorites",              -- Favoritos
        "collections",            -- Colecciones
        "exit_menu",              -- Salir / Reiniciar / Suspender
        "exit",                   -- Salir
        "restart_koreader",       -- Reiniciar KOReader
        "sleep",                  -- Entrar en reposo
        "reboot",                 -- Reiniciar dispositivo
        "poweroff",               -- Apagar
    }
    do
        local MenuSorter = require("ui/menusorter")
        if not MenuSorter._aire_reader_prune then
            MenuSorter._aire_reader_prune = true
            local orig_mergeAndSort = MenuSorter.mergeAndSort
            MenuSorter.mergeAndSort = function(ms, config_prefix, item_table, order)
                if config_prefix == "reader" and config.enabled and type(item_table) == "table" then
                    for _i, key in ipairs(READER_REMOVED_MENU_KEYS) do item_table[key] = nil end
                end
                return orig_mergeAndSort(ms, config_prefix, item_table, order)
            end
            -- Poner nuestras entradas al principio de su pestaña con el orden ya
            -- mezclado (MenuSorter aplica antes settings/*_menu_order.lua del
            -- usuario, que sustituye listas enteras: añadirlas al orden de serie
            -- no bastaba y salían como huérfanas con "NUEVO: ").
            local function ensureFront(order, key, ids, with_sep)
                local list = order[key]
                if type(list) ~= "table" then return end
                local mine = {}
                for _i, id in ipairs(ids) do mine[id] = true end
                local new = {}
                for _i, id in ipairs(ids) do table.insert(new, id) end
                if with_sep then table.insert(new, "----------------------------") end
                local skip_sep = with_sep
                for _i, id in ipairs(list) do
                    if not mine[id] and id ~= "aire" then
                        -- sin dos separadores seguidos justo después de lo nuestro
                        if not (skip_sep and id == "----------------------------") then
                            table.insert(new, id)
                            skip_sep = false
                        end
                    end
                end
                order[key] = new
            end
            local function moveBookmarkBrowserToSearch(order)
                if type(order.main) ~= "table" or type(order.search) ~= "table" then return end
                local new_main, found_in_main = {}, false
                for _i, id in ipairs(order.main) do
                    if id == "bookmark_browser" then
                        found_in_main = true
                    else
                        table.insert(new_main, id)
                    end
                end
                if found_in_main then order.main = new_main end
                local already_in_search = false
                for _i, id in ipairs(order.search) do
                    if id == "bookmark_browser" then already_in_search = true; break end
                end
                if not already_in_search then
                    local new_search, inserted = {}, false
                    for _i, id in ipairs(order.search) do
                        table.insert(new_search, id)
                        if id == "file_search_results" then
                            table.insert(new_search, "bookmark_browser")
                            inserted = true
                        end
                    end
                    if not inserted then table.insert(new_search, "bookmark_browser") end
                    order.search = new_search
                end
            end
            -- "Actualizar Aire" justo debajo del "Actualizar" de KOReader (que pasa a
            -- llamarse "Actualizar KOReader"); sin él, antes de Ayuda. En el
            -- explorador y en el lector, con Aire activado o no.
            local function addAireUpdate(item_table, order)
                local upd = ctx.update
                if not (upd and upd.menuItem) or type(order.main) ~= "table" then return end
                item_table.aire_update = upd.menuItem()
                if item_table.ota_update then item_table.ota_update.text = _("Update KOReader") end
                for _i, id in ipairs(order.main) do
                    if id == "aire_update" then return end
                end
                local new, inserted = {}, false
                for _i, id in ipairs(order.main) do
                    if not inserted and id == "help" and not item_table.ota_update then
                        table.insert(new, "aire_update")
                        inserted = true
                    end
                    table.insert(new, id)
                    if not inserted and id == "ota_update" and item_table.ota_update then
                        table.insert(new, "aire_update")
                        inserted = true
                    end
                end
                if not inserted then table.insert(new, "aire_update") end
                order.main = new
            end
            local orig_sort = MenuSorter.sort
            MenuSorter.sort = function(ms, item_table, order)
                if type(item_table) == "table" and type(order) == "table" then
                    if item_table.help or item_table.ota_update then
                        local ok, err = pcall(addAireUpdate, item_table, order)
                        if not ok then logger.warn("Aire/Menu: Actualizar Aire:", err) end
                    end
                    if item_table.bookmark_browser then
                        moveBookmarkBrowserToSearch(order)
                    end
                    if item_table.aire_home then
                        ensureFront(order, "filemanager_settings", MENU_IDS, true)
                        if config.enabled and item_table.aire_explorer and item_table.aire_explorer.sub_item_table then
                            local exp_sub = item_table.aire_explorer.sub_item_table
                            if not item_table.aire_explorer._aire_merged then
                                item_table.aire_explorer._aire_merged = true
                                local move_keys = {
                                    "filebrowser_settings", "show_filter",
                                    "sort_by", "reverse_sorting", "sort_mixed",
                                }
                                local added_sep = false
                                for _i, k in ipairs(move_keys) do
                                    local it = item_table[k]
                                    if it then
                                        if not added_sep and #exp_sub > 0 then
                                            exp_sub[#exp_sub].separator = true
                                            added_sep = true
                                        end
                                        table.insert(exp_sub, it)
                                    end
                                end
                            end
                            for _i, k in ipairs({
                                "filemanager_display_mode", "start_with",
                                "filebrowser_settings", "show_filter",
                                "sort_by", "reverse_sorting", "sort_mixed",
                            }) do
                                item_table[k] = nil
                            end
                        end
                    end
                end
                return orig_sort(ms, item_table, order)
            end
        end
    end

    -- Menú del plugin: entradas sueltas en la PRIMERA pestaña del explorador
    -- (antes todo iba dentro de un submenú "Pantalla de inicio"):
    --   Usar pantalla de inicio · Inicio › · Barra superior › · Librería y portadas ›
    --   Dock › · Interfaz › · Avanzado ›   (y debajo, lo que KOReader deja ahí)


    function Aire:addToMainMenu(menu_items)
        if config.enabled then removeObsoleteMenuItems(menu_items) end
        local function refresh(mode)
            self:apply()
            UIManager:setDirty(self.ui, mode or "ui")
        end
        local function refreshGrids()
            if self.closeGridViews then self:closeGridViews() end
            refresh("full")
        end
        local function toggle(key, after)
            return function()
                config[key] = not config[key]
                saveConfig()
                if after then after() end
            end
        end
        local function toggleOn(key, after) -- opciones que por defecto están activadas (nil = sí)
            return function()
                config[key] = (config[key] == false)
                saveConfig()
                if after then after() end
            end
        end
        local function isOn(key) return function() return config[key] ~= false end end

        local on_enabled = function() return config.enabled end


        -- 1) Inicio y widgets
        menu_items.aire_home = {
            text = _("Home and widgets"),
            enabled_func = on_enabled,
            sub_item_table = {
                {
                    text = _("Large clock and date"),
                    checked_func = function() return config.big_clock end,
                    callback = toggle("big_clock", refresh),
                },
                {
                    text = _("\"Reading now\" card with light background"),
                    help_text = _("Otherwise, the current book card is black with white text."),
                    checked_func = function() return config.card_white end,
                    callback = toggle("card_white", refresh),
                },
                {
                    text = _("Synopsis on card"),
                    checked_func = function() return config.card_synopsis end,
                    callback = toggle("card_synopsis", refresh),
                    separator = true,
                },
                {
                    text = _("Edit Home widgets"),
                    callback = function()
                        if self.setWidgetsEdit then self:setWidgetsEdit(true) end
                    end,
                },
                {
                    text = _("Widget presets"),
                    enabled_func = function() return self.getWidgetPresets ~= nil end,
                    sub_item_table_func = function()
                        local ConfirmBox = require("ui/widget/confirmbox")
                        local items = {}
                        for _i, p in ipairs(self.getWidgetPresets and self:getWidgetPresets() or {}) do
                            table.insert(items, {
                                text = p.name,
                                keep_menu_open = true,
                                callback = function()
                                    UIManager:show(ConfirmBox:new{
                                        text = T(_("Replace the Home widgets with the \"%1\" preset?"), p.name),
                                        ok_text = _("Apply"),
                                        ok_callback = function() self:applyWidgetPreset(p.id) end,
                                    })
                                end,
                            })
                        end
                        return items
                    end,
                },
            },
        }

        -- 3) Barra superior
        local function statusAvailable(key)
            if key == "frontlight" then return Device:hasFrontlight() end
            if key == "wifi" then return Device:hasWifiToggle() end
            if key == "battery" then return Device:hasBattery() end
            if key == "ssh" then return self.ui and self.ui.SSH ~= nil end
            return true
        end
        local topbar = {}
        for _i, key in ipairs(STATUS_ORDER) do
            if statusAvailable(key) then
                table.insert(topbar, {
                    text = STATUS_LABELS[key],
                    checked_func = function() return config.status[key] end,
                    callback = function()
                        config.status[key] = not config.status[key]
                        saveConfig()
                        refresh()
                    end,
                })
            end
        end
        if #topbar > 0 then
            topbar[#topbar].separator = true
        end
        table.insert(topbar, {
            text = _("Arrange items"),
            keep_menu_open = true,
            callback = function()
                local SortWidget = require("ui/widget/sortwidget")
                local order = (type(config.status_order) == "table" and #config.status_order > 0)
                    and config.status_order or STATUS_ORDER
                local item_table, hidden = {}, {}
                for _i, key in ipairs(order) do
                    if key ~= "update" then
                        if statusAvailable(key) then
                            table.insert(item_table, {
                                text = STATUS_LABELS[key] or key,
                                key = key,
                                dim = not config.status[key],
                            })
                        else
                            table.insert(hidden, key)
                        end
                    end
                end
                UIManager:show(SortWidget:new{
                    title = _("Arrange items"),
                    item_table = item_table,
                    callback = function()
                        local next_order = {}
                        for _i, it in ipairs(item_table) do
                            table.insert(next_order, it.key)
                        end
                        for _i, key in ipairs(hidden) do
                            table.insert(next_order, key)
                        end
                        config.status_order = next_order
                        saveConfig()
                        refresh()
                    end,
                })
            end,
        })
        menu_items.aire_topbar = {
            text = _("Top bar"),
            enabled_func = on_enabled,
            sub_item_table = topbar,
        }

        -- 4) Librería y portadas
        local function colsItem(n)
            return {
                text = n == 3 and _("3 columns (large covers)") or _("4 columns"),
                radio = true,
                checked_func = function() return (config.grid_cols or 4) == n end,
                callback = function()
                    config.grid_cols = n
                    saveConfig()
                    refreshGrids()
                end,
            }
        end
        local cols_items = { colsItem(3), colsItem(4) }
        menu_items.aire_library = {
            text = _("Library and covers"),
            enabled_func = on_enabled,
            sub_item_table = {
                {
                    text_func = function()
                        return T(_("Grid: %1 columns"), config.grid_cols or 4)
                    end,
                    sub_item_table = cols_items,
                    separator = true,
                },
                {
                    text = _("Square covers and series"),
                    checked_func = function() return not config.rounded_covers end,
                    callback = function()
                        config.rounded_covers = not config.rounded_covers
                        config.square_covers = not config.rounded_covers
                        FileManager._aire_rounded_covers = config.rounded_covers
                        saveConfig()
                        if self.ui.file_chooser and self.ui.file_chooser.updateItems then
                            self.ui.file_chooser:updateItems()
                        end
                        refresh("full")
                    end,
                },
                {
                    text = _("Series number on covers"),
                    checked_func = isOn("series_badge"),
                    callback = toggleOn("series_badge", refreshGrids),
                },
                {
                    -- La opción de KOReader (collection_show_mark), traída aquí desde
                    -- Explorador → Configuración: vale para Aire y para CoverBrowser
                    text = _("Show collection mark"),
                    checked_func = function() return G_reader_settings:nilOrTrue("collection_show_mark") end,
                    callback = function()
                        G_reader_settings:flipNilOrTrue("collection_show_mark")
                        if self.ui and self.ui.collections then
                            self.ui.collections.show_mark = G_reader_settings:nilOrTrue("collection_show_mark")
                        end
                        if self.ui and self.ui.file_chooser and self.ui.file_chooser.refreshPath then
                            self.ui.file_chooser:refreshPath()
                        end
                        refreshGrids()
                    end,
                },
                {
                    text = _("Folded corner on started books"),
                    help_text = _("White corner: reading. Gray corner: on hold."),
                    checked_func = isOn("reading_mark"),
                    callback = toggleOn("reading_mark", refreshGrids),
                },
                {
                    text = _("Finished books in gray"),
                    checked_func = isOn("finished_gray"),
                    callback = toggleOn("finished_gray", refreshGrids),
                    separator = true,
                },
                {
                    text = _("Automatic collections by author"),
                    help_text = _("In Collections, a collection appears for each author with 2 or more books. They update automatically and are not saved in KOReader collections."),
                    checked_func = function() return config.coll_auto_author end,
                    callback = toggle("coll_auto_author", function()
                        if self.reloadGridView then pcall(self.reloadGridView, self, "collections") end
                    end),
                },
                {
                    text = _("Automatic collections by genre (keyword)"),
                    help_text = _("In Collections, a collection appears for each keyword with 2 or more books. They update automatically and are not saved in KOReader collections."),
                    checked_func = function() return config.coll_auto_genre end,
                    callback = toggle("coll_auto_genre", function()
                        if self.reloadGridView then pcall(self.reloadGridView, self, "collections") end
                    end),
                },
                {
                    text = _("Automatic collections by language"),
                    help_text = _("In Collections, a collection appears for each language with 2 or more books. They update automatically and are not saved in KOReader collections."),
                    checked_func = function() return config.coll_auto_lang end,
                    callback = toggle("coll_auto_lang", function()
                        if self.reloadGridView then pcall(self.reloadGridView, self, "collections") end
                    end),
                },
            },
        }

        -- 4b) Explorador (modo Explorador y carpetas de la Librería)
        local function coverBrowser() return self.ui and self.ui.coverbrowser end
        local function bimSetting(key)
            local ok, BIM = pcall(require, "bookinfomanager")
            return ok and type(BIM) == "table" and BIM:getSetting(key) or nil
        end
        local VIEW_MODES = {
            { "mosaic_image",        _("Mosaic with covers") },
            { "list_image_meta",     _("List with covers") },
            { "list_only_meta",      _("List without covers") },
            { "list_image_filename", _("List with filenames") },
        }
        local view_items = {}
        for _i, m in ipairs(VIEW_MODES) do
            local mode, label = m[1], m[2]
            table.insert(view_items, {
                text = label,
                radio = true,
                checked_func = function() return (bimSetting("filemanager_display_mode") or "") == mode end,
                callback = function()
                    local cb = coverBrowser()
                    if not (cb and cb.setDisplayMode) then return end
                    cb:setDisplayMode(mode ~= "" and mode or nil)
                    refresh("full")
                end,
            })
        end
        -- Cuadrícula del mosaico: 3 o 4 columnas, como la Librería; las filas se
        -- calculan para que las portadas tengan la misma proporción (alto 1,5 × ancho)
        local function explorerRows(cols)
            local fc = self.ui.file_chooser
            local avail = (fc and fc.height) or (Screen:getHeight() - self:chromeHeight())
            local w = Screen:getWidth() - 2 * S(SIDE_PAD)
            local cell_w = (w - (cols - 1) * S(10)) / cols
            return math.max(2, math.floor(avail / (cell_w * 1.5) + 0.5))
        end
        local function explorerColsItem(cols)
            return {
                text = cols == 3 and _("3 columns (large covers)") or _("4 columns"),
                radio = true,
                checked_func = function()
                    local fc = self.ui.file_chooser
                    return fc and fc.nb_cols_portrait == cols
                end,
                callback = function()
                    local rows = explorerRows(cols)
                    local ok, BIM = pcall(require, "bookinfomanager")
                    if ok and type(BIM) == "table" then
                        BIM:saveSetting("nb_cols_portrait", cols)
                        BIM:saveSetting("nb_rows_portrait", rows)
                    end
                    FileChooser.nb_cols_portrait, FileChooser.nb_rows_portrait = cols, rows
                    local fc = self.ui.file_chooser
                    if fc then
                        fc.nb_cols_portrait, fc.nb_rows_portrait = cols, rows
                        if fc.updateItems then fc:updateItems() end
                    end
                    refresh("full")
                end,
            }
        end
        menu_items.aire_explorer = {
            text = _("File browser"),
            enabled_func = on_enabled,
            sub_item_table = {
                {
                    text = _("View mode"),
                    enabled_func = function() return coverBrowser() ~= nil end,
                    sub_item_table = view_items,
                },
                {
                    text_func = function()
                        local fc = self.ui.file_chooser
                        return T(_("Grid: %1 columns"), fc and fc.nb_cols_portrait or 3)
                    end,
                    enabled_func = function() return (bimSetting("filemanager_display_mode") or "") == "mosaic_image" end,
                    sub_item_table = { explorerColsItem(3), explorerColsItem(4) },
                },
            },
        }

        -- 5) Dock
        menu_items.aire_dock = {
            text = _("Dock"),
            enabled_func = on_enabled,
            sub_item_table = {
                {
                    text = _("Labels under icons"),
                    checked_func = isOn("dock_labels"),
                    callback = toggleOn("dock_labels", function() refresh("full") end),
                },
            },
        }

        -- 7) Avanzado
        local advanced = {
            {
                text = _("Check patches and plugins on startup"),
                help_text = _("When opening KOReader, warns about new patches and plugins and disables those incompatible with Aire."),
                checked_func = function() return config.compat_check end,
                callback = toggle("compat_check"),
            },
            {
                -- Miniaturas de portadas (views/grid/thumbs.lua): se rehacen solas
                -- si el libro cambia; esto es por si cambia solo la portada
                text = _("Clear cover thumbnails"),
                help_text = _("Library, Collections and History keep small copies of the covers to open faster. Clear them if a cover does not update."),
                keep_menu_open = true,
                callback = function()
                    local ok, Thumbs = pcall(dofile, PLUGIN_DIR .. "/views/grid/thumbs.lua")
                    if ok and Thumbs then Thumbs.clear() end
                    for kind in pairs({ library = true, collections = true, history = true, finished = true }) do
                        if self._gv and self._gv[kind] and self.freeGridCovers then pcall(self.freeGridCovers, self, kind) end
                    end
                    require("ui/widget/notification"):notify(_("Cover thumbnails cleared"))
                end,
            },
        }
        -- Solo si está devtools.lua en la carpeta del plugin
        if self.hasTestTools and self:hasTestTools() then
            if #advanced > 0 then advanced[#advanced].separator = true end
            table.insert(advanced, {
                text = _("Tests"),
                sub_item_table = {
                    {
                        text = _("Automatic tests"),
                        callback = function()
                            local ok, runner = pcall(dofile, PLUGIN_DIR .. "/dev/test_runner.lua")
                            if ok and runner and runner.showMenu then
                                UIManager:nextTick(function() runner.showMenu(self, config, PLUGIN_DIR) end)
                            else
                                logger.warn("Aire/Test: error cargando test_runner", runner)
                            end
                        end,
                        separator = true,
                    },
                    (function() local g = galleryMenu(self); g.separator = true; return g end)(),
                    {
                        text = _("Test data (pagination)"),
                        checked_func = function() return config.demo end,
                        callback = function()
                            config.demo = not config.demo
                            saveConfig()
                            if self.closeGridViews then self:closeGridViews() end
                            self._gv = nil -- volver a cargar las vistas con / sin datos de prueba
                            self:apply()
                            UIManager:setDirty(self.ui, "ui")
                        end,
                    },
                    {
                        text = _("Test widgets (all with data)"),
                        checked_func = function() return config.demo_widgets end,
                        callback = function()
                            config.demo_widgets = not config.demo_widgets
                            saveConfig()
                            self:apply()
                            UIManager:setDirty(self.ui, "ui")
                        end,
                    },
                    {
                        text = _("Next batch of test widgets"),
                        enabled_func = function() return config.demo_widgets end,
                        keep_menu_open = true,
                        callback = function()
                            config.demo_widgets_offset = (config.demo_widgets_offset or 0) + 8
                            saveConfig()
                            self:apply()
                            UIManager:setDirty(self.ui, "ui")
                        end,
                    },
                    {
                        text = _("Test stats"),
                        checked_func = function() return config.demo_stats end,
                        callback = function()
                            config.demo_stats = not config.demo_stats
                            saveConfig()
                            self:apply()
                            UIManager:setDirty(self.ui, "ui")
                        end,
                        separator = true,
                    },
                    {
                        text = _("Show dimensions of each book / series"),
                        checked_func = function() return config.debug_sizes end,
                        callback = function()
                            config.debug_sizes = not config.debug_sizes
                            saveConfig()
                            self:apply()
                            UIManager:setDirty(self.ui, "ui")
                        end,
                    },
                    {
                        -- Actualizaciones (views/update_sheet.lua): con esto la versión publicada
                        -- cuenta como nueva y se puede probar todo, también instalarla
                        text = "Simular Aire 0.0.1 (actualizaciones)",
                        checked_func = function() return ctx.update and ctx.update.fakeVersion() ~= nil end,
                        callback = function()
                            if not ctx.update then return end
                            ctx.update.setFakeVersion(not ctx.update.fakeVersion() and "0.0.1" or nil)
                        end,
                    },
                    {
                        -- Capturas sin datos personales (libros de koreader/aire-readme-books)
                        text = "Capturas para el README",
                        callback = function()
                            local TEST = self.getTestTools and self:getTestTools()
                            if TEST and TEST.takeReadmeShots then
                                UIManager:nextTick(function() TEST.takeReadmeShots(self, config, saveConfig) end)
                            end
                        end,
                    },
                    {
                        -- Lo que Aire ha apuntado en crash.log (avisos y errores), sin
                        -- tener que pasar el archivo al ordenador
                        text = _("Aire warnings (crash.log)"),
                        callback = function()
                            local path = require("datastorage"):getDataDir() .. "/crash.log"
                            local lines = {}
                            local fh = io.open(path, "r")
                            if fh then
                                for line in fh:lines() do
                                    if line:find("Aire/", 1, true) and not line:find("Aire/Test", 1, true)
                                            and (line:find(" WARN ", 1, true) or line:find(" ERROR ", 1, true)) then
                                        table.insert(lines, line)
                                        if #lines > 60 then table.remove(lines, 1) end
                                    end
                                end
                                fh:close()
                            end
                            UIManager:show(require("ui/widget/textviewer"):new{
                                title = _("Aire warnings (crash.log)"),
                                text = #lines > 0 and table.concat(lines, "\n") or "—",
                            })
                        end,
                    },
                },
            })
        end

        menu_items.aire_advanced = {
            text = _("Advanced"),
            sub_item_table = advanced,
        }
    end
end
