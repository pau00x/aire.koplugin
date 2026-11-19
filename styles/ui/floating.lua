--[[
    aire.koplugin/styles/ui/floating.lua
    Ventanas flotantes de KOReader: tocar fuera para cerrar con su tamaño real y borde fino; con las hojas
    activadas (opción "sheets"), avisos, diccionario, notas al pie y ventanas con teclado van como hoja
    inferior (sección 21 y ventanas con teclado). Los menús anclados siguen flotando.
    Lo carga styles/ui/init.lua en su orden (recibe la tabla de styles/ui/base.lua).
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
-- 19) BORDE FINO EN LAS VENTANAS FLOTANTES
--     Informativas (QR, progreso) y de escribir o buscar (InputDialog,
--     MultiInputDialog, diccionario): su borde grueso (Size.border.window)
--     pasa a ser el fino de las hojas (con las hojas activadas, además van
--     abajo: sección 21 y ventanas con teclado).
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
        if B.uiOpt("sheets") and rawget(self, "width") == nil and not self.image then
            -- Como hoja inferior (sección 21): texto a todo el ancho de la hoja,
            -- a la izquierda
            self.width = package.loaded.aire_screen.sheetInnerWidth()
            if rawget(self, "alignment") == nil then self.alignment = "left" end
        elseif rawget(self, "width") == nil and not self.image and type(self.text) == "string" then
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

    local INPUT_FACE = Font:getFace("cfont", package.loaded.aire_screen.SHEET.BODY_FONT) -- texto dentro de las cajas
    local FIELD_LABEL_FACE = Font:getFace("cfont", package.loaded.aire_screen.SHEET.ROW_FONT) -- títulos de los campos (MultiInputDialog)
    local NOTE_BOX_HEIGHT = 150                        -- caja de notas: ~6 líneas (antes, todo el alto)

    local function patchInputDialog(mod_path, flag, is_multi)
        local ok_id, Cls = pcall(require, mod_path)
        if ok_id and type(Cls) == "table" and not rawget(Cls, flag) then
            Cls[flag] = true
            safeWrap(Cls, "init", function(orig_init, self, ...)
                local pad = S_(SHEET_PAD)
                -- Como hoja (encima del teclado): ancho de hoja; si no, el del dock
                local as_sheet = B.uiOpt("sheets") and not self.fullscreen
                local w = as_sheet and package.loaded.aire_screen.sheetWidth() or dockWidth()
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
                -- Hoja pegada encima del teclado (o abajo si no está), con el
                -- margen y las esquinas de las hojas. Si no cabe, centrada como
                -- en KOReader (BottomContainer cortaría la parte de arriba).
                if as_sheet then
                    local ok_p, err_p = pcall(function()
                        local SH = package.loaded.aire_screen.SHEET
                        if self.dialog_frame then self.dialog_frame.radius = S_(SH.RADIUS) end
                        local frame = self.movable or self.dialog_frame
                        local root = self[1]
                        if not (frame and root and root.dimen) then return end
                        -- (con el teclado, encima; sin él, sin tapar la barra del lector)
                        local avail = root.dimen.h
                            - (self.keyboard_visible and S_(SH.MARGIN) or package.loaded.aire_screen.sheetBottom())
                        local frame_h = frame:getSize().h
                        -- Medir deja guardada la disposición: quien abre la ventana
                        -- puede añadir filas después (addWidget) y quedarían sin
                        -- posición (VerticalGroup:paintTo, _offsets nil)
                        if self.vgroup and self.vgroup.resetLayout then self.vgroup:resetLayout() end
                        if frame_h > avail then return end
                        local BottomContainer = require("ui/widget/container/bottomcontainer")
                        self[1] = BottomContainer:new{
                            dimen = Geom:new{ x = 0, y = 0, w = root.dimen.w, h = avail },
                            frame,
                        }
                    end)
                    if not ok_p then require("logger").warn("Aire/UI: ventana con teclado como hoja:", err_p) end
                end
                return unpack(res)
            end, TAG)
        end
    end
    patchInputDialog("ui/widget/inputdialog", "_aire_dock_width", false)
    patchInputDialog("ui/widget/multiinputdialog", "_aire_dock_width", true)

    local DICT_BOTTOM_GAP = 10

    -- Ejecuta fn con Size.padding.large cambiado (márgenes internos de algunas
    -- ventanas de KOReader, que lo toman de ahí al montarse)
    local function withLargePadding(v, fn, ...)
        local old = Size.padding.large
        Size.padding.large = v
        local res = { pcall(fn, ...) }
        Size.padding.large = old
        if not res[1] then error(res[2], 0) end
        table.remove(res, 1)
        return unpack(res)
    end
    B.withLargePadding = withLargePadding
    local ok_dq, DictQuickLookup = pcall(require, "ui/widget/dictquicklookup")
    if ok_dq and type(DictQuickLookup) == "table" and not DictQuickLookup._aire_dock_width then
        DictQuickLookup._aire_dock_width = true
        safeWrap(DictQuickLookup, "init", function(orig_dq_init, self, ...)
            local large = self.is_wiki_fullpage or G_reader_settings:isTrue("dict_largewindow") or self.temp_large_window
            if large then return orig_dq_init(self, ...) end
            -- Como hoja inferior (elegido: siempre abajo): ancho de hoja y la
            -- cabecera común (ui/sheet.lua); si no, flotante del ancho del dock
            local as_sheet = B.uiOpt("sheets")
            if rawget(self, "width") == nil then
                self.width = as_sheet and package.loaded.aire_screen.sheetWidth() or dockWidth()
            end
            local init = orig_dq_init
            local pad = S_(package.loaded.aire_screen.SHEET.PAD)
            -- Letra de la definición: la del contenido de las hojas (BODY_FONT) si
            -- el usuario no ha elegido otra en KOReader (Diccionario → Tamaño de
            -- letra); se pone solo mientras se monta, sin guardarla
            local body_tmp = as_sheet and G_reader_settings:hasNot("dict_font_size")
            if body_tmp then
                G_reader_settings:saveSetting("dict_font_size", package.loaded.aire_screen.SHEET.BODY_FONT)
            end
            if as_sheet then
                -- Márgenes de hoja dentro: el título, la palabra, la definición y
                -- los botones a SHEET.PAD del borde (y ese mismo hueco entre bloques)
                init = function(d, ...)
                    return withLargePadding(pad, package.loaded.aire_sheet.withSheetTitleBarAt, pad, orig_dq_init, d, ...)
                end
            end
            -- Hueco bajo los botones (y, como hoja, el margen de los lados)
            local gap_b = as_sheet and math.max(0, pad - Size.span.vertical_default) or S_(DICT_BOTTOM_GAP)
            -- Ventana flotante del diccionario (mantener pulsada una palabra):
            -- botones redondeados y esquinas como las hojas de Aire
            local res
            if B.withSheetButtons then
                -- (sin ensanchar los botones: la ventana es más estrecha que una
                -- hoja y se salían por la derecha). Margen lateral = el de abajo
                -- (VerticalSpan final de la tabla + DICT_BOTTOM_GAP): la tabla se
                -- estrecha lo que falta respecto a Size.padding.default
                local ButtonTable = require("ui/widget/buttontable")
                local side = Size.span.vertical_default + gap_b
                rawset(ButtonTable, "_aire_shrink", 2 * math.max(0, side - Size.padding.default))
                -- Como hoja, sin "Cerrar" (se cierra tocando fuera o con Atrás)
                if as_sheet then rawset(ButtonTable, "_aire_drop_close", true) end
                local ok_i, r = pcall(function(...) return { B.withSheetButtons(init, self, ...) } end, ...)
                rawset(ButtonTable, "_aire_shrink", nil)
                rawset(ButtonTable, "_aire_drop_close", nil)
                if body_tmp then G_reader_settings:delSetting("dict_font_size") end
                if not ok_i then error(r, 0) end
                res = r
            else
                local ok_i, r = pcall(function(...) return { init(self, ...) } end, ...)
                if body_tmp then G_reader_settings:delSetting("dict_font_size") end
                if not ok_i then error(r, 0) end
                res = r
            end
            if as_sheet and self[1] and self.region then
                -- Abajo, con el margen de las hojas (pisando la barra de estado
                -- del lector, como las demás hojas)
                local bottom = package.loaded.aire_screen.sheetBottom()
                self.align = "bottom"
                self.region = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() - bottom }
                self[1].align = "bottom"
                self[1].dimen = self.region
            end
            if self.dict_frame then
                self.dict_frame.radius = S_(B.SHEET_RADIUS or 14)
                -- (El icono "edit" se resuelve a aire.edit en core/icons.lua)
                -- Hueco bajo los botones (quedaban pegados al borde de la ventana)
                local vg = self.dict_frame[1]
                if type(vg) == "table" and vg.resetLayout and not vg._aire_bottom_gap then
                    vg._aire_bottom_gap = true
                    table.insert(vg, VerticalSpan:new{ width = gap_b })
                    vg:resetLayout()
                end
            end
            return unpack(res)
        end, TAG)
    end
end

--===========================================================================
-- 21) AVISOS COMO HOJA INFERIOR
--     Mensajes (InfoMessage), código QR y barra de progreso: abajo, con el
--     ancho, el borde, las esquinas y el relleno de las hojas (ui/screen.lua,
--     SHEET). Se cierran como siempre (tocar o esperar).
--===========================================================================
if B.uiOpt("sheets") then
    local AireScreen = package.loaded.aire_screen
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local logger = require("logger")

    local function sheetFrame(frame)
        local SH = AireScreen.SHEET
        local pad = S_(SH.PAD)
        frame.bordersize = Size.border.thin
        frame.radius = S_(SH.RADIUS)
        frame.padding = pad
        frame.padding_top, frame.padding_bottom, frame.padding_left, frame.padding_right = pad, pad, pad, pad
        frame.width = AireScreen.sheetWidth()
    end
    local function atBottom(dlg, inner)
        dlg[1] = BottomContainer:new{
            dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(),
                h = Screen:getHeight() - AireScreen.sheetBottom() },
            inner,
        }
    end

    -- Título común de los avisos: "Aviso", o el que pase quien lo muestra
    -- (aire_title; false = sin título)
    local _ = require("gettext")
    local VerticalGroup = require("ui/widget/verticalgroup")

    safeWrap(InfoMessage, "init", function(orig_init, self, ...)
        local res = { orig_init(self, ...) }
        local ok, err = pcall(function()
            local frame = self.movable and self.movable[1]
            if not frame then return end
            local title = self.aire_title
            if title == nil then title = _("Notice") end
            if title and frame[1] then
                frame[1] = VerticalGroup:new{ align = "left",
                    package.loaded.aire_sheet.title(title, AireScreen.sheetInnerWidth()), frame[1] }
            end
            sheetFrame(frame)
            atBottom(self, self.movable)
        end)
        if not ok then logger.warn("Aire/UI: aviso como hoja:", err) end
        return unpack(res)
    end, TAG)

    local ok_qr, QRMessage = pcall(require, "ui/widget/qrmessage")
    if ok_qr and type(QRMessage) == "table" then
        safeWrap(QRMessage, "init", function(orig_init, self, ...)
            local res = { orig_init(self, ...) }
            local ok, err = pcall(function()
                local frame = self[1] and self[1][1]
                if not (frame and frame[1]) then return end
                -- El código, centrado en la hoja
                local inner = AireScreen.sheetInnerWidth()
                frame[1] = CenterContainer:new{
                    dimen = Geom:new{ w = inner, h = frame[1]:getSize().h }, frame[1] }
                sheetFrame(frame)
                atBottom(self, frame) -- (onCloseWidget usa self[1][1])
            end)
            if not ok then logger.warn("Aire/UI: QR como hoja:", err) end
            return unpack(res)
        end, TAG)
    end

    -- Notas a pie de página (al tocar una nota en el libro): KOReader las pone a
    -- todo el ancho, con una línea arriba y los márgenes del libro. Como hoja:
    -- se montan creyendo que la pantalla mide lo que una hoja, con el relleno de
    -- las hojas a los lados, y luego van abajo con su marco
    local ok_fw, FootnoteWidget = pcall(require, "ui/widget/footnotewidget")
    if ok_fw and type(FootnoteWidget) == "table" then
        local LineWidget = require("ui/widget/linewidget")
        local Blitbuffer = require("ffi/blitbuffer")
        safeWrap(FootnoteWidget, "init", function(orig_init, self, ...)
            local SH = AireScreen.SHEET
            local sw = Screen:getWidth()
            local inner_w = AireScreen.sheetWidth() - 2 * Size.border.thin
            local dm = self.doc_margins
            if type(dm) == "table" then
                self.doc_margins = { left = S_(SH.PAD), right = S_(SH.PAD), top = dm.top, bottom = dm.bottom }
            end
            local had = rawget(Screen, "getWidth")
            Screen.getWidth = function() return inner_w end
            -- (arriba y abajo del texto, el relleno de las hojas)
            local res = { pcall(B.withLargePadding, S_(SH.PAD), orig_init, self, ...) }
            Screen.getWidth = had
            if not res[1] then error(res[2], 0) end
            table.remove(res, 1)
            local ok, err = pcall(function()
                -- Toques en toda la pantalla (se montó con el ancho de la hoja)
                for _k, ev in pairs(self.ges_events or {}) do
                    local r = ev[1] and ev[1].range
                    if type(r) == "table" and r.w then r.w = sw end
                end
                local c = self.container
                if not c then return end
                -- Sin la línea gruesa de arriba: la hoja ya tiene su borde
                local vg = c[1]
                if vg and not isA(vg[1], LineWidget) then vg = vg[1] end
                if vg and isA(vg[1], LineWidget) then vg[1].background = Blitbuffer.COLOR_WHITE end
                c.bordersize = Size.border.thin
                c.color = Blitbuffer.COLOR_BLACK
                c.radius = S_(SH.RADIUS)
                atBottom(self, c)
            end)
            if not ok then logger.warn("Aire/UI: nota al pie como hoja:", err) end
            return unpack(res)
        end, TAG)
    end

    local ok_pb, ProgressbarDialog = pcall(require, "ui/widget/progressbardialog")
    if ok_pb and type(ProgressbarDialog) == "table" then
        safeWrap(ProgressbarDialog, "init", function(orig_init, self, ...)
            -- Letras de hoja: título (TITLE_FONT, negrita) y subtítulo (SUB_FONT)
            local SH = AireScreen.SHEET
            local orig_getFace = Font.getFace
            Font.getFace = function(font, name, ...)
                if name == "ffont" then return orig_getFace(font, "cfont", SH.TITLE_FONT) end
                if name == "smallffont" then return orig_getFace(font, "cfont", SH.SUB_FONT) end
                return orig_getFace(font, name, ...)
            end
            local res = { pcall(orig_init, self, ...) }
            Font.getFace = orig_getFace
            if not res[1] then error(res[2], 0) end
            table.remove(res, 1)
            local ok, err = pcall(function()
                local frame = self[1]
                if not frame then return end
                sheetFrame(frame)
                atBottom(self, frame)
            end)
            if not ok then logger.warn("Aire/UI: progreso como hoja:", err) end
            return unpack(res)
        end, TAG)
    end
end
