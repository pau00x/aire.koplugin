--[[
    aire.koplugin/views/power.lua
    Menú de energía: hoja inferior con las opciones que admite el dispositivo.
    También define lightened() (estilo "gris" de lo seleccionado, pruebas).
    Se carga desde main.lua como "mixin" (añade métodos a Aire).
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

return function(Aire, ctx)
    -- Módulos y valores compartidos declarados aquí dentro: así no cuentan
    -- como upvalues de esta función (LuaJIT admite 60).
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local FileManager = require("apps/filemanager/filemanager")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local NetworkMgr = require("ui/network/manager")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Widget = require("ui/widget/widget")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local logger = require("logger")
    local _ = require("gettext")
    local C_ = _.pgettext
    local T = require("ffi/util").template
    local S = ctx.S
    local face = ctx.face
    local tappable = ctx.tappable
    local selStyle = ctx.selStyle
    local lightened -- se define abajo (envoltorio Lightened)
    local SEL_GRAY_LIGHTEN = ctx.SEL_GRAY_LIGHTEN

    ---------------------------------------------------------------------------
    -- Menú de energía: hoja inferior (diseño C)
    --
    --   KOReader 2026.07.2                  Actualizar   <- con KOReader y Aire, pregunta cuál
    --   Aire 0.1.0 (gris)
    --   [ Aire 0.2.0 disponible     (Actualizar) ]   <- solo si hay versión nueva
    --   [  Suspender (negro) ]  [  Apagar (borde)  ]     <- grandes
    --     (Reiniciar)      (KOReader)      (Salir)       <- círculos pequeños
    --
    -- Solo salen las opciones que el dispositivo admite. Tocar fuera la cierra.
    ---------------------------------------------------------------------------

    -- Icono en blanco (para fondos negros): se pinta sobre blanco y se invierte
    local InvertedIcon = Widget:extend{ icon = nil, size = nil }
    function InvertedIcon:init()
        self.iw = IconWidget:new{ icon = self.icon, width = self.size, height = self.size, alpha = true }
    end
    function InvertedIcon:getSize() return Geom:new{ w = self.size, h = self.size } end
    function InvertedIcon:paintTo(bb, x, y)
        bb:paintRect(x, y, self.size, self.size, Blitbuffer.COLOR_WHITE)
        self.iw:paintTo(bb, x, y)
        bb:invertRect(x, y, self.size, self.size)
    end
    function InvertedIcon:free() if self.iw then self.iw:free() end end

    -- Envuelve un widget y, tras pintarlo, lo aclara (negro -> gris oscuro)
    local Lightened = WidgetContainer:extend{ amount = SEL_GRAY_LIGHTEN }
    function Lightened:paintTo(bb, x, y)
        self[1]:paintTo(bb, x, y)
        local s = self[1]:getSize()
        bb:lightenRect(x, y, s.w, s.h, self.amount)
    end
    lightened = function(widget)
        return Lightened:new{ widget }
    end

    -- Hoja común (common/sheet.lua): marco, tocar fuera / Atrás y refresco
    local PowerSheet = package.loaded.aire_sheet.Sheet:extend{
        entries = nil,   -- { sleep, poweroff, reboot, restart, exit, update, update_aire, start_aire_update, choose_update } -> función
        version = nil,
        aire_version = nil,   -- "Aire 0.1.0"
        aire_installed = nil, -- "0.1.0"
        aire_latest = nil,    -- versión nueva ya conocida (tarjeta), o nil
    }

    function PowerSheet:init()
        package.loaded.aire_sheet.Sheet.init(self)
        local st = package.loaded.aire_screen.SHEET -- medidas de hoja (common/screen.lua)
        local btn_gap = S(st.BTN_GAP)
        local border = Size.border.thin
        local inner_w = package.loaded.aire_screen.sheetInnerWidth()
        local E = self.entries
        local BLACK_C, WHITE_C = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE

        local function run(fn)
            return function()
                UIManager:close(self)
                fn()
            end
        end

        local content = VerticalGroup:new{ align = "left" }

        -- Cabecera: KOReader y debajo, en gris, Aire (versiones) a la izquierda;
        -- un solo "Actualizar" a la derecha, que pregunta cuál si hay dos
        local on_update = E.update
        if E.update and E.update_aire and E.choose_update then
            on_update = function() E.choose_update(E.update) end
        elseif E.update_aire then
            on_update = E.update_aire
        end
        local names = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = self.version or "KOReader", face = face(true, 15), fgcolor = BLACK_C, padding = 0 },
        }
        if self.aire_version then
            table.insert(names, VerticalSpan:new{ width = S(2) })
            table.insert(names, TextWidget:new{ text = self.aire_version, face = face(false, 12),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY, padding = 0 })
        end
        local head_h = math.max(S(30), names:getSize().h)
        local head = OverlapGroup:new{
            dimen = Geom:new{ w = inner_w, h = head_h },
            LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = head_h }, names },
        }
        if on_update then
            table.insert(head, RightContainer:new{
                dimen = Geom:new{ w = inner_w, h = head_h },
                tappable(HorizontalGroup:new{
                    align = "center",
                    IconWidget:new{ icon = "aire.update", width = S(18), height = S(18), alpha = true },
                    HorizontalSpan:new{ width = S(6) },
                    TextWidget:new{ text = _("Update"), face = face(false, 13), fgcolor = BLACK_C, padding = 0 },
                }, run(on_update), nil, { h = S(10), v = S(10) }),
            })
        end
        table.insert(content, head)
        table.insert(content, VerticalSpan:new{ width = S(10) })

        -- Tarjeta solo si ya se sabe que hay una versión nueva de Aire
        local latest = self.aire_latest
        if latest and E.start_aire_update then
            local P = package.loaded.aire_pages
            local card_in = P.cardInner(inner_w)
            local pill_w = S(110)
            local text_w = card_in - pill_w - S(8)
            local txt = VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = T(_("Aire %1 available"), latest.version), face = face(true, 14),
                    fgcolor = BLACK_C, max_width = text_w, padding = 0 },
                VerticalSpan:new{ width = S(2) },
                TextWidget:new{ text = T(_("You have version %1"), self.aire_installed or "?"), face = face(false, 12),
                    fgcolor = P.GRAY_DARK, max_width = text_w, padding = 0 },
            }
            local row_h = math.max(txt:getSize().h, S(36))
            table.insert(content, P.card(OverlapGroup:new{
                dimen = Geom:new{ w = card_in, h = row_h },
                LeftContainer:new{ dimen = Geom:new{ w = card_in, h = row_h }, txt },
                RightContainer:new{ dimen = Geom:new{ w = card_in, h = row_h },
                    P.pill(_("Update"), pill_w, run(function() E.start_aire_update(latest) end),
                        { primary = true, font = 13, height = S(36) }) },
            }, inner_w))
            table.insert(content, VerticalSpan:new{ width = S(10) })
        end

        -- Botones grandes: Suspender (negro) y Apagar (borde)
        local big = {}
        if E.sleep then table.insert(big, { icon = "aire.moon", text = C_("aire", "Sleep"), fn = E.sleep, dark = true }) end
        if E.poweroff then table.insert(big, { icon = "aire.power", text = _("Power off"), fn = E.poweroff }) end
        if #big > 0 then
            local gap = btn_gap
            local bw = math.floor((inner_w - (#big - 1) * gap) / #big)
            local bh = S(84)
            local row = HorizontalGroup:new{ align = "center" }
            for k, b in ipairs(big) do
                if k > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                local style = selStyle()
                local filled = b.dark and style ~= "outline"
                local fg = filled and WHITE_C or BLACK_C
                local icon = filled and InvertedIcon:new{ icon = b.icon, size = S(28) }
                    or IconWidget:new{ icon = b.icon, width = S(28), height = S(28), alpha = true }
                local bthick = (b.dark and style == "outline") and Size.border.thick or border
                local box = FrameContainer:new{
                    bordersize = bthick,
                    color = BLACK_C,
                    background = filled and BLACK_C or WHITE_C,
                    radius = S(12),
                    padding = 0,
                    width = bw,
                    height = bh,
                    CenterContainer:new{
                        dimen = Geom:new{ w = bw - 2 * bthick, h = bh - 2 * bthick },
                        VerticalGroup:new{
                            align = "center",
                            icon,
                            VerticalSpan:new{ width = S(6) },
                            TextWidget:new{ text = b.text, face = face(true, 14), fgcolor = fg, padding = 0 },
                        },
                    },
                }
                if filled and style == "gray" then box = lightened(box) end
                table.insert(row, tappable(box, run(b.fn)))
            end
            table.insert(content, row)
            table.insert(content, VerticalSpan:new{ width = S(16) })
        end

        -- Botones pequeños: círculo con icono y etiqueta debajo
        local small = {}
        if E.reboot then table.insert(small, { icon = "aire.reboot", text = _("Restart"), fn = E.reboot }) end
        if E.restart then table.insert(small, { icon = "aire.restart", text = _("KOReader"), fn = E.restart }) end
        if E.exit then table.insert(small, { icon = "aire.exit", text = _("Exit"), fn = E.exit }) end
        if #small > 0 then
            local cw = math.floor(inner_w / #small)
            local d = S(48)
            local row = HorizontalGroup:new{ align = "top" }
            for _i, b in ipairs(small) do
                local circle = FrameContainer:new{
                    bordersize = border,
                    color = BLACK_C,
                    radius = math.floor(d / 2),
                    padding = 0,
                    width = d,
                    height = d,
                    CenterContainer:new{
                        dimen = Geom:new{ w = d - 2 * border, h = d - 2 * border },
                        IconWidget:new{ icon = b.icon, width = S(22), height = S(22), alpha = true },
                    },
                }
                local item = VerticalGroup:new{
                    align = "center",
                    circle,
                    VerticalSpan:new{ width = S(5) },
                    TextWidget:new{ text = b.text, face = face(false, 12), fgcolor = BLACK_C, padding = 0 },
                }
                -- Toda la columna responde, no solo el círculo
                table.insert(row, tappable(CenterContainer:new{
                    dimen = Geom:new{ w = cw, h = item:getSize().h },
                    item,
                }, run(b.fn), nil, { h = 0, v = S(6) }))
            end
            table.insert(content, row)
        end

        self:setContent(content)
    end

    local function showPowerDialog()
        local ok, exit = pcall(dofile, "frontend/ui/elements/common_exit_menu_table.lua")
        if not ok or type(exit) ~= "table" then
            logger.warn("Aire: no se pudo leer common_exit_menu_table:", exit)
            return
        end
        local function cb(entry) return entry and entry.callback or nil end
        local entries = {
            sleep = cb(exit.sleep),
            poweroff = cb(exit.poweroff),
            reboot = cb(exit.reboot),
            restart = cb(exit.restart_koreader),
            exit = cb(exit.exit or exit.exit_menu),
        }
        if Device:hasOTAUpdates() then
            entries.update = function()
                NetworkMgr:runWhenOnline(function()
                    require("ui/otamanager"):fetchAndProcessUpdate()
                end)
            end
        end
        local ok_v, rev = pcall(function() return require("version"):getCurrentRevision() end)
        rev = ok_v and type(rev) == "string" and rev:gsub("^v", "") or nil
        -- Aire (views/update.lua): su línea en la cabecera y, si ya se sabe que
        -- hay una versión nueva, la tarjeta
        local upd = ctx.update
        local aire_version, aire_installed, aire_latest
        if upd then
            aire_installed = upd.installedVersion()
            aire_version = "Aire " .. aire_installed
            entries.update_aire = function() upd.check(true) end
            entries.start_aire_update = upd.start
            entries.choose_update = upd.showChooser
            aire_latest = upd.available()
        end
        local sheet = PowerSheet:new{
            entries = entries,
            version = rev and rev ~= "" and ("KOReader " .. rev) or "KOReader",
            aire_version = aire_version,
            aire_installed = aire_installed,
            aire_latest = aire_latest,
        }
        UIManager:show(sheet, "ui")
    end
    -- Para el botón de encendido del menú superior (styles/ui.lua): en el lector
    -- el FileManager está cerrado y no hay instancia de Aire a la que pedírselo
    FileManager.aire_showPowerSheet = showPowerDialog

    -- Para devtools.lua (galería de hojas)
    function Aire:showPowerSheet() showPowerDialog() end

    -- Para los demás mixins
    ctx.showPowerDialog = showPowerDialog
    ctx.lightened = lightened
end
