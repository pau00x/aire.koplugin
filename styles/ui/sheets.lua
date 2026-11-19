--[[
    aire.koplugin/styles/ui/sheets.lua
    Hojas inferiores: estilo común, menús de opciones (ButtonDialog) y otras ventanas como hoja, componentes de las hojas y confirmación de 3 botones.
    Lo carga styles/ui.lua en su orden (recibe la tabla de styles/ui/base.lua
    y lo que exporta styles/ui/sheets.lua).
--]]

local B = ...
local uiOpt = B.uiOpt
local isA = B.isA
local dockWidth = B.dockWidth
local SHEET_MARGIN = B.SHEET_MARGIN
local SHEET_RADIUS = B.SHEET_RADIUS
local CONFIRM_BOX_AS_SHEET = B.CONFIRM_BOX_AS_SHEET
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local WHITE, BLACK = Blitbuffer.COLOR_WHITE, Blitbuffer.COLOR_BLACK

-- stylua: ignore start
local BUTTONDIALOG_AS_SHEET     = uiOpt("sheets")   -- abajo, a todo el ancho, como las hojas de la Pantalla de inicio
local OTHER_DIALOGS_AS_SHEET    = uiOpt("sheets")
-- stylua: ignore end

--===========================================================================
-- ESTILO DE HOJA COMÚN (secciones 11 y 12)
-- Todas las hojas miden lo mismo: el ancho de la pantalla menos SHEET_MARGIN a
-- cada lado, da igual el ancho que pida quien las abre. Dentro, el título va en
-- negrita a la izquierda sin línea debajo y los botones son rectángulos
-- redondeados de borde fino con un hueco entre ellos (como en la hoja de la
-- Pantalla de inicio); el botón principal (el de Intro) va en negro.
--===========================================================================
local Widget = require("ui/widget/widget")
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"
local S_ = function(n) return Screen:scaleBySize(n) end
-- Medidas de las hojas: common/screen.lua (SHEET), la única fuente
local AireScreen = package.loaded.aire_screen
local SHEET_PAD = AireScreen.SHEET.PAD
local SHEET_BTN_H = AireScreen.SHEET.BTN_H
local SHEET_BTN_RADIUS = AireScreen.SHEET.BTN_RADIUS
local SHEET_BTN_GAP = AireScreen.SHEET.BTN_GAP
local SHEET_BTN_FONT = AireScreen.SHEET.BTN_FONT

-- Ancho exterior de cualquier hoja y ancho útil dentro de ella
local sheetWidth, sheetInnerWidth = AireScreen.sheetWidth, AireScreen.sheetInnerWidth
-- (para parches de la comunidad que los leían de aquí; Aire usa common/screen.lua)
ButtonDialog.aire_sheetWidth = sheetWidth
ButtonDialog.aire_sheetInnerWidth = sheetInnerWidth

-- > 0 mientras se monta una hoja: las tablas de botones que se creen entonces
-- toman el estilo de hoja
local sheet_depth = 0
-- true mientras se monta una ventana que no es una hoja (p. ej. el diccionario):
-- botones con el estilo de hoja, pero sin ensanchar la tabla al ancho de hoja
local keep_table_width = false
-- Fondo del botón principal (objeto propio para reconocerlo después)
local PRIMARY_BG = Blitbuffer.Color8(0)
local in_sheet_table = false

local function withSheetStyle(fn, ...)
    sheet_depth = sheet_depth + 1
    local res = { pcall(fn, ...) }
    sheet_depth = sheet_depth - 1
    if not res[1] then error(res[2], 0) end
    table.remove(res, 1)
    return unpack(res)
end

-- Botones con el estilo de hoja en una ventana con su propio ancho
local function withSheetButtons(fn, ...)
    local prev = keep_table_width
    keep_table_width = true
    local res = { pcall(withSheetStyle, fn, ...) }
    keep_table_width = prev
    if not res[1] then error(res[2], 0) end
    table.remove(res, 1)
    return unpack(res)
end

-- Hueco entre filas de botones; con line = true lleva una línea fina gris en
-- medio (separador de grupo)
local SheetGap = Widget:extend{ width = 0, height = 0, line = false }
function SheetGap:getSize() return Geom:new{ w = self.width, h = self.height } end
function SheetGap:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    if self.line then
        local lh = Size.line.thin
        bb:paintRect(x, y + math.floor((self.height - lh) / 2), self.width, lh, Blitbuffer.COLOR_LIGHT_GRAY)
    end
end

if (BUTTONDIALOG_AS_SHEET or OTHER_DIALOGS_AS_SHEET) and not ButtonTable._aire_sheet_style_patched then
    ButtonTable._aire_sheet_style_patched = true

    safeWrap(ButtonTable, "init", function(orig_bt_init, self, ...)
        if sheet_depth <= 0 or self._aire_no_sheet_style then return orig_bt_init(self, ...) end
        local inner = sheetInnerWidth()
        if not keep_table_width and self.width and self.width < inner and self.width >= inner - 3 * Size.padding.default then
            self.width = inner
        end
        -- (diccionario: tabla algo más estrecha para igualar el margen lateral al de abajo)
        local shrink = keep_table_width and rawget(ButtonTable, "_aire_shrink")
        if shrink and self.width then self.width = self.width - shrink end
        -- Casuística de botones en hojas:
        --   · aceptar / principal -> negro
        --   · resto (opciones, acciones, cancelar) -> blanco
        local function isPrimaryBtn(b)
            if type(b) ~= "table" then return false end
            return b.is_enter_default or b.id == "ok" or b.id == "apply" or b.id == "save"
        end
        local orig_buttons = self.buttons
        local styled = {}
        for i, row in ipairs(orig_buttons or {}) do
            local new_row = {}
            for j, b in ipairs(row) do
                local set_font = type(b) == "table" and (b.text or (keep_table_width and b.text_func)) and b.font_size == nil
                local primary = isPrimaryBtn(b) and rawequal(b.background, nil)
                if set_font or primary then
                    local c = setmetatable({}, { __index = b })
                    if set_font then c.font_size = SHEET_BTN_FONT end
                    if primary then c.background = PRIMARY_BG end
                    new_row[j] = c
                else
                    new_row[j] = b
                end
            end
            styled[i] = new_row
        end
        self.buttons = styled
        self.sep_width = S_(SHEET_BTN_GAP)
        in_sheet_table = true
        local ok, err = pcall(orig_bt_init, self, ...)
        in_sheet_table = false
        self.buttons = orig_buttons
        self.sep_width = Size.line.medium -- para las líneas que se añaden al desplazar
        if not ok then error(err, 0) end
        -- Líneas entre filas -> huecos (o línea fina si separan grupos);
        -- líneas entre columnas -> en blanco
        local ok2, err2 = pcall(function()
            local c = self.container
            local uniform = keep_table_width -- (diccionario) mismo hueco entre filas que entre columnas
            for i = 1, #c do
                local w = c[i]
                if uniform and i > 1 and i < #c and isA(w, VerticalSpan) then
                    c[i] = SheetGap:new{ width = 0, height = 0 }
                elseif isA(w, LineWidget) and w.dimen then
                    local is_group = w._aire_group_sep
                    c[i] = SheetGap:new{ width = w.dimen.w, height = is_group and S_(18) or w.dimen.h, line = is_group }
                elseif isA(w, HorizontalGroup) then
                    for _k, x in ipairs(w) do
                        if isA(x, LineWidget) then x.background = Blitbuffer.COLOR_WHITE end
                    end
                end
            end
            if c.resetLayout then c:resetLayout() end
        end)
        if not ok2 then logger.warn("Aire/UI: estilo de hoja en botones:", err2) end
    end, TAG)

    safeWrap(Button, "init", function(orig_btn_init, self, ...)
        if in_sheet_table and (self.bordersize or 0) == 0 then
            self.bordersize = Size.border.thin
            self.radius = S_(SHEET_BTN_RADIUS)
            if (self.text or (keep_table_width and self.text_func)) and not self.height then
                local pv = self.padding_v or self.padding or 0
                self.height = math.max(S_(20), S_(SHEET_BTN_H) - 2 * pv - 2 * self.bordersize)
            end
            self._aire_primary = rawequal(self.background, PRIMARY_BG)
            self._aire_sheet_btn = true
        end
        orig_btn_init(self, ...)
        if self._aire_primary and self.frame then
            self.frame.color = Blitbuffer.COLOR_BLACK
            if self.label_widget and self.text then
                self.label_widget.fgcolor = self.enabled and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_GRAY
            end
        end
    end, TAG)
    -- Resaltado al tocar: KOReader invierte el rectángulo entero (esquinas
    -- cuadradas negras fuera del borde redondeado). En los botones de las hojas
    -- se invierten el fondo y el texto, respetando las esquinas.
    safeWrap(Button, "_doFeedbackHighlight", function(orig_do_hl, self, ...)
        if not (self._aire_sheet_btn and self.text and self[1] and self.label_widget) then
            return orig_do_hl(self, ...)
        end
        if not self._aire_hl then
            self._aire_hl = true
            self[1].background = self[1].background:invert()
            self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
        end
        local UIManager = require("ui/uimanager")
        UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
        UIManager:setDirty(nil, "fast", self[1].dimen)
    end, TAG)
    safeWrap(Button, "_undoFeedbackHighlight", function(orig_undo_hl, self, is_translucent, ...)
        if not (self._aire_sheet_btn and self.text and self[1] and self.label_widget) then
            return orig_undo_hl(self, is_translucent, ...)
        end
        if self._aire_hl then
            self._aire_hl = nil
            self[1].background = self[1].background:invert()
            self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
        end
        local UIManager = require("ui/uimanager")
        UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
        if is_translucent then
            UIManager:setDirty(self.show_parent, "ui", self[1].dimen)
        else
            UIManager:setDirty(nil, self.enabled and "fast" or "ui", self[1].dimen)
        end
    end, TAG)

    -- Que el texto del botón negro siga en blanco al activarlo/desactivarlo
    for _i, name in ipairs({ "enable", "disable" }) do
        local orig = Button[name]
        Button[name] = function(btn, ...)
            local res = orig(btn, ...)
            if btn._aire_primary and btn.text and btn.label_widget then
                btn.label_widget.fgcolor = btn.enabled and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_GRAY
                if btn.label_widget.update then btn.label_widget:update() end
            end
            return res
        end
    end
end

--===========================================================================
-- 11) MENÚS DE OPCIONES (BUTTONDIALOG) COMO HOJA INFERIOR
-- El ButtonDialog se monta igual que siempre (botones, desactivados, mantener
-- pulsado, varias páginas, teclado…), pero con el ancho de hoja, el título y
-- los botones con el estilo de hoja, y colocado abajo con borde fino y
-- esquinas como la hoja del plugin. Los que van pegados a un botón (anchor)
-- se dejan como están.
--===========================================================================
if BUTTONDIALOG_AS_SHEET and not ButtonDialog._aire_sheet_patched then
    ButtonDialog._aire_sheet_patched = true
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    safeWrap(ButtonDialog, "init", function(orig_init, self, ...)
        local as_sheet = not self.anchor
        local pad = S_(SHEET_PAD)
        if not as_sheet and not uiOpt("anchored_style") then return orig_init(self, ...) end
        if not as_sheet then
            -- Anclados (junto al texto seleccionado o a un botón): siguen
            -- flotando donde los pone KOReader, pero con el estilo de las hojas
            -- (título, botones redondeados, borde fino y esquinas). Elegido por
            -- el usuario: "dejarlos flotando pero modernizados".
            self.use_info_style = false
            self.title_align = "left"
            self.title_face = Font:getFace("tfont", 15)
            if rawget(self, "width") == nil and rawget(self, "width_factor") == nil then
                self.width = dockWidth() -- (con shrink_unneeded_width se encogen al contenido)
            end
            withSheetStyle(orig_init, self, ...)
            local ok_a, err_a = pcall(function()
                local frame = self.movable and self.movable[1]
                if not frame then return end
                local apad = S_(10)
                frame.bordersize = Size.border.thin
                frame.radius = S_(SHEET_RADIUS)
                frame.padding = apad
                frame.padding_left, frame.padding_right, frame.padding_top = apad, apad, apad
                frame.padding_bottom = math.max(0, apad - Size.span.vertical_default)
                local vg = frame[1]
                if vg and isA(vg[2], LineWidget) then
                    vg[2] = VerticalSpan:new{ width = S_(8) }
                    if vg.resetLayout then vg:resetLayout() end
                end
            end)
            if not ok_a then logger.warn("Aire/UI: estilo en menú anclado:", err_a) end
            return
        end
        -- Ancho que hay que pedir para que, con el relleno y el borde de la hoja,
        -- mida exactamente sheetWidth()
        self.width = sheetWidth() + 2 * Size.border.window + 2 * Size.padding.button
            - 2 * pad - 2 * Size.border.thin
        self.width_factor = nil
        self.shrink_unneeded_width = false
        -- Título como la hoja: negrita, a la izquierda, sin márgenes propios
        self.use_info_style = false
        self.title_align = "left"
        self.title_face = Font:getFace("tfont", 15)
        self.title_padding = 0
        self.title_margin = 0
        withSheetStyle(orig_init, self, ...)
        if not self.movable then return end
        local ok, err = pcall(function()
            local frame = self.movable[1]
            if frame then
                frame.bordersize = Size.border.thin
                frame.radius = S_(SHEET_RADIUS)
                frame.padding = pad
                frame.padding_left = pad
                frame.padding_right = pad
                frame.padding_top = pad
                -- la tabla ya deja un pequeño hueco bajo la última fila
                frame.padding_bottom = math.max(0, pad - Size.span.vertical_default)
                local vg = frame[1]
                -- Sin la línea bajo el título: un hueco
                if vg and isA(vg[2], LineWidget) then
                    vg[2] = VerticalSpan:new{ width = S_(10) }
                    if vg.resetLayout then vg:resetLayout() end
                end
            end
            self[1] = BottomContainer:new{
                dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(),
                                  h = Screen:getHeight() - S_(SHEET_MARGIN) },
                self.movable,
            }
        end)
        if not ok then logger.warn("Aire/UI: no se pudo colocar el menú como hoja:", err) end
    end, TAG)
end

--===========================================================================
-- 12) OTRAS VENTANAS COMO HOJA INFERIOR
-- Todas montan su contenido dentro de un contenedor del tamaño de la pantalla
-- que lo centra (self[1]). Después de montarlo, y cada vez que lo rehacen (al
-- mover un deslizador, cambiar un número…), ese contenedor se cambia por uno
-- que lo coloca abajo, y su marco pasa a borde fino con esquinas de 14.
-- Ancho: las que aceptan un ancho lo reciben; las que lo calculan a partir de
-- la pantalla se vuelven a montar una vez con el cálculo corregido.
--===========================================================================
if OTHER_DIALOGS_AS_SHEET then
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local MovableContainer = require("ui/widget/container/movablecontainer")

    -- Primer marco visible (con borde o fondo) bajando por los contenedores
    local function findFrame(w, depth)
        if type(w) ~= "table" or depth > 4 then return nil end
        if isA(w, FrameContainer) and ((w.bordersize or 0) > 0 or (w.radius or 0) > 0) then return w end
        if isA(w, MovableContainer) or isA(w, FrameContainer) then return findFrame(w[1], depth + 1) end
        return nil
    end

    local function frameOf(dlg)
        local root = dlg[1]
        return type(root) == "table" and findFrame(root[1], 1) or nil
    end

    -- Ancho del contenido del marco (sin borde ni relleno)
    local function contentWidth(dlg)
        local f = frameOf(dlg)
        local ok, size = pcall(function() return f and f[1] and f[1]:getSize() end)
        return ok and size and size.w or nil
    end

    -- Ancho que debería tener el contenido. Las ventanas de KOReader dejan sus
    -- botones y su título a Size.padding.default de su borde; con este ancho
    -- quedan a SHEET_PAD del borde de la hoja, igual que en las demás hojas.
    local function targetContentWidth()
        return sheetWidth() - 2 * Size.border.thin - 2 * (S_(SHEET_PAD) - Size.padding.default)
    end

    local function toSheet(dlg, add_pad)
        local root = dlg[1]
        if type(root) ~= "table" or root._aire_sheet or isA(root, BottomContainer) then return end
        local child = root[1]
        if type(child) ~= "table" then return end
        local frame = findFrame(child, 1)
        -- Marcos invisibles que solo añaden relleno alrededor del de verdad
        -- (p. ej. Fecha y hora): fuera, el relleno ya lo pone la hoja
        while frame and child ~= frame and isA(child, FrameContainer)
            and (child.bordersize or 0) == 0 and (child.radius or 0) == 0 do
            child = child[1]
        end
        if frame then
            frame.bordersize = Size.border.thin
            frame.radius = S_(SHEET_RADIUS)
            if add_pad then
                -- Recortar el aire excesivo (4 * Size.padding.large) que meten
                -- SpinWidget, DoubleSpinWidget, RadioButtonWidget y DateTimeWidget
                -- alrededor de su contenido para igualar el hueco bajo el título
                local CenterContainer = require("ui/widget/container/centercontainer")
                if isA(frame[1], VerticalGroup) then
                    local trimmed = false
                    for _i, w in ipairs(frame[1]) do
                        if isA(w, CenterContainer) and w.dimen and w[1] then
                            local cs = w[1]:getSize()
                            local target_h = cs.h + S_(8)
                            if w.dimen.h > target_h + S_(4) then
                                w.dimen.h = target_h
                                trimmed = true
                            end
                        end
                    end
                    if trimmed and frame[1].resetLayout then frame[1]:resetLayout() end
                end
                -- El marco mide exactamente lo que cualquier hoja y el
                -- contenido va centrado dentro (lo que sobre o falte se
                -- reparte a los lados); arriba y abajo, el relleno de hoja
                local pad = S_(SHEET_PAD)
                local pad_b = math.max(0, pad - Size.span.vertical_default)
                local outer = sheetWidth()
                local cw = frame[1] and frame[1]:getSize().w or 0
                local free = math.max(0, outer - 2 * frame.bordersize - 2 * (frame.margin or 0) - cw)
                frame.width = outer
                frame.padding = 0
                frame.padding_left = math.floor(free / 2)
                frame.padding_right = free - math.floor(free / 2)
                frame.padding_top, frame.padding_bottom = pad, pad_b
                -- Nunca más alta que la pantalla: si no cabe, menos relleno
                local max_h = Screen:getHeight() - 2 * S_(SHEET_MARGIN)
                local h = frame:getSize().h
                if h > max_h then
                    local cut = math.ceil((h - max_h) / 2)
                    frame.padding_top = math.max(0, pad - cut)
                    frame.padding_bottom = math.max(0, pad_b - cut)
                end
            end
        end
        local sheet = BottomContainer:new{
            dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() - S_(SHEET_MARGIN) },
            child,
        }
        sheet._aire_sheet = true
        dlg[1] = sheet
    end

    -- Ejecutar fn creyendo que la pantalla mide w de ancho
    local function withScreenWidth(w, fn, ...)
        local had = rawget(Screen, "getWidth")
        Screen.getWidth = function() return w end
        local res = { pcall(fn, ...) }
        Screen.getWidth = had
        if not res[1] then error(res[2], 0) end
        table.remove(res, 1)
        return unpack(res)
    end

    -- { módulo, métodos que (re)montan self[1], ancho }
    --   ancho = "param": acepta self.width (se fuerza y se corrige si hace falta)
    --   ancho = número : lo calcula como número × ancho de pantalla
    --   ancho = "once" : acepta self.width, sin volver a montar
    local TARGETS = {
        { "ui/widget/frontlightwidget",     { "init", "layout", "update" }, false }, -- ancho propio: se salía
        { "ui/widget/naturallightwidget",   { "init", "update" },           false },
        { "ui/widget/spinwidget",           { "init", "update" },           "param" },
        { "ui/widget/doublespinwidget",     { "init", "update" },           "param" },
        { "ui/widget/datetimewidget",       { "init", "update" },           "param" },
        { "ui/widget/radiobuttonwidget",    { "init", "update" },           "param" },
        { "ui/widget/openwithdialog",       { "init" },                     "once" },
        { "ui/widget/keyboardlayoutdialog", { "init" },                     "param" },
        -- (Vista rápida del documento: la monta entera styles/skim.lua)
        { "ui/widget/textviewer",           { "init" },                     "param" },
        -- Tienen opciones: también como hoja (revisión de ventanas flotantes)
        { "ui/widget/networksetting",       { "init" },                     "param" }, -- lista de redes wifi
    }
    -- ConfirmBox con widgets añadidos usa toSheet; el normal se construye como MultiConfirmBox
    if CONFIRM_BOX_AS_SHEET then
        table.insert(TARGETS, { "ui/widget/confirmbox", { "init" }, 2 / 3 })
    end

    local function clearShadowed(dlg)
        local mt = getmetatable(dlg)
        local cls = mt and mt.__index
        if type(cls) ~= "table" then return end
        for k, v in pairs(dlg) do
            if type(v) ~= "function" and type(cls[k]) == "function" then dlg[k] = nil end
        end
    end

    -- Corrección de ancho que funcionó, por ventana|ancho objetivo|ancho de pantalla
    local sheet_width_corr = {}

    local function sheetInit(dlg, orig, mode, mod, ...)
        -- Se pide el ancho de contenido de las hojas; si la ventana sale con
        -- otro, se vuelve a montar una vez corrigiendo la diferencia. Lo que
        -- quede de diferencia lo absorbe toSheet (marco de ancho fijo).
        local target = targetContentWidth()
        -- Visor de texto: casi toda la altura; dejar sitio al relleno de hoja
        if mod == "ui/widget/textviewer" then
            if type(dlg.text) == "string" and (dlg.title == _("Description") or dlg.title == "Descripción") then
                dlg.text = dlg.text
                    :gsub("\r\n", "\n"):gsub("\r", "\n")
                    :gsub("<[Bb][Rr]%s*/?>", "\n"):gsub("</[PpDd][^>]*>", "\n\n"):gsub("<[^>]+>", "")
                    :gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&#39;", "'")
                    :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&mdash;", "—"):gsub("&ndash;", "–"):gsub("&hellip;", "…")
                    :gsub("\194\160", " "):gsub("\226\128\139", ""):gsub("\t", " ")
                    :gsub(" +\n", "\n"):gsub("\n +", "\n")
                    :gsub(" +", " "):gsub("\n\n\n+", "\n\n")
                    :gsub("^%s+", ""):gsub("%s+$", "")
            end
            if rawget(dlg, "height") == nil then
                dlg.height = Screen:getHeight() - 2 * S_(SHEET_MARGIN) - 2 * S_(SHEET_PAD)
                    - 2 * Size.border.thin - S_(40)
            end
        end
        -- Letras propias de algunas ventanas (etiquetas de márgenes, guiones
        -- de la fecha): como las hojas
        if rawget(dlg, "title_face") == nil then
            if mod == "ui/widget/doublespinwidget" then dlg.title_face = Font:getFace("cfont", 15)
            elseif mod == "ui/widget/datetimewidget" then dlg.title_face = Font:getFace("tfont", 24) end
        end
        if mode == "param" or mode == "once" then
            dlg.width = target
            dlg.width_factor = nil
        end
        if mode == "once" then return withSheetStyle(orig, dlg, ...) end
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local args, nargs = { ... }, select("#", ...)
        local base_width = dlg.width
        -- Montar con una corrección de ancho (0 = tal cual)
        local function build(corr)
            if corr == 0 then
                dlg.width = base_width
                return { withSheetStyle(orig, dlg, unpack(args, 1, nargs)) }
            elseif mode == "param" then
                dlg.width = base_width + corr
                return { withSheetStyle(orig, dlg, unpack(args, 1, nargs)) }
            else
                dlg.width = base_width
                local fake = math.floor(sw + corr / mode + 0.5)
                return { withScreenWidth(fake, withSheetStyle, orig, dlg, unpack(args, 1, nargs)) }
            end
        end
        local can_correct = mode == "param" or type(mode) == "number"
        if mod == "ui/widget/skimtowidget" and sw >= sh then can_correct = false end -- apaisado: ya va a lo ancho
        -- La corrección que hizo falta la última vez (misma ventana, ancho y
        -- orientación) se aplica ya en el primer montaje: así solo se monta
        -- una vez en lugar de dos
        local key = mod .. "|" .. target .. "|" .. sw
        local corr = can_correct and sheet_width_corr[key] or 0
        local res
        local ok, err = pcall(function() res = build(corr) end)
        if not ok then
            if corr == 0 then error(err, 0) end
            sheet_width_corr[key] = nil
            clearShadowed(dlg)
            corr = 0
            res = build(0)
        end
        if not can_correct then return unpack(res) end
        local cur = contentWidth(dlg)
        local delta = cur and (target - cur) or 0
        if math.abs(delta) < 2 then return unpack(res) end
        local total = corr + delta
        if math.abs(total) > target / 2 then return unpack(res) end
        logger.dbg("Aire/UI: ajustando ancho de hoja:", mod, cur, "->", target)
        clearShadowed(dlg)
        ok, err = pcall(function() res = build(total) end)
        if ok then
            local now = contentWidth(dlg)
            if now and math.abs(target - now) < 2 then sheet_width_corr[key] = total end
        else
            logger.warn("Aire/UI: no se pudo ajustar el ancho:", mod, err)
            sheet_width_corr[key] = nil
            clearShadowed(dlg)
            res = build(0)
        end
        return unpack(res)
    end

    -- Separadores de KOReader (gris oscuro y gruesos, p. ej. "Abrir con…"):
    -- como los de Aire, finos y gris claro
    local function thinSeparators(w, depth)
        depth = depth or 0
        if type(w) ~= "table" or depth > 8 then return end
        if isA(w, LineWidget) and w.dimen and rawequal(w.background, Blitbuffer.COLOR_DARK_GRAY) then
            w.background = Blitbuffer.COLOR_LIGHT_GRAY
            w.dimen.h = Size.line.thin
            return
        end
        for _k, c in ipairs(w) do thinSeparators(c, depth + 1) end
        if w.vgroup and depth == 0 then thinSeparators(w.vgroup, 1) end
    end

    local adapted = 0
    for _i, t in ipairs(TARGETS) do
        local ok, cls = pcall(require, t[1])
        if ok and type(cls) == "table" and not cls._aire_sheet_patched then
            cls._aire_sheet_patched = true
            for _j, name in ipairs(t[2]) do
                local orig = rawget(cls, name) or cls[name]
                if type(orig) == "function" then
                    cls[name] = function(dlg, ...)
                        local res
                        if name == "init" then
                            res = { sheetInit(dlg, orig, t[3], t[1], ...) }
                        else
                            res = { withSheetStyle(orig, dlg, ...) }
                        end
                        if name == "init" then pcall(thinSeparators, dlg) end
                        local ok2, err = pcall(toSheet, dlg, t[3] ~= false)
                        if not ok2 then logger.warn("Aire/UI: no se pudo colocar como hoja:", t[1], err) end
                        return unpack(res)
                    end
                end
            end
            adapted = adapted + 1
        end
    end
    logger.dbg("Aire/UI: ventanas como hoja:", adapted)
end

--===========================================================================
-- Componentes de las hojas (antes al principio de la sección 13): zona
-- tocable, barra con bolita, escalones y botón redondo
--===========================================================================

-- Zona tocable genérica: callback(ges)
local Tap = InputContainer:extend{ callback = nil }
function Tap:init()
    local s = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = s.w, h = s.h }
    self.ges_events = {
        AireTap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
    }
end
function Tap:onAireTap(_args, ges)
    if self.callback then self.callback(ges) end
    return true
end

-- Barra fina redondeada con bolita (valor entre 0 y 1)
local SliderBar = Widget:extend{ width = 0, height = 0, ratio = 0 }
function SliderBar:getSize() return Geom:new{ w = self.width, h = self.height } end
function SliderBar:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    local th = S_(10)
    local ty = y + math.floor((self.height - th) / 2)
    bb:paintRoundedRect(x, ty, self.width, th, Blitbuffer.COLOR_GRAY_D, math.floor(th / 2))
    local r = math.max(0, math.min(1, self.ratio))
    local kx = x + math.floor(r * (self.width - self.height)) + math.floor(self.height / 2)
    if kx - x > th then
        bb:paintRoundedRect(x, ty, kx - x, th, Blitbuffer.COLOR_DARK_GRAY, math.floor(th / 2))
    end
    local kr = math.floor(self.height / 2) - 1
    bb:paintCircle(kx, y + math.floor(self.height / 2), kr, WHITE)
    bb:paintCircle(kx, y + math.floor(self.height / 2), kr, BLACK, S_(2))
end

-- Escalones tocables: n escalones, los k primeros rellenos
local StepBar = Widget:extend{ width = 0, height = 0, n = 1, k = 0 }
function StepBar:getSize() return Geom:new{ w = self.width, h = self.height } end
function StepBar:stepAt(px)
    local d = self.dimen
    if not d then return nil end
    local i = math.floor((px - d.x) / (d.w / self.n)) + 1
    return math.max(1, math.min(self.n, i))
end
function StepBar:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    local gap = self.n > 16 and S_(3) or S_(5)
    local sw = (self.width - (self.n - 1) * gap) / self.n
    for i = 1, self.n do
        local sx = x + math.floor((i - 1) * (sw + gap))
        local w = math.floor(sw)
        if i <= self.k then
            bb:paintRoundedRect(sx, y, w, self.height, Blitbuffer.COLOR_DARK_GRAY, S_(4))
        else
            bb:paintRoundedRect(sx, y, w, self.height, Blitbuffer.COLOR_GRAY_D, S_(4))
        end
    end
end

-- Botón redondo con texto (− / +)
local function roundButton(text, size, cb, hold_cb, show_parent, enabled)
    return Button:new{
        text = text, text_font_size = 22, text_font_bold = false,
        bordersize = Size.border.thin, radius = math.floor(size / 2),
        padding = 0, margin = 0, width = size, height = size - 2 * Size.border.thin,
        enabled = enabled ~= false, callback = cb, hold_callback = hold_cb, show_parent = show_parent,
        _aire_sheet_btn = true,
    }
end

--===========================================================================
-- Confirmación de 3 botones (MultiConfirmBox) como hoja (antes en la sección 13)
--===========================================================================
if OTHER_DIALOGS_AS_SHEET then
    local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
    if ok_fc and type(FontChooser) == "table" and not FontChooser._aire_compact_patched then
        FontChooser._aire_compact_patched = true
        local MovableContainer = require("ui/widget/container/movablecontainer")
        local RadioButtonTable = require("ui/widget/radiobuttontable")
        local FontList = require("fontlist")
        local InfoMessage = require("ui/widget/infomessage")
        local ffiUtil = require("ffi/util")
        safeWrap(FontChooser, "init", function(_orig, self)
            if Device:hasKeys() then
                self.key_events.Close = { { Device.input.group.Back } }
            end
            if Device:isTouchDevice() then
                self.ges_events.TapClose = {
                    GestureRange:new{
                        ges = "tap",
                        range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() },
                    },
                }
            end
            self.layout = {}
            local inner = sheetInnerWidth()
            local pad = S_(SHEET_PAD)
            local title_w = TextWidget:new{
                text = self.title or _("Fonts"),
                face = Font:getFace("tfont", 15),
                fgcolor = BLACK,
                max_width = inner,
                padding = 0,
            }
            local radio_buttons = {}
            for font_file, _font_info in pairs(FontList.fontinfo) do
                local name_text, name = self.getFontNameText(font_file)
                if self.default_font_file and self.default_font_file == font_file then
                    name_text = name_text .. "  ★"
                end
                table.insert(radio_buttons, { {
                    text = name_text,
                    name = name,
                    checked = font_file == self.font_file,
                    provider = font_file,
                    face = Font:getFace(font_file, 16),
                    hold_callback = function()
                        UIManager:show(InfoMessage:new{ text = font_file, show_icon = false })
                    end,
                } })
            end
            if #radio_buttons > 1 then
                table.sort(radio_buttons, function(a, b)
                    if a[1].name ~= b[1].name then
                        return ffiUtil.strcoll(a[1].name, b[1].name)
                    end
                    return ffiUtil.strcoll(a[1].text, b[1].text)
                end)
            end
            local sb_w = ScrollableContainer:getScrollbarWidth()
            local list_w = inner - sb_w
            local radio_button_table = withSheetStyle(function()
                return RadioButtonTable:new{
                    radio_buttons = radio_buttons,
                    width = list_w,
                    button_single_line = true,
                    no_sep = true,
                    focused = true,
                    parent = self,
                    show_parent = self,
                }
            end)
            self:mergeLayoutInVertical(radio_button_table)
            local buttons = { {
                {
                    text = _("Close"),
                    id = "close",
                    callback = function() UIManager:close(self) end,
                },
                {
                    text = _("Set font"),
                    is_enter_default = true,
                    callback = function()
                        if not self.keep_shown_on_apply then UIManager:close(self) end
                        self.callback(radio_button_table.checked_button.provider)
                    end,
                },
            } }
            local button_table = withSheetStyle(function()
                return ButtonTable:new{
                    width = inner,
                    buttons = buttons,
                    zero_sep = true,
                    show_parent = self,
                }
            end)
            self:mergeLayoutInVertical(button_table)

            self.radio_button_table_height = radio_button_table:getSize().h
            local btn_h = (radio_button_table.checked_button and radio_button_table.checked_button:getSize().h) or S_(38)
            local max_rows = 6
            local max_h = max_rows * btn_h
            if self.radio_button_table_height > max_h then
                self.is_scrollable = true
                self.radio_buttons_per_page = max_rows
                self.radio_button_container_height = max_h
            else
                self.radio_button_container_height = self.radio_button_table_height
            end
            self.cropping_widget = ScrollableContainer:new{
                dimen = Geom:new{ w = inner, h = self.radio_button_container_height },
                show_parent = self,
                LeftContainer:new{
                    dimen = Geom:new{ w = list_w, h = self.radio_button_table_height },
                    radio_button_table,
                },
            }
            self:scrollToCheckedButton()

            local frame = FrameContainer:new{
                background = WHITE,
                bordersize = Size.border.thin,
                radius = S_(SHEET_RADIUS),
                padding = pad,
                padding_bottom = math.max(0, pad - Size.span.vertical_default),
                VerticalGroup:new{
                    align = "left",
                    title_w,
                    VerticalSpan:new{ width = S_(10) },
                    self.cropping_widget,
                    VerticalSpan:new{ width = S_(12) },
                    button_table,
                },
            }
            self.movable = MovableContainer:new{ frame }
            self[1] = BottomContainer:new{
                dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() - S_(SHEET_MARGIN) },
                self.movable,
            }
        end, TAG)
    end

    local ok_mcb, MultiConfirmBox = pcall(require, "ui/widget/multiconfirmbox")
    if ok_mcb and type(MultiConfirmBox) == "table" and not MultiConfirmBox._aire_sheet_init then
        MultiConfirmBox._aire_sheet_init = true
        local MovableContainer = require("ui/widget/container/movablecontainer")
        local function buildConfirmSheet(self, button_row)
            if self.dismissable and Device:isTouchDevice() then
                self.ges_events.TapClose = {
                    GestureRange:new{ ges = "tap",
                        range = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } },
                }
            end
            if self.dismissable and Device:hasKeys() then
                self.key_events.Close = { { Device.input.group.Back } }
            end
            local inner = sheetInnerWidth()
            local pad = S_(SHEET_PAD)
            local function buildText(w)
                local vg = VerticalGroup:new{ align = "left",
                    TextBoxWidget:new{ text = self.text or "", face = Font:getFace("tfont", 15), width = w } }
                if self.aire_bold_text then
                    table.insert(vg, VerticalSpan:new{ width = S_(8) })
                    table.insert(vg, TextBoxWidget:new{ text = self.aire_bold_text, face = Font:getFace("cfont", 15), width = w })
                end
                return vg
            end
            local bt = withSheetStyle(function()
                return ButtonTable:new{
                    width = inner,
                    show_parent = self,
                    buttons = button_row,
                }
            end)
            -- Texto muy largo: se desplaza solo el texto y los botones siguen a
            -- la vista (common/sheet.lua: alto máximo de una hoja)
            local text = buildText(inner)
            local max_text_h = package.loaded.aire_sheet.maxContentHeight() - bt:getSize().h - S_(16)
            if text:getSize().h > max_text_h then
                text:free()
                text = ScrollableContainer:new{
                    dimen = Geom:new{ w = inner, h = math.max(S_(80), max_text_h) },
                    show_parent = self,
                    buildText(inner - ScrollableContainer:getScrollbarWidth()),
                }
                self.cropping_widget = text
            end
            -- Marco y posición de hoja comunes (common/sheet.lua), dentro del
            -- MovableContainer que KOReader espera; la tabla ya deja un hueco
            -- bajo la última fila de botones
            local _frame
            _frame, self[1] = package.loaded.aire_sheet.frame(
                VerticalGroup:new{ align = "left", text, VerticalSpan:new{ width = S_(16) }, bt },
                self, {
                    padding_bottom = math.max(0, pad - Size.span.vertical_default),
                    wrap = function(f)
                        self.movable = MovableContainer:new{ f }
                        return self.movable
                    end,
                })
        end

        safeWrap(MultiConfirmBox, "init", function(_orig, self)
            buildConfirmSheet(self, { {
                { text = self.cancel_text, id = "close", callback = function()
                    self.cancel_callback()
                    UIManager:close(self)
                end },
                { text = self.choice1_text, text_func = self.choice1_text_func,
                  enabled = self.choice1_enabled, callback = function()
                    self.choice1_callback()
                    UIManager:close(self)
                end },
                { text = self.choice2_text, text_func = self.choice2_text_func,
                  enabled = self.choice2_enabled, callback = function()
                    self.choice2_callback()
                    UIManager:close(self)
                end },
            } })
        end, TAG)

        if CONFIRM_BOX_AS_SHEET then
            local ok_cb, ConfirmBox = pcall(require, "ui/widget/confirmbox")
            if ok_cb and type(ConfirmBox) == "table" and not ConfirmBox._aire_sheet_like_mcb then
                ConfirmBox._aire_sheet_like_mcb = true
                safeWrap(ConfirmBox, "init", function(orig_cb_init, self)
                    if self._added_widgets then
                        return orig_cb_init(self)
                    end
                    -- Mismos botones que ConfirmBox:init de KOReader: other_buttons
                    -- son FILAS (arriba si other_buttons_first), cada botón extra
                    -- cierra salvo keep_dialog_open, y no_ok_button quita OK
                    local buttons = { {
                        { text = self.cancel_text, id = "close", callback = function()
                            if self.cancel_callback then self.cancel_callback() end
                            UIManager:close(self)
                        end },
                        { text = self.ok_text, is_enter_default = true, callback = function()
                            if self.ok_callback then self.ok_callback() end
                            if self.keep_dialog_open then return end
                            UIManager:close(self)
                        end },
                    } }
                    if self.no_ok_button then
                        table.remove(buttons[1], 2)
                    end
                    if type(self.other_buttons) == "table" then
                        local rownum = self.other_buttons_first and 0 or 1
                        for i, buttons_row in ipairs(self.other_buttons) do
                            local row = {}
                            for _j, button in ipairs(buttons_row) do
                                table.insert(row, {
                                    text = button.text,
                                    callback = function()
                                        if button.callback then button.callback() end
                                        if self.keep_dialog_open then return end
                                        UIManager:close(self)
                                    end,
                                })
                            end
                            table.insert(buttons, rownum + i, row)
                        end
                    end
                    buildConfirmSheet(self, buttons)
                end, TAG)
            end
        end
    end
end

return {
    S_ = S_,
    SHEET_PAD = SHEET_PAD,
    SHEET_BTN_H = SHEET_BTN_H,
    SHEET_BTN_RADIUS = SHEET_BTN_RADIUS,
    SHEET_BTN_GAP = SHEET_BTN_GAP,
    SHEET_BTN_FONT = SHEET_BTN_FONT,
    sheetWidth = sheetWidth,
    sheetInnerWidth = sheetInnerWidth,
    withSheetStyle = withSheetStyle,
    withSheetButtons = withSheetButtons,
    -- Contador vivo: se lee con una función (un valor copiado se quedaría en 0)
    sheetDepth = function() return sheet_depth end,
    Tap = Tap,
    SliderBar = SliderBar,
    StepBar = StepBar,
    roundButton = roundButton,
}
