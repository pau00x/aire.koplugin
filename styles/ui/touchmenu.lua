--[[
    aire.koplugin/styles/ui/touchmenu.lua
    Menú superior (TouchMenu): submenús con chevron y valor en gris, pestañas, pie con hora y batería, separadores suaves.
    Lo carga styles/ui/init.lua en su orden (recibe la tabla de styles/ui/base.lua).
--]]

local B = ...
local liveRect = B.liveRect
local getUpValue = B.getUpValue
local TouchMenuItem = B.TouchMenuItem
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TouchMenu = require("ui/widget/touchmenu")
local logger = require("logger")
local userpatch = require("userpatch")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

-- stylua: ignore start
local SUBMENU_CHEVRON           = true   -- activar "Nombre        valor ›" en TouchMenu
local SHOW_VALUE_ON_RIGHT       = true   -- false: solo mover el chevron, sin separar el valor
local MAX_VALUE_CHARS           = 24     -- valores más largos no se separan
local CHEVRON_SCALE             = 0.55   -- tamaño del chevron respecto al alto del texto
local MENU_SIDE_INSET = B.MENU_SIDE_INSET
local CLEAN_TOUCH_MENU          = true   -- pie "14:32 · 85%" en gris y separadores suaves
local SHEET_MARGIN = B.SHEET_MARGIN
local SHEET_RADIUS = B.SHEET_RADIUS
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"
-- stylua: ignore end

--===========================================================================
-- 3) SUBMENÚS CON CHEVRON FINO Y VALOR EN GRIS A LA DERECHA
--===========================================================================
if SUBMENU_CHEVRON then
    if not TouchMenuItem then logger.warn("Aire/UI: no se encontró TouchMenuItem (chevron desactivado)") end
    if TouchMenuItem and not TouchMenuItem._submenu_chevron then
        TouchMenuItem._submenu_chevron = true
        local orig_getMenuText, getMenuText_idx = getUpValue(TouchMenuItem.init, "getMenuText")
        if orig_getMenuText then
            local split_values = setmetatable({}, { __mode = "k" })
            local in_item_init = false

            local function hasSubmenu(item)
                return item.sub_item_table ~= nil or item.sub_item_table_func ~= nil
            end

            local function getMenuTextNoArrow(item)
                if not hasSubmenu(item) then
                    return orig_getMenuText(item)
                end
                local text = item.text_func and item.text_func() or item.text or ""
                if not in_item_init then
                    return text
                end
                split_values[item] = nil
                -- Texto junto a la flecha SOLO si el submenú es un selector (opciones
                -- de radio) y hay una elegida: entonces se ve cuál. En el resto,
                -- todo el texto a la izquierda.
                local selected
                if type(item.sub_item_table) == "table" then
                    for _i, sub in ipairs(item.sub_item_table) do
                        if type(sub) == "table" and sub.radio then
                            local ok_c, on = true, sub.checked
                            if sub.checked_func then ok_c, on = pcall(sub.checked_func) end
                            if ok_c and on then
                                selected = sub.text_func and sub.text_func() or sub.text
                                break
                            end
                        end
                    end
                end
                if SHOW_VALUE_ON_RIGHT and selected then
                    local name, value = text:match("^(.-):%s+(.+)$")
                    if not name then name, value = text, selected end
                    if name and name ~= "" and value then
                        local chars = util.splitToChars(value)
                        if chars and #chars <= MAX_VALUE_CHARS then
                            split_values[item] = value
                            return name
                        end
                    end
                end
                return text
            end
            userpatch.replaceUpValue(TouchMenuItem.init, getMenuText_idx, getMenuTextNoArrow)

            local function findTextWidget(menu_item)
                local hg = menu_item.item_frame and menu_item.item_frame[1]
                if not hg then return nil end
                for _, w in ipairs(hg) do
                    if getmetatable(w) == TextWidget then return w end
                end
            end

            safeWrap(TouchMenuItem, "init", function(orig_tmi_init, self)
                in_item_init = true
                local ok, err = pcall(orig_tmi_init, self)
                in_item_init = false
                if not ok then error(err) end
                if not hasSubmenu(self.item) then return end

                local text_widget = findTextWidget(self)
                local face = (text_widget and text_widget.face) or self.face
                local line_h = text_widget and text_widget:getSize().h
                if not line_h or line_h <= 0 then
                    local probe = TextWidget:new{ text = "M", face = face }
                    line_h = probe:getSize().h
                    probe:free()
                end

                local chevron_size = math.max(8, math.floor(line_h * CHEVRON_SCALE))
                self._chevron = IconWidget:new{
                    icon = "chevron.right",
                    rotation_angle = BD.mirroredUILayout() and 180 or nil,
                    width = chevron_size,
                    height = chevron_size,
                    alpha = true,
                    dim = (self.isEnabled and not self:isEnabled()) or nil,
                }

                local value = split_values[self.item]
                if value then
                    self._value_widget = TextWidget:new{
                        text = value,
                        face = face,
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                        max_width = math.floor(self.dimen.w * 0.35),
                    }
                    if self._value_widget:isTruncated() then
                        self.text_truncated = true
                    end
                end

                local gap = Size.padding.default
                local edge = Screen:scaleBySize(MENU_SIDE_INSET)
                local reserved = chevron_size + gap + edge
                    + (self._value_widget and (self._value_widget:getSize().w + gap) or 0)
                if text_widget then
                    -- margen izquierdo + ancho de la casilla (checkmark_tap_width
                    -- = casilla + 2 × padding.default)
                    local left_used = edge + math.max(0, (self.checkmark_tap_width or 0) - 2 * Size.padding.default)
                    local available = self.dimen.w - left_used - reserved
                    if text_widget:getSize().w > available and available > 0 then
                        text_widget:setMaxWidth(available)
                        if text_widget:isTruncated() then
                            self.text_truncated = true
                        end
                    end
                end
            end, TAG)

            safeWrap(TouchMenuItem, "paintTo", function(orig_tmi_paintTo, self, bb, x, y)
                orig_tmi_paintTo(self, bb, x, y)
                if not self._chevron then return end
                local w, h = self.dimen.w, self.dimen.h
                local gap = Size.padding.default
                local edge = Screen:scaleBySize(MENU_SIDE_INSET)
                local cs = self._chevron:getSize()
                local mirrored = BD.mirroredUILayout()

                local cx = mirrored and (x + edge) or (x + w - edge - cs.w)
                self._chevron:paintTo(bb, cx, y + math.floor((h - cs.h) / 2))

                if self._value_widget then
                    local vs = self._value_widget:getSize()
                    local vx = mirrored and (cx + cs.w + gap) or (cx - gap - vs.w)
                    self._value_widget:paintTo(bb, vx, y + math.floor((h - vs.h) / 2))
                end
            end, TAG)

            safeWrap(TouchMenuItem, "free", function(orig_tmi_free, self, ...)
                if self._value_widget then self._value_widget:free(); self._value_widget = nil end
                if self._chevron then self._chevron:free(); self._chevron = nil end
                if orig_tmi_free then return orig_tmi_free(self, ...) end
            end, TAG)
        end
    end
end

--===========================================================================
-- 7) MENÚ DESPLEGABLE SUPERIOR (TOUCHMENU) MÁS LIMPIO
--===========================================================================
if CLEAN_TOUCH_MENU and not TouchMenu._clean_style_patched then
    TouchMenu._clean_style_patched = true

    -- Texto de los menús como el resto del plugin (filas de las hojas: cfont 15,
    -- alto 44; textos secundarios: 13). Se usa el TouchMenuItem capturado al
    -- principio del archivo: volver a buscarlo aquí en TouchMenu.updateItems
    -- daba nil (la sección 2.3 ya la ha envuelto) y el menú se quedaba con la
    -- letra de KOReader (smallinfofont 22), mucho más grande que lo demás.
    if TouchMenuItem then
        TouchMenuItem.face = Font:getFace("cfont", 15)
        -- Margen lateral de cada fila: la casilla (o el texto) empieza a
        -- MENU_SIDE_INSET del borde, igual que los separadores, la flecha del
        -- pie y el botón de encendido. KOReader usaba padding.default (5).
        if not TouchMenuItem._aire_side_inset then
            TouchMenuItem._aire_side_inset = true
            safeWrap(TouchMenuItem, "init", function(orig_tmi_init_inset, self)
                orig_tmi_init_inset(self)
                local f = self.item_frame
                if not (f and self.dimen) then return end
                local edge = Screen:scaleBySize(MENU_SIDE_INSET)
                f.padding_left = edge
                f.padding_right = edge
                -- Sangría solo en las filas con casilla: KOReader reserva el hueco
                -- de la casilla en TODAS las filas, así que los textos sin casilla
                -- quedaban metidos hacia dentro. Sin casilla (no hay checked_func)
                -- se quita el hueco y el texto empieza en el margen.
                local hg = f[1]
                local mark_w = 0
                if hg and hg[1] then
                    if self.item.checked_func then
                        mark_w = hg[1]:getSize().w
                    else
                        hg[1] = HorizontalSpan:new{ width = 0 }
                        hg:resetLayout()
                    end
                end
                -- Ancho del texto: hasta el margen derecho, o hasta el valor gris
                -- y la flecha › si los hay (los pinta la sección 3)
                local right = edge
                if self._chevron then
                    right = right + self._chevron:getSize().w + Size.padding.default
                    if self._value_widget then
                        right = right + self._value_widget:getSize().w + Size.padding.default
                    end
                end
                local max_w = self.dimen.w - edge - mark_w - right
                if max_w > 0 then
                    for _, w in ipairs(hg or {}) do
                        if getmetatable(w) == TextWidget then
                            w:setMaxWidth(max_w)
                            self.text_truncated = w:isTruncated() or nil
                        end
                    end
                end
            end, TAG)
        end
    else
        logger.warn("Aire/UI: no se encontró TouchMenuItem (tamaño de letra del menú sin cambiar)")
    end

    safeWrap(TouchMenu, "init", function(orig_TouchMenu_init, self)
        local m = Screen:scaleBySize(SHEET_MARGIN)
        local r = Screen:scaleBySize(SHEET_RADIUS)
        local bw = Size.border.thin
        self.padding = 0
        self.bordersize = bw
        self.width = Screen:getWidth() - 2 * m - 2 * bw
        self.split_color = Blitbuffer.COLOR_LIGHT_GRAY
        self.split_height = Size.line.thin
        self.item_height = Screen:scaleBySize(44) -- igual que las filas de las hojas
        self.fface = Font:getFace("cfont", 13)    -- pie (hora · batería), como los textos grises
        orig_TouchMenu_init(self)
        if self.bar then
            if self.bar[1] then
                self.bar[1].background = nil
                self.bar[1].bordersize = 0
            end
            if self.bar.bar_sep then
                self.bar.bar_sep.dimen.h = Size.line.thin
                self.bar.bar_sep.background = Blitbuffer.COLOR_LIGHT_GRAY
                self.bar.bar_sep.empty_segments = nil
            end
            if self.bar.icon_seps then
                for _, sep in ipairs(self.bar.icon_seps) do
                    sep.paintTo = function() end
                end
            end
            if self.bar.icon_widgets and self.bar.bar_icon_group then
                -- Pestañas: KOReader reparte los iconos con separadores y un hueco
                -- elástico antes del último, calculados para su tamaño de botón.
                -- Aquí se rehace la fila entera: N casillas iguales, cada una con
                -- su píldora centrada, y se ajustan la zona táctil (dimen) y el
                -- destello de IconButton (padding_left / padding_top) a la casilla.
                local Widget = require("ui/widget/widget")
                local bar_ref = self.bar
                local tabs = self.tab_item_table or {}
                local n = #bar_ref.icon_widgets
                local side = Screen:scaleBySize(8)
                local avail = (bar_ref.width or self.width) - 2 * side
                local slot_w = math.floor(avail / math.max(1, n))
                local extra = avail - slot_w * n
                local icon_sz = Screen:scaleBySize(24)
                local pill_w = math.min(Screen:scaleBySize(56), slot_w - Screen:scaleBySize(4))
                local pill_h = Screen:scaleBySize(38)
                local pill_r = Screen:scaleBySize(10)
                local vpad = Screen:scaleBySize(6)
                local slot_h = pill_h + 2 * vpad
                -- Los reemplazos generales de appbar.* viven en core/icons.lua.
                -- Aquí solo queda la excepción contextual del menú superior:
                --   appbar.filebrowser con remember == false (volver a la biblioteca):
                --   icono de Librería si el libro se abrió desde la Pantalla de inicio
                --   (modo Librería) y de carpeta si se abrió desde el explorador.
                local back_icon = "aire.folder"
                local aire_cfg = G_reader_settings:readSetting("aire")
                if type(aire_cfg) == "table" and aire_cfg.enabled ~= false
                        and (aire_cfg.mode or "library") == "library" then
                    back_icon = "aire.library"
                end

                local group = bar_ref.bar_icon_group
                for i = #group, 1, -1 do group[i] = nil end -- sin free: los IconButton se reutilizan
                table.insert(group, HorizontalSpan:new{ width = side + math.floor(extra / 2) })
                for idx, ib in ipairs(bar_ref.icon_widgets) do
                    local tab = tabs[idx]
                    local icon_name = (ib.image and ib.image.icon) or ib.icon
                    if icon_name == "appbar.filebrowser" and tab and tab.remember == false then
                        icon_name = back_icon
                    end
                    if ib.image and ib.image.free then ib.image:free() end
                    local iw = IconWidget:new{ icon = icon_name, width = icon_sz, height = icon_sz, alpha = true }
                    ib.image = iw
                    local icon_holder = Widget:new{
                        dimen = Geom:new{ w = icon_sz, h = icon_sz },
                        getSize = function() return Geom:new{ w = icon_sz, h = icon_sz } end,
                        paintTo = function(_self, bb, x, y)
                            if ib._aire_active then
                                bb:paintRect(x, y, icon_sz, icon_sz, Blitbuffer.COLOR_WHITE)
                                iw:paintTo(bb, x, y)
                                bb:invertRect(x, y, icon_sz, icon_sz)
                            else
                                iw:paintTo(bb, x, y)
                            end
                        end,
                        free = function() iw:free() end,
                    }
                    local pill_box = FrameContainer:new{
                        width = pill_w,
                        height = pill_h,
                        bordersize = 0,
                        padding = 0,
                        radius = pill_r,
                        background = Blitbuffer.COLOR_WHITE,
                        CenterContainer:new{
                            dimen = Geom:new{ w = pill_w, h = pill_h },
                            icon_holder,
                        },
                    }
                    ib._aire_pill_box = pill_box
                    ib[1] = CenterContainer:new{
                        dimen = Geom:new{ w = slot_w, h = slot_h },
                        pill_box,
                    }
                    -- Destello al tocar: IconButton invierte self.image en
                    -- (dimen.x + padding_left, dimen.y + padding_top)
                    ib.padding_left = math.floor((slot_w - pill_w) / 2) + math.floor((pill_w - icon_sz) / 2)
                    ib.padding_right = slot_w - icon_sz - ib.padding_left
                    ib.padding_top = math.floor((slot_h - pill_h) / 2) + math.floor((pill_h - icon_sz) / 2)
                    ib.padding_bottom = slot_h - icon_sz - ib.padding_top
                    -- Zona táctil = casilla entera. Es la MISMA tabla que el rango
                    -- de sus gestos, así que se cambia en el sitio (no se sustituye).
                    if ib.dimen then
                        ib.dimen.w, ib.dimen.h = slot_w, slot_h
                    else
                        ib.dimen = Geom:new{ x = 0, y = 0, w = slot_w, h = slot_h }
                    end
                    table.insert(group, ib)
                end
                group:resetLayout()
                -- Línea bajo las pestañas: con el mismo margen lateral que los
                -- separadores de las filas (KOReader la dibuja de borde a borde)
                local vg_bar = bar_ref[1] and bar_ref[1][1]
                local sep = bar_ref.bar_sep
                if vg_bar and sep and sep.dimen and vg_bar[2] == sep then
                    local edge = Screen:scaleBySize(MENU_SIDE_INSET)
                    local total_w = bar_ref.width or self.width
                    sep.dimen.w = total_w - 2 * edge
                    vg_bar[2] = HorizontalGroup:new{
                        HorizontalSpan:new{ width = edge },
                        sep,
                        HorizontalSpan:new{ width = edge },
                    }
                end
                if vg_bar and vg_bar.resetLayout then
                    vg_bar:resetLayout()
                end
                bar_ref.height = slot_h
                if bar_ref.dimen then bar_ref.dimen.h = slot_h end

                local function styleTabs(active_idx)
                    if bar_ref.bar_sep then bar_ref.bar_sep.empty_segments = nil end
                    for idx, ib in ipairs(bar_ref.icon_widgets) do
                        local act = (idx == active_idx)
                        ib._aire_active = act
                        if ib._aire_pill_box then
                            ib._aire_pill_box.background = act and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
                        end
                    end
                end
                for idx, ib in ipairs(bar_ref.icon_widgets) do
                    local orig_cb = ib.callback
                    local tab = tabs[idx]
                    ib.callback = function()
                        if orig_cb then orig_cb() end
                        -- Las pestañas que solo hacen algo (volver a la biblioteca)
                        -- no se marcan: KOReader tampoco las recuerda
                        if not (tab and tab.remember == false) then styleTabs(idx) end
                    end
                end
                styleTabs(self.cur_tab or self.last_index or 1)
            end
        end
        if self.menu_frame then
            self.menu_frame.bordersize = bw
            self.menu_frame.color = Blitbuffer.COLOR_BLACK
            self.menu_frame.background = Blitbuffer.COLOR_WHITE
            self.menu_frame.radius = r
            self.menu_frame.padding = 0
            self.menu_frame.padding_top = Screen:scaleBySize(6)
            self.menu_frame.padding_bottom = Screen:scaleBySize(6)
        end
        if self.device_info then
            local pwr_sz = Screen:scaleBySize(28)
            local pwr_btn = FrameContainer:new{
                width = pwr_sz,
                height = pwr_sz,
                bordersize = Size.border.thin,
                color = Blitbuffer.COLOR_BLACK,
                radius = Screen:scaleBySize(7),
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = pwr_sz - 2 * Size.border.thin, h = pwr_sz - 2 * Size.border.thin },
                    IconWidget:new{ icon = "aire.power", width = Screen:scaleBySize(18), height = Screen:scaleBySize(18), alpha = true },
                },
            }
            local InputContainer = require("ui/widget/container/inputcontainer")
            local GestureRange = require("ui/gesturerange")
            local pwr_ic = InputContainer:new{ pwr_btn }
            pwr_ic.ges_events = {
                AireTap = { GestureRange:new{
                    ges = "tap",
                    range = function()
                        local d = pwr_ic.dimen
                        if not d then return Geom:new{ x = 0, y = 0, w = 0, h = 0 } end
                        local p = Screen:scaleBySize(6)
                        return Geom:new{ x = d.x - p, y = d.y - p, w = d.w + 2 * p, h = d.h + 2 * p }
                    end,
                } },
            }
            pwr_ic.onAireTap = function()
                self:closeMenu()
                local UIManager = require("ui/uimanager")
                UIManager:nextTick(function()
                    -- La hoja de encendido la exporta main.lua en el módulo
                    -- FileManager, así funciona también dentro del lector (antes se
                    -- mandaba un evento "ShowPowerDialog" que KOReader no tiene)
                    local FM = require("apps/filemanager/filemanager")
                    if FM.aire_showPowerSheet then
                        local ok, err = pcall(FM.aire_showPowerSheet)
                        if not ok then logger.warn("Aire/UI: error en el menú de encendido:", err) end
                    else
                        logger.warn("Aire/UI: menú de encendido no disponible")
                    end
                end)
                return true
            end
            table.insert(self.device_info, pwr_ic)
            table.insert(self.device_info, HorizontalSpan:new{ width = Screen:scaleBySize(MENU_SIDE_INSET) }) -- margen derecho, igual que las filas
            if self.device_info.resetLayout then self.device_info:resetLayout() end
        end
        if self.footer and self.footer[1] and self.footer[1][1] and self.footer[1][1].setIcon then
            -- Flecha ↑ del pie al mismo margen que las filas (KOReader la separaba
            -- un 3,3 % del ancho). setIcon vuelve a montar el botón con este padding.
            -- Tamaño 24 como los iconos de las pestañas (KOReader la pinta a 40 y
            -- con el trazo del SVG quedaba mucho más gruesa); el relleno vertical
            -- mantiene el alto y la zona táctil del botón original.
            local up = self.footer[1][1]
            local up_sz = Screen:scaleBySize(24)
            local up_vpad = math.max(0, math.floor(((up.height or up_sz) - up_sz) / 2))
            up.width, up.height = up_sz, up_sz
            up.padding_left = Screen:scaleBySize(MENU_SIDE_INSET)
            up.padding_right = Screen:scaleBySize(MENU_SIDE_INSET)
            up.padding_top, up.padding_bottom = up_vpad, up_vpad
            up.icon = nil -- para que setIcon vuelva a montar el botón con el tamaño nuevo
            up:setIcon("aire.chevron.up")
        end
        -- Separadores entre filas: mismo margen lateral que el contenido
        local sl = self.split_line
        if sl and sl[1] and sl[2] and sl[3] and sl[2].dimen and self.item_width then
            local edge = Screen:scaleBySize(MENU_SIDE_INSET)
            sl[1].width = edge
            sl[3].width = edge
            sl[2].dimen.w = self.item_width - 2 * edge
            if sl.resetLayout then sl:resetLayout() end
        end
        if self[1] then
            self[1] = FrameContainer:new{
                bordersize = 0,
                padding = 0,
                padding_top = m,
                self[1],
            }
        end
    end, TAG)

    local datetime = require("datetime")
    local function cleanTimeInfoText()
        local txt = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
        if Device:hasBattery() then
            txt = BD.wrap(txt) .. " · " .. BD.wrap(Device:getPowerDevice():getCapacity() .. "%")
        end
        return txt
    end

    safeWrap(TouchMenu, "updateItems", function(prev_TouchMenu_updateItems, self, target_page, target_item_id)
        prev_TouchMenu_updateItems(self, target_page, target_item_id)
        if self.dimen then
            self.dimen.w = Screen:getWidth()
            self.dimen.h = (self[1] and self[1]:getSize().h) or self.dimen.h
        end
        local ti = self.time_info
        if ti and ti.text then
            -- Rehacer el texto "14:32 · 85%" (sin "⌁" ni icono de batería) en gris y más pequeño
            local face_changed = ti.text_font_size ~= 13 or ti.text_font_face ~= "cfont"
            ti.text_font_face = "cfont"
            ti.text_font_size = 13
            local ok, txt = pcall(cleanTimeInfoText)
            if ok and (txt ~= ti.text or face_changed) then
                ti:setText(txt)
            elseif face_changed then
                ti:setText(ti.text)
            end
            if ti.label_widget then
                ti.label_widget.fgcolor = Blitbuffer.COLOR_DARK_GRAY
            end
            if face_changed and self.device_info and self.device_info.resetLayout then
                self.device_info:resetLayout()
            end
        end
    end, TAG)

    safeWrap(TouchMenu, "onTapCloseAllMenus", function(orig_TouchMenu_onTapClose, self, arg, ges_ev)
        local d = (self.menu_frame and self.menu_frame.dimen and liveRect(self.menu_frame)) or self.dimen
        if ges_ev and ges_ev.pos and d and ges_ev.pos:notIntersectWith(d) then
            self:closeMenu()
            return true
        end
        if orig_TouchMenu_onTapClose then
            return orig_TouchMenu_onTapClose(self, arg, ges_ev)
        end
    end, TAG)
end
