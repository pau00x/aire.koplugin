--[[
    aire.koplugin/styles/skim.lua
    Vista rápida del documento (SkimToWidget), opción B, como hoja inferior:
      - Arriba, el título del capítulo en grande y "Capítulo X de Y · pág.".
      - Barra partida en capítulos: los leídos en negro, el actual hasta la
        página en la que estás. Tocarla salta a esa parte del libro.
      - "Capítulo anterior" / "Siguiente capítulo" y −10 −1 +1 +10.
      - Tocar fuera cierra.
    Se mantiene la clase de KOReader (goToPage, pila de posiciones, modo
    vista rápida de PDF); solo cambia cómo se monta. Si falla, la de KOReader.
--]]

local BottomContainer = require("ui/widget/container/bottomcontainer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Size = require("ui/size")
local SkimToWidget = require("ui/widget/skimtowidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local Blitbuffer = require("ffi/blitbuffer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Skim"

if SkimToWidget._aire_skim then return end
SkimToWidget._aire_skim = true

-- Pantallas comunes (common/pages.lua, cargado una vez en main.lua)
local function getP() return package.loaded.aire_pages end

-- Barra por capítulos
local ChapterBar = Widget:extend{ width = 0, height = 0, ticks = nil, page_count = 1, curr = 1 }
function ChapterBar:getSize() return Geom:new{ w = self.width, h = self.height } end
function ChapterBar:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    local n, total = self.page_count, self.width
    local starts = { 1 }
    for _i, t in ipairs(self.ticks or {}) do
        if t > 1 and t <= n and t > starts[#starts] then table.insert(starts, t) end
    end
    local gap = Screen:scaleBySize(3)
    -- Demasiados capítulos para separarlos: barra continua
    if #starts * (gap + Screen:scaleBySize(4)) > total then starts = { 1 }; gap = 0 end
    local avail = total - gap * (#starts - 1)
    local r = math.floor(self.height / 3)
    local cx = x
    for i, s in ipairs(starts) do
        local e = (starts[i + 1] or (n + 1)) - 1
        local sw = (i == #starts) and (x + total - cx) or math.max(1, math.floor(avail * (e - s + 1) / n))
        bb:paintRoundedRect(cx, y, sw, self.height, Blitbuffer.COLOR_LIGHT_GRAY, r)
        local fill
        if self.curr > e then fill = sw
        elseif self.curr >= s then fill = math.max(r * 2, math.floor(sw * (self.curr - s + 1) / (e - s + 1)))
        end
        if fill then bb:paintRoundedRect(cx, y, math.min(sw, fill), self.height, Blitbuffer.COLOR_BLACK, r) end
        cx = cx + sw + gap
    end
end

local function build(self)
    local P = getP()
    local S = P.S
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local style = ButtonDialog.aire_sheet_style or { margin = 6, radius = 14, pad = 14 }
    local sheet_w = ButtonDialog.aire_sheetWidth and ButtonDialog.aire_sheetWidth() or (sw - 2 * S(6))
    local pad = S(style.pad or 14)
    local in_w = sheet_w - 2 * pad - 2 * Size.border.thin

    local toc = self.ui.toc
    local ticks = toc and toc.getTocTicksFlattened and toc:getTocTicksFlattened() or {}
    local ci, cn = 0, 0
    for _i, t in ipairs(ticks) do
        cn = cn + 1
        if t <= self.curr_page then ci = cn end
    end
    local title = toc and toc.getTocTitleByPage and toc:getTocTitleByPage(self.curr_page) or ""
    if title == "" then title = self.ui.doc_props and (self.ui.doc_props.display_title or self.ui.doc_props.title) or "" end
    local sub = self.curr_page .. " / " .. self.page_count
    if cn > 0 and ci > 0 then sub = T(_("Chapter %1 of %2"), ci, cn) .. " · " .. sub end

    self._aire_bar = ChapterBar:new{ width = in_w, height = S(10), ticks = ticks, page_count = self.page_count,
        curr = self.curr_page }
    local gap = S(8)
    local half = math.floor((in_w - gap) / 2)
    local q = math.floor((in_w - 3 * gap) / 4)
    local function go(p) return function() self:goToPage(p) end end
    local prev_ch = toc and toc:getPreviousChapter(self.curr_page)
    local next_ch = toc and toc:getNextChapter(self.curr_page)
    local content = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = title, face = P.face(true, 17), fgcolor = P.BLACK, max_width = in_w, padding = 0 },
        VerticalSpan:new{ width = S(2) },
        TextWidget:new{ text = sub, face = P.face(false, 13), fgcolor = P.GRAY_DARK, max_width = in_w, padding = 0 },
        VerticalSpan:new{ width = S(12) },
        self._aire_bar,
        VerticalSpan:new{ width = S(12) },
        HorizontalGroup:new{
            align = "center",
            P.pill("‹ " .. _("Previous chapter"), half, prev_ch and go(prev_ch) or nil,
                { disabled = not prev_ch, on_hold = go(1) }),
            HorizontalSpan:new{ width = gap },
            P.pill(_("Next chapter") .. " ›", half, next_ch and go(next_ch) or nil,
                { disabled = not next_ch, on_hold = go(self.page_count) }),
        },
        VerticalSpan:new{ width = gap },
        HorizontalGroup:new{
            align = "center",
            P.pill("−10", q, go(self.curr_page - 10)), HorizontalSpan:new{ width = gap },
            P.pill("−1", q, go(self.curr_page - 1)), HorizontalSpan:new{ width = gap },
            P.pill("+1", q, go(self.curr_page + 1)), HorizontalSpan:new{ width = gap },
            P.pill("+10", q, go(self.curr_page + 10)),
        },
    }
    self.skimto_frame = FrameContainer:new{
        width = sheet_w,
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        radius = S(style.radius or 14),
        padding = pad,
        content,
    }
    self[1] = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh - S(style.margin or 6) },
        self.skimto_frame,
    }
end

safeWrap(SkimToWidget, "init", function(orig_init, self)
    local ok, err = pcall(function()
        if self.ui.paging then self.ui.paging:enterSkimMode() end
        self.curr_page = self.ui:getCurrentPage()
        self.page_count = self.ui.document:getPageCount()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        if Device:hasKeys() then
            self.key_events = self.key_events or {}
            self.key_events.Close = { { Device.input.group.Back } }
        end
        self.ges_events = self.ges_events or {}
        self.ges_events.TapProgress = { GestureRange:new{ ges = "tap", range = self.dimen } }
        build(self)
        self._aire = true
    end)
    if ok then return end
    logger.warn("Aire/Skim:", err)
    self._aire = nil
    if self.ui.paging then pcall(self.ui.paging.exitSkimMode, self.ui.paging) end
    return orig_init(self)
end, TAG)

safeWrap(SkimToWidget, "update", function(orig_update, self, ...)
    if not self._aire then return orig_update(self, ...) end
    if self.curr_page <= 0 then self.curr_page = 1 end
    if self.curr_page > self.page_count then self.curr_page = self.page_count end
    local old = self.skimto_frame and self.skimto_frame.dimen and self.skimto_frame.dimen:copy()
    build(self)
    UIManager:setDirty(self, function() return "ui", old end)
end, TAG)

safeWrap(SkimToWidget, "onTapProgress", function(orig_tap, self, arg, ges_ev)
    if not self._aire then return orig_tap(self, arg, ges_ev) end
    local bar = self._aire_bar
    local pos = ges_ev and ges_ev.pos
    if pos and bar and bar.dimen and pos:intersectWith(bar.dimen) then
        local frac = (pos.x - bar.dimen.x) / math.max(1, bar.dimen.w)
        self:goToPage(math.max(1, math.min(self.page_count, math.floor(frac * self.page_count + 0.5))))
    elseif pos and self.skimto_frame and self.skimto_frame.dimen and not pos:intersectWith(self.skimto_frame.dimen) then
        self:onClose()
    end
    return true
end, TAG)

logger.dbg("Aire/Skim: aplicado desde el plugin")
