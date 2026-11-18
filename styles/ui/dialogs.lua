--[[
    aire.koplugin/styles/ui/dialogs.lua
    Diálogos y avisos: esquinas redondeadas, botones y títulos limpios, InfoMessage/ConfirmBox centrados, 'Abriendo «Título»…' y avisos rápidos.
    Lo carga styles/ui.lua en su orden (recibe la tabla de styles/ui/base.lua).
--]]

local B = ...
local uiOpt = B.uiOpt
local isA = B.isA
local getUpValue = B.getUpValue
local Device = require("device")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BookList = require("ui/widget/booklist")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local ConfirmBox = require("ui/widget/confirmbox")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local LineWidget = require("ui/widget/linewidget")
local Notification = require("ui/widget/notification")
local ReaderUI = require("apps/reader/readerui")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local userpatch = require("userpatch")
local _ = require("gettext")
local T = require("ffi/util").template
local Screen = Device.screen

-- stylua: ignore start
local WINDOW_RADIUS             = 12     -- radio de las esquinas de los diálogos
local NO_BOLD_IN_BUTTONS        = true   -- botones en texto normal (no negrita)
local BOLD_TITLE                = true   -- título en negrita en ButtonDialog
local SINGLE_GROUP_SEPARATOR    = true   -- una sola línea entre grupos de botones
local GROUP_SEPARATOR_BLACK     = true   -- false: línea gris como las demás
local CLEAN_INFO_MESSAGE        = true   -- quitar icono gigante en InfoMessage y centrar
local CLEAN_CONFIRM_BOX         = true   -- quitar icono "?" en ConfirmBox y centrar
local CONFIRM_BOX_AS_SHEET = B.CONFIRM_BOX_AS_SHEET
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"
local OPENING_BOOK_TITLE        = uiOpt("opening_title")   -- mostrar "Abriendo «Título»…"
local PILL_NOTIFICATIONS        = true   -- esquinas redondeadas como los diálogos
-- stylua: ignore end

--===========================================================================
-- 1) DIÁLOGOS Y VENTANAS EMERGENTES
--===========================================================================
if WINDOW_RADIUS and WINDOW_RADIUS > 0 then
    Size.radius.window = Screen:scaleBySize(WINDOW_RADIUS)

    -- Repintar el borde redondeado después de los hijos y mantener redondeado el
    -- fondo blanco de los botones sin borde para no comer 1 píxel en las esquinas
    -- inferiores de los diálogos.
    if not FrameContainer._rounded_border_after_patched then
        FrameContainer._rounded_border_after_patched = true
        -- Dobladillo en la esquina superior derecha (lector y miniaturas de explorador de páginas)
        function FrameContainer._aire_draw_top_right_fold(bb, X, Y, sz, t, r)
            local WHITE = Blitbuffer.COLOR_WHITE
            local BLACK = Blitbuffer.COLOR_BLACK
            if r and r > 0 then
                local rf = math.min(r, math.floor(sz * 0.35))
                bb:paintRoundedRect(X, Y, sz, sz, WHITE, rf)
                bb:paintBorder(X, Y, sz, sz, t, BLACK, rf, true)
                -- Conservar solo la esquina inferior izquierda (X, Y + sz) redondeada
                bb:paintRect(X, Y, rf, rf, WHITE)
                bb:paintRect(X + sz - rf, Y + sz - rf, rf, rf, WHITE)
                bb:paintRect(X, Y, t, sz - rf, BLACK)
                bb:paintRect(X + rf, Y + sz - t, sz - rf, t, BLACK)
                for i = 0, sz - 1 do
                    bb:paintRect(X + i + 1, Y + i, sz - 1 - i, 1, WHITE)
                    bb:paintRect(X + i, Y + i, t, 1, BLACK)
                end
            else
                for i = 0, sz - 1 do
                    bb:paintRect(X + i + 1, Y + i, sz - 1 - i, 1, WHITE)
                    bb:paintRect(X, Y + i, i, 1, WHITE)
                    bb:paintRect(X + i, Y + i, t, 1, BLACK)
                end
                bb:paintRect(X, Y, t, sz, BLACK)
                bb:paintRect(X, Y + sz - t, sz, t, BLACK)
            end
        end
        local orig_FrameContainer_paintTo = FrameContainer.paintTo
        -- "Suavizado de la interfaz": se lee una vez y se actualiza solo cuando
        -- cambia (el menú de KOReader lo cambia con flipNilOrTrue/saveSetting),
        -- en vez de consultar los ajustes en cada marco pintado
        local anti_alias = G_reader_settings:nilOrTrue("anti_alias_ui")
        for _i, m in ipairs({ "flipNilOrTrue", "saveSetting", "delSetting", "makeTrue", "makeFalse", "toggle" }) do
            local orig_m = G_reader_settings[m]
            if type(orig_m) == "function" then
                G_reader_settings[m] = function(st, key, ...)
                    local r = { orig_m(st, key, ...) }
                    if key == "anti_alias_ui" then anti_alias = st:nilOrTrue("anti_alias_ui") end
                    return unpack(r)
                end
            end
        end

        -- Lo que Aire pinta encima del marco (esquinas, borde, cinta, etiqueta).
        -- Va aparte y protegido: este paintTo es el de TODOS los marcos de
        -- KOReader y un fallo aquí lo cerraría entero.
        local function paintAireExtras(self, bb, x, y)
            if self.bordersize and self.bordersize > 0 and self.radius and self.radius > 0 and self[1] then
                local my_size = self:getSize()
                local container_width = self.width or my_size.w
                local container_height = self.height or my_size.h
                local cx, cy = x + self.margin, y + self.margin
                local cw, ch = container_width - self.margin * 2, container_height - self.margin * 2
                if self._aire_clip_corners then
                    local r = self.radius
                    local bg = self._aire_clip_bg or Blitbuffer.COLOR_WHITE
                    for dy = 0, r - 1 do
                        local dx = r - math.floor(math.sqrt(r * r - (r - dy - 0.5) ^ 2) + 0.5)
                        if dx > 0 then
                            bb:paintRect(cx, cy + dy, dx, 1, bg)
                            bb:paintRect(cx + cw - dx, cy + dy, dx, 1, bg)
                            bb:paintRect(cx, cy + ch - 1 - dy, dx, 1, bg)
                            bb:paintRect(cx + cw - dx, cy + ch - 1 - dy, dx, 1, bg)
                        end
                    end
                end
                bb:paintBorder(cx, cy, cw, ch, self.bordersize, self.color, self.radius, anti_alias)
            end
            if self._aire_bookmark_fold then
                local my_size = self:getSize()
                local cw = (self.width or my_size.w) - self.margin * 2
                local cx, cy = x + self.margin, y + self.margin
                -- Miniatura con marcador: cinta negra colgando del borde de
                -- arriba (antes, un dobladillo como el del lector)
                local rw = math.max(Screen:scaleBySize(10), math.floor(cw * 0.09))
                local rh = math.floor(rw * 1.7)
                local rx = cx + cw - rw - math.max(Screen:scaleBySize(6), (self.radius or 0))
                local notch = math.floor(rw / 2)
                bb:paintRect(rx, cy, rw, rh, Blitbuffer.COLOR_BLACK)
                for row = 0, notch - 1 do
                    local half = math.floor((notch - row) * rw / (2 * notch))
                    if half > 0 then
                        bb:paintRect(rx + math.floor(rw / 2) - half, cy + rh - 1 - row, 2 * half, 1, Blitbuffer.COLOR_WHITE)
                    end
                end
            end
            if self._aire_page_label and self._aire_page_label ~= "" then
                local my_size = self:getSize()
                local cw = (self.width or my_size.w) - self.margin * 2
                local ch = (self.height or my_size.h) - self.margin * 2
                local cx, cy = x + self.margin, y + self.margin
                local tw = TextWidget:new{
                    text = tostring(self._aire_page_label),
                    face = Font:getFace("tfont", 10),
                    fgcolor = Blitbuffer.COLOR_WHITE,
                    padding = 0,
                }
                local ts = tw:getSize()
                local pad_h, pad_v = Screen:scaleBySize(7), Screen:scaleBySize(2)
                local pw = math.min(cw - Screen:scaleBySize(8), ts.w + 2 * pad_h)
                local ph = ts.h + 2 * pad_v
                local px = cx + math.floor((cw - pw) / 2)
                local py = cy + ch - ph - Screen:scaleBySize(6)
                bb:paintRoundedRect(px, py, pw, ph, Blitbuffer.COLOR_BLACK, math.floor(ph / 2))
                tw:paintTo(bb, px + math.floor((pw - ts.w) / 2), py + pad_v)
                tw:free()
            end
        end
        function FrameContainer:paintTo(bb, x, y)
            orig_FrameContainer_paintTo(self, bb, x, y)
            -- (la mayoría de marcos no tiene nada de esto: salir sin más)
            if not ((self.radius and self.radius > 0 and self.bordersize and self.bordersize > 0)
                    or self._aire_bookmark_fold or self._aire_page_label) then
                return
            end
            local ok, err = pcall(paintAireExtras, self, bb, x, y)
            if not ok then logger.warn("Aire/UI: pintando un marco:", err) end
        end
    end

    if not Button._rounded_bg_patched then
        Button._rounded_bg_patched = true
        safeWrap(Button, "init", function(orig_Button_init, self)
            orig_Button_init(self)
            if self.bordersize == 0 and not self.radius and self.frame then
                self.frame.radius = Size.radius.button
                self.frame._keep_btn_radius = true
            end
        end, TAG)

        safeWrap(Button, "_doFeedbackHighlight", function(orig_Button_doFeedbackHighlight, self)
            if self[1] and self[1]._keep_btn_radius then
                self[1].radius = nil
            end
            return orig_Button_doFeedbackHighlight(self)
        end, TAG)

        safeWrap(Button, "_undoFeedbackHighlight", function(orig_Button_undoFeedbackHighlight, self, is_translucent)
            if self.text and self[1] and self[1]._keep_btn_radius and self[1].radius == Size.radius.button then
                self[1].background = self[1].background:invert()
                self.label_widget.fgcolor = self.label_widget.fgcolor:invert()
                local UIManager = require("ui/uimanager")
                UIManager:widgetRepaint(self[1], self[1].dimen.x, self[1].dimen.y)
                if is_translucent then
                    UIManager:setDirty(self.show_parent, "ui", self[1].dimen)
                else
                    UIManager:setDirty(nil, self.enabled and "fast" or "ui", self[1].dimen)
                end
                return
            end
            return orig_Button_undoFeedbackHighlight(self, is_translucent)
        end, TAG)
    end
end

if BOLD_TITLE and not ButtonDialog._bold_title_patched then
    ButtonDialog._bold_title_patched = true
    safeWrap(ButtonDialog, "init", function(orig_ButtonDialog_init, self)
        if rawget(self, "use_info_style") == nil then
            self.use_info_style = false
        end
        return orig_ButtonDialog_init(self)
    end, TAG)
end

local function collapseEmptyRows(bt)
    local c = bt.container
    if not c then return end
    local changed = false
    local i = 1
    while i <= #c do
        local w = c[i]
        if isA(w, HorizontalGroup) and #w == 0 then
            -- Esperado: [Línea] [Hueco] [fila vacía] [Hueco] [Línea]
            local before_line = c[i - 2]
            local first = (isA(c[i - 1], VerticalSpan)) and i - 1 or i
            local last = (isA(c[i + 1], VerticalSpan)) and i + 1 or i
            local after_line = c[last + 1]
            if isA(after_line, LineWidget) then
                last = last + 1
            end
            for _ = first, last do table.remove(c, first) end
            local keep = isA(before_line, LineWidget) and before_line or nil
            if keep then keep._aire_group_sep = true end -- hojas: separador de grupo
            if keep and GROUP_SEPARATOR_BLACK then
                keep.background = Blitbuffer.COLOR_BLACK
            end
            changed = true
            i = first
        else
            i = i + 1
        end
    end
    if changed and c.resetLayout then c:resetLayout() end
end

if (NO_BOLD_IN_BUTTONS or SINGLE_GROUP_SEPARATOR) and not ButtonTable._single_sep_patched then
    ButtonTable._single_sep_patched = true
    safeWrap(ButtonTable, "init", function(orig_ButtonTable_init, self)
        if NO_BOLD_IN_BUTTONS and self.buttons then
            for _, row in ipairs(self.buttons) do
                for _, btn in ipairs(row) do
                    if type(btn) == "table" and btn.font_bold == nil then
                        btn.font_bold = false
                    end
                end
            end
        end
        orig_ButtonTable_init(self)
        if SINGLE_GROUP_SEPARATOR then
            local ok, err = pcall(collapseEmptyRows, self)
            if not ok then logger.warn("Aire/UI: no se pudo unificar separadores:", err) end
        end
    end, TAG)
end

if CLEAN_INFO_MESSAGE and not InfoMessage._modern_style_patched then
    InfoMessage._modern_style_patched = true
    safeWrap(InfoMessage, "init", function(orig_InfoMessage_init, self)
        if rawget(self, "show_icon") == nil and not self.image then
            self.show_icon = false
        end
        if not self.show_icon and rawget(self, "alignment") == nil and not self.height then
            self.alignment = "center"
        end
        orig_InfoMessage_init(self)
        local frame = self.movable and self.movable[1]
        if frame then
            frame.bordersize = Size.border.thin
            if not self.show_icon then
                frame.padding_top = Size.padding.large
                frame.padding_bottom = Size.padding.large
                frame.padding_left = Size.padding.fullscreen
                frame.padding_right = Size.padding.fullscreen
            end
        end
    end, TAG)
end

if CLEAN_CONFIRM_BOX and not ConfirmBox._modern_style_patched then
    ConfirmBox._modern_style_patched = true
    local TextBoxWidget_up, tbw_idx = getUpValue(ConfirmBox.init, "TextBoxWidget")
    safeWrap(ConfirmBox, "init", function(orig_ConfirmBox_init, self)
        local center_text = not CONFIRM_BOX_AS_SHEET and not self._added_widgets and TextBoxWidget_up ~= nil
        if center_text then
            local CenteredTBW = setmetatable({}, { __index = TextBoxWidget_up })
            function CenteredTBW:new(o)
                if o and o.alignment == nil then o.alignment = "center" end
                return TextBoxWidget_up.new(TextBoxWidget_up, o)
            end
            userpatch.replaceUpValue(orig_ConfirmBox_init, tbw_idx, CenteredTBW)
        end
        local ok, err = pcall(orig_ConfirmBox_init, self)
        if center_text then
            userpatch.replaceUpValue(orig_ConfirmBox_init, tbw_idx, TextBoxWidget_up)
        end
        if not ok then error(err) end

        local frame = self.movable and self.movable[1]
        if frame then frame.bordersize = Size.border.thin end
        local vgroup = frame and frame[1]
        local content = vgroup and vgroup[1]
        if content and #content >= 3 and self.text_group and content[3] == self.text_group then
            if content[1] and content[1].free then content[1]:free() end
            table.remove(content, 1) -- IconWidget
            table.remove(content, 1) -- HorizontalSpan
            content:resetLayout()
            local bt = vgroup[3]
            local target_w = (bt and bt:getSize().w) or self.text_widget_width
            if target_w and self.text_group:getSize().w < target_w then
                local pad = math.floor((target_w - self.text_group:getSize().w) / 2)
                if pad > 0 then
                    table.insert(content, 1, WidgetContainer:new{ dimen = Geom:new{ w = pad, h = 1 } })
                    content:resetLayout()
                end
            end
            vgroup:resetLayout()
        end
    end, TAG)
end

--===========================================================================
-- 5) MENSAJE "ABRIENDO «TÍTULO»…" AL ABRIR UN LIBRO
--===========================================================================
if OPENING_BOOK_TITLE and not ReaderUI._opening_book_title then
    ReaderUI._opening_book_title = true

    local function getBookTitle(file)
        local props
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if ok_bim and BookInfoManager and BookInfoManager.getDocProps then
            local ok, res = pcall(BookInfoManager.getDocProps, BookInfoManager, file)
            if ok and res then props = res end
        end
        if not (props and props.title) and BookList.hasBookBeenOpened(file) then
            local ok, ds = pcall(BookList.getDocSettings, file)
            local saved = ok and ds and ds:readSetting("doc_props")
            if saved then props = saved end
        end
        local ok_bi, BookInfo = pcall(require, "apps/filemanager/filemanagerbookinfo")
        if ok_bi and BookInfo and BookInfo.extendProps then
            local ok, ext = pcall(BookInfo.extendProps, props, file)
            if ok and ext then props = ext end
        end
        local title = props and props.title
        if type(title) == "string" and title ~= "" and title ~= "\u{FFFF}" then
            return title
        end
    end

    safeWrap(ReaderUI, "showReaderCoroutine", function(orig_showReaderCoroutine, self, file, provider, seamless)
        local ok, title = pcall(getBookTitle, file)
        if not ok then
            logger.warn("Aire/UI: no se pudo leer el título:", title)
            title = nil
        end
        if not title then
            return orig_showReaderCoroutine(self, file, provider, seamless)
        end

        local own_new = rawget(InfoMessage, "new")
        local base_new = InfoMessage.new
        local replaced = false
        InfoMessage.new = function(cls, o)
            if not replaced and cls == InfoMessage and type(o) == "table" then
                replaced = true
                o.text = T(_("Opening \"%1\"…"), BD.auto(title))
            end
            return base_new(cls, o)
        end
        local ok_call, err = pcall(orig_showReaderCoroutine, self, file, provider, seamless)
        rawset(InfoMessage, "new", own_new)
        if not ok_call then error(err) end
    end, TAG)
end

--===========================================================================
-- 6) AVISOS RÁPIDOS (NOTIFICATION / TOASTS) EN FORMA DE PÍLDORA
--===========================================================================
if PILL_NOTIFICATIONS and not Notification._pill_patched then
    Notification._pill_patched = true
    safeWrap(Notification, "init", function(orig_Notification_init, self)
        orig_Notification_init(self)
        local f = self.frame
        if not f then return end
        f.padding_left = Size.padding.large
        f.padding_right = Size.padding.large
        f.padding_top = Size.padding.default
        f.padding_bottom = Size.padding.default
        -- Mismo radio y borde fino que el resto de ventanas del plugin
        f.radius = Size.radius.window
        f.bordersize = Size.border.thin
        f._size = nil
        local sz = f:getSize()
        if self[1] and self[1][1] and self._shown_idx then
            self[1][1].height = sz.h * (self._shown_idx - 1) + (self.margin or 0)
            if self[1].resetLayout then self[1]:resetLayout() end
        end
    end, TAG)
end
