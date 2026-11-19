--[[
    aire.koplugin/styles/plugins/calendar.lua
    Rediseño moderno de CalendarView ("Calendario") coherente con el calendario de Estadísticas:
      - Título "Calendario" y subtítulo "duración · N págs. · N días leyendo"
      - Fila de mes con flechas ‹  Mes Año  › entre el subtítulo y los días de la semana
      - Sin botones inferiores
      - Celdas con mapa de calor de 4 niveles de gris/negro (igual que stats.lua)
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local datetime = require("datetime")
local logger = require("logger")
local userpatch = require("userpatch")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (ui/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Calendar"
local AireUI = package.loaded.aire_ui
local S, face, BLACK, WHITE, GRAY_DARK, GRAY_LIGHT = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_LIGHT

local GRAY = Blitbuffer.COLOR_GRAY

local LEVEL_COLORS = {
    Blitbuffer.COLOR_GRAY_E,
    Blitbuffer.COLOR_GRAY_B,
    Blitbuffer.COLOR_GRAY_5,
    Blitbuffer.COLOR_BLACK,
}


local function makeArrow(icon_name, nav_h, on_tap)
    local iw = IconWidget:new{ icon = icon_name, width = S(24), height = S(24), alpha = true }
    local box = CenterContainer:new{ dimen = Geom:new{ w = S(24), h = nav_h }, iw }
    local ic = InputContainer:new{ box }
    ic._aire_enabled = true
    ic.ges_events = {
        AireTap = { GestureRange:new{
            ges = "tap",
            range = function()
                local d = ic.dimen
                if not d then return Geom:new{ x = 0, y = 0, w = 0, h = 0 } end
                local ph, pv = S(14), S(6)
                return Geom:new{ x = d.x - ph, y = d.y - pv, w = d.w + 2 * ph, h = d.h + 2 * pv }
            end,
        } },
    }
    ic.onAireTap = function()
        if ic._aire_enabled and on_tap then on_tap() end
        return true
    end
    local function setEnabled(en)
        ic._aire_enabled = en and true or false
        iw.dim = not ic._aire_enabled
    end
    return ic, setEnabled
end

local function patchCalendar(_ReaderStatistics)
    local ok, CalendarView = pcall(require, "calendarview")
    if not ok or type(CalendarView) ~= "table" or CalendarView._aire_styled then return end
    CalendarView._aire_styled = true

    local CalendarDay = package.loaded.aire_ui.getUpValue(CalendarView._populateItems, "CalendarDay")
    if CalendarDay and not CalendarDay._aire_styled then
        CalendarDay._aire_styled = true
        safeWrap(CalendarDay, "init", function(orig_day_init, self)
            orig_day_init(self)
            local box = self[1]
            if type(box) == "table" then
                box.radius = S(5)
                box.bordersize = Size.border.thin
                if self.filler or self.is_future then
                    box.color = GRAY_LIGHT
                    box.background = WHITE
                    if self.daynum_w then self.daynum_w.fgcolor = GRAY end
                else
                    box.color = BLACK
                    box.background = WHITE
                    if self.daynum_w then self.daynum_w.fgcolor = BLACK end
                    if self.nb_not_shown_w then self.nb_not_shown_w.fgcolor = GRAY_DARK end
                end
            end
        end, TAG)
    end

    safeWrap(CalendarView, "init", function(orig_init, self)
        self.outer_padding = S(SIDE)
        self.inner_padding = S(5)

        -- KOReader rellena los días (consultas a la base de datos) dentro de
        -- init; se aplaza al _populateItems del final, cuando ya está la fila
        -- del mes, para hacerlo una sola vez. La pantalla solo guarda una
        -- referencia a main_content, que se llena después.
        local had_own_populate = rawget(self, "_populateItems")
        self._populateItems = function() end
        -- Cabecera de Aire (ui/screen.lua): "Calendario" y un subtítulo
        -- provisional que se cambia al rellenar el mes
        local ok_init, err = pcall(package.loaded.aire_screen.withTitleBar, {
            fullscreen = true,
            title = _("Calendar"),
            set = { subtitle = "" },
            subtitle = _("Loading month…"),
        }, orig_init, self)
        self._populateItems = had_own_populate
        if not ok_init then error(err) end

        -- Celdas cuadradas (mismo tamaño que el calendario de Estadísticas)
        if self.day_width and self.week_height and self.week_height > self.day_width then
            self.week_height = self.day_width
            local nb = (self.nb_book_spans or 3) + (self.show_hourly_histogram and 2 or 1)
            self.span_height = math.max(S(10), math.floor((self.week_height - 2 * (self.day_border or Size.border.default)) / nb))
            local TextBoxWidget = require("ui/widget/textboxwidget")
            local th = math.min(self.span_height, self.week_height / 3)
            self.span_font_size = TextBoxWidget:getFontSizeToFitHeight(th, 1, 0.3)
        end

        -- Fila de mes con flechas ‹ Mes Año › (igual que stats.lua)
        local sw = self.dimen and self.dimen.w or Screen:getWidth()
        local w = sw - 2 * S(SIDE)
        local nav_h = S(36)
        local prev_ic, set_prev = makeArrow("chevron.left", nav_h, function() self:prevMonth() end)
        local next_ic, set_next = makeArrow("chevron.right", nav_h, function() self:nextMonth() end)
        local month_lbl = TextWidget:new{ text = "", face = face(true, 17), fgcolor = BLACK, padding = 0 }
        local month_bar = FrameContainer:new{
            bordersize = 0,
            padding = 0,
            padding_left = S(SIDE),
            padding_right = S(SIDE),
            padding_bottom = S(8),
            OverlapGroup:new{
                dimen = Geom:new{ w = w, h = nav_h },
                LeftContainer:new{ dimen = Geom:new{ w = w, h = nav_h }, prev_ic },
                CenterContainer:new{ dimen = Geom:new{ w = w, h = nav_h }, month_lbl },
                RightContainer:new{ dimen = Geom:new{ w = w, h = nav_h }, next_ic },
            },
        }
        self._aire_month_lbl = month_lbl
        self._aire_set_prev = set_prev
        self._aire_set_next = set_next

        -- Insertar month_bar entre title_bar y day_names dentro del VerticalGroup principal
        local og = self[1] and self[1][1]
        local vg = og and og[1]
        if type(vg) == "table" then
            table.insert(vg, 2, month_bar)
            vg:resetLayout()
        end

        if self.page_info then
            self.page_info:clear()
            self.page_info:resetLayout()
        end
        self:_populateItems()
    end, TAG)

    safeWrap(CalendarView, "_populateItems", function(orig_populate, self)
        local books_by_day = self.reader_statistics and self.cur_month
            and self.reader_statistics:getReadBookByDay(self.cur_month)
        local day_secs, max_secs, active_days, total_secs, total_pages = {}, 0, 0, 0, 0
        if type(books_by_day) == "table" then
            for day_s, list in pairs(books_by_day) do
                if type(list) == "table" and #list > 0 then
                    local s, p = 0, 0
                    for _, b in ipairs(list) do
                        s = s + (tonumber(b.duration) or tonumber(b.time) or 0)
                        p = p + (tonumber(b.pages) or 0)
                    end
                    local d = tonumber(day_s:sub(9, 10))
                    if d then day_secs[d] = s end
                    if s > max_secs then max_secs = s end
                    active_days = active_days + 1
                    total_secs = total_secs + s
                    total_pages = total_pages + p
                end
            end
        end

        orig_populate(self)

        if self.weeks and max_secs > 0 then
            for _, wk in ipairs(self.weeks) do
                for _, day_w in ipairs(wk) do
                    if day_w and day_w.daynum and not day_w.filler and not day_w.is_future then
                        local s = day_secs[day_w.daynum] or 0
                        local lvl = s > 0 and math.max(1, math.min(4, math.ceil(4 * s / max_secs))) or 0
                        local box = day_w[1]
                        if type(box) == "table" and lvl > 0 then
                            box.background = LEVEL_COLORS[lvl]
                            if day_w.daynum_w then day_w.daynum_w.fgcolor = lvl >= 3 and WHITE or BLACK end
                            if day_w.nb_not_shown_w then
                                day_w.nb_not_shown_w.fgcolor = lvl >= 3 and WHITE or GRAY_DARK
                            end
                        end
                    end
                end
            end
        end

        local month_start_ts = os.time({
            year = self.cur_month:sub(1, 4),
            month = self.cur_month:sub(6),
            day = 1,
        })
        local month_text = datetime.longMonthTranslation[os.date("%B", month_start_ts)] .. os.date(" %Y", month_start_ts)
        if self._aire_month_lbl then
            self._aire_month_lbl:setText(month_text)
        end
        if self._aire_set_prev then
            self._aire_set_prev(self.cur_month > self.min_month)
        end
        if self._aire_set_next then
            self._aire_set_next(self.cur_month < self.max_month or self.browse_future_months)
        end
        if self.title_bar then
            self.title_bar:setTitle(_("Calendar"), true)
            local sub
            if active_days == 0 then
                sub = _("No reading sessions this month")
            else
                local dur = datetime.secondsToClockDuration("letters", total_secs, true, true)
                sub = dur .. " · " .. T(_("%1 pp."), total_pages) .. " · "
                    .. T(N_("%1 day reading", "%1 days reading", active_days), active_days)
            end
            self.title_bar:setSubTitle(sub, true)
        end
    end, TAG)

    logger.dbg("Aire/Calendar: aplicado desde el plugin")
end

-- "Línea de tiempo de hoy" (CalendarDayView, local de calendarview.lua):
-- tramos de lectura redondeados con borde gris, líneas de las horas finas y
-- horas en gris. Mismo funcionamiento que en KOReader.
local function patchDayView()
    local ok, CalendarView = pcall(require, "calendarview")
    if not ok or type(CalendarView) ~= "table" or type(CalendarView.showCalendarDayView) ~= "function" then return end
    local DayView = package.loaded.aire_ui.getUpValue(CalendarView.showCalendarDayView, "CalendarDayView")
    if type(DayView) ~= "table" or DayView._aire_timeline then return end
    DayView._aire_timeline = true

    safeWrap(DayView, "generateSpan", function(orig_span, self, ...)
        local span = orig_span(self, ...)
        if span then
            local h = span.height or S(20)
            span.radius = math.max(2, math.floor(h / 4))
            span.bordersize = Size.border.thin
            span.color = Blitbuffer.COLOR_DARK_GRAY
        end
        return span
    end, TAG)

    safeWrap(DayView, "refreshTimeline", function(orig_refresh, self, ...)
        local res = orig_refresh(self, ...)
        pcall(function()
            for _i, w in ipairs(self.timeline or {}) do
                if type(w) == "table" and getmetatable(w) == FrameContainer then
                    -- Líneas horizontales de las horas: finas
                    if rawequal(w.background, Blitbuffer.COLOR_LIGHT_GRAY) and w.width and w.height
                            and w.width > w.height and w.height <= Size.border.default * 2 then
                        w.height = Size.line.thin
                    end
                    -- Horas: en gris
                    local cc = w[1]
                    local tw = type(cc) == "table" and cc[1]
                    if rawequal(w.background, Blitbuffer.COLOR_WHITE) and type(tw) == "table" and getmetatable(tw) == TextWidget then
                        tw.fgcolor = Blitbuffer.COLOR_DARK_GRAY
                    end
                end
            end
        end)
        return res
    end, TAG)
end

-- Protegido: los parches de plugins se ejecutan dentro de FileManager:init y
-- un error sin pcall impediría arrancar KOReader
userpatch.registerPatchPluginFunc("statistics", function(plugin)
    local ok, err = pcall(patchCalendar, plugin)
    if not ok then logger.warn("Aire/Calendar: no se pudo aplicar:", err) end
    local ok2, err2 = pcall(patchDayView)
    if not ok2 then logger.warn("Aire/Calendar: línea de tiempo:", err2) end
end)
