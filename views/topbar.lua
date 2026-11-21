--[[
    aire.koplugin/views/topbar.lua
    Barra superior (hora, estado, energía), reloj grande y fecha, barra de
    estado de las pantallas completas y refresco cada minuto / al cambiar Wi-Fi, carga o luz.
    Se carga desde main.lua como "mixin" (añade métodos a Aire).
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

return function(Aire, ctx)
    -- Módulos y valores compartidos declarados aquí dentro: así no cuentan
    -- como upvalues de esta función (LuaJIT admite 60).
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local NetworkMgr = require("ui/network/manager")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local datetime = require("datetime")
    local _ = require("gettext")
    local C_ = _.pgettext
    local T = require("ffi/util").template
    local Screen = Device.screen
    local S = ctx.S
    local face = ctx.face
    local config = ctx.config
    local BLACK = ctx.BLACK
    local WHITE = ctx.WHITE
    local GRAY_TEXT = ctx.GRAY_TEXT
    local TOP_PAD = ctx.TOP_PAD
    local SIDE_PAD = ctx.SIDE_PAD
    local showPowerDialog = ctx.showPowerDialog

    -- Indicadores de la derecha de la barra superior, en este orden
    local STATUS_ORDER = { "ssh", "memory", "wifi", "frontlight", "battery", "update" }
    local STATUS_LABELS = {
        ssh        = _("SSH active"),
        memory     = _("Memory used"),
        wifi       = _("Wi-Fi"),
        frontlight = _("Light level"),
        battery    = _("Battery"),
        update     = _("Update indicator"),
    }

    local AireScreen = package.loaded.aire_screen

    local function statusItem(key)
        if key == "ssh" then
            local fm = require("apps/filemanager/filemanager").instance
            local ssh = fm and fm.SSH
            if ssh and ssh.isRunning and ssh:isRunning() then
                return { kind = "icon", icon = "aire.status.ssh" }
            end
        elseif key == "memory" then
            local f = io.open("/proc/self/statm", "r")
            if not f then return nil end
            local _size, rss = f:read("*number", "*number")
            f:close()
            if not rss then return nil end
            return {
                kind = "icon_text",
                icon = "aire.status.memory",
                text = ("%dM"):format(math.floor(rss * 4096 / 1024 / 1024 + 0.5)),
            }
        elseif key == "wifi" then
            if NetworkMgr:isWifiOn() then
                return { kind = "icon", icon = AireScreen.wifiStatusIcon() }
            end
        elseif key == "frontlight" then
            if Device:hasFrontlight() then
                local powerd = Device:getPowerDevice()
                if powerd:isFrontlightOn() then
                    return {
                        kind = "icon_text",
                        icon = "aire.status.sun",
                        text = tostring(powerd:frontlightIntensity()),
                    }
                end
            end
        elseif key == "battery" then
            if Device:hasBattery() then
                local powerd = Device:getPowerDevice()
                local lvl = powerd:getCapacity()
                return {
                    kind = "battery",
                    level = lvl,
                    charging = powerd:isCharging() == true,
                    text = lvl .. "%",
                }
            end
        end
    end

    local function buildStatusData()
        local items = {}
        local order = (type(config.status_order) == "table" and #config.status_order > 0)
            and config.status_order or STATUS_ORDER
        for _i, key in ipairs(order) do
            if key ~= "update" and config.status[key] then
                local it = statusItem(key)
                if it then table.insert(items, it) end
            end
        end
        local update_dot = config.status.update == true
            and ctx.update ~= nil and ctx.update.available ~= nil and ctx.update.available() ~= nil
        return { items = items, update_dot = update_dot }
    end

    local function clockString()
        return datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    end

    -- Mes dentro de una fecha ("16 de noviembre"): con contexto propio porque en
    -- muchos idiomas va en minúscula, a diferencia del nombre suelto de KOReader
    local DATE_MONTHS = {
        C_("aire", "January"), C_("aire", "February"), C_("aire", "March"),
        C_("aire", "April"), C_("aire", "May"), C_("aire", "June"),
        C_("aire", "July"), C_("aire", "August"), C_("aire", "September"),
        C_("aire", "October"), C_("aire", "November"), C_("aire", "December"),
    }

    local function dateString()
        -- Día de la semana traducido por KOReader (datetime.lua); el orden lo
        -- decide la traducción ("Monday, November 16" / "Lunes, 16 de noviembre")
        local t = os.date("*t")
        local day = datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[t.wday]]
        return T(_("%1, %2 %3"), day, DATE_MONTHS[t.month], t.day)
    end


    ---------------------------------------------------------------------------
    -- Construcción de la pantalla
    ---------------------------------------------------------------------------
    local function showTopMenu()
        local ReaderUI = require("apps/reader/readerui")
        local fm = require("apps/filemanager/filemanager").instance
        local host = (ReaderUI and ReaderUI.instance) or fm
        if host and host.menu and host.menu.onShowMenu then
            host.menu:onShowMenu()
        end
    end

    -- Datos de la barra de estado común (ui/screen.lua)
    AireScreen.setStatusSource{
        clock = clockString,
        data = buildStatusData,
        power = showPowerDialog,
        menu = showTopMenu,
    }

    function Aire:buildTopBar(w)
        -- Izquierda: la hora (en Inicio con el reloj grande no se repite).
        local hide_clock = self:isHomeVisible() and config.big_clock
        local bar, parts = AireScreen.statusBar(w, { hide_clock = hide_clock })
        self._top_clock_w = parts.clock
        self._top_clock_hidden = hide_clock
        self._status_w = parts.status
        self._status_group = parts.group
        self._status_update = parts.update
        return bar
    end

    -- Barra de estado compartida para vistas a pantalla completa (TitleBar.fullscreen)
    Aire._aire_fs_bars = Aire._aire_fs_bars or setmetatable({}, { __mode = "k" })
    require("ui/widget/titlebar")._aire_build_status_bar = function(tb, total_w)
        local pad = S(SIDE_PAD)
        local w = math.max(100, (total_w or Screen:getWidth()) - 2 * pad)
        local inner, parts = AireScreen.statusBar(w)
        local bar = FrameContainer:new{
            bordersize = 0,
            background = WHITE,
            padding_left = pad,
            padding_right = pad,
            padding_top = S(TOP_PAD),
            padding_bottom = 0,
            inner,
        }
        tb._aire_update_status = parts.update
        Aire._aire_fs_bars[tb] = true
        return bar
    end

    -- Parte de arriba común de las vistas propias (Librería, Estadísticas,
    -- Explorador…): margen, barra de estado, hueco y cabecera (si hay title).
    --   opts.title, opts.on_back   cabecera "Título" o "‹ Título"
    --   opts.menu_icon / menu_text, on_menu, on_menu_hold   botón de la derecha
    --   opts.gap_after             hueco debajo del título (por defecto SUB_GAP)
    -- Devuelve el VerticalGroup para seguir añadiendo contenido. Apunta el alto
    -- de la barra de estado (_header_h) para refrescar solo esa franja.
    function Aire:buildScreenTop(w, opts)
        opts = opts or {}
        local VerticalSpan = require("ui/widget/verticalspan")
        local MT = AireScreen.METRICS
        local content = VerticalGroup:new{ align = "left" }
        table.insert(content, VerticalSpan:new{ width = S(TOP_PAD) })
        table.insert(content, self:buildTopBar(w))
        self._clock_w, self._date_w = nil, nil
        self._header_h = content:getSize().h + S(4)
        table.insert(content, VerticalSpan:new{ width = S(MT.HEADER_GAP) })
        if opts.title then
            table.insert(content, (AireScreen.header(w, {
                title = opts.title, on_back = opts.on_back,
                menu_icon = opts.menu_icon, menu_text = opts.menu_text,
                on_menu = opts.on_menu, on_menu_hold = opts.on_menu_hold,
            })))
            table.insert(content, VerticalSpan:new{ width = S(opts.gap_after or MT.SUB_GAP) })
        end
        -- getSize() de arriba dejó medida la disposición con solo la barra de
        -- estado: sin esto, lo que se añada después no tiene posición y pintar
        -- revienta (VerticalGroup:paintTo, _offsets[i] nil)
        content:resetLayout()
        return content
    end

    function Aire:buildClock(w)
        self._clock_w = TextWidget:new{ text = clockString(), face = face(true, 56), fgcolor = BLACK, padding = 0 }
        self._date_w = TextWidget:new{ text = dateString(), face = face(false, 16), fgcolor = GRAY_TEXT, padding = 0 }
        local clock_h = self._clock_w:getSize().h
        local date_h = self._date_w:getSize().h
        return VerticalGroup:new{
            align = "center",
            CenterContainer:new{ dimen = Geom:new{ w = w, h = clock_h }, self._clock_w },
            CenterContainer:new{ dimen = Geom:new{ w = w, h = date_h }, self._date_w },
        }
    end

    ---------------------------------------------------------------------------
    -- Reloj y estado en vivo
    ---------------------------------------------------------------------------
    function Aire:refreshHeader()
        if not config.enabled or self._suspended or self._aire_closed or not self._status_w then return end
        if self._status_update then
            self._status_update()
        elseif self._status_group then
            self._status_group:resetLayout()
        end
        if self._clock_w then self._clock_w:setText(clockString()) end
        if self._date_w then self._date_w:setText(dateString()) end
        local UIManager = require("ui/uimanager")
        local top = UIManager.getTopmostVisibleWidget and UIManager:getTopmostVisibleWidget()
        if not top or top == self.ui then
            UIManager:setDirty(self.ui, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = self._header_h or S(64) })
        else
            for tb in pairs(Aire._aire_fs_bars) do
                if tb._aire_update_status then tb._aire_update_status() end
            end
            if top.covers_fullscreen then
                UIManager:setDirty(top, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = S(64) })
            end
        end
        self:scheduleTick()
    end

    function Aire:scheduleTick()
        if not self._tick_fn then
            self._tick_fn = function() self:refreshHeader() end
        end
        UIManager:unschedule(self._tick_fn)
        if config.enabled and not self._suspended then
            UIManager:scheduleIn(61 - tonumber(os.date("%S")), self._tick_fn)
        end
    end

    function Aire:unscheduleTick()
        if self._tick_fn then UIManager:unschedule(self._tick_fn) end
    end

    local function refreshHeaderAndWidgets(self)
        self:refreshHeader()
        if self.refreshWidgets then self:refreshWidgets() end
    end
    function Aire:onNetworkConnected() refreshHeaderAndWidgets(self) end
    function Aire:onNetworkDisconnected() refreshHeaderAndWidgets(self) end
    function Aire:onCharging() refreshHeaderAndWidgets(self) end
    function Aire:onNotCharging()
        if self.invalidateLibraryCache then self:invalidateLibraryCache() end
        refreshHeaderAndWidgets(self)
    end
    function Aire:onTimeFormatChanged() self:refreshHeader() end
    function Aire:onFrontlightStateChanged() refreshHeaderAndWidgets(self) end
    -- Al cerrar el diálogo de luz (views/widgets/init.lua lo anuncia): actualizar los widgets y la barra
    function Aire:onHomeWidgetsRefresh()
        if self.refreshWidgets then self:refreshWidgets() end
        self:refreshHeader()
    end

    -- Para menu.lua (opciones de la barra superior)
    ctx.STATUS_ORDER = STATUS_ORDER
    ctx.STATUS_LABELS = STATUS_LABELS
end
