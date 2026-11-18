--[[
    aire.koplugin/views/dock.lua
    Dock (barra de navegación inferior): botones, pestañas según la vista,
    tocar / mantener, selector de modo y el dock de las pantallas completas.
    Se carga desde main.lua como "mixin" (añade métodos a Aire).
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

return function(Aire, ctx)
    -- Módulos y valores compartidos declarados aquí dentro: así no cuentan
    -- como upvalues de esta función (LuaJIT admite 60).
    local Blitbuffer = require("ffi/blitbuffer")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Device = require("device")
    local FileManager = require("apps/filemanager/filemanager")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local IconWidget = require("ui/widget/iconwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local _ = require("gettext")
    local Screen = Device.screen
    local S = ctx.S
    local face = ctx.face
    local config = ctx.config
    local BLACK = ctx.BLACK
    local WHITE = ctx.WHITE
    local selStyle = ctx.selStyle
    local SEL_GRAY_LIGHTEN = ctx.SEL_GRAY_LIGHTEN
    local SIDE_PAD = ctx.SIDE_PAD

    -- Barra de navegación inferior
    local NAV_ORDER = { "library", "collections", "home", "history", "stats" }
    local NAV_META = {
        library     = { icon = "aire.library",     label = _("Library") },
        collections = { icon = "aire.collections", label = _("Collections") },
        home        = { icon = "aire.home",        label = _("Home") },
        history     = { icon = "aire.history",     label = _("History") },
        stats       = { icon = "aire.stats",       label = _("Stats") },
    }

    -- Dock del modo Explorador: Subir · Carpetas · Inicio · Buscar · Más
    local EXPLORER_DOCK = {
        { id = "fm_up",      icon = "aire.chevron.down", rotation_angle = 180, label = _("Go up") },
        { id = "fm_folders", icon = "aire.folder",       label = _("Folders") },
        { id = "fm_home",    icon = "aire.home",         label = _("Home") },
        { id = "fm_search",  icon = "aire.search",       label = _("Search") },
        { id = "fm_plus",    icon = "aire.plus",         label = _("More") },
    }

    ---------------------------------------------------------------------------
    -- Botón de la barra de navegación (icono + etiqueta; activo = píldora negra)
    ---------------------------------------------------------------------------
    local NavItem = InputContainer:extend{
        item = nil,          -- { id, icon, label, placeholder }
        width = nil,
        height = nil,
        active = false,
        callback = nil,      -- callback(id)
        hold_callback = nil, -- hold_callback(id)
        no_label = false,    -- opción del menú "Etiquetas bajo los iconos"
    }

    function NavItem:init()
        self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
        self.id = self.item.id
        self.icon_size = S(26)
        if not self.item.placeholder then
            self.icon = IconWidget:new{
                icon = self.item.icon,
                rotation_angle = self.item.rotation_angle or 0,
                width = self.icon_size,
                height = self.icon_size,
                alpha = true,
            }
        end
        self.label = TextWidget:new{
            text = self.item.label or " ",
            face = face(self.active, 12),
            fgcolor = (self.active and selStyle() ~= "outline") and WHITE or BLACK,
            max_width = self.width - 2 * S(4),
            padding = 0,
        }
        self.ges_events = {
            AireTap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
            AireHold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
        }
    end

    function NavItem:getSize()
        return Geom:new{ w = self.width, h = self.height }
    end

    function NavItem:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        local isz = self.icon_size
        local lsz = self.label:getSize()
        local gap = S(4)
        if self.no_label then lsz, gap = { w = 0, h = 0 }, 0 end
        local content_h = isz + gap + lsz.h
        local iy = y + math.floor((self.height - content_h) / 2)
        local ix = x + math.floor((self.width - isz) / 2)
        local lx = x + math.floor((self.width - lsz.w) / 2)

        if self.item.placeholder then
            -- Hueco libre: recuadro gris punteado-suave del tamaño del icono
            bb:paintBorder(ix, iy, isz, isz, Size.border.thin, Blitbuffer.COLOR_LIGHT_GRAY, S(6))
        elseif self.active and selStyle() == "outline" then
            -- Contorno: borde grueso, icono y etiqueta en negro
            local inset = S(3)
            bb:paintBorder(x + inset, y + inset, self.width - 2 * inset, self.height - 2 * inset,
                Size.border.thick, BLACK, S(10))
            self.icon:paintTo(bb, ix, iy)
        elseif self.active then
            local inset = S(3)
            local pw, ph = self.width - 2 * inset, self.height - 2 * inset
            bb:paintRoundedRect(x + inset, y + inset, pw, ph, BLACK, S(10))
            -- Icono blanco sobre negro: pintarlo sobre blanco e invertir solo su recuadro
            bb:paintRect(ix, iy, isz, isz, WHITE)
            self.icon:paintTo(bb, ix, iy)
            bb:invertRect(ix, iy, isz, isz)
            if selStyle() == "gray" then
                -- Gris oscuro: pintar la etiqueta y aclarar toda la píldora
                if not self.no_label then self.label:paintTo(bb, lx, iy + isz + gap) end
                bb:lightenRect(x + inset, y + inset, pw, ph, SEL_GRAY_LIGHTEN)
                return
            end
        else
            self.icon:paintTo(bb, ix, iy)
        end
        if not self.no_label then self.label:paintTo(bb, lx, iy + isz + gap) end
    end

    function NavItem:onAireTap()
        if self.callback and not self.item.placeholder then self.callback(self.id) end
        return true
    end

    function NavItem:onAireHold()
        if self.hold_callback and not self.item.placeholder then self.hold_callback(self.id) end
        return true
    end

    function NavItem:free()
        if self.icon then self.icon:free() end
        if self.label then self.label:free() end
    end

    -- Dock según la vista:
    --   Inicio y pestaña Librería -> pestañas (Librería, Colecciones, Inicio, Historial, Estadísticas)
    --   Modo Explorador           -> Home (carpeta de inicio), Buscar, 2 huecos libres, +
    function Aire:dockItems()
        if self:isOwnView() then
            local items = {}
            for _i, id in ipairs(NAV_ORDER) do
                local meta = NAV_META[id]
                table.insert(items, { id = id, icon = meta.icon, label = meta.label })
            end
            -- Terminados y Calendario se abren desde Estadísticas: marcar esa pestaña
            local active = self.view
            if active == "finished" or active == "calendar" then active = "stats" end
            return items, active
        end
        -- Home marcado cuando el explorador está en la carpeta de inicio
        return EXPLORER_DOCK, (self:isAtHomeFolder() and "fm_home" or nil)
    end

    function Aire:buildNavBar(w, opts)
        opts = opts or {}
        local items, active_id
        if opts.home_items then
            items = {}
            for _i, id in ipairs(NAV_ORDER) do
                local meta = NAV_META[id]
                table.insert(items, { id = id, icon = meta.icon, label = meta.label })
            end
        else
            items, active_id = self:dockItems()
        end
        if opts.no_active then active_id = nil end
        local border = Size.border.thin
        local pad = S(4)
        local inner_w = w - 2 * (border + pad)
        local h = S(64)
        local n = #items
        local base_w = math.floor(inner_w / n)
        local rem = inner_w - base_w * n
        local group = HorizontalGroup:new{ align = "center" }
        for i, item in ipairs(items) do
            table.insert(group, NavItem:new{
                item = item,
                width = base_w + (i <= rem and 1 or 0),
                height = h,
                active = (item.id == active_id),
                no_label = config.dock_labels == false,
                callback = function(tapped)
                    if opts.on_tap then opts.on_tap(tapped) else self:onNavTap(tapped) end
                end,
                hold_callback = function(held)
                    if not opts.on_tap then self:onNavHold(held) end
                end,
            })
        end
        return FrameContainer:new{
            bordersize = border,
            color = BLACK,
            radius = S(12),
            padding = pad,
            group,
        }
    end

    -- Dock de las pantallas completas (common/screen.lua decide cuándo sale y
    -- dónde va): las pestañas de Inicio, sin ninguna marcada; al tocar una se
    -- cierra la pantalla. Solo con la Pantalla de inicio activada (si no,
    -- llevaría a pestañas que no existen).
    package.loaded.aire_screen.setDockSource{
        active = function()
            local inst = Aire._active_instance
            return config.enabled and inst ~= nil and not inst._aire_closed
        end,
        build = function(owner_widget)
            local inst = Aire._active_instance
            if not inst then return nil end
            return inst:buildNavBar(Screen:getWidth() - 2 * S(SIDE_PAD), {
                home_items = true,
                no_active = true,
                on_tap = function(tapped)
                    if owner_widget then require("ui/uimanager"):close(owner_widget) end
                    inst:onNavTap(tapped)
                end,
            })
        end,
    }

    ---------------------------------------------------------------------------
    -- Acciones
    ---------------------------------------------------------------------------
    function Aire:showModeSelector()
        local dialog
        local function choose(mode)
            UIManager:close(dialog)
            if mode == "library" then
                self:showHome()
            else
                self:showExplorer()
            end
        end
        local function label(mode, text)
            return config.mode == mode and (text .. "  " .. _("(current)")) or text
        end
        dialog = ButtonDialog:new{
            title = _("Main view"),
            title_align = "center",
            buttons = {
                {{ text = label("library", _("Library")), callback = function() choose("library") end }},
                {{ text = label("explorer", _("File browser")), callback = function() choose("explorer") end }},
            },
        }
        UIManager:show(dialog)
    end

    function Aire:onNavTap(id)
        local fm = self.ui
        if id == "home" then
            if not self:isHomeVisible() then self:showHome() end
        elseif id == "library" or id == "collections" or id == "history" then
            self:showGridView(id)
        elseif id == "fm_up" then
            if fm.file_chooser and fm.file_chooser.onFolderUp then fm.file_chooser:onFolderUp() end
        elseif id == "fm_home" then
            FileManager.onHome(fm) -- la casa de siempre: carpeta de inicio
        elseif id == "fm_folders" then
            fm:onShowFolderMenu() -- el menú que antes abría mantener pulsada la casa
        elseif id == "fm_search" then
            if fm.filesearcher then fm.filesearcher:onShowFileSearch() end
        elseif id == "fm_plus" then
            fm:onShowPlusMenu()
        elseif id == "stats" then
            if self.showStatsView then self:showStatsView() end
        end
    end

    -- Mantener pulsado Inicio (modo Librería) o Home (modo Explorador): cambiar
    -- de modo directamente, sin menú
    function Aire:onNavHold(id)
        if id == "home" then
            self:showExplorer()
        elseif id == "fm_home" then
            self:showHome()
        end
    end
end
