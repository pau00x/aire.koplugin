--[[
    aire.koplugin/common/compat.lua
    Comprobación al arrancar KOReader (una vez por sesión):

      - Busca parches (patches/*.lua) y plugins (*.koplugin) nuevos desde la
        última vez y los apunta (se avisa de cuáles son).
      - Si alguno es incompatible con Aire (porque el plugin ya
        hace lo mismo o choca con él), lo desactiva:
          · parches: se renombran a "<nombre>.disabled"
          · plugins: se marcan como desactivados en los ajustes de KOReader
        y avisa de cuáles y de que hay que reiniciar para que surta efecto.

    Se puede apagar en el menú: Aire → Avanzado → "Comprobar parches y
    plugins al arrancar" (config.compat_check).
--]]

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

-- Parches de la comunidad que Aire ya incluye o con los que choca
-- (nombre del archivo -> motivo)
local CONFLICT_PATCHES = {
    ["2-statusbar-better-compact.lua"] = _("the plugin has its own status bar"),
    ["2-button-dialog-style.lua"]    = _("included in Aire"),
    ["2-browser-dot-pagination.lua"] = _("included in Aire"),
    ["2-menu-submenu-chevron.lua"]   = _("included in Aire"),
    ["2-modern-checkmarks.lua"]      = _("included in Aire"),
    ["2--disable-all-CB-widgets.lua"] = _("included in Aire"),
    ["2--stretched-rounded-covers.lua"] = _("conflicts with plugin covers"),
    ["2-browser-hide-underline.lua"] = _("included in Aire"),
    ["2-new-collections-star.lua"]   = _("conflicts with plugin covers"),
    ["2-new-progress-bar.lua"]       = _("conflicts with plugin covers"),
    ["2-new-status-icons.lua"]       = _("conflicts with plugin covers"),
    ["2-series-badge-numbered.lua"]  = _("conflicts with plugin covers"),
    ["20-faded-finished-books.lua"]  = _("conflicts with plugin covers"),
}

-- Plugins que sustituyen el explorador o la pantalla principal
local CONFLICT_PLUGINS = {
    projecttitle = _("replaces the file browser and covers"),
    simpleui     = _("replaces the home screen"),
    coverbrowserplus = _("replaces the file browser covers"),
}

local M = {}
-- main.lua hace dofile de este archivo cada vez que se crea el FileManager
-- (al volver de cada libro), así que la marca "ya se hizo" no puede ser una
-- variable local de aquí: se guarda en un módulo que sí persiste.
local session = require("apps/filemanager/filemanager")

local function listPatches()
    local dir = DataStorage:getPatchesDir()
    local out = {}
    if lfs.attributes(dir, "mode") ~= "directory" then return out, dir end
    for name in lfs.dir(dir) do
        if name:match("%.lua$") then out[name] = true end
    end
    return out, dir
end

local function listPlugins()
    local out = {}
    for _i, dir in ipairs({ "plugins", DataStorage:getDataDir() .. "/plugins" }) do
        if lfs.attributes(dir, "mode") == "directory" then
            for name in lfs.dir(dir) do
                local plugin = name:match("^(.+)%.koplugin$")
                if plugin and lfs.attributes(dir .. "/" .. name, "mode") == "directory" then
                    out[plugin] = true
                end
            end
        end
    end
    return out
end

-- Devuelve la lista de cambios (para poder probarlo); muestra el aviso si hay algo
function M.run(config, saveConfig)
    if session._aire_compat_done or not config.compat_check then return end
    session._aire_compat_done = true

    local patches, patch_dir = listPatches()
    local plugins = listPlugins()

    -- Nuevos desde la última vez
    local known = type(config.compat_known) == "table" and config.compat_known or nil
    local new_items = {}
    if known then
        for name in pairs(patches) do
            if not known["patch:" .. name] then table.insert(new_items, name) end
        end
        for name in pairs(plugins) do
            if not known["plugin:" .. name] then table.insert(new_items, name .. ".koplugin") end
        end
    end

    -- Incompatibles: desactivar
    local disabled = {}
    for name in pairs(patches) do
        local why = CONFLICT_PATCHES[name]
        if why then
            local from = patch_dir .. "/" .. name
            local to = from .. ".disabled"
            if lfs.attributes(to) then to = from .. "." .. os.date("%Y%m%d%H%M%S") .. ".disabled" end
            local ok, err = os.rename(from, to)
            if ok then
                patches[name] = nil
                table.insert(disabled, ("%s — %s"):format(name, why))
                logger.info("Aire/Compat: parche desactivado:", name, why)
            else
                logger.warn("Aire/Compat: no se pudo desactivar", name, err)
            end
        end
    end
    local plugins_disabled = G_reader_settings:readSetting("plugins_disabled") or {}
    local changed_plugins = false
    for name in pairs(plugins) do
        local why = CONFLICT_PLUGINS[name]
        if why and not plugins_disabled[name] then
            plugins_disabled[name] = true
            changed_plugins = true
            table.insert(disabled, ("%s.koplugin — %s"):format(name, why))
            logger.info("Aire/Compat: plugin desactivado:", name, why)
        end
    end
    if changed_plugins then G_reader_settings:saveSetting("plugins_disabled", plugins_disabled) end

    -- Guardar lo que hay ahora para la próxima vez
    local now_known = {}
    for name in pairs(patches) do now_known["patch:" .. name] = true end
    for name in pairs(plugins) do now_known["plugin:" .. name] = true end
    config.compat_known = now_known
    saveConfig()

    -- Lo que se acaba de desactivar ya sale en su apartado: no repetirlo en "nuevos"
    if #disabled > 0 and #new_items > 0 then
        local shown = {}
        for _i, n in ipairs(new_items) do
            local plain = n:gsub("%.koplugin$", "")
            local is_disabled = (CONFLICT_PATCHES[n] and not patches[n])
                or (n ~= plain and CONFLICT_PLUGINS[plain])
            if not is_disabled then table.insert(shown, n) end
        end
        new_items = shown
    end
    if #disabled == 0 and #new_items == 0 then return end
    table.sort(new_items)
    local lines = {}
    if #new_items > 0 then
        table.insert(lines, _("New since last time:"))
        for _i, n in ipairs(new_items) do table.insert(lines, "  · " .. n) end
    end
    if #disabled > 0 then
        if #lines > 0 then table.insert(lines, "") end
        table.insert(lines, _("Disabled due to incompatibility with the Home screen:"))
        for _i, n in ipairs(disabled) do table.insert(lines, "  · " .. n) end
        table.insert(lines, "")
        table.insert(lines, _("Restart KOReader for the change to take effect."))
    end
    UIManager:scheduleIn(1, function()
        local ButtonDialog = require("ui/widget/buttondialog")
        local Font = require("ui/font")
        local TextBoxWidget = require("ui/widget/textboxwidget")
        local Screen = require("device").screen
        local compat_dlg
        local buttons = {}
        if #disabled > 0 then
            table.insert(buttons, {
                { text = _("Later"), callback = function() UIManager:close(compat_dlg) end },
                { text = _("Restart KOReader"), is_enter_default = true, callback = function()
                    UIManager:close(compat_dlg)
                    UIManager:restartKOReader()
                end },
            })
        else
            table.insert(buttons, {
                { text = _("Got it"), is_enter_default = true, callback = function() UIManager:close(compat_dlg) end },
            })
        end
        compat_dlg = ButtonDialog:new{
            title = _("Compatibility"),
            title_align = "left",
            -- ButtonDialog no tiene info_text: el texto va como widget añadido
            _added_widgets = {
                TextBoxWidget:new{
                    text = table.concat(lines, "\n"),
                    width = ButtonDialog.aire_sheetInnerWidth and ButtonDialog.aire_sheetInnerWidth()
                        or (Screen:getWidth() - 2 * Screen:scaleBySize(40)),
                    face = Font:getFace("cfont", 15),
                    alignment = "left",
                },
            },
            buttons = buttons,
            tap_close_callback = function() UIManager:close(compat_dlg) end,
        }
        UIManager:show(compat_dlg)
    end)
end

return M
