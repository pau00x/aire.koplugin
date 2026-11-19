--[[
    aire.koplugin/styles/ui/init.lua
    Estilo general de Aire en todo KOReader. Se carga una vez desde main.lua y
    carga las piezas de styles/ui/ en orden:

      base         funciones y medidas compartidas (va la primera: captura
                   TouchMenuItem antes de que nadie envuelva TouchMenu)
      dialogs      diálogos y avisos, "Abriendo «Título»…", avisos rápidos
      pagination   paginación por puntos y aviso en listas vacías
      touchmenu    menú superior: submenús con chevron, pestañas y pie
      checkmarks   casillas y botones de opción con iconos SVG
      titlebar     barras de título, barra de estado, dock y pantallas completas
      progress     barras de progreso en forma de cápsula
      sheets       hojas inferiores: estilo común, ButtonDialog y otras ventanas,
                   componentes de las hojas y confirmación de 3 botones
      pickers      números, fecha, listas y títulos dentro de las hojas
      lightsheet   hoja propia de Iluminación (escalones de brillo y calidez)
      readermenu   menú inferior del lector (ConfigDialog) como hoja
      floating     ventanas que siguen flotando (tocar fuera, borde, ancho)

    El ORDEN IMPORTA: varias piezas envuelven los mismos métodos de KOReader
    (p. ej. ButtonDialog.init). Cada pieza recibe la tabla B (base.lua más lo que
    exporta sheets.lua). Si una falla, deja un aviso en el log y las demás siguen.
--]]

local logger = require("logger")

local UI_DIR = debug.getinfo(1, "S").source:match("^@(.+)[/\\][^/\\]+$") or ""
local B

local function loadPart(name)
    local fn, err = loadfile(UI_DIR .. "/" .. name .. ".lua")
    if not fn then
        logger.warn("Aire/UI: no se pudo cargar", name, err)
        return nil
    end
    local ok, res = pcall(fn, B)
    if not ok then
        logger.warn("Aire/UI: error en", name, res)
        return nil
    end
    return res
end

B = loadPart("base") or {}
loadPart("dialogs")
loadPart("pagination")
loadPart("touchmenu")
loadPart("checkmarks")
loadPart("titlebar")
loadPart("progress")
do -- lo que exporta sheets.lua (estilo de hoja y componentes) también va en B
    local exported = loadPart("sheets")
    if exported then
        for k, v in pairs(exported) do B[k] = v end
    end
end
loadPart("pickers")
loadPart("lightsheet")
loadPart("readermenu")
loadPart("floating")

logger.dbg("Aire/UI: interfaz general aplicada desde el plugin")
