--[[--
    Bundled icon resolver for aire.koplugin.
    Hooks IconWidget:init so "aire.*" icons bundled in <plugin_dir>/icons/
    are found automatically even when not copied to koreader/icons/.
    User overrides in <DataDir>/icons/ still take precedence.

    Naming: aire.<name> (dock, menus, power sheet), aire.widget.<name> (Home
    widgets), aire.checkbox.on|off and aire.radio.on|off (checkmarks).
--]]

local DataStorage = require("datastorage")
local IconWidget = require("ui/widget/iconwidget")
local lfs = require("libs/libkoreader-lfs")

local M = {}

--- Path of an Aire icon: the user's override if there is one, else the bundled
-- file; nil if neither exists. Works once register() has run.
function M.path(name)
    local user_path = DataStorage:getDataDir() .. "/icons/" .. name .. ".svg"
    if lfs.attributes(user_path, "mode") == "file" then
        return user_path
    end
    local dir = IconWidget._aire_icons_dir
    local plugin_path = dir and (dir .. "/" .. name .. ".svg")
    if plugin_path and lfs.attributes(plugin_path, "mode") == "file" then
        return plugin_path
    end
end

function M.register(plugin_dir)
    if IconWidget._aire_icons_hooked or not plugin_dir then
        return
    end
    IconWidget._aire_icons_hooked = true
    -- Para otros módulos (p. ej. las casillas de styles/ui/checkmarks.lua)
    IconWidget._aire_icons_dir = plugin_dir .. "/icons"
    IconWidget._aire_icon_path = M.path
    local orig_init = IconWidget.init
    IconWidget.init = function(self)
        if not self.image and not self.file and type(self.icon) == "string" and self.icon:match("^aire%.") then
            self.file = M.path(self.icon)
        end
        return orig_init(self)
    end
end

return M
