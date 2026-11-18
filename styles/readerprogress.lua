--[[
    aire.koplugin/styles/readerprogress.lua
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
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local AireUI = package.loaded.aire_ui
local S = AireUI.S



local function fmtDur(secs)
    local fmt = G_reader_settings:readSetting("duration_format")
    return datetime.secondsToClockDuration(fmt, math.max(0, tonumber(secs) or 0), true, true)
end

local function buildDays(dates)
    local map = {}
    for _i, d in ipairs(dates or {}) do
        if d[3] and d[2] then map[d[3]] = tonumber(d[2]) or 0 end
    end
    local now = os.time()
    local days, total = {}, 0
    for offset = 6, 0, -1 do
        local t = now - offset * 86400
        local key = os.date("%Y-%m-%d", t)
        local secs = map[key] or 0
        total = total + secs
        table.insert(days, {
            letter = AireUI.dayLetter(os.date("*t", t).wday),
            secs = secs,
            is_today = (offset == 0),
        })
    end
    return days, total
end

local function buildBarsWidget(w, h, days)
    local max_s = 1
    for _i, d in ipairs(days) do
        if d.secs > max_s then max_s = d.secs end
    end
    local label_face = Font:getFace("cfont", 12)
    local lbl_h = S(20)
    local chart_h = math.max(S(40), h - lbl_h - S(8))
    local n = #days
    local col_w = math.floor(w / n)
    local bar_w = math.min(S(28), math.floor(col_w * 0.55))
    local r = S(5)

    local bars = Widget:new{
        dimen = Geom:new{ w = w, h = chart_h },
        paintTo = function(_self, bb, x, y)
            for i, d in ipairs(days) do
                local cx = x + (i - 1) * col_w + math.floor((col_w - bar_w) / 2)
                local bh = d.secs > 0 and math.max(S(6), math.floor(chart_h * d.secs / max_s)) or S(3)
                local col = d.secs == 0 and Blitbuffer.COLOR_GRAY_D
                    or (d.is_today and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_GRAY)
                bb:paintRoundedRect(cx, y + chart_h - bh, bar_w, bh, col, math.min(r, math.floor(bh / 2)))
            end
        end,
    }
    local letters = HorizontalGroup:new{ align = "center" }
    for i, d in ipairs(days) do
        table.insert(letters, CenterContainer:new{
            dimen = Geom:new{ w = col_w, h = lbl_h },
            TextWidget:new{
                text = d.letter,
                face = label_face,
                bold = d.is_today,
                fgcolor = d.is_today and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
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

        TitleBar._aire_pending_subtitle = _("Last 7 days summary")
        local tb = TitleBar:new{
            width = sw,
            fullscreen = true,
            align = "left",
            title = _("Reading progress"),
            left_icon = "chevron.left",
            left_icon_tap_callback = function() self:onClose() end,
            show_parent = self,
        }
        TitleBar._aire_pending_subtitle = nil

        local days, week_total = buildDays(self.dates)
        local avg_secs = math.floor(week_total / 7 + 0.5)

        -- 3 Tarjetas métricas arriba
        local gap = S(8)
        local pad = S(10)
        local cw = math.floor((dock_w - 2 * gap) / 3)
        local function makeCard(val, sub, w_card)
            local in_w = math.max(10, w_card - 2 * (pad + Size.border.thin))
            local vg = VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = val, face = Font:getFace("cfont", 16), bold = true, max_width = in_w, padding = 0 },
                VerticalSpan:new{ width = S(3) },
                TextWidget:new{ text = sub, face = Font:getFace("cfont", 12), fgcolor = Blitbuffer.COLOR_DARK_GRAY, max_width = in_w, padding = 0 },
            }
            return FrameContainer:new{
                bordersize = Size.border.thin,
                color = Blitbuffer.COLOR_GRAY,
                background = Blitbuffer.COLOR_GRAY_E,
                radius = S(10),
                padding = pad,
                LeftContainer:new{ dimen = Geom:new{ w = in_w, h = vg:getSize().h }, vg },
            }
        end
        local c1 = makeCard(fmtDur(self.today_duration), T(_("today · %1 pp."), self.today_pages or 0), cw)
        local c2 = makeCard(fmtDur(week_total), _("last 7 days"), cw)
        local c3 = makeCard(fmtDur(avg_secs), _("avg. / day"), dock_w - 2 * (cw + gap))
        local row_cards = HorizontalGroup:new{
            align = "top",
            c1, HorizontalSpan:new{ width = gap },
            c2, HorizontalSpan:new{ width = gap },
            c3,
        }

        -- Tarjeta inferior: Sesión actual
        local ses_pad = S(12)
        local ses_in_w = dock_w - 2 * (ses_pad + Size.border.thin)
        local ses_vg = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = _("CURRENT SESSION"), face = Font:getFace("cfont", 11), bold = true, fgcolor = Blitbuffer.COLOR_DARK_GRAY, padding = 0 },
            VerticalSpan:new{ width = S(4) },
            TextWidget:new{
                text = fmtDur(self.current_duration) .. " · " .. T(N_("%1 page read", "%1 pages read", self.current_pages or 0), self.current_pages or 0),
                face = Font:getFace("cfont", 15),
                bold = true,
                max_width = ses_in_w,
                padding = 0,
            },
        }
        local ses_card = FrameContainer:new{
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_GRAY,
            background = Blitbuffer.COLOR_GRAY_E,
            radius = S(10),
            padding = ses_pad,
            LeftContainer:new{ dimen = Geom:new{ w = ses_in_w, h = ses_vg:getSize().h }, ses_vg },
        }

        -- Tarjeta central: Gráfico de barras 7 días
        local sh = Screen:getHeight()
        local ch_pad = S(12)
        local ch_in_w = dock_w - 2 * (ch_pad + Size.border.thin)
        local ch_lbl = TextWidget:new{ text = _("WEEKLY ACTIVITY"), face = Font:getFace("cfont", 11), bold = true, fgcolor = Blitbuffer.COLOR_DARK_GRAY, padding = 0 }
        local used = tb:getHeight() + row_cards:getSize().h + ses_card:getSize().h + S(12) * 2 + S(16)
        local bars_h = math.max(S(110), math.min(S(240), sh - used - ch_lbl:getSize().h - 2 * (ch_pad + Size.border.thin) - S(24)))
        local chart_card = FrameContainer:new{
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            radius = S(10),
            padding = ch_pad,
            VerticalGroup:new{
                align = "left",
                ch_lbl,
                VerticalSpan:new{ width = S(10) },
                buildBarsWidget(ch_in_w, bars_h, days),
            },
        }

        local body = VerticalGroup:new{
            align = "left",
            row_cards,
            VerticalSpan:new{ width = S(12) },
            chart_card,
            VerticalSpan:new{ width = S(12) },
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
