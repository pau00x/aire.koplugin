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
    local BD = require("ui/bidi")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local NetworkMgr = require("ui/network/manager")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
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
    local tappable = ctx.tappable
    local config = ctx.config
    local BLACK = ctx.BLACK
    local WHITE = ctx.WHITE
    local GRAY_TEXT = ctx.GRAY_TEXT
    local SEPARATOR = ctx.SEPARATOR
    local emptyGeom = ctx.emptyGeom
    local TOP_PAD = ctx.TOP_PAD
    local SIDE_PAD = ctx.SIDE_PAD
    local showPowerDialog = ctx.showPowerDialog

    -- Indicadores de la derecha de la barra superior, en este orden
    local STATUS_ORDER = { "memory", "frontlight", "battery" }
    local STATUS_LABELS = {
        memory     = _("Memory used"),
        frontlight = _("Light level"),
        battery    = _("Battery"),
    }

    local function statusText(key)
        if key == "memory" then
            local f = io.open("/proc/self/statm", "r")
            if not f then return nil end
            local _size, rss = f:read("*number", "*number")
            f:close()
            if not rss then return nil end
            return ("%dM"):format(math.floor(rss * 4096 / 1024 / 1024 + 0.5))
        elseif key == "wifi" then
            return NetworkMgr:isWifiOn() and "" or nil
        elseif key == "frontlight" then
            if Device:hasFrontlight() then
                local powerd = Device:getPowerDevice()
                if powerd:isFrontlightOn() then
                    return ("☼%d"):format(powerd:frontlightIntensity())
                end
            end
        elseif key == "battery" then
            if Device:hasBattery() then
                local powerd = Device:getPowerDevice()
                local lvl = powerd:getCapacity()
                local sym = powerd:getBatterySymbol(powerd:isCharged(), powerd:isCharging(), lvl)
                return BD.wrap(sym) .. BD.wrap(lvl .. "%")
            end
        end
    end

    local function buildStatusString()
        local parts = {}
        for _i, key in ipairs(STATUS_ORDER) do
            if config.status[key] then
                local t = statusText(key)
                if t and t ~= "" then table.insert(parts, t) end
            end
        end
        return table.concat(parts, SEPARATOR)
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

    function Aire:buildTopBar(w)
        -- Izquierda: la hora (en Inicio con el reloj grande no se repite).
        local hide_clock = self:isHomeVisible() and config.big_clock
        self._top_clock_w = TextWidget:new{
            text = hide_clock and "" or clockString(),
            face = face(true, 16),
            fgcolor = BLACK,
            padding = 0,
        }
        self._top_clock_hidden = hide_clock
        local selector = FrameContainer:new{
            bordersize = 0,
            padding = 0,
            padding_top = S(6),
            padding_bottom = S(6),
            background = WHITE,
            self._top_clock_w,
        }

        -- Derecha: indicadores + botón de energía
        self._status_w = TextWidget:new{
            text = buildStatusString(),
            face = face(false, 14),
            fgcolor = BLACK,
            padding = 0,
        }
        local power_size = S(38)
        local power = tappable(FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            radius = S(8),
            padding = 0,
            width = power_size,
            height = power_size,
            CenterContainer:new{
                dimen = Geom:new{ w = power_size - 2 * Size.border.thin, h = power_size - 2 * Size.border.thin },
                IconWidget:new{ icon = "aire.power", width = S(24), height = S(24), alpha = true },
            },
        }, showPowerDialog, nil, S(8))
        self._status_group = HorizontalGroup:new{
            align = "center",
            self._status_w,
            HorizontalSpan:new{ width = S(12) },
            power,
        }

        local h = math.max(power_size, selector:getSize().h)
        local bar = InputContainer:new{
            OverlapGroup:new{
                dimen = Geom:new{ w = w, h = h },
                LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, selector },
                RightContainer:new{ dimen = Geom:new{ w = w, h = h }, self._status_group },
            },
        }
        bar.ges_events = {
            AireTopMenuTap = { GestureRange:new{
                ges = "tap",
                range = function()
                    local d = bar.dimen
                    if not d then return emptyGeom() end
                    local pd = power.dimen
                    local max_w = pd and math.max(0, pd.x - S(8) - d.x) or d.w
                    return Geom:new{ x = 0, y = 0, w = d.x + max_w, h = d.y + d.h }
                end,
            } },
            AireSwipeMenu = { GestureRange:new{
                ges = "swipe",
                range = function()
                    local d = bar.dimen
                    if not d then return emptyGeom() end
                    return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = d.y + d.h }
                end,
            } },
        }
        bar.onAireTopMenuTap = function() showTopMenu() return true end
        bar.onAireSwipeMenu = function(_self, ges)
            if ges and ges.direction == "south" then showTopMenu() return true end
            return false
        end
        return bar
    end

    -- Barra de estado compartida para vistas a pantalla completa (TitleBar.fullscreen)
    Aire._aire_fs_bars = Aire._aire_fs_bars or setmetatable({}, { __mode = "k" })
    require("ui/widget/titlebar")._aire_build_status_bar = function(tb, total_w)
        local pad = S(SIDE_PAD)
        local w = math.max(100, (total_w or Screen:getWidth()) - 2 * pad)
        local clk = TextWidget:new{ text = clockString(), face = face(true, 16), fgcolor = BLACK, padding = 0 }
        local clk_box = FrameContainer:new{
            bordersize = 0, padding = 0, padding_top = S(6), padding_bottom = S(6),
            background = WHITE,
            clk,
        }
        local st = TextWidget:new{ text = buildStatusString(), face = face(false, 14), fgcolor = BLACK, padding = 0 }
        local power_size = S(38)
        local power = tappable(FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            radius = S(8),
            padding = 0,
            width = power_size,
            height = power_size,
            CenterContainer:new{
                dimen = Geom:new{ w = power_size - 2 * Size.border.thin, h = power_size - 2 * Size.border.thin },
                IconWidget:new{ icon = "aire.power", width = S(24), height = S(24), alpha = true },
            },
        }, showPowerDialog, nil, S(8))
        local st_grp = HorizontalGroup:new{ align = "center", st, HorizontalSpan:new{ width = S(12) }, power }
        local row_h = math.max(power_size, clk_box:getSize().h)
        local inner = InputContainer:new{
            OverlapGroup:new{
                dimen = Geom:new{ w = w, h = row_h },
                LeftContainer:new{ dimen = Geom:new{ w = w, h = row_h }, clk_box },
                RightContainer:new{ dimen = Geom:new{ w = w, h = row_h }, st_grp },
            },
        }
        inner.ges_events = {
            AireTopMenuTap = { GestureRange:new{
                ges = "tap",
                range = function()
                    local d = inner.dimen
                    if not d then return emptyGeom() end
                    local pd = power.dimen
                    local max_w = pd and math.max(0, pd.x - S(8) - d.x) or d.w
                    return Geom:new{ x = 0, y = 0, w = d.x + max_w, h = d.y + d.h }
                end,
            } },
            AireSwipeMenu = { GestureRange:new{
                ges = "swipe",
                range = function()
                    local d = inner.dimen
                    if not d then return emptyGeom() end
                    return Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = d.y + d.h }
                end,
            } },
        }
        inner.onAireTopMenuTap = function() showTopMenu() return true end
        inner.onAireSwipeMenu = function(_self, ges)
            if ges and ges.direction == "south" then showTopMenu() return true end
            return false
        end
        local bar = FrameContainer:new{
            bordersize = 0,
            background = WHITE,
            padding_left = pad,
            padding_right = pad,
            padding_top = S(TOP_PAD),
            padding_bottom = 0,
            inner,
        }
        tb._aire_update_status = function()
            clk:setText(clockString())
            st:setText(buildStatusString())
            st_grp:resetLayout()
        end
        Aire._aire_fs_bars[tb] = true
        return bar
    end

    function Aire:buildViewTitle(w, title)
        local tw = TextWidget:new{
            text = title,
            face = face(true, 17),
            fgcolor = BLACK,
            max_width = w,
            padding = 0,
        }
        return FrameContainer:new{
            bordersize = 0, padding = 0, padding_top = S(3), padding_bottom = S(3), width = w,
            LeftContainer:new{
                dimen = Geom:new{ w = w, h = math.max(tw:getSize().h, S(24)) },
                tw,
            },
        }
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
        if not config.enabled or self._suspended or not self._status_w then return end
        self._status_w:setText(buildStatusString())
        if self._status_group then self._status_group:resetLayout() end
        if self._clock_w then self._clock_w:setText(clockString()) end
        if self._top_clock_w and not self._top_clock_hidden then self._top_clock_w:setText(clockString()) end
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
    function Aire:onNotCharging() refreshHeaderAndWidgets(self) end
    function Aire:onTimeFormatChanged() self:refreshHeader() end
    function Aire:onFrontlightStateChanged() refreshHeaderAndWidgets(self) end
    -- Al cerrar el diálogo de luz (views/widgets.lua lo anuncia): actualizar los widgets
    function Aire:onHomeWidgetsRefresh()
        if self.refreshWidgets then self:refreshWidgets() end
    end

    -- Para menu.lua (opciones de la barra superior)
    ctx.STATUS_ORDER = STATUS_ORDER
    ctx.STATUS_LABELS = STATUS_LABELS
end
