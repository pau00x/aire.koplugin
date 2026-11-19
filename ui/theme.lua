--[[--
    Shared UI helpers and color palette for aire.koplugin.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")

local Screen = Device.screen

local M = {}

M.BLACK       = Blitbuffer.COLOR_BLACK
M.WHITE       = Blitbuffer.COLOR_WHITE
M.GRAY_DARK   = Blitbuffer.COLOR_DARK_GRAY
M.GRAY_TEXT   = Blitbuffer.COLOR_DARK_GRAY
M.GRAY        = Blitbuffer.COLOR_GRAY
M.GRAY_LIGHT  = Blitbuffer.COLOR_LIGHT_GRAY
M.GRAY_CARD   = Blitbuffer.COLOR_GRAY_E
M.GRAY_BORDER = Blitbuffer.COLOR_GRAY_B
M.GRAY_LINE   = Blitbuffer.COLOR_GRAY_D

function M.S(n)
    return Screen:scaleBySize(n)
end

function M.face(bold, size)
    return Font:getFace(bold and "tfont" or "cfont", size)
end

local function emptyGeom()
    return Geom:new{ x = 0, y = 0, w = 0, h = 0 }
end

--- Wrap a widget so it responds to tap (and optionally hold).
-- @param widget Widget to wrap
-- @param on_tap Callback on tap
-- @param on_hold Optional callback on hold
-- @param expand Extra touch padding in px: number or { h = ..., v = ... }
function M.tappable(widget, on_tap, on_hold, expand)
    local ic = InputContainer:new{ widget }
    local eh, ev = 0, 0
    if type(expand) == "number" then
        eh, ev = expand, expand
    elseif type(expand) == "table" then
        eh, ev = expand.h or 0, expand.v or 0
    end
    local range = function()
        local d = ic.dimen
        if not d then return emptyGeom() end
        if eh == 0 and ev == 0 then return d end
        return Geom:new{ x = d.x - eh, y = d.y - ev, w = d.w + 2 * eh, h = d.h + 2 * ev }
    end
    ic.ges_events = {
        AireTap = { GestureRange:new{ ges = "tap", range = range } },
    }
    ic.onAireTap = function()
        if on_tap then on_tap() end
        return true
    end
    if on_hold then
        ic.ges_events.AireHold = { GestureRange:new{ ges = "hold", range = range } }
        ic.onAireHold = function()
            on_hold()
            return true
        end
    end
    return ic
end

--- "Título · autor" del libro abierto (subtítulo de Índice, Marcadores,
-- Resultados de búsqueda…); "" si no hay datos.
function M.bookSubtitle(ui)
    local props = ui and ui.doc_props
    local t = props and (props.display_title or props.title) or ""
    local a = props and props.authors or ""
    if t ~= "" and a ~= "" then return t .. " · " .. a end
    return t ~= "" and t or a
end

--- Inicial del día de la semana (wday de os.date: 1 = domingo) en el idioma
-- de KOReader. En español, la costumbre: L M X J V S D (miércoles = X).
local DAY_ES = { "D", "L", "M", "X", "J", "V", "S" }
function M.dayLetter(wday)
    local lang = G_reader_settings and G_reader_settings:readSetting("language") or ""
    if lang:match("^es") then return DAY_ES[wday] or "?" end
    local dt = require("datetime")
    local short = dt.weekDays and dt.weekDays[wday]
    local tr = short and dt.shortDayOfWeekTranslation and dt.shortDayOfWeekTranslation[short] or short or "?"
    local first = tostring(tr):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"
    -- (mayúscula también fuera del ASCII: ruso, griego…)
    local ok_u, U = pcall(require, "ffi/utf8proc")
    if ok_u and U and U.uppercase_dumb then
        local ok, up = pcall(U.uppercase_dumb, first)
        if ok and type(up) == "string" then return up end
    end
    return first:upper()
end

--===========================================================================
-- Robustez: piezas comunes para tocar KOReader sin poder romperlo
--===========================================================================
local logger = require("logger")

--- getUpValue seguro: userpatch.getUpValue revienta si no recibe una función
-- (pasó con el vocabulario el 17 nov 2026: KOReader no arrancaba).
-- Devuelve lo mismo que userpatch.getUpValue: el valor Y su posición (la
-- posición hace falta para setUpValue; perderla dejó sin menú superior).
function M.getUpValue(fn, name)
    if type(fn) ~= "function" then return nil end
    local ok, v, idx = pcall(require("userpatch").getUpValue, fn, name)
    if ok then return v, idx end
end

-- (pack/unpack con el número exacto de valores: un nil en medio no corta)
local function pack(...) return { n = select("#", ...), ... } end

--- Envuelve cls[method] con fn(orig, self, ...). Si la parte de Aire falla:
--   · antes de llamar a orig -> se ejecuta el original (como si Aire no estuviera)
--   · después -> se devuelve lo que devolvió el original
-- y queda un WARN con el nombre. Nunca se ejecuta el original dos veces, y si
-- el que falla es el original de KOReader, su error sigue su curso.
-- Devuelve el original (o nil si no había nada que envolver).
local function callable(f)
    if type(f) == "function" then return true end
    local mt = type(f) == "table" and getmetatable(f)
    return mt and type(mt.__call) == "function" or false
end

function M.safeWrap(cls, method, fn, tag)
    local orig = type(cls) == "table" and cls[method]
    -- (función o tabla llamable: onShowVocabBuilder llega a ser una tabla)
    if not callable(orig) then return nil end
    local label = (tag or "Aire") .. ": " .. tostring(method)
    cls[method] = function(self, ...)
        local called, res, orig_err = false, nil, nil
        local function guarded(...)
            called = true
            local r = pack(pcall(orig, ...))
            if not r[1] then
                orig_err = r[2]
                error(r[2], 0)
            end
            res = r
            return unpack(r, 2, r.n)
        end
        local out = pack(pcall(fn, guarded, self, ...))
        if out[1] then return unpack(out, 2, out.n) end
        -- El fallo es de KOReader (no de Aire): que siga como sin Aire
        if orig_err ~= nil then error(orig_err, 0) end
        logger.warn(label, out[2])
        if called then return unpack(res, 2, res.n) end
        return orig(self, ...)
    end
    return orig
end

--- Ejecuta fn(...) con cls.new cambiado por hook(base_new, cls, o) y lo deja
-- como estaba pase lo que pase (rawget/rawset: no deja un campo propio en la
-- clase si "new" era heredado). Devuelve lo que devuelva fn; los errores de fn
-- se propagan después de restaurar.
function M.withTemporaryNew(cls, hook, fn, ...)
    local own = rawget(cls, "new")
    local base = cls.new
    rawset(cls, "new", function(c, o) return hook(base, c, o) end)
    local out = pack(pcall(fn, ...))
    rawset(cls, "new", own)
    if not out[1] then error(out[2], 0) end
    return unpack(out, 2, out.n)
end

return M
