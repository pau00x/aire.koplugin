--[[
    aire.koplugin/views/explorer.lua
    Modo Explorador: franjas superior (ruta, ordenar) e inferior (dock)
    alrededor del explorador de archivos de KOReader.
    Se carga desde main.lua como "mixin" (añade métodos a Aire).
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

return function(Aire, ctx)
    -- Módulos y valores compartidos declarados aquí dentro: así no cuentan
    -- como upvalues de esta función (LuaJIT admite 60).
    local BD = require("ui/bidi")
    local Device = require("device")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local _ = require("gettext")
    local Screen = Device.screen
    local S = ctx.S
    local config = ctx.config
    local TOP_GAP_BELOW = ctx.TOP_GAP_BELOW
    local SIDE_PAD = ctx.SIDE_PAD

    -- Ruta de la carpeta actual (como la mostraba la barra de KOReader)
    function Aire:pathText(path)
        local fm = self.ui
        path = path or self._last_path or (fm.file_chooser and fm.file_chooser.path)
        if not path then return " " end
        return (fm.folder_shortcuts and fm.folder_shortcuts:getShortcutFullName(path))
            or BD.directory(filemanagerutil.abbreviate(path))
    end

    -- ¿Puede subir de carpeta el explorador?
    function Aire:canExplorerGoUp(path)
        local fc = self.ui and self.ui.file_chooser
        path = path or self._last_path or (fc and fc.path) or filemanagerutil.getHomeFolder()
        if not path or path == "/" then return false end
        if G_reader_settings:isTrue("lock_home_folder") and self:isAtHomeFolder(path) then return false end
        return true
    end

    local UTF8_CAP = { ["á"] = "Á", ["é"] = "É", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ñ"] = "Ñ", ["ü"] = "Ü" }
    local function capFirst(s)
        if type(s) ~= "string" or s == "" then return s end
        return (s:gsub("^([%z\1-\127\194-\244][\128-\191]*)", function(c)
            return UTF8_CAP[c] or c:upper()
        end))
    end

    -- Franja superior del explorador: barra de estado + título (Inicio / ‹ Carpeta) + ruta/Ordenar
    function Aire:buildTopArea(sw)
        local fm = self.ui
        local w = sw - 2 * S(SIDE_PAD)
        local fc = fm and fm.file_chooser
        local cur_path = self._last_path or (fc and fc.path) or filemanagerutil.getHomeFolder()
        local at_home = self:isAtHomeFolder(cur_path)
        local can_up = self:canExplorerGoUp(cur_path)
        self._explorer_can_up = can_up

        local sort_label = _("Sort")
        if fc and fc.getCollate then
            local ok_c, col = pcall(fc.getCollate, fc)
            if ok_c and type(col) == "table" and col.text and (col.menu_order or 999) <= 60 then
                sort_label = capFirst(col.text)
            end
        end
        -- Hoja para elegir el orden (ui/sheet.lua), la misma que la de la
        -- Librería: el orden actual relleno y debajo invertir / mezclar carpetas.
        -- (El botón con el orden actual va en la cabecera.)
        local function openSort()
            if not (fc and fc.collates) then return end
            local cur_col, cur_id = fc:getCollate()
            local list = {}
            for k, v in pairs(fc.collates) do
                if v.menu_order and v.menu_order <= 60 then
                    table.insert(list, { id = k, text = capFirst(v.text), order = v.menu_order })
                end
            end
            table.sort(list, function(a, b) return a.order < b.order end)
            local function after()
                self:apply()
                UIManager:setDirty(self.ui, "ui")
            end
            local function flip(setting)
                return function()
                    G_reader_settings:flipNilOrFalse(setting)
                    if fc.refreshPath then fc:refreshPath() end
                    after()
                end
            end
            local sorts = {}
            for _i, item in ipairs(list) do
                local k = item.id
                table.insert(sorts, { text = item.text, active = (k == cur_id), callback = function()
                    if fm and fm.onSetSortBy then fm:onSetSortBy(k) end
                    after()
                end })
            end
            local extras = {
                { text = _("Reverse sorting"), active = G_reader_settings:isTrue("reverse_collate"),
                  callback = flip("reverse_collate") },
            }
            if cur_col and cur_col.can_collate_mixed then
                table.insert(extras, { text = _("Mix folders"), active = G_reader_settings:isTrue("collate_mixed"),
                    callback = flip("collate_mixed") })
            end
            package.loaded.aire_sheet.showChoices{
                title = _("Sort files"),
                groups = { { heading = _("SORT BY"), items = sorts }, { items = extras } },
                style = ctx.selStyle and ctx.selStyle() or "black",
                lighten = ctx.lightened,
            }
        end

        local folder_name = at_home and _("Home")
            or (cur_path == "/" and "/")
            or BD.directory((cur_path and cur_path:match("([^/]+)/*$")) or self:pathText(cur_path))
        -- Cabecera común (ui/screen.lua): en subcarpetas, "‹ Carpeta" sube un
        -- nivel; a la derecha, el orden actual ▾
        local AireScreen = package.loaded.aire_screen
        local title_w = AireScreen.header(w, {
            title = folder_name,
            menu_text = sort_label,
            on_menu = openSort,
            on_back = can_up and function()
                if fm and fm.file_chooser and fm.file_chooser.onFolderUp then
                    fm.file_chooser:onFolderUp()
                end
            end or nil,
        })
        local vg = self:buildScreenTop(w)
        table.insert(vg, title_w)
        table.insert(vg, VerticalSpan:new{ width = S(AireScreen.METRICS.SUB_GAP) })

        -- Ruta como subtítulo (cortada por la izquierda si no cabe)
        local path_str = at_home and BD.directory(cur_path) or self:pathText(cur_path)
        local path_row
        path_row, self._path_w = AireScreen.subtitle(w, path_str, { truncate_left = true })
        table.insert(vg, path_row)
        table.insert(vg, VerticalSpan:new{ width = S(TOP_GAP_BELOW) })

        return HorizontalGroup:new{
            HorizontalSpan:new{ width = S(SIDE_PAD) },
            vg,
        }
    end

    -- Alto que ocupan nuestras franjas en el explorador (se mide construyéndolas)
    function Aire:chromeHeight()
        local sw = Screen:getWidth()
        -- Medir sin pisar los widgets vivos (reloj, estado, ruta) de la vista
        -- actual: se construyen copias y se restauran las referencias
        local saved = {}
        local KEYS = { "_explorer_can_up", "_path_w", "_status_group", "_status_update", "_status_w", "_top_clock_hidden", "_top_clock_w" }
        for _i, k in ipairs(KEYS) do saved[k] = self[k] end
        local top, dock = self:buildTopArea(sw), self:buildNavBar(sw - 2 * S(SIDE_PAD))
        local h = top:getSize().h + package.loaded.aire_screen.dockReserve(dock)
        top:free()
        dock:free()
        for _i, k in ipairs(KEYS) do self[k] = saved[k] end
        return h
    end

    function Aire:buildFilesView()
        local fm = self.ui
        local sw = Screen:getWidth()
        self._dock_at_home = self:isAtHomeFolder()
        local top = self:buildTopArea(sw)
        self._clock_w, self._date_w = nil, nil
        self._header_h = top:getSize().h
        local dock = self:buildNavBar(sw - 2 * S(SIDE_PAD))
        return package.loaded.aire_screen.root(VerticalGroup:new{
            align = "left",
            top,
            fm._aire_orig_ui,
        }, dock)
    end

    -- ¿Está el explorador en la carpeta de inicio?
    function Aire:isAtHomeFolder(path)
        local fc = self.ui and self.ui.file_chooser
        path = path or self._last_path or (fc and fc.path)
        if not path then return false end
        local function norm(p) return (p:gsub("/+$", "")) end
        return norm(path) == norm(filemanagerutil.getHomeFolder())
    end

    function Aire:onPathChanged(path)
        if self:isOwnView() or not config.enabled then return end
        self._last_path = path
        local at_home = self:isAtHomeFolder(path)
        local can_up = self:canExplorerGoUp(path)
        if at_home ~= self._dock_at_home or can_up ~= self._explorer_can_up or can_up then
            -- Cambia el marcado de Home en el dock o el nombre de la carpeta en cabecera
            self._dock_at_home = at_home
            self._explorer_can_up = can_up
            self:apply()
            UIManager:setDirty(self.ui, "ui")
            return
        end
        if not self._path_w then return end -- (ruta oculta en el menú Explorador)
        self._path_w:setText(self:pathText(path))
        UIManager:setDirty(self.ui, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = self._header_h or S(80) })
        -- sin return true: FileManager también tiene que recibir el evento
    end
end
