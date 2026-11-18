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
    local ButtonDialog = require("ui/widget/buttondialog")
    local Device = require("device")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local _ = require("gettext")
    local Screen = Device.screen
    local S = ctx.S
    local face = ctx.face
    local tappable = ctx.tappable
    local config = ctx.config
    local BLACK = ctx.BLACK
    local GRAY_TEXT = ctx.GRAY_TEXT
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
        local sort_btn = tappable(FrameContainer:new{
            bordersize = 0, padding = 0, padding_left = S(8), padding_top = S(4), padding_bottom = S(4),
            HorizontalGroup:new{
                align = "center",
                TextWidget:new{ text = sort_label, face = face(false, 13), fgcolor = BLACK, padding = 0 },
                HorizontalSpan:new{ width = S(2) },
                IconWidget:new{ icon = "aire.chevron.down", width = S(16), height = S(16), alpha = true },
            },
        }, function()
            if not (fc and fc.collates) then return end
            local _cur_col, cur_id = fc:getCollate()
            local list = {}
            for k, v in pairs(fc.collates) do
                if v.menu_order and v.menu_order <= 60 then
                    table.insert(list, { id = k, text = capFirst(v.text), order = v.menu_order })
                end
            end
            table.sort(list, function(a, b) return a.order < b.order end)
            local dialog
            local buttons, row = {}, {}
            for _i, item in ipairs(list) do
                local k = item.id
                table.insert(row, {
                    text = item.text,
                    is_enter_default = (k == cur_id),
                    callback = function()
                        UIManager:close(dialog, "ui")
                        if fm and fm.onSetSortBy then fm:onSetSortBy(k) end
                        self:apply()
                        UIManager:setDirty(self.ui, "ui")
                    end,
                })
                if #row == 2 then table.insert(buttons, row); row = {} end
            end
            if #row > 0 then table.insert(buttons, row) end
            table.insert(buttons, {})
            local rev = G_reader_settings:isTrue("reverse_collate")
            local extra_row = { {
                text = _("Reverse sorting"),
                is_enter_default = rev,
                callback = function()
                    UIManager:close(dialog, "ui")
                    G_reader_settings:flipNilOrFalse("reverse_collate")
                    if fc.refreshPath then fc:refreshPath() end
                    self:apply()
                    UIManager:setDirty(self.ui, "ui")
                end,
            } }
            if _cur_col and _cur_col.can_collate_mixed then
                local mixed = G_reader_settings:isTrue("collate_mixed")
                table.insert(extra_row, {
                    text = _("Mix folders"),
                    is_enter_default = mixed,
                    callback = function()
                        UIManager:close(dialog, "ui")
                        G_reader_settings:flipNilOrFalse("collate_mixed")
                        if fc.refreshPath then fc:refreshPath() end
                        self:apply()
                        UIManager:setDirty(self.ui, "ui")
                    end,
                })
            end
            table.insert(buttons, extra_row)
            dialog = ButtonDialog:new{
                title = _("Sort files"),
                title_align = "left",
                buttons = buttons,
            }
            UIManager:show(dialog)
        end, nil, { h = S(8), v = S(10) })
        local sort_w = sort_btn:getSize().w


        local folder_name = at_home and _("Home")
            or (cur_path == "/" and "/")
            or BD.directory((cur_path and cur_path:match("([^/]+)/*$")) or self:pathText(cur_path))
        -- Cabecera común (common/screen.lua): en subcarpetas, "‹ Carpeta" sube un nivel
        local title_w = package.loaded.aire_screen.header(w, {
            title = folder_name,
            on_back = can_up and function()
                if fm and fm.file_chooser and fm.file_chooser.onFolderUp then
                    fm.file_chooser:onFolderUp()
                end
            end or nil,
        })
        local vg = self:buildScreenTop(w)
        table.insert(vg, title_w)
        table.insert(vg, VerticalSpan:new{ width = S(package.loaded.aire_screen.METRICS.SUB_GAP) })

        -- Fila de la ruta y Ordenar
        local show_path = true
        local show_sort = true
        self._path_w = nil
        if show_path or show_sort then
            local og = OverlapGroup:new{ dimen = Geom:new{ w = w, h = S(28) } }
            local rh = S(28)
            if show_path then
                local path_str = at_home and BD.directory(cur_path) or self:pathText(cur_path)
                self._path_w = TextWidget:new{
                    text = path_str,
                    face = face(false, 13),
                    fgcolor = GRAY_TEXT,
                    max_width = math.max(S(80), w - (show_sort and (sort_w + S(10)) or 0)),
                    truncate_left = true,
                    padding = 0,
                }
                rh = math.max(rh, self._path_w:getSize().h)
            end
            if show_sort then rh = math.max(rh, sort_btn:getSize().h) end
            og.dimen.h = rh
            if self._path_w then
                table.insert(og, LeftContainer:new{ dimen = Geom:new{ w = w, h = rh }, self._path_w })
            end
            if show_sort then
                table.insert(og, RightContainer:new{ dimen = Geom:new{ w = w, h = rh }, sort_btn })
            end
            table.insert(vg, og)
        end
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
        local KEYS = { "_explorer_can_up", "_path_w", "_status_group", "_status_w", "_top_clock_hidden", "_top_clock_w" }
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
