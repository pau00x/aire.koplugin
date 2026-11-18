--[[
    aire.koplugin/styles/sortwidget.lua
    Pantalla de ordenar de KOReader (SortWidget): "Ordenar colecciones" y
    otras listas que se ordenan a mano. Se carga una vez desde main.lua,
    después de styles/ui.lua (que ya le pone la barra de título de Aire).

      - Cada fila en una tarjeta redondeada; la elegida para mover, en negro
        (KOReader invertía el rectángulo entero, con esquinas cuadradas).
      - Abajo: puntos de página (como el resto de listas de Aire; deslizar
        cambia de página, igual que antes) y cuatro botones: Cerrar / Cancelar,
        primera página o subir al principio, última página o bajar al final,
        y Aplicar. Hacen lo mismo que los de KOReader, que siguen ahí sin verse.
--]]

local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local SortWidget = require("ui/widget/sortwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local AireUI = package.loaded.aire_ui
local S, face, BLACK, WHITE, GRAY_DARK, GRAY_LINE = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_LINE
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local safeWrap = AireUI.safeWrap
local TAG = "Aire/SortWidget"

if SortWidget._aire_styled then return end
SortWidget._aire_styled = true

local BTN_H = 44
local GAP = 8

-- Filas: tarjeta redondeada (la marcada para mover, en negro)
local SortItemWidget = AireUI.getUpValue(SortWidget._populateItems, "SortItemWidget")
if SortItemWidget and not SortItemWidget._aire_card then
    SortItemWidget._aire_card = true
    safeWrap(SortItemWidget, "init", function(orig, self)
        orig(self)
        local inv = self.invert and true or false
        local w, h = self.width, self.height
        local inner_h = h - 2 * Size.border.thin
        local row = HorizontalGroup:new{ align = "center" }
        local check_w = 0
        if self.item.checked_func or self.item.checked ~= nil then
            check_w = self.checkmark_widget:getSize().w
            table.insert(row, CenterContainer:new{ dimen = Geom:new{ w = check_w + S(8), h = inner_h }, self.checkmark_widget })
        else
            table.insert(row, HorizontalSpan:new{ width = S(14) })
            check_w = S(14) - S(8)
        end
        table.insert(row, TextWidget:new{
            text = self.item.text,
            face = face(false, 15),
            fgcolor = inv and WHITE or (self.item.dim and GRAY_DARK or BLACK),
            max_width = w - check_w - S(8) - S(14) - 2 * Size.border.thin,
            padding = 0,
        })
        self[1] = FrameContainer:new{
            width = w,
            height = h,
            bordersize = Size.border.thin,
            color = inv and BLACK or GRAY_LINE,
            background = inv and BLACK or WHITE,
            radius = S(10),
            padding = 0,
            focusable = true,
            focus_border_size = Size.border.thin,
            LeftContainer:new{ dimen = Geom:new{ w = w - 2 * Size.border.thin, h = inner_h }, row },
        }
    end, TAG)
end

-- Botón redondeado con texto o icono; apagado si no se puede usar
local function pill(sw, w, label, icon, primary, enabled, cb)
    local inner
    if icon then
        inner = IconWidget:new{ icon = icon, width = S(26), height = S(26), alpha = true, dim = not enabled or nil }
    else
        inner = TextWidget:new{ text = label, face = face(primary, 15), padding = 0, max_width = w - S(10),
            fgcolor = primary and WHITE or (enabled and BLACK or GRAY_DARK) }
    end
    local h = S(BTN_H)
    local frame = FrameContainer:new{
        width = w, height = h, bordersize = Size.border.thin,
        color = primary and BLACK or GRAY_LINE,
        background = primary and BLACK or WHITE,
        radius = S(10), padding = 0,
        CenterContainer:new{ dimen = Geom:new{ w = w - 2 * Size.border.thin, h = h - 2 * Size.border.thin }, inner },
    }
    if not enabled then return frame end
    return AireUI.tappable(frame, cb)
end

local function buildFooter(sw)
    local DotPager = require("ui/widget/menu")._aire_dot_pager_cls
    local w = sw.dimen.w
    local side = S(SIDE)
    local gap = S(GAP)
    local bw = math.floor((w - 2 * side - 3 * gap) / 4)
    local marked = (sw.marked or 0) > 0
    local fu, ld = sw.footer_first_up, sw.footer_last_down
    local function tapBtn(btn) return function() if btn and btn.callback then btn.callback() end end end
    local row = HorizontalGroup:new{
        align = "center",
        pill(sw, bw, marked and _("Cancel") or _("Close"), nil, false, true, tapBtn(sw.footer_cancel)),
        HorizontalSpan:new{ width = gap },
        pill(sw, bw, nil, marked and "move.up" or "chevron.first", false, fu and fu.enabled ~= false, tapBtn(fu)),
        HorizontalSpan:new{ width = gap },
        pill(sw, bw, nil, marked and "move.down" or "chevron.last", false, ld and ld.enabled ~= false, tapBtn(ld)),
        HorizontalSpan:new{ width = gap },
        pill(sw, bw, _("Apply"), nil, true, true, tapBtn(sw.footer_ok)),
    }
    local vg = VerticalGroup:new{ align = "center" }
    if DotPager then
        table.insert(vg, DotPager:new{ get_state = function() return sw.show_page or 1, sw.pages or 1 end })
    end
    table.insert(vg, row)
    table.insert(vg, VerticalSpan:new{ width = S(12) })
    return BottomContainer:new{ dimen = sw.dimen:copy(), vg }
end

-- Pie de página: el de Aire en lugar del de KOReader (se rehace en cada
-- página, porque los botones cambian al elegir una fila)
local function placeFooter(sw)
    local content = sw[1] and sw[1][1]
    if type(content) ~= "table" or not content[2] then return end
    content[2] = buildFooter(sw)
end

safeWrap(SortWidget, "init", function(orig, self, ...)
    local res = { orig(self, ...) }
    -- Hueco bajo la barra de título (la primera tarjeta quedaba pegada)
    local frame_content = self[1] and self[1][1] and self[1][1][1]
    local vg = frame_content and frame_content[1]
    if type(vg) == "table" and vg[2] and vg[2].width ~= nil and vg.resetLayout then
        vg[2].width = math.max(vg[2].width or 0, S(12))
        vg:resetLayout()
    end
    -- Filas por página con el alto de este pie (KOReader las calculó con el suyo)
    local footer_h = buildFooter(self)[1]:getSize().h
    local th = self.title_bar and self.title_bar:getHeight() or 0
    local line_h = (self.item_height or S(48)) + (self.item_margin or 0)
    local per = math.max(1, math.floor((self.dimen.h - th - S(12) - footer_h - Size.padding.large) / line_h))
    if per ~= self.items_per_page then
        self.items_per_page = per
        self.pages = math.max(1, math.ceil(#self.item_table / per))
        self.show_page = math.min(self.show_page or 1, self.pages)
        self:_populateItems()
    end
    placeFooter(self)
    return unpack(res)
end, TAG)

safeWrap(SortWidget, "_populateItems", function(orig, self, ...)
    local res = { orig(self, ...) }
    placeFooter(self)
    return unpack(res)
end, TAG)

logger.dbg("Aire/SortWidget: aplicado desde el plugin")
