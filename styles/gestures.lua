--[[
    aire.koplugin/styles/gestures.lua
    Resumen de gestos (plugin Gestures), opción B:
      - Arriba, la pantalla dibujada con lo que hace tocar cada esquina.
      - Debajo, el resto de gestos por secciones (cabecera gris + filas
        gesto / acción). Los de varias acciones se tocan para ver el detalle.
    Mismos datos que KOReader: se deja que su función monte la lista y se
    muestra con las piezas de common/pages.lua. Si falla, la de KOReader.
--]]

local Dispatcher = require("dispatcher")
local Geom = require("ui/geometry")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalSpan = require("ui/widget/verticalspan")
local Size = require("ui/size")
local logger = require("logger")

local _ = require("gettext")
local T = require("ffi/util").template

-- Pantallas comunes (common/pages.lua, cargado una vez en main.lua)
local function getP() return package.loaded.aire_pages end

local CORNERS = {
    { id = "tap_top_left_corner",     v = TopContainer,    h = LeftContainer },
    { id = "tap_top_right_corner",    v = TopContainer,    h = RightContainer },
    { id = "tap_left_bottom_corner",  v = BottomContainer, h = LeftContainer },
    { id = "tap_right_bottom_corner", v = BottomContainer, h = RightContainer },
}

-- Nombres de los gestos (local de gestures.koplugin), capturado de la función
-- original antes de envolverla
local GESTURES_LIST = {}

local function buildPage(gestures, o)
    local P = getP()
    local S = P.S
    local nothing = Dispatcher:menuTextFunc({})
    local gestures_list = GESTURES_LIST
    -- Nombres de las esquinas (para quitarlas de la lista: van en el dibujo)
    local corner_names = {}
    for _i, c in ipairs(CORNERS) do
        if gestures_list[c.id] then corner_names[gestures_list[c.id]] = true end
    end

    -- Subtítulo: cuántos gestos tienen una acción
    local n_set = 0
    for _id, g in pairs(gestures.gestures or {}) do
        local txt = Dispatcher:menuTextFunc(g)
        if txt and txt ~= nothing then n_set = n_set + 1 end
    end

    return P.Page:new{
        title = o.title,
        subtitle = T(_("Gestures set: %1"), n_set),
        build = function(_pg, w, h)
            local widgets = {}
            -- Dibujo de la pantalla con las 4 esquinas
            local map_h = math.floor(w * 0.62)
            local in_w = w - 2 * Size.border.thin
            local in_h = map_h - 2 * Size.border.thin
            local og = OverlapGroup:new{ dimen = Geom:new{ w = in_w, h = in_h } }
            local pad = S(8)
            for _i, c in ipairs(CORNERS) do
                local g = gestures.gestures and gestures.gestures[c.id]
                local txt = g and Dispatcher:menuTextFunc(g)
                if txt and txt ~= nothing then
                    local chip = FrameContainer:new{
                        bordersize = 0, background = P.BLACK, radius = S(10),
                        padding = S(6), padding_left = S(10), padding_right = S(10),
                        TextWidget:new{ text = txt, face = P.face(false, 12), fgcolor = P.WHITE,
                            max_width = math.floor(in_w / 2) - 3 * pad, padding = 0 },
                    }
                    local holder = FrameContainer:new{ bordersize = 0, padding = pad, chip }
                    table.insert(og, c.v:new{ dimen = Geom:new{ w = in_w, h = in_h },
                        c.h:new{ dimen = Geom:new{ w = in_w, h = holder:getSize().h }, holder } })
                end
            end
            table.insert(widgets, FrameContainer:new{
                width = w, height = map_h, bordersize = Size.border.thin, color = P.GRAY_BORDER,
                background = P.WHITE, radius = S(14), padding = 0, og,
            })
            -- Resto: secciones (cabecera gris) y filas
            local skip_section = false
            for _i, e in ipairs(o.kv_pairs or {}) do
                if type(e) == "table" then
                    local is_header = (e[2] == " " or e[2] == "") and not e.callback
                    if is_header then
                        -- La sección de toques en esquina ya está en el dibujo
                        skip_section = false
                        local nxt = o.kv_pairs[_i + 1]
                        if nxt and corner_names[nxt[1]] then skip_section = true end
                        if not skip_section then
                            table.insert(widgets, VerticalSpan:new{ width = S(10) })
                            table.insert(widgets, P.label(e[1], w))
                        end
                    elseif not skip_section then
                        table.insert(widgets, P.row(e[1], e[2], w, e.callback, { height = S(38) }))
                    end
                end
            end
            return P.packPages(widgets, h, 0)
        end,
    }
end

-- KOReader monta el resumen como un KeyValuePage con uno de estos títulos: se
-- devuelve la pantalla de Aire en su lugar. (No se engancha al plugin Gestures
-- porque su parche de plugin no llegaba a aplicarse en el dispositivo.)
if not KeyValuePage._aire_gesture_overview then
    KeyValuePage._aire_gesture_overview = true
    local _ = require("gettext")
    local titles = { [_("Gestures in file browser")] = true, [_("Gestures in reader")] = true }
    local base_new = KeyValuePage.new
    KeyValuePage.new = function(cls, o)
        if cls == KeyValuePage and type(o) == "table" and titles[o.title] and type(o.kv_pairs) == "table" then
            local RUI = package.loaded["apps/reader/readerui"]
            local FM = package.loaded["apps/filemanager/filemanager"]
            local gestures = (RUI and RUI.instance and RUI.instance.gestures)
                or (FM and FM.instance and FM.instance.gestures)
            if gestures then
                if not next(GESTURES_LIST) and type(gestures.onShowGestureOverview) == "function" then
                    GESTURES_LIST = package.loaded.aire_ui.getUpValue(gestures.onShowGestureOverview, "gestures_list") or {}
                end
                local ok, page = pcall(buildPage, gestures, o)
                if ok and page then return page end
                logger.warn("Aire/Gestures:", page)
            end
        end
        return base_new(cls, o)
    end
end

logger.dbg("Aire/Gestures: aplicado desde el plugin")
