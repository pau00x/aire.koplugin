--[[
    aire.koplugin/styles/ui/floating.lua
    Ventanas que siguen flotando: tocar fuera para cerrar con su tamaño real, solo borde fino y ancho del dock.
    Lo carga styles/ui.lua en su orden (recibe la tabla de styles/ui/base.lua).
--]]

local B = ...
local isA = B.isA
local dockWidth = B.dockWidth
local S_ = B.S_
local SHEET_PAD = B.SHEET_PAD
local withSheetStyle = B.withSheetStyle
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InfoMessage = require("ui/widget/infomessage")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalSpan = require("ui/widget/verticalspan")
local Screen = Device.screen
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"

--===========================================================================
-- 18) "TOCAR FUERA PARA CERRAR" CON EL TAMAÑO REAL DE LA VENTANA
--     (ver liveRect: el dimen de MovableContainer conserva el tamaño de la
--     primera vez que se pintó)
--===========================================================================
do
    local ok_bd, BD_ = pcall(require, "ui/widget/buttondialog")
    if ok_bd and type(BD_) == "table" and not BD_._aire_live_tapclose then
        BD_._aire_live_tapclose = true
        safeWrap(BD_, "onTapClose", function(_orig, self, arg, ges)
            local m = self.movable
            local r = m and m.dimen and m.dimen.x and m[1] and (function()
                local ok, size = pcall(m[1].getSize, m[1])
                if not ok or not size then return m.dimen end
                return Geom:new{ x = m.dimen.x, y = m.dimen.y, w = size.w, h = size.h }
            end)() or (m and m.dimen)
            if not r or (ges and ges.pos and ges.pos:notIntersectWith(r)) then
                self:onClose()
            end
            return true
        end, TAG)
    end
end

--===========================================================================
-- 19) VENTANAS FLOTANTES QUE SIGUEN FLOTANDO: SOLO EL BORDE FINO
--     Informativas (QR, progreso) y de escribir o buscar (InputDialog,
--     MultiInputDialog, diccionario): no pasan a hoja, solo se cambia su
--     borde grueso (Size.border.window) por el fino de las hojas.
--===========================================================================
do
    local function thinBorders(w, depth)
        if type(w) ~= "table" or depth > 7 then return end
        if isA(w, FrameContainer) and w.bordersize == Size.border.window and Size.border.window > Size.border.thin then
            w.bordersize = Size.border.thin
        end
        for i = 1, #w do thinBorders(w[i], depth + 1) end
    end
    local FLOATING = {
        { "ui/widget/inputdialog",       { "init" } },
        { "ui/widget/multiinputdialog",  { "init" } },
        { "ui/widget/dictquicklookup",   { "init", "update" } },
        { "ui/widget/progressbardialog", { "init" } },
        { "ui/widget/qrmessage",         { "init" } },
    }
    for _i, t in ipairs(FLOATING) do
        local ok, cls = pcall(require, t[1])
        if ok and type(cls) == "table" and not rawget(cls, "_aire_thin_border") then
            cls._aire_thin_border = true
            for _j, name in ipairs(t[2]) do
                local orig = rawget(cls, name)
                if type(orig) == "function" then
                    cls[name] = function(self, ...)
                        local res = { orig(self, ...) }
                        pcall(thinBorders, self, 1)
                        return unpack(res)
                    end
                end
            end
        end
    end
end

--===========================================================================
-- 20) VENTANAS FLOTANTES TAN ANCHAS COMO EL DOCK
--     Mensajes, escribir / buscar y diccionario: mismo ancho que el dock de
--     la Pantalla de inicio (antes 2/3 o 0,8 de la pantalla). No se tocan las
--     de pantalla completa ni la ventana grande del diccionario.
--===========================================================================
do
    -- InfoMessage: fuente cfont 15 y ancho ajustado al contenido (hasta dockWidth)
    safeWrap(InfoMessage, "init", function(orig_im_init, self, ...)
        if not self.face then
            self.face = Font:getFace(self.monospace_font and "infont" or "cfont", 15)
        end
        if rawget(self, "width") == nil and not self.image and type(self.text) == "string" then
            local max_w = dockWidth() - 2 * (Size.padding.fullscreen + Size.border.thin)
            local longest = 0
            for line in (self.text .. "\n"):gmatch("(.-)\n") do
                local tw = TextWidget:new{ text = line, face = self.face, padding = 0 }
                local w = tw:getSize().w
                tw:free()
                if w > longest then longest = w end
            end
            self.width = math.min(max_w, math.max(Screen:scaleBySize(120), longest + Screen:scaleBySize(8)))
        end
        return orig_im_init(self, ...)
    end, TAG)

    local INPUT_FACE = Font:getFace("cfont", 16)       -- texto dentro de las cajas
    local FIELD_LABEL_FACE = Font:getFace("cfont", 14) -- títulos de los campos (MultiInputDialog)
    local NOTE_BOX_HEIGHT = 150                        -- caja de notas: ~6 líneas (antes, todo el alto)

    local function patchInputDialog(mod_path, flag, is_multi)
        local ok_id, Cls = pcall(require, mod_path)
        if ok_id and type(Cls) == "table" and not rawget(Cls, flag) then
            Cls[flag] = true
            safeWrap(Cls, "init", function(orig_init, self, ...)
                local pad = S_(SHEET_PAD)
                local w = dockWidth()
                if not self.fullscreen then
                    local inner_w = w - 2 * pad - 2 * Size.border.thin
                    self.width = w
                    self.button_padding = pad
                    self.input_margin = pad
                    self.input_padding = Size.padding.default
                    self.text_width = inner_w - 2 * self.input_padding - 2 * (Size.border.input or Size.border.thin)
                    if rawget(self, "text_face") == nil then
                        self.text_face = Font:getFace("cfont", 15)
                    end
                    if rawget(self, "description_face") == nil then
                        self.description_face = Font:getFace("cfont", 13)
                    end
                    -- Texto de la caja: la x_smallinfofont de KOReader es muy grande
                    if rawget(self, "input_face") == nil then
                        self.input_face = INPUT_FACE
                    end
                    -- Sin los espacios fijos encima y debajo de la caja
                    if not is_multi and rawget(self, "condensed") == nil then
                        self.condensed = true
                    end
                    -- "Usar todo el alto" (nota de un marcador, editar el texto
                    -- subrayado…): la caja ocupaba todo el sitio sobre el teclado y
                    -- la ventana quedaba pegada arriba. Caja de unas 6 líneas (con
                    -- desplazamiento si hay más texto) y la ventana entera a la vista.
                    if not is_multi and rawget(self, "use_available_height") then
                        self.use_available_height = false
                        if rawget(self, "text_height") == nil then
                            self.text_height = S_(NOTE_BOX_HEIGHT)
                        end
                    end
                end
                local res
                -- (los argumentos se capturan aquí: nunca usar ... dentro de una closure)
                local args, nargs = { ... }, select("#", ...)
                local multi_layout = is_multi and not self.fullscreen
                local orig_getFace
                if multi_layout then
                    -- MultiInputDialog hace los campos al 90 % del ancho y centrados
                    -- (más sangría que el título y los botones). Su init llama antes
                    -- a InputDialog.init: ese init (el de abajo, is_multi = false)
                    -- deja un ancho con el que el 90 % es justo el de los campos
                    -- alineados con el título. Aquí se restaura al terminar.
                    self._aire_multi_dock_w = w
                    -- Títulos de los campos: KOReader usa una fuente fija (x_smallinfofont)
                    orig_getFace = Font.getFace
                    Font.getFace = function(font, name, ...)
                        if name == "x_smallinfofont" then return FIELD_LABEL_FACE end
                        return orig_getFace(font, name, ...)
                    end
                end
                local ok_init, err = pcall(function()
                    if not self.fullscreen and withSheetStyle then
                        res = { withSheetStyle(orig_init, self, unpack(args, 1, nargs)) }
                    else
                        res = { orig_init(self, unpack(args, 1, nargs)) }
                    end
                end)
                if orig_getFace then Font.getFace = orig_getFace end
                if multi_layout then
                    self.width = w
                    self._aire_multi_dock_w = nil
                end
                if not ok_init then error(err, 0) end
                if not self.fullscreen and self.dialog_frame then
                    self.dialog_frame.padding_bottom = math.max(0, pad - Size.span.vertical_default)
                    if self.dialog_frame.resetLayout then self.dialog_frame:resetLayout() end
                end
                -- InputDialog.init dentro de MultiInputDialog: el ancho con el que su
                -- 90 % deja la caja (ancho + 2·(relleno + borde)) entre los rellenos
                -- de la hoja, alineada con el título y los botones
                if not is_multi and self._aire_multi_dock_w then
                    local field_w = self._aire_multi_dock_w - 2 * pad
                        - 2 * (Size.padding.default + Size.border.inputtext)
                    self.width = math.ceil((field_w + 0.5) / 0.9)
                end
                return unpack(res)
            end, TAG)
        end
    end
    patchInputDialog("ui/widget/inputdialog", "_aire_dock_width", false)
    patchInputDialog("ui/widget/multiinputdialog", "_aire_dock_width", true)

    local DICT_BOTTOM_GAP = 10
    local ok_dq, DictQuickLookup = pcall(require, "ui/widget/dictquicklookup")
    if ok_dq and type(DictQuickLookup) == "table" and not DictQuickLookup._aire_dock_width then
        DictQuickLookup._aire_dock_width = true
        safeWrap(DictQuickLookup, "init", function(orig_dq_init, self, ...)
            local large = self.is_wiki_fullpage or G_reader_settings:isTrue("dict_largewindow") or self.temp_large_window
            if large then return orig_dq_init(self, ...) end
            if rawget(self, "width") == nil then self.width = dockWidth() end
            -- Ventana flotante del diccionario (mantener pulsada una palabra):
            -- botones redondeados y esquinas como las hojas de Aire
            local res
            if B.withSheetButtons then
                -- (sin ensanchar los botones: la ventana es más estrecha que una
                -- hoja y se salían por la derecha). Margen lateral = el de abajo
                -- (VerticalSpan final de la tabla + DICT_BOTTOM_GAP): la tabla se
                -- estrecha lo que falta respecto a Size.padding.default
                local ButtonTable = require("ui/widget/buttontable")
                local side = Size.span.vertical_default + S_(DICT_BOTTOM_GAP)
                rawset(ButtonTable, "_aire_shrink", 2 * math.max(0, side - Size.padding.default))
                local ok_i, r = pcall(function(...) return { B.withSheetButtons(orig_dq_init, self, ...) } end, ...)
                rawset(ButtonTable, "_aire_shrink", nil)
                if not ok_i then error(r, 0) end
                res = r
            else
                res = { orig_dq_init(self, ...) }
            end
            if self.dict_frame then
                self.dict_frame.radius = S_(B.SHEET_RADIUS or 14)
                -- Lápiz de editar la palabra: el de Aire
                local function findEdit(w, depth)
                    if type(w) ~= "table" or depth > 8 then return end
                    if w.icon == "edit" and w.setIcon then return w end
                    for _k, c in ipairs(w) do
                        local f = findEdit(c, depth + 1)
                        if f then return f end
                    end
                end
                local edit_btn = findEdit(self.dict_frame, 0)
                if edit_btn then pcall(edit_btn.setIcon, edit_btn, "aire.edit") end
                -- Hueco bajo los botones (quedaban pegados al borde de la ventana)
                local vg = self.dict_frame[1]
                if type(vg) == "table" and vg.resetLayout and not vg._aire_bottom_gap then
                    vg._aire_bottom_gap = true
                    table.insert(vg, VerticalSpan:new{ width = S_(DICT_BOTTOM_GAP) })
                    vg:resetLayout()
                end
            end
            return unpack(res)
        end, TAG)
    end
end
