--[[
    aire.koplugin/styles/plugins/readerprogress.lua
    Rediseño moderno (Opción B) de ReaderProgress (plugin Estadísticas):
      - Cabecera unificada de pantalla completa (barra de estado + ‹ Progreso de lectura + subtítulo)
      - 3 tarjetas métricas arriba (Hoy, 7 días, Media/día)
      - Gráfico de barras vertical de los últimos 7 días
      - Tarjeta SESIÓN ACTUAL abajo
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local datetime = require("datetime")
local logger = require("logger")
local userpatch = require("userpatch")
local _ = require("gettext")
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/ReaderProgress"
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (ui/screen.lua)
local AireUI = package.loaded.aire_ui
local S = AireUI.S
local face = AireUI.face
local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

local function fmtDur(secs)
    local fmt = G_reader_settings:readSetting("duration_format")
    return datetime.secondsToClockDuration(fmt, math.max(0, tonumber(secs) or 0), true, true)
end

local function readDailyGoalSecs()
    local saved = G_reader_settings:readSetting("aire_home")
    local mins = type(saved) == "table" and tonumber(saved.stats_goal_daily_min) or 0
    return (mins and mins > 0) and math.floor(mins * 60) or 0
end

local function buildDays(dates)
    local map = {}
    for _i, d in ipairs(dates or {}) do
        if d[3] and d[2] then map[d[3]] = tonumber(d[2]) or 0 end
    end
    local now = os.time()
    local days, total, active = {}, 0, 0
    for offset = 6, 0, -1 do
        local t = now - offset * 86400
        local key = os.date("%Y-%m-%d", t)
        local secs = map[key] or 0
        total = total + secs
        if secs > 0 then active = active + 1 end
        table.insert(days, {
            letter = AireUI.dayLetter(os.date("*t", t).wday),
            secs = secs,
            is_today = (offset == 0),
        })
    end
    return days, total, active
end

local function buildBarsWidget(w, h, days, ref_secs)
    local max_s = ref_secs and ref_secs > 0 and ref_secs or 1
    for _i, d in ipairs(days) do
        if d.secs > max_s then max_s = d.secs end
    end
    local lbl_h = S(20)
    local chart_h = math.max(S(44), h - lbl_h - S(8))
    local n = #days
    local col_w = math.floor(w / n)
    local bar_w = math.min(S(28), math.floor(col_w * 0.55))
    local r = S(5)

    local bars = Widget:new{
        dimen = Geom:new{ w = w, h = chart_h },
        paintTo = function(_self, bb, x, y)
            -- Línea discontinua de referencia (objetivo diario o media 7 días)
            if ref_secs and ref_secs > 0 and max_s > 0 then
                local ry = y + chart_h - math.max(S(4), math.floor(chart_h * ref_secs / max_s))
                local dash, gap = S(5), S(4)
                local dx = x
                while dx < x + w do
                    local dw = math.min(dash, x + w - dx)
                    bb:paintRect(dx, ry, dw, 1, Blitbuffer.COLOR_GRAY_7)
                    dx = dx + dash + gap
                end
            end
            for i, d in ipairs(days) do
                local cx = x + (i - 1) * col_w + math.floor((col_w - bar_w) / 2)
                local bh = d.secs > 0 and math.max(S(6), math.floor(chart_h * d.secs / max_s)) or S(3)
                local col = d.secs == 0 and Blitbuffer.COLOR_GRAY_D
                    or (d.is_today and BLACK or Blitbuffer.COLOR_GRAY_9)
                bb:paintRoundedRect(cx, y + chart_h - bh, bar_w, bh, col, math.min(r, math.floor(bh / 2)))
            end
        end,
    }
    local letters = HorizontalGroup:new{ align = "center" }
    for _i, d in ipairs(days) do
        table.insert(letters, CenterContainer:new{
            dimen = Geom:new{ w = col_w, h = lbl_h },
            TextWidget:new{
                text = d.letter,
                face = face(d.is_today, 12),
                fgcolor = d.is_today and BLACK or GRAY_TEXT,
                padding = 0,
            },
        })
    end
    return VerticalGroup:new{
        align = "center",
        bars,
        VerticalSpan:new{ width = S(8) },
        letters,
    }
end

local function patchStatistics()
    local ok, ReaderProgress = pcall(require, "readerprogress")
    if not ok or type(ReaderProgress) ~= "table" or ReaderProgress._aire_styled then return end
    ReaderProgress._aire_styled = true

    safeWrap(ReaderProgress, "getStatusContent", function(_orig, self, width)
        local sw = width or Screen:getWidth()
        local side = S(SIDE)
        local dock_w = sw - 2 * side

        local days, week_total, active_days = buildDays(self.dates)
        local avg_secs = math.floor(week_total / 7 + 0.5)
        local goal_secs = readDailyGoalSecs()
        local ref_secs = goal_secs > 0 and goal_secs or avg_secs

        local tb = TitleBar:new{
            width = sw,
            fullscreen = true,
            align = "left",
            title = _("Reading progress"),
            _aire_subtitle = T(_("Last 7 days · %1"), fmtDur(week_total)),
            left_icon = "chevron.left",
            left_icon_tap_callback = function() self:onClose() end,
            show_parent = self,
        }

        -- 3 tarjetas KPI unificadas (mismo lenguaje que Estadísticas / Recap)
        local gap = S(10)
        local pad = S(10)
        local cw = math.floor((dock_w - 2 * gap) / 3)
        local function makeKpiCard(title_txt, val_txt, sub_txt, w_card)
            local in_w = math.max(10, w_card - 2 * (pad + Size.border.thin))
            local vg = VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = title_txt, face = face(true, 11), fgcolor = GRAY_TEXT, max_width = in_w, padding = 0 },
                VerticalSpan:new{ width = S(4) },
                TextWidget:new{ text = val_txt, face = face(true, 16), fgcolor = BLACK, max_width = in_w, padding = 0 },
                VerticalSpan:new{ width = S(2) },
                TextWidget:new{ text = sub_txt, face = face(false, 11), fgcolor = GRAY_TEXT, max_width = in_w, padding = 0 },
            }
            return FrameContainer:new{
                bordersize = Size.border.thin,
                color = BLACK,
                background = WHITE,
                radius = S(10),
                padding = pad,
                width = w_card,
                LeftContainer:new{ dimen = Geom:new{ w = in_w, h = vg:getSize().h }, vg },
            }
        end
        local today_pages = self.today_pages or 0
        local c1 = makeKpiCard(_("Today"), fmtDur(self.today_duration),
            T(N_("%1 page", "%1 pages", today_pages), today_pages), cw)
        local c2 = makeKpiCard(_("7 days"), fmtDur(week_total),
            T(_("%1/7 days"), active_days), cw)
        local avg_sub = goal_secs > 0 and T(_("goal %1"), fmtDur(goal_secs)) or _("daily avg.")
        local c3 = makeKpiCard(_("Avg. / day"), fmtDur(avg_secs), avg_sub, dock_w - 2 * (cw + gap))
        local row_cards = HorizontalGroup:new{
            align = "top",
            c1, HorizontalSpan:new{ width = gap },
            c2, HorizontalSpan:new{ width = gap },
            c3,
        }

        -- Tarjeta inferior: Sesión actual (con velocidad págs./h si hay datos)
        local ses_pad = S(10)
        local ses_in_w = dock_w - 2 * (ses_pad + Size.border.thin)
        local cur_secs = tonumber(self.current_duration) or 0
        local cur_pages = tonumber(self.current_pages) or 0
        local speed = (cur_secs >= 60 and cur_pages > 0) and math.floor(cur_pages * 3600 / cur_secs + 0.5) or 0
        local ses_lbl = TextWidget:new{ text = _("CURRENT SESSION"), face = face(true, 11), fgcolor = GRAY_TEXT, padding = 0 }
        local ses_head = ses_lbl
        if speed > 0 then
            local sp_w = TextWidget:new{ text = T(_("%1 pp./h"), speed), face = face(true, 12), fgcolor = BLACK, padding = 0 }
            local hh = math.max(ses_lbl:getSize().h, sp_w:getSize().h)
            ses_head = OverlapGroup:new{
                dimen = Geom:new{ w = ses_in_w, h = hh },
                LeftContainer:new{ dimen = Geom:new{ w = ses_in_w, h = hh }, ses_lbl },
                RightContainer:new{ dimen = Geom:new{ w = ses_in_w, h = hh }, sp_w },
            }
        end
        local ses_vg = VerticalGroup:new{
            align = "left",
            ses_head,
            VerticalSpan:new{ width = S(4) },
            TextWidget:new{
                text = fmtDur(cur_secs) .. " · " .. T(N_("%1 page read", "%1 pages read", cur_pages), cur_pages),
                face = face(true, 15),
                fgcolor = BLACK,
                max_width = ses_in_w,
                padding = 0,
            },
        }
        local ses_card = FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            background = WHITE,
            radius = S(10),
            padding = ses_pad,
            width = dock_w,
            LeftContainer:new{ dimen = Geom:new{ w = ses_in_w, h = ses_vg:getSize().h }, ses_vg },
        }

        -- Tarjeta central: Actividad 7 días con línea de objetivo/media
        local sh = Screen:getHeight()
        local ch_pad = S(10)
        local ch_in_w = dock_w - 2 * (ch_pad + Size.border.thin)
        local ch_lbl = TextWidget:new{ text = _("WEEKLY ACTIVITY"), face = face(true, 11), fgcolor = GRAY_TEXT, padding = 0 }
        local ch_head = ch_lbl
        if ref_secs > 0 then
            local badge_txt = goal_secs > 0 and T(_("goal %1"), fmtDur(goal_secs)) or T(_("avg. %1"), fmtDur(avg_secs))
            local badge = FrameContainer:new{
                bordersize = Size.border.thin,
                color = BLACK,
                radius = S(5),
                padding_top = S(1), padding_bottom = S(1),
                padding_left = S(5), padding_right = S(5),
                TextWidget:new{ text = badge_txt, face = face(true, 11), fgcolor = BLACK, padding = 0 },
            }
            local hh = math.max(ch_lbl:getSize().h, badge:getSize().h)
            ch_head = OverlapGroup:new{
                dimen = Geom:new{ w = ch_in_w, h = hh },
                LeftContainer:new{ dimen = Geom:new{ w = ch_in_w, h = hh }, ch_lbl },
                RightContainer:new{ dimen = Geom:new{ w = ch_in_w, h = hh }, badge },
            }
        end
        local used = tb:getHeight() + row_cards:getSize().h + ses_card:getSize().h + gap * 2 + S(16)
        local bars_h = math.max(S(110), math.min(S(240), sh - used - ch_head:getSize().h - 2 * (ch_pad + Size.border.thin) - S(24)))
        local ch_vg = VerticalGroup:new{
            align = "left",
            ch_head,
            VerticalSpan:new{ width = S(10) },
            buildBarsWidget(ch_in_w, bars_h, days, ref_secs),
        }
        local chart_card = FrameContainer:new{
            bordersize = Size.border.thin,
            color = BLACK,
            background = WHITE,
            radius = S(10),
            padding = ch_pad,
            width = dock_w,
            LeftContainer:new{ dimen = Geom:new{ w = ch_in_w, h = ch_vg:getSize().h }, ch_vg },
        }

        local body = VerticalGroup:new{
            align = "left",
            row_cards,
            VerticalSpan:new{ width = gap },
            chart_card,
            VerticalSpan:new{ width = gap },
            ses_card,
        }
        return VerticalGroup:new{
            align = "center",
            tb,
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = body:getSize().h }, body },
        }
    end, TAG)

    logger.dbg("Aire/ReaderProgress: aplicado desde el plugin")
end

-- Protegido: los parches de plugins se ejecutan dentro de FileManager:init y
-- un error sin pcall impediría arrancar KOReader
userpatch.registerPatchPluginFunc("statistics", function(plugin)
    local ok, err = pcall(patchStatistics, plugin)
    if not ok then logger.warn("Aire/ReaderProgress: no se pudo aplicar:", err) end
end)
