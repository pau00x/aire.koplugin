--[[
    aire.koplugin/styles/filemanager/sortwidget.lua
    Pantalla de ordenar de KOReader (SortWidget): "Ordenar colecciones" y
    otras listas que se ordenan a mano. Se carga una vez desde main.lua,
    después de styles/ui/init.lua (que ya le pone la barra de título de Aire).

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
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (ui/screen.lua)
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
            -- (relleno de las tarjetas de lista: ui/screen.lua)
            table.insert(row, HorizontalSpan:new{ width = S(package.loaded.aire_screen.LIST.CARD_PAD) })
            check_w = S(package.loaded.aire_screen.LIST.CARD_PAD) - S(8)
        end
        table.insert(row, TextWidget:new{
            text = self.item.text,
            face = face(false, 15),
            fgcolor = inv and WHITE or (self.item.dim and GRAY_DARK or BLACK),
            max_width = w - check_w - S(8) - S(package.loaded.aire_screen.LIST.CARD_PAD) - 2 * Size.border.thin,
            padding = 0,
        })
        self[1] = FrameContainer:new{
            width = w,
            height = h,
            bordersize = Size.border.thin,
            color = inv and BLACK or GRAY_LINE,
            background = inv and BLACK or WHITE,
            radius = S(package.loaded.aire_screen.LIST.CARD_RADIUS), -- (tarjeta de lista: ui/screen.lua)
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
    local row
    if sw.sort_disabled then
        -- Lista solo para elegir ("Mover a libro"…): nada que subir o bajar, y
        -- de página se cambia con los puntos o deslizando. Solo Cerrar y Aplicar.
        local hw = math.floor((w - 2 * side - gap) / 2)
        row = HorizontalGroup:new{
            align = "center",
            pill(sw, hw, _("Close"), nil, false, true, tapBtn(sw.footer_cancel)),
            HorizontalSpan:new{ width = gap },
            pill(sw, hw, _("Apply"), nil, true, true, tapBtn(sw.footer_ok)),
        }
    else
        local up_enabled = marked and (fu and fu.enabled ~= false) or false
        local down_enabled = marked and (ld and ld.enabled ~= false) or false
        row = HorizontalGroup:new{
            align = "center",
            pill(sw, bw, marked and _("Cancel") or _("Close"), nil, false, true, tapBtn(sw.footer_cancel)),
            HorizontalSpan:new{ width = gap },
            pill(sw, bw, nil, "move.up", false, up_enabled, tapBtn(fu)),
            HorizontalSpan:new{ width = gap },
            pill(sw, bw, nil, "move.down", false, down_enabled, tapBtn(ld)),
            HorizontalSpan:new{ width = gap },
            pill(sw, bw, _("Apply"), nil, true, true, tapBtn(sw.footer_ok)),
        }
    end
    -- Como los puntos sobre el dock (ui/screen.lua): puntos, el mismo
    -- hueco, los botones y el margen inferior del dock
    local MT = package.loaded.aire_screen.METRICS
    local vg = VerticalGroup:new{ align = "center" }
    if DotPager then
        table.insert(vg, DotPager:new{ get_state = function() return sw.show_page or 1, sw.pages or 1 end })
        table.insert(vg, VerticalSpan:new{ width = S(MT.DOTS_BOTTOM) })
    end
    table.insert(vg, row)
    table.insert(vg, VerticalSpan:new{ width = S(MT.DOCK_MARGIN_BOTTOM) })
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
    local MT = package.loaded.aire_screen.METRICS
    -- Márgenes de Aire (ui/screen.lua): tarjetas a SIDE de los lados (KOReader
    -- dejaba su padding.large) y separadas como las demás listas (GAP)
    self.item_width = self.dimen.w - 2 * S(SIDE)
    self.item_margin = S(GAP)
    -- Hueco bajo la barra de título: el común, contando el margen que KOReader
    -- pone encima de cada tarjeta. Con varias páginas KOReader centraba la lista
    -- con un hueco calculado para su pie (no el de Aire): la lista y los puntos
    -- quedaban descolocados (p. ej. "Mover a libro" del vocabulario)
    local top_gap = math.max(0, S(MT.CONTENT_GAP) - self.item_margin)
    local frame_content = self[1] and self[1][1] and self[1][1][1]
    local vg = frame_content and frame_content[1]
    if type(vg) == "table" and vg[2] and vg[2].width ~= nil and vg.resetLayout then
        vg[2].width = top_gap
        vg:resetLayout()
    end
    -- Filas por página con este pie (KOReader las calculó con el suyo) y el
    -- hueco común entre la última tarjeta y los puntos
    local footer_h = buildFooter(self)[1]:getSize().h
    local th = self.title_bar and self.title_bar:getHeight() or 0
    local line_h = (self.item_height or S(48)) + self.item_margin
    local per = math.max(1, math.floor((self.dimen.h - th - top_gap - footer_h - S(MT.DOTS_GAP)) / line_h))
    self.items_per_page = per
    self.pages = math.max(1, math.ceil(#self.item_table / per))
    self.show_page = math.min(self.show_page or 1, self.pages)
    self:_populateItems()
    placeFooter(self)
    return unpack(res)
end, TAG)

safeWrap(SortWidget, "_populateItems", function(orig, self, ...)
    local res = { orig(self, ...) }
    placeFooter(self)
    return unpack(res)
end, TAG)

-- Menú ≡ de SortWidget ("Ordenar de la A a la Z"…): como hoja inferior de
-- Aire en lugar de popup flotante anclado al icono.
if type(SortWidget.onShowWidgetMenu) == "function" then
    local ButtonDialog = require("ui/widget/buttondialog")
    safeWrap(SortWidget, "onShowWidgetMenu", function(orig, self, ...)
        return AireUI.withTemporaryNew(ButtonDialog, function(base_new, cls, o)
            if type(o) == "table" then
                o.anchor = nil
                o.shrink_unneeded_width = nil
                if not o.title or o.title == "" then
                    o.title = self.title
                end
            end
            return base_new(cls, o)
        end, orig, self, ...)
    end, TAG)
end

logger.dbg("Aire/SortWidget: aplicado desde el plugin")
