--[[
    aire.koplugin/views/stats/init.lua
    Pestaña "Estadísticas" de la pantalla de inicio (panel de resumen):

      14:32                                   43%  [⏻]
      ┌────────┐ ┌────────┐ ┌────────┐
      │ 42 min │ │ 7 días │ │   12   │   <- hoy (+ páginas), racha, terminados este año
      └────────┘ └────────┘ └────────┘
      ÚLTIMOS 7 DÍAS · 4 h 10 min
      ▁ ▅ ▂   ▇ ▄ ▆                       <- barras por día (tocar: calendario de KOReader)
      L M X J V S D
      LEYENDO AHORA
      [portada] Título · 3 h 20 min · quedan ~2 h 50 min   (tocar: abrir)
      ESTE MES
      9 h 05 min      612 págs.      41 págs./h
      [dock]

    Datos: statistics.sqlite3 del plugin de Estadísticas (páginas leídas con
    hora y duración). Los terminados salen del estado de los libros del
    historial (fecha de "summary.modified").
    Se carga desde main.lua como "mixin". OJO: no usar "_" como variable.
--]]

local _ = require("gettext")

local STATS_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]*$") or "plugins/aire.koplugin/views/stats"
-- Datos (base de datos, resúmenes) y gráficos (barras, calendario)
local StatsData = dofile(STATS_DIR .. "/data.lua")
local fmtDuration, fmtDelta, calcSpeed = StatsData.fmtDuration, StatsData.fmtDelta, StatsData.calcSpeed
local loadStats, MONTHS, WEEKDAYS_LONG = StatsData.loadStats, StatsData.MONTHS, StatsData.WEEKDAYS_LONG
local loadMonth, loadDay, loadRecap = StatsData.loadMonth, StatsData.loadDay, StatsData.loadRecap
local deleteBookStats, countFinishedYear = StatsData.deleteBookStats, StatsData.countFinishedYear
local Charts = dofile(STATS_DIR .. "/charts.lua")(StatsData)
local WeekBars, HorizontalBars, WeekdayBars = Charts.WeekBars, Charts.HorizontalBars, Charts.WeekdayBars
local RecapBars, CalendarGrid = Charts.RecapBars, Charts.CalendarGrid

---------------------------------------------------------------------------
-- Mixin
---------------------------------------------------------------------------
return function(Aire, ctx)
    -- Módulos que usa el mixin, declarados aquí dentro: así no cuentan como
    -- upvalues de esta función (LuaJIT admite 60). require devuelve el
    -- mismo módulo que arriba.
    local Blitbuffer = require("ffi/blitbuffer")
    local BookList = require("ui/widget/booklist")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local ImageWidget = require("ui/widget/imagewidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local KeyValuePage = require("ui/widget/keyvaluepage")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local ProgressWidget = require("ui/widget/progresswidget")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local lfs = require("libs/libkoreader-lfs")
    local logger = require("logger")
    local _ = require("gettext")
    local N_ = _.ngettext
    local T = require("ffi/util").template
    local Screen = require("device").screen
    local BLACK = Blitbuffer.COLOR_BLACK
    local WHITE = Blitbuffer.COLOR_WHITE
    local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

    local S, face, tappable, config, saveConfig = ctx.S, ctx.face, ctx.tappable, ctx.config, ctx.saveConfig

    local function sectionLabel(text)
        return TextWidget:new{ text = text, face = face(true, 12), fgcolor = GRAY_TEXT, padding = 0 }
    end

    local function sectionRow(w, left_text, right_w)
        local lw = sectionLabel(left_text)
        if not right_w then return lw end
        local h = math.max(lw:getSize().h, right_w:getSize().h)
        return OverlapGroup:new{
            dimen = Geom:new{ w = w, h = h },
            LeftContainer:new{ dimen = Geom:new{ w = w, h = h }, lw },
            RightContainer:new{ dimen = Geom:new{ w = w, h = h }, right_w },
        }
    end

    local function deltaBadge(pct)
        local txt = fmtDelta(pct)
        if not txt then return nil end
        return FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            radius = S(5),
            padding_top = S(1), padding_bottom = S(1),
            padding_left = S(5), padding_right = S(5),
            TextWidget:new{ text = txt, face = face(true, 11), fgcolor = BLACK, padding = 0 },
        }
    end

    local function slotLabel(id)
        if id == "morning" then return _("Morning")
        elseif id == "afternoon" then return _("Afternoon")
        elseif id == "evening" then return _("Evening")
        elseif id == "night" then return _("Night") end
        return ""
    end

    local function tile(w, big, small, icon)
        local pad = S(9)
        local inner_w = w - 2 * Size.border.thin
        local big_w = TextWidget:new{ text = big, face = face(true, 18), fgcolor = BLACK, max_width = inner_w - 2 * pad, padding = 0 }
        local small_w = TextWidget:new{ text = small, face = face(false, 12), fgcolor = GRAY_TEXT, max_width = inner_w - 2 * pad, padding = 0 }
        local vg = VerticalGroup:new{ align = "center" }
        if icon then
            table.insert(vg, IconWidget:new{ icon = icon, width = S(16), height = S(16), alpha = true })
            table.insert(vg, VerticalSpan:new{ width = S(4) })
        end
        table.insert(vg, big_w)
        table.insert(vg, VerticalSpan:new{ width = S(2) })
        table.insert(vg, small_w)
        local h = vg:getSize().h + 2 * pad
        return FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            radius = S(10),
            padding = 0,
            width = w,
            height = h + 2 * Size.border.thin,
            CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = h }, vg },
        }
    end

    local function navCard(cw, card_title, card_sub)
        local pad = S(10)
        local chev = IconWidget:new{ icon = "chevron.right", width = S(16), height = S(16), alpha = true }
        local inner_w = cw - 2 * (pad + Size.border.thin)
        local text_w = inner_w - chev:getSize().w - S(6)
        local tg = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = card_title, face = face(true, 14), fgcolor = BLACK, max_width = text_w, padding = 0 },
            VerticalSpan:new{ width = S(2) },
            TextWidget:new{ text = card_sub, face = face(false, 12), fgcolor = GRAY_TEXT, max_width = text_w, padding = 0 },
        }
        local row_h = math.max(tg:getSize().h, chev:getSize().h)
        return FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            radius = S(10),
            padding = pad,
            width = cw,
            OverlapGroup:new{
                dimen = Geom:new{ w = inner_w, h = row_h },
                LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = row_h }, tg },
                RightContainer:new{ dimen = Geom:new{ w = inner_w, h = row_h }, chev },
            },
        }
    end

    function Aire:buildStatsCurrent(w, st)
        local cur = st.current
        local file = cur and cur.file or G_reader_settings:readSetting("lastfile")
        if not file or lfs.attributes(file, "mode") ~= "file" then
            return TextWidget:new{ text = _("No book in progress"), face = face(false, 14), fgcolor = GRAY_TEXT, padding = 0 }
        end
        local props = {}
        if self.ui.bookinfo then
            local ok, p = pcall(self.ui.bookinfo.getDocProps, self.ui.bookinfo, file, nil, true)
            if ok and type(p) == "table" then props = p end
        end
        BookList.resetBookInfoCache(file)
        local info = BookList.getBookInfo(file) or {}
        local pf = tonumber(info.percent_finished) or 0
        local pages = tonumber(info.pages) or tonumber(props.pages)
        local title = props.display_title or props.title or (file:match("([^/]+)$") or file)

        -- Línea de tiempo: leído, estimación restante y velocidad en este libro
        local line = _("No stats for this book")
        if cur and cur.read_secs > 0 then
            line = fmtDuration(cur.read_secs)
            if pages and pages > 0 and cur.read_pages > 0 and pf < 1 then
                local left = math.max(0, pages * (1 - pf)) * (cur.read_secs / cur.read_pages)
                line = line .. " · " .. T(_("~%1 left"), fmtDuration(left))
            end
            local speed = calcSpeed(cur.read_pages, cur.read_secs)
            if speed > 0 then
                line = line .. " · " .. T(_("%1 pp./h"), speed)
            end
        end

        local pad = S(10)
        local cover_h = S(64)
        local cover
        local ok_bim, BIM = pcall(require, "bookinfomanager")
        if ok_bim and type(BIM) == "table" then
            local ok_bi, bi = pcall(BIM.getBookInfo, BIM, file, true)
            if ok_bi and bi and bi.has_cover and bi.cover_bb then
                self._stats_cover = bi.cover_bb
                local rounded = config and config.rounded_covers == true
                cover = FrameContainer:new{
                    bordersize = Size.border.thin, color = BLACK, padding = 0, margin = 0,
                    radius = rounded and S(6) or 0, _aire_clip_corners = rounded,
                    ImageWidget:new{
                        image = bi.cover_bb, image_disposable = false,
                        scale_factor = math.min(cover_h / bi.cover_bb:getHeight(), (cover_h * 0.75) / bi.cover_bb:getWidth()),
                    },
                }
            end
        end
        local cover_w = cover and cover:getSize().w or 0
        local col_w = w - 2 * (pad + Size.border.thin) - cover_w - (cover and S(12) or 0)
        local pct_w = TextWidget:new{
            text = ("%d%%"):format(math.floor(math.max(0, math.min(1, pf)) * 100 + 0.5)),
            face = face(true, 11), fgcolor = GRAY_TEXT, padding = 0,
        }
        local bar_w = math.max(S(40), col_w - pct_w:getSize().w - S(8))
        local prog_row = HorizontalGroup:new{
            align = "center",
            ProgressWidget:new{
                width = bar_w, height = S(7), percentage = math.max(0, math.min(1, pf)),
                fillcolor = Blitbuffer.COLOR_DARK_GRAY, bgcolor = Blitbuffer.COLOR_GRAY_D, bordersize = 0,
                radius = S(4), margin_h = 0, margin_v = 0,
            },
            HorizontalSpan:new{ width = S(8) },
            pct_w,
        }
        local col = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = title, face = face(true, 15), fgcolor = BLACK, max_width = col_w, padding = 0 },
            VerticalSpan:new{ width = S(3) },
            TextWidget:new{ text = line, face = face(false, 12), fgcolor = GRAY_TEXT, max_width = col_w, padding = 0 },
            VerticalSpan:new{ width = S(7) },
            prog_row,
        }
        local row = HorizontalGroup:new{ align = "center" }
        if cover then
            table.insert(row, cover)
            table.insert(row, HorizontalSpan:new{ width = S(12) })
        end
        table.insert(row, col)
        return tappable(FrameContainer:new{
            bordersize = Size.border.thin, color = BLACK, radius = S(10), padding = pad,
            width = w,
            LeftContainer:new{ dimen = Geom:new{ w = w - 2 * (pad + Size.border.thin), h = row:getSize().h }, row },
        }, function() filemanagerutil.openFile(self.ui, file) end)
    end

    function Aire:buildStatsView()
        if self._stats_cover then
            pcall(self._stats_cover.free, self._stats_cover)
            self._stats_cover = nil
        end
        StatsData.state.FAKE = (config.demo_stats and self.getTestTools and self:getTestTools()) or nil
        local st = loadStats()
        countFinishedYear(self, st)
        local sw = Screen:getWidth()
        local side = S(ctx.SIDE_PAD)
        local w = sw - 2 * side

        local content = self:buildScreenTop(w, { title = _("Stats") })
        local sub_txt
        if st.ok then
            sub_txt = T(_("This month · %1 · %2 pp."), fmtDuration(st.month_secs), st.month_pages)
            local m_delta = fmtDelta(st.month_delta_pct)
            if m_delta then sub_txt = sub_txt .. " · " .. m_delta end
        else
            sub_txt = _("Activity summary")
        end
        -- Subtítulo común (ui/screen.lua); al tocarlo, el calendario
        local sub_row = package.loaded.aire_screen.subtitle(w, sub_txt)
        table.insert(content, tappable(sub_row, function() self:showCalendarView() end, nil, { h = 0, v = S(6) }))
        table.insert(content, VerticalSpan:new{ width = S(10) })

        if not st.ok then
            table.insert(content, TextWidget:new{
                text = _("No data: enable the Statistics plugin and read a bit"),
                face = face(false, 14), fgcolor = GRAY_TEXT, max_width = w, padding = 0,
            })
            table.insert(content, VerticalSpan:new{ width = S(12) })
        end

        -- 3 casillas superiores (las únicas con icono): hoy, racha, terminados
        local tgap = S(10)
        local tw = math.floor((w - 2 * tgap) / 3)
        local today_small = T(_("today · %1 pp."), st.today_pages)
        local streak_small = (st.best_streak and st.best_streak > 0)
            and T(_("streak · max %1"), st.best_streak)
            or _("streak")
        table.insert(content, HorizontalGroup:new{
            align = "top",
            tappable(tile(tw, fmtDuration(st.today_secs), today_small, "aire.widget.timer"),
                function() self:showCalendarView() end),
            HorizontalSpan:new{ width = tgap },
            tappable(tile(tw, T(N_("%1 day", "%1 days", st.streak), st.streak), streak_small, "aire.widget.flame"),
                function() self:showCalendarView() end),
            HorizontalSpan:new{ width = tgap },
            tappable(tile(w - 2 * (tw + tgap), tostring(st.finished_year), T(_("finished in %1"), st.year), "aire.widget.done"),
                function() if self.showGridView then self:showGridView("finished") end end),
        })

        -- Últimos 7 días (con comparativa y línea de media diaria; tocar: calendario)
        table.insert(content, VerticalSpan:new{ width = S(16) })
        table.insert(content, sectionRow(w, _("LAST 7 DAYS") .. " · " .. fmtDuration(st.week_total), deltaBadge(st.week_delta_pct)))
        table.insert(content, VerticalSpan:new{ width = S(6) })
        local avg_7 = st.week_total > 0 and math.floor(st.week_total / 7) or 0
        table.insert(content, tappable(WeekBars:new{
            width = w, height = S(96), days = st.week,
            avg_secs = avg_7, avg_label = avg_7 > 0 and T(_("avg %1"), fmtDuration(avg_7)) or nil,
        }, function()
            self:showCalendarView()
        end))

        -- Leyendo ahora
        table.insert(content, VerticalSpan:new{ width = S(16) })
        table.insert(content, sectionLabel(_("CURRENTLY READING")))
        table.insert(content, VerticalSpan:new{ width = S(6) })
        local ok_cur, cur = pcall(self.buildStatsCurrent, self, w, st)
        if ok_cur then
            table.insert(content, cur)
        else
            logger.warn("Aire/Stats: error en el libro actual:", cur)
        end

        -- Explorar: Géneros y hábitos + Recaps (tarjetas limpias sin iconos)
        table.insert(content, VerticalSpan:new{ width = S(16) })
        table.insert(content, sectionLabel(_("EXPLORE")))
        table.insert(content, VerticalSpan:new{ width = S(6) })

        local hab_parts = {}
        if st.top_genres and #st.top_genres > 0 then
            for i = 1, math.min(2, #st.top_genres) do
                local g = st.top_genres[i]
                table.insert(hab_parts, ("%s (%d%%)"):format(g.label, g.pct))
            end
        end
        if st.fav_slot then
            table.insert(hab_parts, slotLabel(st.fav_slot))
        end
        local hab_sub = #hab_parts > 0 and table.concat(hab_parts, " · ") or _("No reading habits yet")
        table.insert(content, tappable(navCard(w, _("Genres & habits"), hab_sub), function()
            self:showHabitsView()
        end))
        table.insert(content, VerticalSpan:new{ width = S(8) })

        local rgap = S(10)
        local rw = math.floor((w - rgap) / 2)
        local now_m = tonumber(os.date("%m"))
        local month_sub = st.ok and (MONTHS[now_m] .. " · " .. fmtDuration(st.month_secs)) or MONTHS[now_m]
        local year_sub = st.ok and (st.year .. " · " .. fmtDuration(st.year_secs)) or st.year
        table.insert(content, HorizontalGroup:new{
            align = "top",
            tappable(navCard(rw, _("Monthly recap"), month_sub), function() self:showRecapView("month") end),
            HorizontalSpan:new{ width = rgap },
            tappable(navCard(w - rw - rgap, _("Annual recap"), year_sub), function() self:showRecapView("year") end),
        })
        content:resetLayout()

        local dock = self:buildNavBar(w)
        return package.loaded.aire_screen.root(HorizontalGroup:new{ HorizontalSpan:new{ width = side }, content }, dock)
    end

    -------------------------------------------------------------------------
    -- Géneros y hábitos (se abre desde la tarjeta en Estadísticas)
    -------------------------------------------------------------------------
    function Aire:buildHabitsView()
        StatsData.state.FAKE = (config.demo_stats and self.getTestTools and self:getTestTools()) or nil
        local st = loadStats()
        local sw = Screen:getWidth()
        local side = S(ctx.SIDE_PAD)
        local w = sw - 2 * side

        local content = self:buildScreenTop(w, {
            title = _("Genres & habits"),
            on_back = function() self:showStatsView() end,
        })
        local sub_parts = { st.year }
        if st.year_speed and st.year_speed > 0 then
            table.insert(sub_parts, T(_("%1 pp./h"), st.year_speed))
        end
        if st.best_streak and st.best_streak > 0 then
            table.insert(sub_parts, T(_("Best streak: %1"),
                T(N_("%1 day", "%1 days", st.best_streak), st.best_streak)))
        end
        table.insert(content, (package.loaded.aire_screen.subtitle(w, table.concat(sub_parts, " · "))))
        table.insert(content, VerticalSpan:new{ width = S(14) })

        -- Top 5 géneros más leídos
        table.insert(content, sectionLabel(_("MOST READ GENRES")))
        table.insert(content, VerticalSpan:new{ width = S(8) })
        if st.top_genres and #st.top_genres > 0 then
            local max_secs = st.top_genres[1].secs or 1
            local items = {}
            for _i, g in ipairs(st.top_genres) do
                local books_txt = T(N_("%1 book", "%1 books", g.books), g.books)
                table.insert(items, {
                    label = g.label,
                    detail = ("%d%% · %s · %s"):format(g.pct, fmtDuration(g.secs), books_txt),
                    ratio = max_secs > 0 and (g.secs / max_secs) or 0,
                })
            end
            table.insert(content, HorizontalBars:new{ width = w, items = items })
        else
            table.insert(content, TextWidget:new{
                text = _("No genre metadata yet"),
                face = face(false, 13), fgcolor = GRAY_TEXT, max_width = w, padding = 0,
            })
        end

        -- Franja horaria (4 tarjetas limpias; la favorita en negro)
        table.insert(content, VerticalSpan:new{ width = S(20) })
        local fav_slot_w = nil
        if st.fav_slot and st.time_slots then
            for _i, s in ipairs(st.time_slots) do
                if s.id == st.fav_slot and s.pct > 0 then
                    fav_slot_w = TextWidget:new{
                        text = ("%s (%d%%)"):format(slotLabel(s.id), s.pct),
                        face = face(true, 12), fgcolor = BLACK, padding = 0,
                    }
                    break
                end
            end
        end
        table.insert(content, sectionRow(w, _("WHEN YOU READ"), fav_slot_w))
        table.insert(content, VerticalSpan:new{ width = S(8) })
        if st.time_slots and #st.time_slots == 4 then
            local sgap = S(8)
            local sw_card = math.floor((w - 3 * sgap) / 4)
            local srow = HorizontalGroup:new{ align = "top" }
            for i, s in ipairs(st.time_slots) do
                if i > 1 then table.insert(srow, HorizontalSpan:new{ width = sgap }) end
                local cw = (i == 4) and (w - 3 * (sw_card + sgap)) or sw_card
                local active = (s.id == st.fav_slot and s.secs > 0)
                local pad = S(8)
                local inner_w = cw - 2 * Size.border.thin
                local vg = VerticalGroup:new{
                    align = "center",
                    TextWidget:new{
                        text = ("%d%%"):format(s.pct),
                        face = face(true, 16), fgcolor = active and WHITE or BLACK,
                        max_width = inner_w - 2 * pad, padding = 0,
                    },
                    VerticalSpan:new{ width = S(2) },
                    TextWidget:new{
                        text = slotLabel(s.id),
                        face = face(false, 11), fgcolor = active and WHITE or GRAY_TEXT,
                        max_width = inner_w - 2 * pad, padding = 0,
                    },
                }
                local h = vg:getSize().h + 2 * pad
                table.insert(srow, FrameContainer:new{
                    bordersize = Size.border.thin,
                    color = BLACK,
                    background = active and BLACK or WHITE,
                    radius = S(10),
                    padding = 0,
                    width = cw,
                    height = h + 2 * Size.border.thin,
                    CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = h }, vg },
                })
            end
            table.insert(content, srow)
        end

        -- Días de la semana (L-D)
        table.insert(content, VerticalSpan:new{ width = S(20) })
        local fav_wd_w = nil
        if st.fav_weekday and st.weekdays and st.weekdays[st.fav_weekday] and st.weekdays[st.fav_weekday].secs > 0 then
            local lua_wday = (st.fav_weekday % 7) + 1
            local wd_name = WEEKDAYS_LONG[lua_wday] or ""
            fav_wd_w = TextWidget:new{
                text = ("%s (%d%%)"):format(wd_name, st.weekdays[st.fav_weekday].pct),
                face = face(true, 12), fgcolor = BLACK, padding = 0,
            }
        end
        table.insert(content, sectionRow(w, _("DAYS OF THE WEEK"), fav_wd_w))
        table.insert(content, VerticalSpan:new{ width = S(8) })
        if st.weekdays and #st.weekdays == 7 then
            table.insert(content, WeekdayBars:new{
                width = w, height = S(90), days = st.weekdays, fav = st.fav_weekday,
            })
        end
        content:resetLayout()

        local dock = self:buildNavBar(w)
        return package.loaded.aire_screen.root(HorizontalGroup:new{ HorizontalSpan:new{ width = side }, content }, dock)
    end

    function Aire:showHabitsView()
        if self.closeGridViews then self:closeGridViews(true) end
        config.mode = "library"
        saveConfig()
        self.view = "habits"
        self:apply()
        UIManager:setDirty(self.ui, "flashui")
    end

    -------------------------------------------------------------------------
    -- Calendario (se abre al tocar las barras de la semana)
    -------------------------------------------------------------------------
    function Aire:buildCalendarView()
        local now = os.date("*t")
        self._cal = self._cal or { year = now.year, month = now.month, day = now.day }
        local C = self._cal
        StatsData.state.FAKE = (config.demo_stats and self.getTestTools and self:getTestTools()) or nil
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local side = S(ctx.SIDE_PAD)
        local w = sw - 2 * side
        local data = loadMonth(C.year, C.month)

        local content = self:buildScreenTop(w, { title = _("Calendar"), on_back = function() self:showStatsView() end })
        -- Subtítulo en la fila común (ui/screen.lua)
        table.insert(content, (package.loaded.aire_screen.subtitle(w, fmtDuration(data.secs) .. " · "
            .. T(_("%1 pp."), data.pages) .. " · "
            .. T(N_("%1 day reading", "%1 days reading", data.read_days), data.read_days))))
        table.insert(content, VerticalSpan:new{ width = S(package.loaded.aire_screen.METRICS.CONTENT_GAP) })

        -- Mes con flechas (no se puede pasar del mes actual)
        local is_current = C.year == now.year and C.month == now.month
        local nav_h = S(36)
        -- Flechas pegadas a los bordes y del mismo tamaño que el "‹" de
        -- "‹ Calendario", para que queden alineadas en vertical con él
        local function arrow(icon, enabled, delta)
            local iw = IconWidget:new{ icon = icon, width = S(24), height = S(24), alpha = true, dim = not enabled }
            local box = CenterContainer:new{ dimen = Geom:new{ w = S(24), h = nav_h }, iw }
            if not enabled then return box end
            return tappable(box, function() self:calendarMonth(delta) end, nil, { h = S(14), v = S(6) })
        end
        table.insert(content, OverlapGroup:new{
            dimen = Geom:new{ w = w, h = nav_h },
            LeftContainer:new{ dimen = Geom:new{ w = w, h = nav_h }, arrow("chevron.left", true, -1) },
            CenterContainer:new{
                dimen = Geom:new{ w = w, h = nav_h },
                TextWidget:new{ text = MONTHS[C.month] .. " " .. C.year, face = face(true, 17), fgcolor = BLACK, padding = 0 },
            },
            RightContainer:new{ dimen = Geom:new{ w = w, h = nav_h }, arrow("chevron.right", not is_current, 1) },
        })
        table.insert(content, VerticalSpan:new{ width = S(8) })

        -- Letras de los días (lunes primero)
        local gap = S(5)
        local cw = math.floor((w - 6 * gap) / 7)
        local letters = HorizontalGroup:new{ align = "center" }
        local dayLetter = package.loaded.aire_ui.dayLetter
        for i, wd in ipairs({ 2, 3, 4, 5, 6, 7, 1 }) do
            local l = dayLetter(wd)
            if i > 1 then table.insert(letters, HorizontalSpan:new{ width = gap }) end
            table.insert(letters, CenterContainer:new{
                dimen = Geom:new{ w = cw, h = S(20) },
                TextWidget:new{ text = l, face = face(false, 12), fgcolor = GRAY_TEXT, padding = 0 },
            })
        end
        table.insert(content, letters)
        table.insert(content, VerticalSpan:new{ width = S(4) })

        -- Espacio: lo de arriba ya está; abajo, el dock y el detalle del día
        -- (cabecera + 3 libros como mínimo). Lo que sobra es para el calendario.
        content:resetLayout()
        local dock = self:buildNavBar(w)
        local dock_area = package.loaded.aire_screen.dockReserve(dock)
        local row_h = S(package.loaded.aire_screen.LIST.ROW_H) -- (filas comunes: ui/list.lua)
        local detail_min = S(16) + S(20) + S(8) + 3 * row_h
        local grid_max = sh - content:getSize().h - dock_area - detail_min
        table.insert(content, CalendarGrid:new{
            width = w, max_height = grid_max,
            year = C.year, month = C.month, data = data, selected = C.day,
            on_select = function(d)
                C.day = d
                self:apply()
                UIManager:setDirty(self.ui, "ui")
            end,
            on_swipe = function(delta) self:calendarMonth(delta) end,
        })

        -- Día seleccionado: tiempo, páginas y libros que leíste
        table.insert(content, VerticalSpan:new{ width = S(16) })
        if C.day then
            local info = data.days[C.day]
            local t_day = os.time{ year = C.year, month = C.month, day = C.day, hour = 12 }
            local wday = WEEKDAYS_LONG[tonumber(os.date("%w", t_day)) + 1]
            local head = ("%s %d"):format(wday:upper(), C.day)
            if info then
                head = head .. " · " .. fmtDuration(info.secs) .. " · " .. T(_("%1 pp."), info.pages)
            end
            table.insert(content, TextWidget:new{ text = head, face = face(true, 12), fgcolor = GRAY_TEXT, max_width = w, padding = 0 })
            table.insert(content, VerticalSpan:new{ width = S(8) })
            local books = info and loadDay(C.year, C.month, C.day) or {}
            if #books == 0 then
                local future_day = C.year == now.year and C.month == now.month and C.day > now.day
                table.insert(content, TextWidget:new{
                    text = future_day and _("Hasn't arrived yet") or _("You didn't read that day"),
                    face = face(false, 14), fgcolor = GRAY_TEXT, padding = 0,
                })
            end
            -- Cuántos libros caben sin llegar al dock (si sobran, "+N más")
            content:resetLayout()
            local room = sh - dock_area - content:getSize().h
            local fit = math.max(0, math.floor(room / row_h))
            local shown = math.min(#books, fit)
            if shown < #books then
                shown = math.max(0, math.min(#books, fit - 1)) -- deja sitio a "+N más"
            end
            local function showBookStatsSheet(b)
                if not b.id_book then return end
                local ButtonDialog = require("ui/widget/buttondialog")
                local TextBoxWidget = require("ui/widget/textboxwidget")
                local dlg
                local function refreshCal()
                    self:apply()
                    UIManager:setDirty(self.ui, "ui")
                end
                local function confirmSheet(title, msg, ok_text, on_ok)
                    local cdlg
                    local iw = package.loaded.aire_screen.sheetInnerWidth()
                    cdlg = ButtonDialog:new{
                        title = title,
                        title_align = "left",
                        _added_widgets = {
                            TextBoxWidget:new{
                                text = msg,
                                width = iw,
                                face = Font:getFace("cfont", 15),
                                fgcolor = GRAY_TEXT,
                                alignment = "left",
                            },
                        },
                        buttons = { {
                            { text = _("Cancel"), callback = function() UIManager:close(cdlg) end },
                            { text = ok_text, is_enter_default = true, callback = function()
                                UIManager:close(cdlg)
                                on_ok()
                            end },
                        } },
                    }
                    UIManager:show(cdlg)
                end
                dlg = ButtonDialog:new{
                    title = b.title,
                    title_align = "left",
                    buttons = {
                        { {
                            text = _("Delete minutes from this day"),
                            callback = function()
                                UIManager:close(dlg)
                                confirmSheet(
                                    _("Delete minutes for this day?"),
                                    b.title .. " (" .. fmtDuration(b.secs) .. ")",
                                    _("Delete"),
                                    function()
                                        if deleteBookStats(b.id_book, C.year, C.month, C.day) then
                                            if self._gv and self._gv.history then self._gv.history.loaded = false end
                                            refreshCal()
                                        end
                                    end
                                )
                            end,
                        } },
                        { {
                            text = _("Delete all book stats"),
                            callback = function()
                                UIManager:close(dlg)
                                confirmSheet(
                                    _("Delete all stats?"),
                                    b.title,
                                    _("Delete"),
                                    function()
                                        if deleteBookStats(b.id_book) then
                                            if self._gv and self._gv.history then self._gv.history.loaded = false end
                                            refreshCal()
                                        end
                                    end
                                )
                            end,
                        } },
                    },
                }
                UIManager:show(dlg)
            end
            -- Filas comunes (ui/list.lua): el libro (es el elemento) y su tiempo
            local Lst = package.loaded.aire_list
            for i = 1, shown do
                local b = books[i]
                local open = b.id_book and function() showBookStatsSheet(b) end or nil
                table.insert(content, Lst.row({ key = b.title, key_main = true, value = fmtDuration(b.secs),
                    callback = open, hold_callback = open, line = i < shown or shown < #books }, w))
            end
            if shown < #books then
                -- "+N más ›": abre la lista completa del día
                local day_title = head
                table.insert(content, Lst.row({ key = T(_("+%1 more"), #books - shown), line = false, callback = function()
                    local kv_page
                    local kv = {}
                    for _i, b in ipairs(books) do
                        table.insert(kv, {
                            b.title,
                            fmtDuration(b.secs) .. " · " .. T(_("%1 pp."), b.pages),
                            callback = b.id_book and function()
                                if kv_page then UIManager:close(kv_page) end
                                showBookStatsSheet(b)
                            end or nil,
                        })
                    end
                    kv_page = KeyValuePage:new{ title = day_title, kv_pairs = kv }
                    UIManager:show(kv_page)
                end }, w))
            end
        end
        content:resetLayout()

        return package.loaded.aire_screen.root(HorizontalGroup:new{ HorizontalSpan:new{ width = side }, content }, dock)
    end

    function Aire:calendarMonth(delta)
        local C = self._cal
        if not C then return end
        local now = os.date("*t")
        local y, m = C.year, C.month + delta
        if m < 1 then y, m = y - 1, 12 elseif m > 12 then y, m = y + 1, 1 end
        if y > now.year or (y == now.year and m > now.month) then return end
        C.year, C.month = y, m
        C.day = (y == now.year and m == now.month) and now.day or nil
        self:apply()
        UIManager:setDirty(self.ui, "ui")
    end

    function Aire:showCalendarView()
        self._cal = nil -- abrir siempre en el mes actual, con hoy seleccionado
        config.mode = "library"
        saveConfig()
        self.view = "calendar"
        self:apply()
        UIManager:setDirty(self.ui, "flashui")
    end

    -------------------------------------------------------------------------
    -- Recap mensual y anual (se abre desde las tarjetas de Estadísticas)
    -------------------------------------------------------------------------
    function Aire:buildRecapView()
        local now = os.date("*t")
        self._recap = self._recap or { mode = "month", year = now.year, month = now.month }
        local R = self._recap
        local mode = R.mode == "year" and "year" or "month"
        StatsData.state.FAKE = (config.demo_stats and self.getTestTools and self:getTestTools()) or nil
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local side = S(ctx.SIDE_PAD)
        local w = sw - 2 * side
        local recap = loadRecap(self, mode, R.year, R.month)

        local content = self:buildScreenTop(w, {
            -- Sin subtítulo: el hueco común entre la cabecera y el contenido
            title = _("Recap"), on_back = function() self:showStatsView() end,
            gap_after = package.loaded.aire_screen.METRICS.CONTENT_GAP,
        })

        -- Selector Mensual / Anual
        local tab_gap = S(8)
        local tab_w = math.floor((w - tab_gap) / 2)
        local tab_h = S(34)
        local function modeTab(tw, label, m)
            local active = mode == m
            return tappable(FrameContainer:new{
                bordersize = Size.border.thin,
                color = BLACK,
                background = active and BLACK or WHITE,
                radius = S(8),
                padding = 0,
                width = tw,
                height = tab_h,
                CenterContainer:new{
                    dimen = Geom:new{ w = tw - 2 * Size.border.thin, h = tab_h - 2 * Size.border.thin },
                    TextWidget:new{
                        text = label,
                        face = face(active, 14),
                        fgcolor = active and WHITE or BLACK,
                        padding = 0,
                    },
                },
            }, function()
                if R.mode ~= m then
                    R.mode = m
                    self:apply()
                    UIManager:setDirty(self.ui, "ui")
                end
            end)
        end
        table.insert(content, HorizontalGroup:new{
            align = "center",
            modeTab(tab_w, _("Monthly"), "month"),
            HorizontalSpan:new{ width = tab_gap },
            modeTab(w - tab_w - tab_gap, _("Annual"), "year"),
        })
        table.insert(content, VerticalSpan:new{ width = S(10) })

        -- Navegador de periodo (‹ Noviembre 2026 › / ‹ 2026 ›)
        local is_current = (mode == "year" and R.year == now.year)
            or (mode == "month" and R.year == now.year and R.month == now.month)
        local nav_h = S(36)
        local function arrow(icon, enabled, delta)
            local iw = IconWidget:new{ icon = icon, width = S(24), height = S(24), alpha = true, dim = not enabled }
            local box = CenterContainer:new{ dimen = Geom:new{ w = S(24), h = nav_h }, iw }
            if not enabled then return box end
            return tappable(box, function() self:recapStep(delta) end, nil, { h = S(14), v = S(6) })
        end
        local period_title = mode == "month" and (MONTHS[R.month] .. " " .. R.year) or tostring(R.year)
        table.insert(content, OverlapGroup:new{
            dimen = Geom:new{ w = w, h = nav_h },
            LeftContainer:new{ dimen = Geom:new{ w = w, h = nav_h }, arrow("chevron.left", true, -1) },
            CenterContainer:new{
                dimen = Geom:new{ w = w, h = nav_h },
                TextWidget:new{ text = period_title, face = face(true, 17), fgcolor = BLACK, padding = 0 },
            },
            RightContainer:new{ dimen = Geom:new{ w = w, h = nav_h }, arrow("chevron.right", not is_current, 1) },
        })
        table.insert(content, VerticalSpan:new{ width = S(10) })

        local dock = self:buildNavBar(w)
        local dock_area = package.loaded.aire_screen.dockReserve(dock)

        if recap.total_secs == 0 and #recap.finished_books == 0 then
            table.insert(content, VerticalSpan:new{ width = S(24) })
            table.insert(content, CenterContainer:new{
                dimen = Geom:new{ w = w, h = S(40) },
                TextWidget:new{
                    text = _("No reading activity in this period"),
                    face = face(false, 14), fgcolor = GRAY_TEXT, max_width = w, padding = 0,
                },
            })
        else
            -- 3 casillas resumen: tiempo, páginas/velocidad, terminados
            local tgap = S(10)
            local tw = math.floor((w - 2 * tgap) / 3)
            local speed = recap.total_secs > 0 and math.floor(recap.total_pages / (recap.total_secs / 3600) + 0.5) or 0
            local pages_sub = speed > 0 and T(_("%1 pp./h"), speed) or _("pages read")
            local fin_n = #recap.finished_books
            table.insert(content, HorizontalGroup:new{
                align = "top",
                tile(tw, fmtDuration(recap.total_secs), _("reading time")),
                HorizontalSpan:new{ width = tgap },
                tile(tw, tostring(recap.total_pages), pages_sub),
                HorizontalSpan:new{ width = tgap },
                tappable(tile(w - 2 * (tw + tgap), tostring(fin_n), N_("finished book", "finished books", fin_n)),
                    function()
                        if self.showGridView then
                            config.fin_filter = mode == "month" and "month" or "year"
                            saveConfig()
                            self:showGridView("finished")
                        end
                    end),
            })

            -- Gráfica de ritmo (días del mes o meses del año)
            table.insert(content, VerticalSpan:new{ width = S(18) })
            local rhythm_lbl = mode == "month" and _("DAILY RHYTHM") or _("MONTHLY RHYTHM")
            table.insert(content, sectionLabel(rhythm_lbl .. " · "
                .. T(N_("%1 day reading", "%1 days reading", recap.read_days), recap.read_days)))
            table.insert(content, VerticalSpan:new{ width = S(8) })
            table.insert(content, RecapBars:new{ width = w, height = S(90), bars = recap.bars })

            -- Hitos del periodo
            table.insert(content, VerticalSpan:new{ width = S(18) })
            table.insert(content, sectionLabel(_("HIGHLIGHTS")))
            table.insert(content, VerticalSpan:new{ width = S(6) })
            -- Filas clave / valor comunes (ui/list.lua)
            local function kvRow(k, v)
                table.insert(content, package.loaded.aire_list.row({ key = k, value = v }, w))
            end
            local avg_secs = recap.read_days > 0 and (recap.total_secs / recap.read_days) or 0
            kvRow(_("Daily average"), fmtDuration(avg_secs))
            if recap.best_day and recap.best_day.day then
                local bd_lbl = mode == "month"
                    and T(_("Day %1"), recap.best_day.day)
                    or ("%d %s"):format(recap.best_day.day, MONTHS[recap.best_day.month] or "")
                kvRow(_("Best day"), bd_lbl .. " · " .. fmtDuration(recap.best_day.secs))
            end
            if mode == "year" and recap.best_month then
                kvRow(_("Best month"), (MONTHS[recap.best_month.month] or "") .. " · " .. fmtDuration(recap.best_month.secs))
            end
            if recap.top_author then
                kvRow(_("Top author"), recap.top_author.name .. " · " .. fmtDuration(recap.top_author.secs))
            end

            -- Libros más leídos del periodo (los que quepan sobre el dock)
            if #recap.top_books > 0 then
                table.insert(content, VerticalSpan:new{ width = S(14) })
                table.insert(content, sectionLabel(_("MOST READ")))
                table.insert(content, VerticalSpan:new{ width = S(6) })
                content:resetLayout()
                -- Filas comunes (ui/list.lua): el libro (es el elemento) y su tiempo
                local row_h = S(package.loaded.aire_screen.LIST.ROW_H) + Size.line.thin
                local fit = math.max(0, math.floor((sh - dock_area - content:getSize().h) / row_h))
                local shown = math.min(#recap.top_books, fit)
                for i = 1, shown do
                    local b = recap.top_books[i]
                    table.insert(content, package.loaded.aire_list.row({
                        key = ("%d. %s"):format(i, b.title), key_main = true,
                        value = fmtDuration(b.secs), line = i < shown,
                    }, w))
                end
            end
        end
        content:resetLayout()

        local body = package.loaded.aire_screen.root(HorizontalGroup:new{ HorizontalSpan:new{ width = side }, content }, dock)
        local ic = InputContainer:new{
            dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
            body,
        }
        ic.ges_events = {
            AireSwipe = { GestureRange:new{ ges = "swipe", range = function() return ic.dimen end } },
        }
        ic.onAireSwipe = function(_self, ges)
            local dir = ges and ges.direction
            if dir == "west" or dir == "east" then
                self:recapStep(dir == "west" and 1 or -1)
                return true
            end
            return false
        end
        return ic
    end

    function Aire:recapStep(delta)
        local R = self._recap
        if not R then return end
        local now = os.date("*t")
        if R.mode == "year" then
            local y = R.year + delta
            if y > now.year then return end
            R.year = y
        else
            local y, m = R.year, R.month + delta
            if m < 1 then y, m = y - 1, 12 elseif m > 12 then y, m = y + 1, 1 end
            if y > now.year or (y == now.year and m > now.month) then return end
            R.year, R.month = y, m
        end
        self:apply()
        UIManager:setDirty(self.ui, "ui")
    end

    function Aire:showRecapView(mode)
        if self.closeGridViews then self:closeGridViews(true) end
        local now = os.date("*t")
        self._recap = { mode = mode == "year" and "year" or "month", year = now.year, month = now.month }
        config.mode = "library"
        saveConfig()
        self.view = "recap"
        self:apply()
        UIManager:setDirty(self.ui, "flashui")
    end

    -- Para los widgets de Inicio: hoy, racha, terminados del año…
    function Aire:getQuickStats()
        StatsData.state.FAKE = (config.demo_stats and self.getTestTools and self:getTestTools()) or nil
        local ok, st = pcall(loadStats)
        if ok then
            countFinishedYear(self, st)
            return st
        end
        logger.warn("Aire/Stats: error en los datos rápidos:", st)
        return nil
    end

    function Aire:showStatsView()
        if self.closeGridViews then self:closeGridViews(true) end
        config.mode = "library"
        saveConfig()
        self.view = "stats"
        self:apply()
        UIManager:setDirty(self.ui, "flashui")
    end

    function Aire:closeStatsView()
        if self._stats_cover then
            pcall(self._stats_cover.free, self._stats_cover)
            self._stats_cover = nil
        end
    end
end
