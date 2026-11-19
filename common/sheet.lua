--[[
    aire.koplugin/common/sheet.lua
    Hojas inferiores de Aire: lo que todas comparten, en un solo sitio.

      frame(content, owner)  marco de hoja (ancho de hoja, borde fino, esquinas,
                             relleno) colocado abajo con su margen. Si content es
                             una función (w -> widget) y no cabe en la pantalla,
                             se desplaza (ScrollableContainer). Lo usan también
                             las ventanas de KOReader que Aire monta como hoja.
      Sheet                  hoja propia: frame + cierre (tocar fuera, Atrás;
                             deslizar no cierra ni pasa a lo de debajo) y
                             refresco al abrirse y al cerrarse.

    Las medidas son las de common/screen.lua (SHEET). Se carga una vez desde
    main.lua en package.loaded.aire_sheet, después de common/screen.lua.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local UIManager = require("ui/uimanager")
local Screen = Device.screen
local AireScreen = package.loaded.aire_screen

local M = {}

local function S(n) return Screen:scaleBySize(n) end

-- Recuadro real de un widget ya pintado: FrameContainer solo guarda el tamaño
-- de la primera pintura (regla 9 del traspaso)
local function liveRect(w)
    local d = w and w.dimen
    if not (d and d.x and d.y) then return d end
    local ok, size = pcall(w.getSize, w)
    if not ok or not size then return d end
    return Geom:new{ x = d.x, y = d.y, w = size.w, h = size.h }
end
M.liveRect = liveRect

-- Alto máximo del contenido de una hoja (pantalla menos márgenes, relleno y borde)
function M.maxContentHeight()
    local SH = AireScreen.SHEET
    return Screen:getHeight() - 2 * S(SH.MARGIN) - 2 * (S(SH.PAD) + Size.border.thin)
end

--===========================================================================
-- frame(content, owner, opts) -> frame, root
--   content  widget ya montado, o function(w) -> widget (w = ancho útil); con
--            función, si no cabe, se vuelve a montar más estrecho y se desplaza
--   owner    la ventana que se muestra (para el desplazamiento: cropping_widget)
--   opts.padding_bottom  relleno inferior propio (p. ej. si lo de dentro ya
--                        deja un hueco bajo la última fila de botones)
--   opts.wrap            function(frame) -> widget que va dentro de root (p. ej.
--                        el MovableContainer que KOReader espera en ConfirmBox)
--===========================================================================
function M.frame(content, owner, opts)
    opts = opts or {}
    local SH = AireScreen.SHEET
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local body = content
    if type(content) == "function" then
        local inner = AireScreen.sheetInnerWidth()
        body = content(inner)
        local max_h = M.maxContentHeight()
        if body:getSize().h > max_h then
            local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
            if body.free then body:free() end
            local narrow = content(inner - ScrollableContainer:getScrollbarWidth())
            body = ScrollableContainer:new{
                dimen = Geom:new{ w = inner, h = max_h },
                show_parent = owner,
                narrow,
            }
            if owner then owner.cropping_widget = body end
        end
    end
    local frame = FrameContainer:new{
        width = AireScreen.sheetWidth(),
        bordersize = Size.border.thin,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        radius = S(SH.RADIUS),
        padding = S(SH.PAD),
        padding_bottom = opts.padding_bottom,
        body,
    }
    local root = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh - S(SH.MARGIN) },
        opts.wrap and opts.wrap(frame) or frame,
    }
    return frame, root
end

--===========================================================================
-- Sheet: hoja propia de Aire
--   Sheet:new{ content = widget | function(w), close_callback, dismissable,
--              full_refresh }
--   o, en una subclase, llamar a Sheet.init(self) y después self:setContent(...)
--   dismissable  false: ni tocar fuera ni Atrás la cierran (p. ej. descargando)
--   full_refresh al cerrar, refrescar toda la pantalla (lo de debajo cambió)
--   close()      la cierra (y llama a close_callback); onClose respeta dismissable
--===========================================================================
local Sheet = InputContainer:extend{
    modal = true,
    dismissable = true,
    full_refresh = false,
    close_callback = nil,
    content = nil,
}
M.Sheet = Sheet

function Sheet:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        AireSheetTapOut = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        AireSheetSwipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    if self.content then self:setContent(self.content) end
end

function Sheet:setContent(content)
    self.frame, self[1] = M.frame(content, self)
    self.sheet = self.frame -- (nombre que usaban algunas hojas)
end

-- Tocar dentro de la hoja sin dar a un botón: nada; fuera: cerrar
function Sheet:onAireSheetTapOut(_arg, ges)
    local fd = self.frame and liveRect(self.frame)
    if ges and ges.pos and fd and fd.x and ges.pos:intersectWith(fd) then return true end
    return self:onClose()
end

-- Deslizar no cierra la hoja ni llega a la pantalla de debajo
function Sheet:onAireSheetSwipe()
    return true
end

function Sheet:onClose()
    if not self.dismissable then return true end
    return self:close()
end

function Sheet:close()
    if self._closed then return true end
    self._closed = true
    UIManager:close(self, self.full_refresh and "ui" or nil)
    if self.close_callback then self.close_callback() end
    return true
end

-- Sin tipo de refresco, UIManager:show solo pinta en memoria y en el Kindle la
-- hoja no siempre aparecía (4.19 del traspaso)
function Sheet:onShow()
    UIManager:setDirty(self, function() return "ui", self.frame and liveRect(self.frame) end)
end

function Sheet:onCloseWidget()
    if self.full_refresh then
        UIManager:setDirty(nil, "ui")
    else
        UIManager:setDirty(nil, function() return "ui", self.frame and liveRect(self.frame) end)
    end
end

return M
