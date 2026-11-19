--[[
    aire.koplugin/views/update.lua
    Actualizaciones de Aire: hojas (versión nueva, descargando, instalada),
    comprobación semanal y entrada "Actualizar Aire" del menú superior.
    La red y la instalación están en common/update.lua.
    Se carga desde main.lua como "mixin"; deja en ctx.update lo que usan
    menu.lua (entrada del menú) y views/power.lua (línea de Aire y tarjeta).
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

return function(Aire, ctx)
    -- Módulos declarados aquí dentro: así no cuentan como upvalues (LuaJIT admite 60)
    local Device = require("device")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local InfoMessage = require("ui/widget/infomessage")
    local NetworkMgr = require("ui/network/manager")
    local Size = require("ui/size")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local logger = require("logger")
    local _ = require("gettext")
    local T = require("ffi/util").template
    local S = ctx.S
    local face = ctx.face
    local config = ctx.config
    local saveConfig = ctx.saveConfig
    local PLUGIN_DIR = ctx.PLUGIN_DIR

    local WEEK = 7 * 24 * 3600

    -- common/update.lua, cargado una vez (la primera vez que hace falta)
    local Upd_cache
    local function getUpd()
        if Upd_cache then return Upd_cache end
        local ok, Upd = pcall(dofile, PLUGIN_DIR .. "/common/update.lua")
        if ok and type(Upd) == "table" then
            Upd_cache = Upd
            return Upd
        end
        logger.warn("Aire/Update: no se pudo cargar common/update.lua:", Upd)
    end
    local function getP() return package.loaded.aire_pages end

    -- Versión instalada al arrancar (la que está corriendo, aunque ya se haya
    -- instalado otra en disco y falte reiniciar)
    local running_version
    local fake_version -- pruebas (Avanzado → Pruebas): simular una versión antigua
    local function installedVersion()
        if fake_version then return fake_version end
        if not running_version then
            local Upd = getUpd()
            running_version = Upd and Upd.installedVersion() or "0"
        end
        return running_version
    end
    local installed_pending -- versión instalada en esta sesión (falta reiniciar)

    -- Versión nueva ya conocida (de la última comprobación), si sigue siendo nueva
    local function available()
        local l = config.update_latest
        if type(l) ~= "table" or type(l.version) ~= "string" then return nil end
        if installed_pending == l.version then return nil end
        local Upd = getUpd()
        if not (Upd and Upd.isNewer(l.version, installedVersion())) then return nil end
        if not config.update_beta and l.prerelease then return nil end
        return l
    end

    ---------------------------------------------------------------------------
    -- Hoja inferior común (como la de los marcadores)
    ---------------------------------------------------------------------------
    -- Hoja común (common/sheet.lua): marco, tocar fuera / Atrás (si dismissable)
    -- y refresco al abrir y cerrar
    local UpdateSheet = package.loaded.aire_sheet.Sheet

    local function sheetGeometry()
        local style = package.loaded.aire_screen.SHEET
        local sheet_w = package.loaded.aire_screen.sheetWidth()
        local pad = S(style.PAD)
        return style, sheet_w, pad, sheet_w - 2 * pad - 2 * Size.border.thin
    end

    local function newSheet(content, opts)
        opts = opts or {}
        opts.content = content
        return UpdateSheet:new(opts)
    end

    -- Fila de píldoras del mismo ancho; la última puede ser la principal (negra)
    -- Botones y título comunes de las hojas (common/sheet.lua, SHEET)
    local function pillRow(buttons, in_w)
        return package.loaded.aire_sheet.buttons(buttons, in_w)
    end

    local function title(text, in_w)
        return TextWidget:new{ text = text, face = face(true, package.loaded.aire_screen.SHEET.TITLE_FONT),
            fgcolor = getP().BLACK, max_width = in_w, padding = 0 }
    end

    local function formatDate(iso)
        local y, m, d = tostring(iso or ""):match("^(%d+)%-(%d+)%-(%d+)")
        if not y then return nil end
        local t = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
        local ok, s = pcall(function() return require("datetime").secondsToDate(t, true) end)
        return ok and s or iso
    end

    local function friendlySize(bytes)
        local ok, s = pcall(function() return require("util").getFriendlySize(bytes) end)
        return ok and s or tostring(bytes)
    end

    local function restartKOReader()
        if Device:canRestart() then
            UIManager:broadcastEvent(require("ui/event"):new("Restart"))
        end
    end

    local runUpdate -- se define abajo

    ---------------------------------------------------------------------------
    -- 4 · Instalada: ofrecer reinicio
    ---------------------------------------------------------------------------
    local function showInstalled(info)
        local P = getP()
        local in_w = select(4, sheetGeometry())
        local sheet
        local buttons = {
            { text = _("Later"), callback = function() UIManager:close(sheet) end },
        }
        if Device:canRestart() then
            table.insert(buttons, { text = _("Restart now"), primary = true, callback = function()
                UIManager:close(sheet)
                restartKOReader()
            end })
        end
        sheet = newSheet(VerticalGroup:new{
            align = "left",
            title(T(_("Aire %1 installed"), info.version), in_w),
            VerticalSpan:new{ width = S(6) },
            P.text(Device:canRestart()
                and _("It will be used after restarting KOReader. Your settings are kept.")
                or _("Restart KOReader to use it. Your settings are kept."),
                in_w, { size = 13, color = P.GRAY_DARK }),
            VerticalSpan:new{ width = S(14) },
            pillRow(buttons, in_w),
        })
        UIManager:show(sheet)
    end

    ---------------------------------------------------------------------------
    -- 3 · Descargando e instalando (la descarga bloquea KOReader unos segundos:
    -- la barra se repinta a mano desde la propia descarga)
    ---------------------------------------------------------------------------
    local function showProgress(info)
        local P = getP()
        local in_w = select(4, sheetGeometry())
        local bar = P.bar(in_w, 0, S(8))
        local label = TextWidget:new{ text = _("Downloading…"), face = face(false, 13),
            fgcolor = P.GRAY_DARK, max_width = in_w, padding = 0 }
        local sheet = newSheet(VerticalGroup:new{
            align = "left",
            title(_("Updating Aire"), in_w),
            VerticalSpan:new{ width = S(12) },
            bar,
            VerticalSpan:new{ width = S(8) },
            label,
        }, { dismissable = false })
        UIManager:show(sheet)
        UIManager:forceRePaint()
        local last = -1
        local function set(pct, text)
            bar.pct = pct
            label:setText(text)
            UIManager:setDirty(sheet, function() return "fast", sheet.frame.dimen end)
            UIManager:forceRePaint()
        end
        return sheet, function(got, total)
            local pct = (total and total > 0) and math.min(1, got / total) or 0
            local step = math.floor(pct * 10)
            if step == last then return end
            last = step
            set(pct, T(_("Downloading… %1 of %2"), friendlySize(got), friendlySize(total)))
        end, function(text) set(1, text) end
    end

    runUpdate = function(info)
        NetworkMgr:runWhenOnline(function()
            local Upd = getUpd()
            if not Upd then return end
            local sheet, on_progress, set_label = showProgress(info)
            local path, err = Upd.download(info, on_progress)
            local ok
            if path then
                set_label(_("Installing…"))
                ok, err = Upd.install(path, info)
            end
            UIManager:close(sheet)
            if ok then
                installed_pending = info.version
                config.update_latest = nil
                config.update_skipped = nil
                saveConfig()
                showInstalled(info)
            else
                Upd.warn("no se pudo instalar", info.version, err)
                UIManager:show(InfoMessage:new{
                    text = T(_("Could not install the update. Aire %1 is still installed."), installedVersion()),
                })
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Todas las novedades: pantalla de Aire (common/pages.lua) con el texto de
    -- la release ya sin Markdown: títulos de sección en gris, cada novedad con
    -- su nombre en negrita, páginas con puntos. Al cerrarla, on_close.
    ---------------------------------------------------------------------------
    local function showNotes(info, on_close)
        local P = getP()
        local Upd = getUpd()
        if not (P and Upd) then return end
        local blocks = Upd.parseNotes(info.notes)
        P.Page:new{
            title = T(_("Aire %1"), info.version),
            subtitle = formatDate(info.date),
            close_callback = on_close,
            build = function(_page, w, h)
                local widgets = {}
                local function add(widget, gap)
                    widget._aire_gap = gap
                    table.insert(widgets, widget)
                end
                for i, b in ipairs(blocks) do
                    if b.kind == "heading" then
                        add(P.label(b.text, w), i > 1 and S(18) or 0)
                    elseif b.kind == "item" then
                        local indent = b.sub and S(16) or 0
                        local bullet = TextWidget:new{ text = b.sub and "◦" or "•", face = face(true, 14),
                            fgcolor = P.BLACK, padding = 0 }
                        local bullet_gap = S(8)
                        local tw = w - indent - bullet:getSize().w - bullet_gap
                        local vg = VerticalGroup:new{ align = "left" }
                        if b.lead then
                            table.insert(vg, P.text(b.lead, tw, { bold = true, size = 14 }))
                            if b.text ~= "" then
                                table.insert(vg, VerticalSpan:new{ width = S(2) })
                                table.insert(vg, P.text(b.text, tw, { size = 13, color = P.GRAY_DARK }))
                            end
                        else
                            table.insert(vg, P.text(b.text, tw, { size = 14 }))
                        end
                        add(HorizontalGroup:new{
                            align = "top",
                            HorizontalSpan:new{ width = indent },
                            bullet,
                            HorizontalSpan:new{ width = bullet_gap },
                            vg,
                        }, S(b.sub and 4 or 10))
                    else
                        add(P.text(b.text, w, { size = 14 }), S(10))
                    end
                end
                if #widgets == 0 then
                    add(P.text("—", w, { size = 14, color = P.GRAY_DARK }), 0)
                end
                widgets[1]._aire_gap = 0
                return P.packPages(widgets, h)
            end,
        }:show()
    end

    ---------------------------------------------------------------------------
    -- 2 · Hay una versión nueva
    ---------------------------------------------------------------------------
    local function showNewVersion(info)
        local P = getP()
        local Upd = getUpd()
        if not Upd then return end
        local in_w = select(4, sheetGeometry())
        local sheet
        local meta = { T(_("Aire %1"), info.version) }
        if info.prerelease then table.insert(meta, _("beta")) end
        local date = formatDate(info.date)
        if date then table.insert(meta, date) end
        if info.size and info.size > 0 then table.insert(meta, friendlySize(info.size)) end
        local content = VerticalGroup:new{
            align = "left",
            title(_("A new version is available"), in_w),
            VerticalSpan:new{ width = S(4) },
            P.text(table.concat(meta, " · ") .. "\n" .. T(_("You have version %1"), installedVersion()),
                in_w, { size = 12, color = P.GRAY_DARK }),
        }
        -- Novedades: las 3 primeras líneas "- …" del texto de la release; tocar = todas
        local items = Upd.notesSummary(info.notes, 3)
        if #items > 0 then
            local card_in = P.cardInner(in_w)
            local lines = {}
            for _i, it in ipairs(items) do table.insert(lines, "· " .. it) end
            local notes = VerticalGroup:new{ align = "left",
                P.text(table.concat(lines, "\n"), card_in, { size = 13, max_lines = 4 }) }
            table.insert(notes, VerticalSpan:new{ width = S(4) })
            table.insert(notes, TextWidget:new{ text = _("See all changes") .. " ›", face = face(false, 12),
                fgcolor = P.GRAY_DARK, max_width = card_in, padding = 0 })
            table.insert(content, VerticalSpan:new{ width = S(10) })
            -- La hoja se cierra para no tapar las novedades y vuelve al cerrarlas
            table.insert(content, P.tappable(P.card(notes, in_w), function()
                UIManager:close(sheet)
                showNotes(info, function() showNewVersion(info) end)
            end))
        end
        -- Esta copia tiene dev/ (pruebas): la versión publicada no la trae
        if Upd.hasDevFolder() then
            table.insert(content, VerticalSpan:new{ width = S(10) })
            table.insert(content, P.text(_("This copy has the dev/ folder (tests). The new version does not include it, so it will be removed."),
                in_w, { size = 12, color = P.GRAY_DARK }))
        end
        table.insert(content, VerticalSpan:new{ width = S(14) })
        table.insert(content, pillRow({
            { text = _("Skip"), callback = function()
                config.update_skipped = info.version
                saveConfig()
                UIManager:close(sheet)
            end },
            { text = _("Later"), callback = function() UIManager:close(sheet) end },
            { text = _("Update"), primary = true, callback = function()
                UIManager:close(sheet)
                runUpdate(info)
            end },
        }, in_w))
        sheet = newSheet(content)
        UIManager:show(sheet)
    end

    ---------------------------------------------------------------------------
    -- Comprobar (manual: con avisos; automática: en silencio salvo versión nueva)
    ---------------------------------------------------------------------------
    local function doCheck(manual)
        local Upd = getUpd()
        if not Upd then return end
        local info, err = Upd.fetchLatest(config.update_beta == true)
        config.update_last_check = os.time()
        if not info then
            saveConfig()
            if manual then
                Upd.warn("no se pudo comprobar:", err)
                UIManager:show(InfoMessage:new{ text = _("Could not check for updates. Try again later.") })
            else
                logger.dbg("Aire/Update: comprobación automática fallida:", err)
            end
            return
        end
        if Upd.isNewer(info.version, installedVersion()) and installed_pending ~= info.version then
            -- Se guarda sin el texto entero si es muy largo (va en settings.reader.lua)
            if #info.notes > 4000 then info.notes = info.notes:sub(1, 4000) end
            config.update_latest = info
            saveConfig()
            if manual or config.update_skipped ~= info.version then
                showNewVersion(info)
            end
        else
            config.update_latest = nil
            saveConfig()
            if manual then
                UIManager:show(InfoMessage:new{
                    text = T(_("You already have the latest version (%1)."), installedVersion()),
                })
            end
        end
    end

    local function check(manual)
        if manual then
            local working = InfoMessage:new{ text = "⌛", show_icon = false, alignment = "center" }
            UIManager:show(working)
            UIManager:forceRePaint()
            UIManager:close(working)
        end
        NetworkMgr:runWhenOnline(function() doCheck(manual) end)
    end

    -- Comprobación semanal: al conectarse el Wi-Fi (KOReader lo avisa también al
    -- arrancar si ya estaba conectado). Nunca enciende el Wi-Fi ni corre en el lector.
    local prev_onNetworkConnected = Aire.onNetworkConnected
    function Aire:onNetworkConnected(...)
        if prev_onNetworkConnected then prev_onNetworkConnected(self, ...) end
        if self._aire_closed or not self.ui or self.ui.document then return end
        if config.update_auto == false or self._update_scheduled then return end
        if os.time() - (tonumber(config.update_last_check) or 0) < WEEK then return end
        self._update_scheduled = true
        UIManager:scheduleIn(5, function()
            self._update_scheduled = nil
            if self._aire_closed then return end
            if NetworkMgr:isOnline() then
                local ok, err = pcall(doCheck, false)
                if not ok then logger.warn("Aire/Update: error en la comprobación automática:", err) end
            end
        end)
    end

    -- Al arrancar bien (explorador listo, 10 s después): borrar la versión
    -- anterior (.old) y restos de una instalación a medias (.new). Una vez por sesión.
    local cleaned = false
    function Aire:cleanupUpdateLeftovers()
        if cleaned then return end
        cleaned = true
        UIManager:scheduleIn(10, function()
            local Upd = getUpd()
            if Upd then
                local ok, err = pcall(Upd.cleanup)
                if not ok then logger.warn("Aire/Update: error borrando restos:", err) end
            end
        end)
    end

    ---------------------------------------------------------------------------
    -- Menú superior: "Actualizar Aire" (junto a "Actualizar KOReader")
    ---------------------------------------------------------------------------
    local function menuItem()
        return {
            text_func = function()
                local l = available()
                return l and T(_("Update Aire (%1 available)"), l.version) or _("Update Aire")
            end,
            hold_callback = function() check(true) end,
            sub_item_table = {
                {
                    text = _("Check for updates"),
                    callback = function() check(true) end,
                },
                {
                    text = _("Settings"),
                    sub_item_table = {
                        {
                            text = _("Check every week"),
                            help_text = _("Only when Wi-Fi is already on: Aire never turns it on."),
                            checked_func = function() return config.update_auto ~= false end,
                            callback = function()
                                config.update_auto = (config.update_auto == false)
                                saveConfig()
                            end,
                        },
                        {
                            text = _("Include beta versions"),
                            checked_func = function() return config.update_beta == true end,
                            callback = function()
                                config.update_beta = not config.update_beta
                                saveConfig()
                            end,
                            separator = true,
                        },
                        {
                            text_func = function()
                                local t = tonumber(config.update_last_check)
                                local when = t and t > 0 and formatDate(os.date("%Y-%m-%d", t)) or _("never")
                                return T(_("Last check: %1"), when)
                            end,
                            enabled_func = function() return false end,
                        },
                    },
                },
                {
                    text_func = function() return T(_("Installed version: %1"), installedVersion()) end,
                    enabled_func = function() return false end,
                },
            },
        }
    end

    ---------------------------------------------------------------------------
    -- Hoja de energía → "Actualizar": elegir KOReader o Aire
    ---------------------------------------------------------------------------
    local function showChooser(on_koreader)
        local P = getP()
        local in_w = select(4, sheetGeometry())
        local sheet
        local l = available()
        sheet = newSheet(VerticalGroup:new{
            align = "left",
            title(_("Update"), in_w),
            VerticalSpan:new{ width = S(6) },
            P.row("KOReader", nil, in_w, function()
                UIManager:close(sheet)
                on_koreader()
            end),
            P.row(l and T(_("Aire %1 available"), l.version) or "Aire", nil, in_w, function()
                UIManager:close(sheet)
                check(true)
            end, { no_line = true }),
        })
        UIManager:show(sheet)
    end

    ctx.update = {
        showChooser = showChooser,
        check = check,
        available = available,
        installedVersion = installedVersion,
        showNewVersion = showNewVersion,
        runUpdate = runUpdate,
        menuItem = menuItem,
        -- Pruebas: con una versión antigua simulada, la publicada cuenta como nueva
        fakeVersion = function() return fake_version end,
        setFakeVersion = function(v) fake_version = v end,
        -- Tarjeta de la hoja de energía: directamente a instalar, salvo si hay
        -- dev/ (entonces la hoja con el aviso)
        start = function(info)
            local Upd = getUpd()
            if Upd and Upd.hasDevFolder() then showNewVersion(info) else runUpdate(info) end
        end,
    }

    -- Para devtools.lua (galería de hojas) y pruebas
    function Aire:showUpdateSheet(info) showNewVersion(info) end
end
