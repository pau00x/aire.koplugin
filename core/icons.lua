--[[--
    Bundled icon resolver for aire.koplugin.
    Hooks IconWidget:init so:
      1) "aire.*" icons bundled in <plugin_dir>/icons/ are found automatically
         even when not copied to koreader/icons/.
      2) Native KOReader icons listed in M.OVERRIDES are replaced globally by
         their Aire equivalents.
    User overrides in <DataDir>/icons/ still take precedence in both cases.

    Naming: aire.<name> (dock, menus, power sheet), aire.widget.<name> (Home
    widgets), aire.checkbox.on|off and aire.radio.on|off (checkmarks).
--]]

local DataStorage = require("datastorage")
local IconWidget = require("ui/widget/iconwidget")
local lfs = require("libs/libkoreader-lfs")

local M = {}

--- Single source of truth for global KOReader -> Aire icon replacements.
-- Context-dependent overrides (e.g. appbar.filebrowser -> aire.library when
-- returning from the reader in Library mode) stay in their UI modules.
M.OVERRIDES = {
    ["appbar.filebrowser"] = "aire.folder",
    ["appbar.settings"]    = "aire.settings",
    ["appbar.tools"]       = "aire.tools",
    ["appbar.search"]      = "aire.search",
    ["appbar.menu"]        = "aire.menu",
    ["appbar.typeset"]     = "aire.typeset",
    ["appbar.contrast"]    = "aire.widget.contrast",
    ["appbar.navigation"]  = "aire.navigation",
    ["appbar.textsize"]    = "aire.text",
    ["appbar.rotation"]    = "aire.rotation",
    ["appbar.crop"]        = "aire.crop",
    ["appbar.pagefit"]     = "aire.pagefit",
    ["appbar.pageview"]    = "aire.pageview",
    ["chevron.up"]         = "aire.chevron.up",
    ["chevron.left"]       = "aire.chevron.left",
    ["chevron.right"]      = "aire.chevron.right",
    ["chevron.first"]      = "aire.chevron.first",
    ["chevron.last"]       = "aire.chevron.last",
    ["star.empty"]         = "aire.star.empty",
    ["star.full"]          = "aire.star.full",
    ["star.white"]         = "aire.star.white",
    ["edit"]                 = "aire.edit",
    ["home"]                 = "aire.home",
    ["plus"]                 = "aire.plus",
    ["exit"]                 = "aire.exit",
    ["check"]                = "aire.check",
    ["close"]                = "aire.close",
    ["cancel"]               = "aire.cancel",
    ["back.top"]             = "aire.back.top",
    ["back.top.rtl"]         = "aire.back.top.rtl",
    ["control.expand"]       = "aire.control.expand",
    ["control.collapse"]     = "aire.control.collapse",
    ["control.expand.alpha"] = "aire.control.expand.alpha",
    ["move.up"]              = "aire.move.up",
    ["move.down"]            = "aire.move.down",
    ["triangle"]             = "aire.triangle",
    ["bookmark"]             = "aire.bookmark",
    ["book.opened"]          = "aire.book.opened",
    ["position.marker"]      = "aire.position.marker",
    ["position.marker.top"]  = "aire.position.marker.top",
    ["notice-info"]          = "aire.notice.info",
    ["notice-warning"]       = "aire.notice.warning",
    ["notice-question"]      = "aire.notice.question",
    ["info"]                 = "aire.info",
    ["icon-not-found"]       = "aire.icon.not.found",
    ["wifi.open.0"]          = "aire.wifi.open.0",
    ["wifi.open.25"]         = "aire.wifi.open.25",
    ["wifi.open.50"]         = "aire.wifi.open.50",
    ["wifi.open.75"]         = "aire.wifi.open.75",
    ["wifi.open.100"]        = "aire.wifi.open.100",
    ["wifi.secure.0"]        = "aire.wifi.secure.0",
    ["wifi.secure.25"]       = "aire.wifi.secure.25",
    ["wifi.secure.50"]       = "aire.wifi.secure.50",
    ["wifi.secure.75"]       = "aire.wifi.secure.75",
    ["wifi.secure.100"]      = "aire.wifi.secure.100",
    ["align.auto"]           = "aire.align.auto",
    ["align.left"]           = "aire.align.left",
    ["align.center"]         = "aire.align.center",
    ["align.right"]          = "aire.align.right",
    ["align.justify"]        = "aire.align.justify",
    ["column.one"]           = "aire.column.one",
    ["column.two"]           = "aire.column.two",
    ["column.three"]         = "aire.column.three",
    ["zoom.page"]            = "aire.zoom.page",
    ["zoom.content"]         = "aire.zoom.content",
    ["zoom.column"]          = "aire.zoom.column",
    ["zoom.row"]             = "aire.zoom.row",
    ["zoom.manual"]          = "aire.zoom.manual",
    ["rotation.P.0UR"]       = "aire.rotation.P.0UR",
    ["rotation.P.90CW"]      = "aire.rotation.P.90CW",
    ["rotation.P.180UD"]     = "aire.rotation.P.180UD",
    ["rotation.P.90CCW"]     = "aire.rotation.P.90CCW",
    ["rotation.L.0UR"]       = "aire.rotation.L.0UR",
    ["rotation.L.90CW"]      = "aire.rotation.L.90CW",
    ["rotation.L.180UD"]     = "aire.rotation.L.180UD",
    ["rotation.L.90CCW"]     = "aire.rotation.L.90CCW",
    ["direction.LRTB"]       = "aire.direction.LRTB",
    ["direction.RLTB"]       = "aire.direction.RLTB",
    ["direction.LRBT"]       = "aire.direction.LRBT",
    ["direction.RLBT"]       = "aire.direction.RLBT",
    ["direction.TBLR"]       = "aire.direction.TBLR",
    ["direction.TBRL"]       = "aire.direction.TBRL",
    ["direction.BTLR"]       = "aire.direction.BTLR",
    ["direction.BTRL"]       = "aire.direction.BTRL",
    ["cre.render.ready"]     = "aire.cre.render.ready",
    ["cre.render.working"]   = "aire.cre.render.working",
    ["cre.render.partial"]   = "aire.cre.render.partial",
    ["cre.render.reload"]    = "aire.cre.render.reload",
    ["texture-box"]          = "aire.texture.box",
    ["appbar.pokeball"]      = "aire.pokeball",
}

local user_icon_cache = {}
local path_cache = {}

local function findUserIcon(name)
    local cached = user_icon_cache[name]
    if cached ~= nil then return cached end
    local base = DataStorage:getDataDir() .. "/icons/" .. name
    local p = base .. ".svg"
    if lfs.attributes(p, "mode") == "file" then
        user_icon_cache[name] = p
        return p
    end
    p = base .. ".png"
    if lfs.attributes(p, "mode") == "file" then
        user_icon_cache[name] = p
        return p
    end
    user_icon_cache[name] = false
    return false
end

local function userIconExists(name)
    return findUserIcon(name) ~= false
end

function M.clearCache()
    user_icon_cache = {}
    path_cache = {}
end

--- Resolve a KOReader icon name to its Aire equivalent (if any).
function M.resolve(name)
    return M.OVERRIDES[name] or name
end

--- Path of an Aire icon: the user's override if there is one, else the bundled
-- file; nil if neither exists. Works once register() has run.
function M.path(name)
    local cached = path_cache[name]
    if cached ~= nil then return cached or nil end
    local user_path = findUserIcon(name)
    if user_path then
        path_cache[name] = user_path
        return user_path
    end
    local dir = IconWidget._aire_icons_dir
    if dir then
        local plugin_path = dir .. "/" .. name .. ".svg"
        if lfs.attributes(plugin_path, "mode") == "file" then
            path_cache[name] = plugin_path
            return plugin_path
        end
        path_cache[name] = false
    end
    return nil
end

function M.register(plugin_dir)
    if IconWidget._aire_icons_hooked or not plugin_dir then
        return
    end
    IconWidget._aire_icons_hooked = true
    -- Para otros módulos (p. ej. las casillas de styles/ui/checkmarks.lua)
    IconWidget._aire_icons_dir = plugin_dir .. "/icons"
    IconWidget._aire_icon_path = M.path
    IconWidget._aire_icon_overrides = M.OVERRIDES
    IconWidget._aire_resolve_icon = M.resolve
    local orig_init = IconWidget.init
    IconWidget.init = function(self)
        if not self.image and not self.file and type(self.icon) == "string" then
            if self.icon:match("^aire%.") then
                self.file = M.path(self.icon)
            else
                local mapped = M.OVERRIDES[self.icon]
                if mapped and not userIconExists(self.icon) then
                    self.file = M.path(mapped)
                end
            end
        end
        return orig_init(self)
    end
end

return M
