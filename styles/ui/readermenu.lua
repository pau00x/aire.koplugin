--[[
    aire.koplugin/styles/ui/readermenu.lua
    Menú inferior del lector (ConfigDialog) como hoja inferior, con controles y pestañas con el estilo de Aire.
    Lo carga styles/ui.lua en su orden (recibe la tabla de styles/ui/base.lua
    y lo que exporta styles/ui/sheets.lua).
--]]

local B = ...
local uiOpt = B.uiOpt
local getUpValue = B.getUpValue
local SHEET_MARGIN = B.SHEET_MARGIN
local SHEET_RADIUS = B.SHEET_RADIUS
local MENU_SIDE_INSET = B.MENU_SIDE_INSET
local SHEET_PAD = B.SHEET_PAD
local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"

--===========================================================================
-- 17) MENÚ INFERIOR DEL LECTOR (ConfigDialog) COMO HOJA INFERIOR
--     Diseño A elegido: tarjeta separada SHEET_MARGIN de los bordes, borde
--     fino y esquinas SHEET_RADIUS, nombre de la pestaña arriba a la
--     izquierda, opciones en medio y las pestañas abajo (como el dock), con
--     la activa en píldora negra. Parte 1: hoja y pestañas; los controles
--     (interruptores, barras) siguen siendo los de KOReader.
--===========================================================================
do
    local ok_cd, ConfigDialog = pcall(require, "ui/widget/configdialog")
    if ok_cd and type(ConfigDialog) == "table" and not ConfigDialog._aire_sheet_style and uiOpt("reader_menu_sheet") then
        ConfigDialog._aire_sheet_style = true
        local BottomContainer = require("ui/widget/container/bottomcontainer")

        -- Nombre de cada pestaña (KOReader no lo tiene: solo icono)
        local TAB_TITLES = {
            ["appbar.rotation"] = _("Orientation"),
            ["appbar.crop"]     = _("Margins"),
            ["appbar.pagefit"]  = _("Page fit"),
            ["appbar.pageview"] = _("Layout"),
            ["appbar.textsize"] = _("Text"),
            ["appbar.contrast"] = _("Contrast"),
            ["appbar.settings"] = _("More settings"),
        }
        -- Los mismos iconos que en el menú superior cuando existen; Contraste,
        -- el de contraste de Aire (el del widget de modo nocturno), no el
        -- círculo rayado de KOReader
        local TAB_ICONS = {
            ["appbar.settings"] = "aire.settings",
            ["appbar.contrast"] = "aire.widget.contrast",
            ["appbar.textsize"] = "aire.text", -- cuadrado con una "A" (icono de texto de Aire)
            -- Mismo trazo y tamaño que los del menú superior (los de KOReader
            -- se veían más grandes o más pequeños según el dibujo)
            ["appbar.rotation"] = "aire.rotation",
            ["appbar.crop"] = "aire.crop",
            ["appbar.pageview"] = "aire.pageview",
        }

        -- Ejecutar fn creyendo que la pantalla mide w de ancho: ConfigOption
        -- reparte nombres y controles como fracción de Screen:getWidth()
        local function withWidth(w, fn, ...)
            local had = rawget(Screen, "getWidth")
            Screen.getWidth = function() return w end
            local ok, err = pcall(fn, ...)
            Screen.getWidth = had
            if not ok then error(err, 0) end
        end

        local function styleSheet(self)
            local sw, sh = Screen:getWidth(), Screen:getHeight()
            local margin = Screen:scaleBySize(SHEET_MARGIN)
            local border = Size.border.thin
            local card_w = sw - 2 * margin
            local inner_w = card_w - 2 * border
            local edge = Screen:scaleBySize(MENU_SIDE_INSET)
            local options = self.config_options or {}
            local cur = options[self.panel_index] or {}

            -- Título: nombre de la pestaña activa
            local title = TextWidget:new{
                text = TAB_TITLES[cur.icon] or "",
                face = Font:getFace("tfont", 15),
                fgcolor = Blitbuffer.COLOR_BLACK,
                max_width = inner_w - 2 * edge,
                padding = 0,
            }

            -- Pestañas: casillas iguales con la píldora centrada (como el menú superior)
            local items = self.config_menubar and self.config_menubar.menu_items or {}
            local n = #items
            local tabs = HorizontalGroup:new{ align = "center" }
            if n > 0 then
                local avail = inner_w - 2 * edge
                local slot_w = math.floor(avail / n)
                local extra = avail - slot_w * n
                local icon_sz = Screen:scaleBySize(24)
                local pill_w = math.min(Screen:scaleBySize(56), slot_w - Screen:scaleBySize(4))
                local pill_h = Screen:scaleBySize(38)
                local vpad = Screen:scaleBySize(4)
                local slot_h = pill_h + 2 * vpad
                table.insert(tabs, HorizontalSpan:new{ width = edge + math.floor(extra / 2) })
                for idx, ib in ipairs(items) do
                    local opt = options[idx] or {}
                    local icon_name = TAB_ICONS[opt.icon] or opt.icon or ib.icon
                    local active = (idx == self.panel_index)
                    if ib.image and ib.image.free then ib.image:free() end
                    local iw = IconWidget:new{ icon = icon_name, width = icon_sz, height = icon_sz, alpha = true }
                    ib.image = iw
                    local holder = WidgetContainer:new{
                        dimen = Geom:new{ w = icon_sz, h = icon_sz },
                        iw,
                    }
                    if active then
                        -- Icono blanco sobre negro: pintar sobre blanco e invertir
                        holder.paintTo = function(_self, bb, x, y)
                            bb:paintRect(x, y, icon_sz, icon_sz, Blitbuffer.COLOR_WHITE)
                            iw:paintTo(bb, x, y)
                            bb:invertRect(x, y, icon_sz, icon_sz)
                        end
                    end
                    ib[1] = CenterContainer:new{
                        dimen = Geom:new{ w = slot_w, h = slot_h },
                        FrameContainer:new{
                            width = pill_w, height = pill_h,
                            bordersize = 0, padding = 0,
                            radius = Screen:scaleBySize(10),
                            background = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                            CenterContainer:new{ dimen = Geom:new{ w = pill_w, h = pill_h }, holder },
                        },
                    }
                    -- Destello y zona táctil de IconButton ajustados a la casilla
                    ib.padding_left = math.floor((slot_w - icon_sz) / 2)
                    ib.padding_right = slot_w - icon_sz - ib.padding_left
                    ib.padding_top = math.floor((slot_h - icon_sz) / 2)
                    ib.padding_bottom = slot_h - icon_sz - ib.padding_top
                    if ib.dimen then
                        ib.dimen.w, ib.dimen.h = slot_w, slot_h
                    else
                        ib.dimen = Geom:new{ x = 0, y = 0, w = slot_w, h = slot_h }
                    end
                    table.insert(tabs, ib)
                end
            end

            if self.config_panel then
                self.config_panel.padding = 0
                self.config_panel.padding_left, self.config_panel.padding_right = 0, 0
            end
            local content = VerticalGroup:new{
                align = "left",
                HorizontalSpan:new{ width = inner_w }, -- ancho fijo: la hoja siempre mide card_w
                VerticalSpan:new{ width = Screen:scaleBySize(SHEET_PAD) },
                HorizontalGroup:new{ HorizontalSpan:new{ width = edge }, title },
                -- Panel de opciones al ancho exacto de la hoja: ConfigPanel trae su
                -- propio relleno (padding.default a cada lado) y hacía la hoja 10 px
                -- más ancha, así que BottomContainer la dejaba desplazada a la izquierda
                CenterContainer:new{
                    dimen = Geom:new{ w = inner_w, h = self.config_panel:getSize().h },
                    self.config_panel,
                },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = edge },
                    LineWidget:new{
                        dimen = Geom:new{ w = inner_w - 2 * edge, h = Size.line.thin },
                        background = Blitbuffer.COLOR_LIGHT_GRAY,
                    },
                },
                VerticalSpan:new{ width = Screen:scaleBySize(4) },
                tabs,
                VerticalSpan:new{ width = Screen:scaleBySize(6) },
            }
            self.dialog_frame = FrameContainer:new{
                bordersize = border,
                color = Blitbuffer.COLOR_BLACK,
                background = Blitbuffer.COLOR_WHITE,
                radius = Screen:scaleBySize(SHEET_RADIUS),
                padding = 0,
                width = card_w,
                content,
            }
            self[1] = BottomContainer:new{
                dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh - margin },
                self.dialog_frame,
            }
        end

        -----------------------------------------------------------------
        -- Parte 2: controles. Solo los que se crean mientras se monta este
        -- menú (building_sheet); en otros diálogos siguen como en KOReader.
        -----------------------------------------------------------------
        local building_sheet = false
        local BLACK, WHITE = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE

        -- Interruptores: contorno negro fino y la opción elegida en negro
        -- (KOReader: contorno y elegida en gris oscuro)
        local ok_ts, ToggleSwitch = pcall(require, "ui/widget/toggleswitch")
        if ok_ts and type(ToggleSwitch) == "table" and not ToggleSwitch._aire_sheet_style then
            ToggleSwitch._aire_sheet_style = true
            safeWrap(ToggleSwitch, "init", function(orig_ts_init, self, ...)
                local styled = building_sheet
                if styled then
                    self.fgcolor = BLACK
                    self.bgcolor = WHITE
                end
                orig_ts_init(self, ...)
                if not styled or not self.toggle_frame then return end
                local fr = self.toggle_frame
                fr.color = BLACK
                local r_items = math.max(0, (fr.radius or 0) - (fr.padding or 0))
                for _, row in ipairs(self.toggle_content or {}) do
                    for _, cell in ipairs(row) do
                        cell.radius = r_items
                    end
                end
            end, TAG)
        end

        -- Barras de valores: píldoras redondeadas con borde negro fino; las
        -- marcadas en gris oscuro (como las barras de progreso del plugin), el
        -- valor por defecto con borde grueso. Sin "invert": en un botón
        -- redondeado pintaría de negro las esquinas.
        local ok_bp, ButtonProgressWidget = pcall(require, "ui/widget/buttonprogresswidget")
        if ok_bp and type(ButtonProgressWidget) == "table" and not ButtonProgressWidget._aire_sheet_style then
            ButtonProgressWidget._aire_sheet_style = true
            safeWrap(ButtonProgressWidget, "init", function(orig_bp_init, self, ...)
                if building_sheet then self._aire_sheet_ctl = true end
                return orig_bp_init(self, ...)
            end, TAG)
            safeWrap(ButtonProgressWidget, "update", function(orig_bp_update, self, ...)
                orig_bp_update(self, ...)
                if not self._aire_sheet_ctl or not self.buttonprogress_content then return end
                local r = Screen:scaleBySize(6)
                local vi = 0
                for _, w in ipairs(self.buttonprogress_content) do
                    local b = w
                    -- Estilo gris fino: el botón marcado va dentro de otro marco
                    if type(b) == "table" and not b.frame and type(b[1]) == "table" and b[1].frame then b = b[1] end
                    if type(b) == "table" and b.frame then
                        local f = b.frame
                        local is_value = b.text == ""
                        local marked = false
                        if is_value then
                            vi = vi + 1
                            marked = vi <= (tonumber(self.position) or 0)
                        end
                        f.radius = r
                        f.invert = false
                        f.color = BLACK
                        f.bordersize = (is_value and vi == self.default_position) and Size.border.thick or Size.border.thin
                        f.background = marked and Blitbuffer.COLOR_DARK_GRAY or WHITE
                    end
                end
            end, TAG)
        end

        -----------------------------------------------------------------
        -- Parte 3: contenido de las pestañas (filas de opciones)
        --   · nombres a la izquierda, cfont 15 (KOReader: 20, a la derecha)
        --   · letras / iconos: la opción elegida en píldora (no subrayado)
        --   · separadores grises finos entre filas, margen MENU_SIDE_INSET
        --   · alto de las filas: el de KOReader (con 44 quedaba amontonado)
        -----------------------------------------------------------------
        local ConfigPanel = getUpValue(ConfigDialog.update, "ConfigPanel")
        local ConfigOption = ConfigPanel and ConfigPanel.init and getUpValue(ConfigPanel.init, "ConfigOption")
        local OptionTextItem = ConfigOption and getUpValue(ConfigOption.init, "OptionTextItem")
        local OptionIconItem = ConfigOption and getUpValue(ConfigOption.init, "OptionIconItem")
        local LeftContainer_ = require("ui/widget/container/leftcontainer")
        local RightContainer_ = require("ui/widget/container/rightcontainer")

        -- Píldora en lugar de subrayado: se pinta el contenido sobre blanco y
        -- se invierte solo su recuadro, con la píldora redondeada alrededor
        local function pillPaint(uc, bb, x, y)
            local size = uc:getSize()
            if not uc.dimen then
                uc.dimen = Geom:new{ x = x, y = y, w = size.w, h = size.h }
            else
                uc.dimen.x, uc.dimen.y = x, y
            end
            local content = uc[1]
            local cs = content:getSize()
            local cy = y + math.floor((size.h - cs.h) / 2)
            local selected = not rawequal(uc.color, nil) and uc.color ~= WHITE
            if selected then
                local ph, pv = Screen:scaleBySize(4), Screen:scaleBySize(3)
                bb:paintRoundedRect(x - ph, cy - pv, cs.w + 2 * ph, cs.h + 2 * pv, uc.color, Screen:scaleBySize(8))
                bb:paintRect(x, cy, cs.w, cs.h, WHITE)
                content:paintTo(bb, x, cy)
                bb:invertRect(x, cy, cs.w, cs.h)
            else
                content:paintTo(bb, x, cy)
            end
        end
        for _, cls in ipairs({ OptionTextItem or false, OptionIconItem or false }) do
            if cls and not cls._aire_sheet_style then
                cls._aire_sheet_style = true
                local orig_item_init = cls.init
                cls.init = function(item, ...)
                    orig_item_init(item, ...)
                    if building_sheet and item.underline_container then
                        item.underline_container.paintTo = pillPaint
                    end
                end
            end
        end

        if ConfigOption and not ConfigOption._aire_sheet_style then
            ConfigOption._aire_sheet_style = true
            safeWrap(ConfigOption, "init", function(orig_co_init, self, ...)
                if not building_sheet then return orig_co_init(self, ...) end
                -- Valores por defecto de esta hoja, solo durante el montaje (las
                -- tablas de opciones son de KOReader: se dejan como estaban)
                local touched = {}
                for _, opt in ipairs(self.options or {}) do
                    local t = {}
                    if opt.name_font_size == nil then opt.name_font_size = 15; t.nfs = true end
                    touched[opt] = t
                end
                local ok, err = pcall(orig_co_init, self, ...)
                for opt, t in pairs(touched) do
                    if t.nfs then opt.name_font_size = nil end
                end
                if not ok then error(err, 0) end

                local vg = self[1]
                if type(vg) ~= "table" then return end
                local total_w = Screen:getWidth() -- (el ancho de la hoja: ConfigDialog lo cambia)
                local edge = Screen:scaleBySize(MENU_SIDE_INSET)
                local new_vg = VerticalGroup:new{ align = "left" }
                local rows = 0
                local first_opt = self.options and self.options[1]
                local first_is_font_size = first_opt and first_opt.name == "font_size"
                for _, child in ipairs(vg) do
                    if type(child) == "table" and child[1] and getmetatable(child[1]) == RightContainer_ then
                        -- Nombre a la izquierda, con el margen lateral de la hoja
                        local rc = child[1]
                        local btn = rc[1]
                        if btn then
                            local pad_small = Size.padding.small
                            child[1] = LeftContainer_:new{
                                dimen = rc.dimen,
                                HorizontalGroup:new{
                                    align = "center",
                                    HorizontalSpan:new{ width = math.max(0, edge - pad_small) },
                                    btn,
                                },
                            }
                            child:resetLayout()
                        end
                    end
                    if type(child) == "table" and getmetatable(child) == HorizontalGroup then
                        rows = rows + 1
                        if rows > 1 then
                            if rows == 2 and first_is_font_size then
                                -- Pestaña Texto: la fila de tamaños quedaba pegada a la línea
                                table.insert(new_vg, VerticalSpan:new{ width = Screen:scaleBySize(8) })
                            end
                            table.insert(new_vg, HorizontalGroup:new{
                                HorizontalSpan:new{ width = edge },
                                LineWidget:new{
                                    dimen = Geom:new{ w = total_w - 2 * edge, h = Size.line.thin },
                                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                                },
                            })
                        end
                    end
                    table.insert(new_vg, child)
                end
                self[1] = new_vg
                self.dimen = new_vg:getSize()
            end, TAG)
        end

        safeWrap(ConfigDialog, "update", function(orig_cd_update, self)
            -- Alto anterior: KOReader solo repinta lo de detrás si cambia el nº de
            -- filas (en su diseño todas miden igual). Aquí no, así que si la hoja
            -- queda más baja se repinta la zona antigua (si no, su parte de
            -- arriba se quedaba en pantalla, también al cerrar)
            local old_dimen = self.dialog_frame and self.dialog_frame.dimen
                and self.dialog_frame.dimen.h and self.dialog_frame.dimen:copy()
            local sw = Screen:getWidth()
            local inner_w = sw - 2 * Screen:scaleBySize(SHEET_MARGIN) - 2 * Size.border.thin
            -- Las opciones se calculan para el ancho de dentro de la hoja
            building_sheet = true
            local ok = pcall(withWidth, inner_w, orig_cd_update, self)
            building_sheet = false
            if not ok then
                -- Si algo falla con el ancho cambiado, el menú de serie
                logger.warn("Aire/UI: menú inferior sin estilo de hoja (error al calcular)")
                return orig_cd_update(self)
            end
            local ok_s, err = pcall(styleSheet, self)
            if not ok_s then
                logger.warn("Aire/UI: no se pudo dar estilo de hoja al menú inferior:", err)
                return orig_cd_update(self)
            end
            if old_dimen and self.dialog_frame and self.dialog_frame:getSize().h < old_dimen.h then
                local UIManager_ = require("ui/uimanager")
                UIManager_:setDirty("all", function() return "ui", old_dimen end)
            end
        end, TAG)
    end
end
