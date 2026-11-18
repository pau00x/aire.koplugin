local _ = require("gettext")
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.+)[/\\][^/\\]+$")
if plugin_dir then
    pcall(function() dofile(plugin_dir .. "/common/l10n.lua").load(plugin_dir) end)
end
-- (Sin "name": KOReader lo toma del nombre de la carpeta, aire.koplugin, y
-- avisa en el log de que en _meta.lua está obsoleto.)
return {
    fullname = _("Aire"),
    -- Versión de Aire (única fuente: main.lua la lee de aquí y la escribe en el log)
    version = "0.1.0",
    description = _("Home screen with the current book, widgets, library, collections, history and stats, and a bottom navigation bar."),
}
