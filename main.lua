--[[
    aire.koplugin / main.lua  (v2)

    Pantalla de inicio que sustituye a la vista del FileManager:

      ┌──────────────────────────────────────────┐
      │ 14:32                   35M · 91%  [⏻]  │  <- hora, estado, energía
      │                                          │
      │                 11:25                    │  <- reloj grande + fecha (opcional)
      │           martes, 17 de marzo            │
      │                                          │
      │ LEYENDO AHORA                            │
      │ ┌──────────────────────────────────────┐ │
      │ │ [portada]  Título                    │ │
      │ │            Autor                     │ │
      │ │            Serie #2                  │ │
      │ │            ━━━━━─────────────        │ │
      │ │            14% leído    Pág. 68/480  │ │
      │ │            [ Continuar leyendo ]     │ │
      │ └──────────────────────────────────────┘ │
      │                                          │
      │ [Librería][Colecc.][Inicio][Hist.][Est.] │  <- navegación inferior
      └──────────────────────────────────────────┘

    Modos (mantener pulsado Inicio / Home en el dock):
      - Librería: esta pantalla. La pestaña "Librería" abre el explorador en la
        carpeta de inicio (home_dir) del FileManager.
      - Explorador: el FileManager normal de siempre.
    En el explorador, el icono de la casa vuelve a esta pantalla.

    Este archivo: carga de módulos, ajustes, enganches del explorador, la clase
    Aire (init, apply, cambiar de vista, ciclo de vida). El resto son "mixins"
    que añaden métodos a Aire (ver la lista al cargarlos más abajo):
      views/power.lua · topbar.lua · dock.lua · explorer.lua · home.lua
      views/grid.lua · stats.lua · widgets.lua · update.lua · menu.lua
    Ajustes por defecto y lectura: common/config.lua.
--]]

local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local FileManager = require("apps/filemanager/filemanager")
local Geom = require("ui/geometry")

local function emptyGeom()
    return Geom:new{ x = 0, y = 0, w = 0, h = 0 }
end
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local _ = require("gettext")
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.+)[/\\][^/\\]+$")
local UI = nil
if plugin_dir then
    -- Traducciones: normalmente ya las cargó _meta.lua (KOReader lo lee antes)
    if not _._aire_l10n_lang then
        pcall(function() dofile(plugin_dir .. "/common/l10n.lua").load(plugin_dir) end)
    end
    pcall(function() dofile(plugin_dir .. "/common/icons.lua").register(plugin_dir) end)
    -- Piezas comunes (medidas, letra, colores, zonas pulsables, envoltorios
    -- seguros): todos los módulos las toman de package.loaded.aire_ui, la
    -- estructura de las pantallas completas (medidas, puntos de página) de
    -- package.loaded.aire_screen y las pantallas de common/pages.lua de
    -- package.loaded.aire_pages
    UI = dofile(plugin_dir .. "/common/ui.lua")
    package.loaded.aire_ui = UI
    package.loaded.aire_screen = dofile(plugin_dir .. "/common/screen.lua")
    -- Hojas inferiores (marco, cierre, refresco, desplazamiento): common/sheet.lua
    package.loaded.aire_sheet = dofile(plugin_dir .. "/common/sheet.lua")
    package.loaded.aire_pages = dofile(plugin_dir .. "/common/pages.lua")
    -- Cabecera en crash.log (como la de KOReader) con la versión de _meta.lua,
    -- para que cada log diga cuál era. Es lo único que Aire escribe siempre al
    -- arrancar; el resto va con logger.dbg (registro detallado de KOReader).
    local ok_meta, meta = pcall(dofile, plugin_dir .. "/_meta.lua")
    local version = ok_meta and type(meta) == "table" and meta.version or "?"
    io.stdout:write(table.concat({
        "",
        "          _",
        "   __ _  (_)  _ __   ___",
        "  / _` | | | | '__| / _ \\",
        " | (_| | | | | |   |  __/",
        "  \\__,_| |_| |_|    \\___|",
        "",
        "  Aire " .. version .. " for KOReader",
        "",
    }, "\n") .. "\n")
    io.stdout:flush()
    logger.info("Aire version", version)
end
local Screen = Device.screen

local BLACK = UI.BLACK
local WHITE = UI.WHITE
local GRAY_TEXT = UI.GRAY_TEXT
local SEPARATOR = "  "


-- Ajustes (valores por defecto y lectura en common/config.lua)
local Config = dofile((plugin_dir or "plugins/aire.koplugin") .. "/common/config.lua")
local config = Config.load()
FileManager._aire_rounded_covers = config.rounded_covers

-- Estilo de lo seleccionado / acción principal (opción de devtools.lua):
--   "black"   relleno negro (por defecto)
--   "gray"    relleno gris oscuro (se pinta en negro y se aclara)
--   "outline" sin relleno: borde grueso y negrita
-- Sin devtools.lua siempre "black".
local style_state = { test = false }
local function selStyle()
    if style_state.test and (config.sel_style == "gray" or config.sel_style == "outline") then
        return config.sel_style
    end
    return "black"
end
local SEL_GRAY_LIGHTEN = 0.28 -- negro -> gris oscuro (~#474747); el blanco sigue blanco

-- Estilos de pantallas de KOReader y fichas. Se cargan una sola vez (KOReader
-- hace dofile de main.lua una vez por sesión). Mientras se carga main.lua la
-- carpeta del plugin aún no está en package.path, así que se usa su ruta.
local PLUGIN_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]*$") or "plugins/aire.koplugin"
local function loadModule(file)
    local ok, err = pcall(dofile, PLUGIN_DIR .. "/" .. file)
    if not ok then logger.warn("Aire: error cargando", file, err) end
end
-- El orden importa: bookinfo.lua lee
-- KeyValueItem de KeyValuePage antes de que styles/ui.lua lo envuelva.
loadModule("styles/covers.lua")              -- portadas del mosaico
loadModule("styles/bookinfo.lua")            -- Información del libro
loadModule("styles/bookmap.lua")             -- Mapa del libro (BookMapWidget)
loadModule("styles/pagebrowser.lua")         -- Explorador de páginas (PageBrowserWidget)
loadModule("styles/imageviewer.lua")         -- Visor de imágenes / portadas (ImageViewer)
loadModule("styles/readerprogress.lua")      -- Progreso de lectura (statistics.koplugin)
loadModule("styles/calendar.lua")            -- Calendario de lectura (statistics.koplugin)
loadModule("styles/vocabbuilder.lua")        -- Constructor de vocabulario (vocabbuilder.koplugin)
loadModule("styles/toc.lua")                 -- Índice del libro (ReaderToc)
loadModule("styles/bookmark.lua")            -- Marcadores y notas (ReaderBookmark)
loadModule("styles/search.lua")              -- Resultados de búsqueda (ReaderSearch)
loadModule("styles/shortcuts.lua")           -- Atajos de carpetas (FileManagerShortcuts)
loadModule("styles/bookstatus.lua")          -- Estado del libro (BookStatusWidget)
loadModule("styles/collections.lua")         -- Lista de colecciones de KOReader (elegir colecciones)
loadModule("styles/statspages.lua")          -- Estadísticas: libro actual, intervalo de tiempo, línea de tiempo
loadModule("styles/gestures.lua")            -- Resumen de gestos (plugin Gestures)
loadModule("styles/skim.lua")                -- Vista rápida del documento (SkimToWidget)
loadModule("styles/highlight.lua")           -- Subrayados: mantener pulsado uno existente
loadModule("styles/footer.lua")              -- Barra de estado del lector (ReaderFooter)
loadModule("views/booksheet.lua")           -- ficha al mantener pulsado
loadModule("styles/ui.lua")                  -- interfaz general: carga styles/ui/*.lua
loadModule("styles/sortwidget.lua")          -- Ordenar (colecciones…): tarjetas y puntos de página (después de ui.lua)

-- El explorador (FileChooser "filemanager") se crea con la altura que deja
-- libre nuestra barra superior. Menu/Mosaic calculan todo a partir de height.
local pending_fc_height = nil
if not FileChooser._aire_height_hooked then
    FileChooser._aire_height_hooked = true
    local orig_fc_init = FileChooser.init
    FileChooser.init = function(fc, ...)
        if fc.name == "filemanager" and pending_fc_height and not fc.height then
            fc.height = pending_fc_height
            -- Sin la barra de título de KOReader: la ruta va en nuestra franja y
            -- casa / + en el dock. La TitleBar sigue existiendo (KOReader la usa
            -- para la ruta y el modo selección), solo no se dibuja ni ocupa alto.
            fc.no_title = true
        end
        return orig_fc_init(fc, ...)
    end
    local orig_gen = FileChooser.genItemTableFromPath
    if orig_gen then
        FileChooser.genItemTableFromPath = function(fc, path, ...)
            local item_table = orig_gen(fc, path, ...)
            if fc.name == "filemanager" and config.enabled and type(item_table) == "table" then
                for i = #item_table, 1, -1 do
                    if item_table[i] and item_table[i].is_go_up then
                        table.remove(item_table, i)
                    end
                end
            end
            return item_table
        end
    end
end

local function saveConfig()
    G_reader_settings:saveSetting(Config.SETTINGS_KEY, config)
end

---------------------------------------------------------------------------
-- Utilidades
---------------------------------------------------------------------------
local S = UI.S
local face = UI.face
local tappable = UI.tappable

---------------------------------------------------------------------------
-- Plugin
---------------------------------------------------------------------------
local Aire = WidgetContainer:extend{
    name = "aire",
    is_doc_only = false,
}

function Aire:init()
    Aire._active_instance = self
    if not self.ui or self.ui.document then return end
    local fm = self.ui
    local plugin = self
    self.view = (config.mode == "library") and "home" or "files"

    -- setupLayout se llama en FileManager:init (después de crear los plugins)
    -- y en cada reinit/rotación: el explorador se crea más bajo para dejar sitio
    -- a nuestra barra superior; guardamos su vista y aplicamos la nuestra.
    local orig_setupLayout = fm.setupLayout
    fm.setupLayout = function(f, ...)
        if config.enabled then
            pending_fc_height = Screen:getHeight() - plugin:chromeHeight()
        end
        local ok, res = pcall(orig_setupLayout, f, ...)
        pending_fc_height = nil
        if not ok then error(res, 0) end
        f._aire_orig_ui = f[1]
        f._aire_orig_layout = f.layout
        plugin:apply()
        return res
    end

    -- En la vista Librería (pestaña), la casa vuelve a Inicio.
    -- En el modo Explorador la casa hace lo de siempre (carpeta de inicio).
    local orig_onHome = fm.onHome
    fm.onHome = function(f, ...)
        if config.enabled and config.mode == "library" then
            if plugin.view ~= "home" then plugin:showHome() end
            return true
        end
        return orig_onHome(f, ...)
    end

    -- Con la pantalla de inicio visible, los swipes horizontales no deben pasar páginas del explorador oculto
    local orig_onSwipeFM = fm.onSwipeFM
    if orig_onSwipeFM then
        fm.onSwipeFM = function(f, ges, ...)
            if plugin:isOwnView() then
                local dir = ges and ges.direction
                if dir == "west" or dir == "east" then return true end
                return false
            end
            return orig_onSwipeFM(f, ges, ...)
        end
    end

    -- Al mostrarse el FileManager, KOReader solo refresca la zona del explorador
    --. Como ahora es más bajo, la franja del
    -- dock se quedaba con la imagen anterior ("Starting KOReader", interfaz del
    -- Kindle). Pedimos un refresco completo en cuanto se haya mostrado.
    fm:registerPostInitCallback(function()
        UIManager:nextTick(function()
            if config.enabled then UIManager:setDirty(fm, "full") end
            -- Restos de una actualización (aire.koplugin.old / .new)
            if plugin.cleanupUpdateLeftovers then pcall(plugin.cleanupUpdateLeftovers, plugin) end
            -- Parches / plugins nuevos o incompatibles (common/compat.lua), una vez por sesión
            local ok, compat = pcall(dofile, PLUGIN_DIR .. "/common/compat.lua")
            if ok and type(compat) == "table" then
                local ok2, err = pcall(compat.run, config, saveConfig)
                if not ok2 then logger.warn("Aire: error en la comprobación de compatibilidad:", err) end
            elseif not ok then
                logger.warn("Aire: error cargando compat.lua:", compat)
            end
        end)
    end)

    if fm.menu then
        fm.menu:registerToMainMenu(self)
        -- Opciones que rehacen el explorador (alto de la cabecera, activar):
        -- con el menú abierto, el reinit hace que KOReader cierre y reabra el
        -- menú en la raíz de la pestaña ("me saca un nivel atrás"). Se deja
        -- pendiente y se hace al cerrar el menú.
        local menu = fm.menu
        local orig_close = menu.onCloseFileManagerMenu
        if orig_close then
            menu.onCloseFileManagerMenu = function(m, ...)
                local res = orig_close(m, ...)
                if plugin._aire_reinit_pending then
                    plugin._aire_reinit_pending = nil
                    UIManager:nextTick(function() fm:reinit() end)
                end
                return res
            end
        end
    end
end

-- Rehacer el explorador ahora o, si el menú superior está abierto, al cerrarlo
function Aire:requestReinit()
    local menu = self.ui and self.ui.menu
    if menu and menu.menu_container then
        self._aire_reinit_pending = true
    else
        self.ui:reinit()
    end
end

-- Vistas propias del plugin (modo Librería): Inicio, Librería…
-- Para devtools.lua (galería de hojas)

function Aire:isOwnView()
    -- _aire_closed: el FileManager ya se cerró (p. ej. al abrir un libro); así
    -- los refrescos diferidos (refreshSoon, sondeo de análisis) no tocan nada
    return config.enabled and config.mode == "library" and not self._aire_closed
end

function Aire:isHomeVisible()
    return self:isOwnView() and self.view == "home"
end

-- Márgenes (iguales en Inicio, vistas y explorador): common/screen.lua
local METRICS = package.loaded.aire_screen.METRICS
local TOP_PAD, TOP_GAP_BELOW, SIDE_PAD = METRICS.TOP_PAD, METRICS.TOP_GAP_BELOW, METRICS.SIDE
local DOCK_GAP_ABOVE, DOCK_MARGIN_BOTTOM = METRICS.DOCK_GAP_ABOVE, METRICS.DOCK_MARGIN_BOTTOM
local WIDGET_GAP = 14 -- separación de los widgets de Inicio (con la tarjeta, entre sí y con el dock)

-- Vistas propias (añaden métodos a Aire):
--   grid.lua  Librería / Colecciones / Historial
--   stats.lua  Estadísticas
do
    local view_ctx = {
        S = S, face = face, tappable = tappable,
        config = config, saveConfig = saveConfig,
        TOP_PAD = TOP_PAD, SIDE_PAD = SIDE_PAD,
        DOCK_GAP_ABOVE = DOCK_GAP_ABOVE, DOCK_MARGIN_BOTTOM = DOCK_MARGIN_BOTTOM,
        PLUGIN_DIR = PLUGIN_DIR,
        WIDGET_GAP = WIDGET_GAP,
        selStyle = selStyle,
        -- Valores compartidos con los mixins de views/ y menu.lua
        BLACK = BLACK, WHITE = WHITE, GRAY_TEXT = GRAY_TEXT, SEPARATOR = SEPARATOR,
        emptyGeom = emptyGeom, SEL_GRAY_LIGHTEN = SEL_GRAY_LIGHTEN, TOP_GAP_BELOW = TOP_GAP_BELOW,
        -- views/power.lua añade showPowerDialog y lightened; views/home.lua, getCurrentBook
    }
    -- El orden importa: cada uno puede usar lo que los anteriores dejan en el contexto
    for _i, file in ipairs({
        "views/power.lua", "views/topbar.lua", "views/dock.lua", "views/explorer.lua",
        "views/home.lua", "views/grid.lua", "views/stats.lua", "views/widgets.lua", "views/update.lua",
        "menu.lua",
    }) do
        local ok, mixin = pcall(dofile, PLUGIN_DIR .. "/" .. file)
        if ok and type(mixin) == "function" then
            local ok2, err = pcall(mixin, Aire, view_ctx)
            if not ok2 then logger.warn("Aire: error iniciando", file, err) end
        else
            logger.warn("Aire: error cargando", file, mixin)
        end
    end
    style_state.test = Aire.hasTestTools ~= nil and Aire.hasTestTools() == true
end

function Aire:apply()
    local fm = self.ui
    if self._aire_closed or not fm or not fm._aire_orig_ui then return end
    -- El modo edición de widgets es solo de Inicio: al ir a otra pestaña se cierra
    if not (self:isOwnView() and self.view == "home") then self._widgets_edit = nil end
    if self:isOwnView() then
        if self.isGridView and self:isGridView(self.view) then
            fm[1] = self:buildGridView(self.view)
        elseif self.view == "stats" and self.buildStatsView then
            fm[1] = self:buildStatsView()
        elseif self.view == "calendar" and self.buildCalendarView then
            fm[1] = self:buildCalendarView()
        elseif self.view == "recap" and self.buildRecapView then
            fm[1] = self:buildRecapView()
        else
            self.view = "home"
            fm[1] = self:buildHome()
        end
        fm.layout = nil
    elseif config.enabled then
        fm[1] = self:buildFilesView()
        fm.layout = fm.file_chooser and fm.file_chooser.layout or fm._aire_orig_layout
    else
        fm[1] = fm._aire_orig_ui
        fm.layout = fm.file_chooser and fm.file_chooser.layout or fm._aire_orig_layout
    end
    if config.enabled then self:scheduleTick() else self:unscheduleTick() end
end

function Aire:showHome()
    if self.view ~= "home" then
        self._w_random = nil
        -- Desde otra pestaña pueden haber cambiado estados, historial o
        -- estadísticas: los widgets vuelven a leer sus datos
        if self.invalidateWidgetData then self:invalidateWidgetData() end
    end
    config.mode = "library"
    saveConfig()
    if self.closeGridViews then self:closeGridViews(true) end
    if self.closeStatsView then self:closeStatsView() end
    self.view = "home"
    self:apply()
    UIManager:setDirty(self.ui, "flashui")
end

function Aire:showFiles(go_home_dir)
    self.view = "files"
    self:apply()
    if go_home_dir and self.ui.file_chooser then
        self.ui.file_chooser:changeToPath(filemanagerutil.getHomeFolder())
    end
    UIManager:setDirty(self.ui, "flashui")
end

function Aire:showExplorer()
    if self.closeGridViews then self:closeGridViews() end
    config.mode = "explorer"
    saveConfig()
    self:showFiles(false)
end


function Aire:onSuspend()
    self._suspended = true
    self:unscheduleTick()
end

function Aire:onResume()
    self._suspended = false
    self:refreshHeader()
end

function Aire:onCloseWidget()
    self._aire_closed = true
    self:unscheduleTick()
    if self.closeGridViews then self:closeGridViews() end
    if self.closeStatsView then self:closeStatsView() end
    if self.freeWidgetCovers then self:freeWidgetCovers() end
end

---------------------------------------------------------------------------
-- Menú (Ajustes del explorador)
---------------------------------------------------------------------------
-- Pruebas (galería de pantallas, devtools.lua): monta una vista del plugin con
-- datos de prueba como widget aparte, sin cambiar la vista del explorador.
-- Al cerrar la galería hay que llamar a finishViewSnapshots().
function Aire:buildViewSnapshot(view)
    local saved = { view = self.view, demo = config.demo, demo_stats = config.demo_stats,
                    demo_widgets = config.demo_widgets, edit = self._widgets_edit, cal = self._cal, recap = self._recap }
    if not self._aire_snapshot_active then
        self._aire_snapshot_active = true
        if self.closeGridViews then self:closeGridViews() end
        self._gv = nil -- volver a cargar las vistas con los datos de prueba
    end
    config.demo, config.demo_stats, config.demo_widgets = true, true, true
    self._widgets_edit = nil
    self.view = view
    local ok, res = pcall(function()
        if view == "home" then return self:buildHome() end
        if view == "stats" and self.buildStatsView then return self:buildStatsView() end
        if view == "calendar" and self.buildCalendarView then self._cal = nil; return self:buildCalendarView() end
        if (view == "recap_month" or view == "recap_year") and self.buildRecapView then
            local now = os.date("*t")
            self._recap = { mode = view == "recap_year" and "year" or "month", year = now.year, month = now.month }
            return self:buildRecapView()
        end
        if self.isGridView and self:isGridView(view) and self.buildGridView then return self:buildGridView(view) end
    end)
    self.view, config.demo, config.demo_stats, config.demo_widgets = saved.view, saved.demo, saved.demo_stats, saved.demo_widgets
    self._widgets_edit, self._cal, self._recap = saved.edit, saved.cal, saved.recap
    if not ok then logger.warn("Aire/DevTools: no se pudo montar la vista", view, res) return nil end
    return res
end

function Aire:finishViewSnapshots()
    if not self._aire_snapshot_active then return end
    self._aire_snapshot_active = nil
    if self.closeGridViews then self:closeGridViews() end
    self._gv = nil -- datos reales otra vez
    self:apply()
    UIManager:setDirty(self.ui, "full")
end

-- Pruebas: cambiar el estilo de lo seleccionado y redibujar
function Aire:setSelStyle(style)
    config.sel_style = style
    saveConfig()
    self:apply()
    UIManager:setDirty(self.ui, "full")
end

return Aire
