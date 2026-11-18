--[[
    aire.koplugin/styles/bookstatus.lua
    Rediseño moderno (Opción A) de BookStatusWidget ("Estado del libro"):
      - Cabecera unificada de pantalla completa (barra de estado + ‹ Estado del libro + archivo)
      - Hero compacto: portada redondeada + título + autor + barra de progreso + resumen
      - Tarjeta gris "ESTADO DE LECTURA" con 3 píldoras (Leyendo / En pausa / Terminado)
      - Tarjeta gris "VALORACIÓN" con etiqueta dinámica ("X de 5 estrellas") y 5 estrellas
      - Tarjeta blanca redondeada "RESEÑA / NOTAS" que ocupa el resto del alto disponible
--]]

local BookList = require("ui/widget/booklist")
local BookStatusWidget = require("ui/widget/bookstatuswidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local RenderImage = require("ui/renderimage")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/BookStatus"
local C_ = _.pgettext
local T = require("ffi/util").template
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local AireUI = package.loaded.aire_ui
local S, face, BLACK, WHITE, GRAY_DARK, GRAY_CARD, GRAY_BORDER = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_CARD, AireUI.GRAY_BORDER

if BookStatusWidget._aire_styled then return end
BookStatusWidget._aire_styled = true



local STATUS_OPTIONS = {
    { key = "reading",   label = C_("aire", "Reading") },
    { key = "abandoned", label = C_("aire", "On hold") },
    { key = "complete",  label = C_("aire", "Finished") },
}

local function ratingLabel(num)
    local n = tonumber(num) or 0
    if n <= 0 then return _("Not rated") end
    if n == 1 then return _("1 of 5 stars") end
    return string.format(_("%d of 5 stars"), n)
end

local function wrapTappable(widget, on_tap)
    local ic = InputContainer:new{ widget }
    ic.ges_events = {
        AireTap = { GestureRange:new{
            ges = "tap",
            range = function() return ic.dimen or Geom:new{ x = 0, y = 0, w = 0, h = 0 } end,
        } },
    }
    ic.onAireTap = function()
        on_tap()
        return true
    end
    return ic
end

safeWrap(BookStatusWidget, "setStar", function(_orig, self, num)
    if not self.stars_container then return true end
    self.stars_container:clear()

    local star_sz = S(28)
    local function makeStar(icon_name, idx)
        local ic_w = IconWidget:new{ icon = icon_name, width = star_sz, height = star_sz, alpha = true }
        if self.readonly then
            return ic_w
        end
        return wrapTappable(ic_w, function() self:setStar(idx) end)
    end

    local stars_group = HorizontalGroup:new{ align = "center" }
    local row = {}
    if num then
        num = (num == 1 and self.summary and self.summary.rating == 1) and 0 or num
        if self.summary then
            self.summary.rating = num ~= 0 and num or nil
        end
        if self.ui and self.ui.document and self.ui.document.file then
            BookList.setBookInfoCacheProperty(self.ui.document.file, "rating", num)
        end
        self.updated = true

        for i = 1, num do
            if i > 1 then table.insert(stars_group, HorizontalSpan:new{ width = S(4) }) end
            local star = makeStar("star.full", i)
            table.insert(stars_group, star)
            table.insert(row, star)
        end
    else
        num = 0
    end

    for i = num + 1, 5 do
        if i > 1 then table.insert(stars_group, HorizontalSpan:new{ width = S(4) }) end
        local star = makeStar("star.empty", i)
        table.insert(stars_group, star)
        table.insert(row, star)
    end
    self.layout[1] = row
    table.insert(self.stars_container, stars_group)

    if self._aire_rating_label_w then
        self._aire_rating_label_w:setText(ratingLabel(num))
    end
    self:refocusWidget()
    UIManager:setDirty(self, "ui", nil, true)
    return true
end, TAG)

function BookStatusWidget:_aireBuildHero(inner_w)
    local props = self.ui and self.ui.doc_props or {}
    local lang = props.language
    local cov_w, cov_h = S(84), S(126)
    local rounded = FileManager._aire_rounded_covers == true

    local cover_widget
    local thumb = self.ui and self.ui.bookinfo and self.ui.bookinfo:getCoverImage(self.ui.document)
    if thumb then
        local cbb_w, cbb_h = thumb:getWidth(), thumb:getHeight()
        local scale = math.min(cov_w / cbb_w, cov_h / cbb_h)
        local tw = math.max(1, math.min(cov_w, math.floor(cbb_w * scale + 0.5)))
        local th = math.max(1, math.min(cov_h, math.floor(cbb_h * scale + 0.5)))
        if tw ~= cbb_w or th ~= cbb_h then
            thumb = RenderImage:scaleBlitBuffer(thumb, tw, th, true)
        end
        cover_widget = FrameContainer:new{
            bordersize = Size.border.thin,
            color = GRAY_BORDER,
            radius = rounded and S(8) or 0,
            _aire_clip_corners = rounded,
            padding = 0,
            margin = 0,
            ImageWidget:new{ image = thumb, width = tw, height = th },
        }
    else
        cover_widget = FrameContainer:new{
            width = cov_w,
            height = cov_h,
            bordersize = Size.border.thin,
            color = GRAY_BORDER,
            background = GRAY_CARD,
            radius = rounded and S(8) or 0,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = cov_w - 2 * Size.border.thin, h = cov_h - 2 * Size.border.thin },
                TextWidget:new{ text = "—", face = face(false, 16), fgcolor = GRAY_DARK },
            },
        }
    end

    local gap = S(14)
    local text_w = math.max(S(100), inner_w - cover_widget:getSize().w - gap)
    local cur_page = (self.ui and self.ui.getCurrentPage and self.ui:getCurrentPage()) or 1
    local total_pages = math.max(1, tonumber(self.total_pages) or 1)
    local pct = math.max(0, math.min(1, cur_page / total_pages))

    local meta = VerticalGroup:new{ align = "left" }
    table.insert(meta, TextBoxWidget:new{
        text = props.display_title or props.title or _("Book"),
        lang = lang,
        face = face(true, 16),
        fgcolor = BLACK,
        width = text_w,
        padding = 0,
    })
    if props.authors and props.authors ~= "" then
        table.insert(meta, VerticalSpan:new{ width = S(3) })
        table.insert(meta, TextBoxWidget:new{
            text = props.authors,
            lang = lang,
            face = face(false, 13),
            fgcolor = GRAY_DARK,
            width = text_w,
            padding = 0,
        })
    end
    table.insert(meta, VerticalSpan:new{ width = S(10) })
    table.insert(meta, ProgressWidget:new{
        width = text_w,
        height = S(8),
        percentage = pct,
        bordersize = 0,
        margin_h = 0,
        margin_v = 0,
        bgcolor = GRAY_CARD,
        fillcolor = BLACK,
        ticks = nil,
        last = nil,
    })
    table.insert(meta, VerticalSpan:new{ width = S(6) })
    local hours = self.getStatHours and self:getStatHours() or "—"
    table.insert(meta, TextBoxWidget:new{
        text = string.format("%d %%", math.floor(pct * 100 + 0.5)) .. " · " .. T(_("p. %1 of %2"), cur_page, total_pages) .. " · " .. hours,
        face = face(false, 12),
        fgcolor = GRAY_DARK,
        width = text_w,
        padding = 0,
    })

    local row_h = math.max(cover_widget:getSize().h, meta:getSize().h)
    return HorizontalGroup:new{
        align = "center",
        cover_widget,
        HorizontalSpan:new{ width = gap },
        CenterContainer:new{
            dimen = Geom:new{ w = text_w, h = row_h },
            LeftContainer:new{ dimen = Geom:new{ w = text_w, h = row_h }, meta },
        },
    }
end

function BookStatusWidget:_aireBuildStatusCard(inner_w)
    local pad = S(14)
    local card_in = inner_w - 2 * pad - 2 * Size.border.thin
    local gap = S(8)
    local pill_w = math.floor((card_in - 2 * gap) / 3)
    local pill_h = S(36)

    local row = HorizontalGroup:new{ align = "center" }
    local function rebuildPills()
        row:clear()
        local cur = (self.summary and self.summary.status) or "reading"
        for i, opt in ipairs(STATUS_OPTIONS) do
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
            local active = (cur == opt.key)
            local lbl = TextWidget:new{
                text = opt.label,
                face = face(active, 13),
                fgcolor = active and WHITE or BLACK,
                max_width = pill_w - S(8),
                padding = 0,
            }
            local pill = FrameContainer:new{
                width = pill_w,
                height = pill_h,
                bordersize = Size.border.thin,
                color = active and BLACK or GRAY_BORDER,
                background = active and BLACK or WHITE,
                radius = S(9),
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = pill_w - 2 * Size.border.thin, h = pill_h - 2 * Size.border.thin },
                    lbl,
                },
            }
            if not self.readonly then
                pill = wrapTappable(pill, function()
                    -- KOReader espera (lista_de_opciones, índice): option_name[option_value].
                    -- Con (clave, i) el estado se guardaba vacío (("reading")[1] == nil).
                    self:onChangeBookStatus({ opt.key }, 1)
                    rebuildPills()
                    UIManager:setDirty(self, "ui")
                end)
            end
            table.insert(row, pill)
        end
        row:resetLayout()
    end
    rebuildPills()

    return FrameContainer:new{
        width = inner_w,
        bordersize = Size.border.thin,
        color = GRAY_BORDER,
        background = GRAY_CARD,
        radius = S(12),
        padding = pad,
        VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = _("READING STATUS"), face = face(true, 11), fgcolor = GRAY_DARK, padding = 0 },
            VerticalSpan:new{ width = S(10) },
            row,
        },
    }
end

function BookStatusWidget:_aireBuildRatingCard(inner_w)
    local pad = S(14)
    local card_in = inner_w - 2 * pad - 2 * Size.border.thin
    local cur_rating = self.summary and self.summary.rating or 0

    self._aire_rating_label_w = TextWidget:new{
        text = ratingLabel(cur_rating),
        face = face(false, 12),
        fgcolor = GRAY_DARK,
        padding = 0,
    }
    local left_col = VerticalGroup:new{
        align = "left",
        TextWidget:new{ text = _("RATING"), face = face(true, 11), fgcolor = GRAY_DARK, padding = 0 },
        VerticalSpan:new{ width = S(3) },
        self._aire_rating_label_w,
    }

    local stars_w = math.floor(card_in * 0.56)
    local stars_h = S(36)
    self.stars_container = RightContainer:new{
        dimen = Geom:new{ w = stars_w, h = stars_h },
    }
    self:setStar(cur_rating)

    local row_h = math.max(left_col:getSize().h, stars_h)
    return FrameContainer:new{
        width = inner_w,
        bordersize = Size.border.thin,
        color = GRAY_BORDER,
        background = GRAY_CARD,
        radius = S(12),
        padding = pad,
        OverlapGroup:new{
            dimen = Geom:new{ w = card_in, h = row_h },
            LeftContainer:new{ dimen = Geom:new{ w = card_in, h = row_h }, left_col },
            RightContainer:new{ dimen = Geom:new{ w = card_in, h = row_h }, self.stars_container },
        },
    }
end

safeWrap(BookStatusWidget, "getStatusContent", function(_orig, self, width)
    local doc = self.ui and self.ui.document
    local sub = doc and doc.file and select(2, util.splitFilePathName(doc.file))
    if not sub or sub == "" then
        local props = self.ui and self.ui.doc_props
        sub = props and (props.display_title or props.title) or _("Rating and review")
    end

    local title_bar = TitleBar:new{
        fullscreen = true,
        width = width,
        title = _("Book status"),
        _aire_subtitle = sub,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    local side = S(SIDE)
    local inner_w = width - 2 * side
    local hero = self:_aireBuildHero(inner_w)
    local status_card = self:_aireBuildStatusCard(inner_w)
    local rating_card = self:_aireBuildRatingCard(inner_w)

    local top_group = VerticalGroup:new{
        align = "left",
        title_bar,
        FrameContainer:new{
            bordersize = 0,
            padding = 0,
            padding_left = side,
            padding_right = side,
            VerticalGroup:new{
                align = "left",
                VerticalSpan:new{ width = S(4) },
                hero,
                VerticalSpan:new{ width = S(14) },
                status_card,
                VerticalSpan:new{ width = S(10) },
                rating_card,
                VerticalSpan:new{ width = S(10) },
            },
        },
    }

    local pad = S(14)
    local bottom_pad = S(16)
    local used_h = top_group:getSize().h
    local review_card_h = math.max(S(140), Screen:getHeight() - used_h - bottom_pad)
    local review_in_w = inner_w - 2 * pad - 2 * Size.border.thin
    local lbl_w = TextWidget:new{ text = _("REVIEW / NOTES"), face = face(true, 11), fgcolor = GRAY_DARK, padding = 0 }
    local note_h = math.max(S(80), review_card_h - 2 * pad - 2 * Size.border.thin - lbl_w:getSize().h - S(8))

    local has_note = self.summary and self.summary.note and #self.summary.note > 0
    self.note_widget = TextBoxWidget:new{
        text = has_note and self.summary.note or (not self.readonly and _("Tap to add or edit your review of this book…") or ""),
        face = face(false, 14),
        fgcolor = has_note and BLACK or GRAY_DARK,
        width = review_in_w,
        height = note_h,
        scroll = true,
        readonly = self.readonly,
        parent = self,
    }

    self.note_frame = FrameContainer:new{
        width = inner_w,
        height = review_card_h,
        bordersize = Size.border.thin,
        color = GRAY_BORDER,
        background = WHITE,
        radius = S(12),
        padding = pad,
        VerticalGroup:new{
            align = "left",
            lbl_w,
            VerticalSpan:new{ width = S(8) },
            self.note_widget,
        },
    }
    if not self.readonly then
        self.note_frame.onGesture = function(_frame, ev)
            if ev and ev.ges == "tap" and ev.pos
                and self.note_frame and self.note_frame.dimen
                and ev.pos:intersectWith(self.note_frame.dimen)
            then
                return self:openReviewDialog()
            end
            return false
        end
    end
    table.insert(self.layout, { self.note_frame })

    table.insert(top_group, FrameContainer:new{
        bordersize = 0,
        padding = 0,
        padding_left = side,
        padding_right = side,
        padding_bottom = bottom_pad,
        self.note_frame,
    })
    top_group:resetLayout()
    return top_group
end, TAG)

logger.dbg("Aire/BookStatus: aplicado desde el plugin")
