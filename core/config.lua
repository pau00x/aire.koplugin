--[[
    aire.koplugin/core/config.lua
    Ajustes del plugin (clave "aire" en settings.reader.lua): valores por
    defecto y lectura. TODA clave nueva hay que añadirla en load() o se pierde.
--]]

local SETTINGS_KEY = "aire"

local DEFAULTS = {
    enabled = true,
    mode = "library",        -- "library" (esta pantalla) | "explorer" (FileManager normal)
    big_clock = true,
    status = { ssh = true, memory = false, wifi = true, frontlight = false, battery = true, update = true },
    status_order = { "ssh", "memory", "wifi", "frontlight", "battery" },
}

local function loadConfig()
    local saved = G_reader_settings:readSetting(SETTINGS_KEY)
    if type(saved) ~= "table" then saved = {} end
    local cfg = {
        enabled = true,
        mode = (saved.mode == "explorer") and "explorer" or "library",
        big_clock = saved.big_clock ~= false,
        demo = saved.demo == true,               -- devtools.lua: datos falsos en las vistas
        debug_sizes = saved.debug_sizes == true, -- devtools.lua: medidas encima de cada celda
        demo_stats = saved.demo_stats == true,   -- devtools.lua: estadísticas inventadas
        sel_style = type(saved.sel_style) == "string" and saved.sel_style or "black", -- devtools.lua
        demo_widgets = saved.demo_widgets == true,          -- devtools.lua: widgets de prueba
        demo_widgets_offset = tonumber(saved.demo_widgets_offset) or 0,
        lib_filter = type(saved.lib_filter) == "string" and saved.lib_filter or "all",
        lib_sort = type(saved.lib_sort) == "string" and saved.lib_sort or "smart",
        lib_sort_rev = saved.lib_sort_rev == true,
        lib_mixed = saved.lib_mixed ~= false,
        coll_filter = type(saved.coll_filter) == "string" and saved.coll_filter or "all",
        coll_sort = type(saved.coll_sort) == "string" and saved.coll_sort or "manual",
        coll_sort_rev = saved.coll_sort_rev == true,
        coll_list_filter = type(saved.coll_list_filter) == "string" and saved.coll_list_filter or "all",
        coll_list_sort = type(saved.coll_list_sort) == "string" and saved.coll_list_sort or "manual",
        coll_list_sort_rev = saved.coll_list_sort_rev == true,
        coll_auto_author = saved.coll_auto_author ~= false, -- colecciones automáticas por autor (sí por defecto)
        coll_auto_genre = saved.coll_auto_genre == true,   -- colecciones automáticas por género (palabra clave)
        hist_filter = type(saved.hist_filter) == "string" and saved.hist_filter or "all",
        hist_sort = type(saved.hist_sort) == "string" and saved.hist_sort or "recent",
        hist_sort_rev = saved.hist_sort_rev == true,
        fin_filter = type(saved.fin_filter) == "string" and saved.fin_filter or "year",
        fin_sort = type(saved.fin_sort) == "string" and saved.fin_sort or "recent",
        fin_sort_rev = saved.fin_sort_rev == true,
        stats_goal_daily_min = math.max(0, math.floor(tonumber(saved.stats_goal_daily_min) or 0)),
        stats_goal_yearly_books = math.max(0, math.floor(tonumber(saved.stats_goal_yearly_books) or 0)),
        status = {},
    }
    local st = type(saved.status) == "table" and saved.status or {}
    for k, def in pairs(DEFAULTS.status) do
        if type(st[k]) == "boolean" then cfg.status[k] = st[k] else cfg.status[k] = def end
    end
    -- Orden de los iconos de la barra superior (conserva claves válidas y añade las nuevas)
    local valid_order, seen_order = {}, {}
    for _i, k in ipairs(DEFAULTS.status_order) do valid_order[k] = true end
    cfg.status_order = {}
    if type(saved.status_order) == "table" then
        for _i, k in ipairs(saved.status_order) do
            if valid_order[k] and not seen_order[k] then
                seen_order[k] = true
                table.insert(cfg.status_order, k)
            end
        end
    end
    for _i, k in ipairs(DEFAULTS.status_order) do
        if not seen_order[k] then
            table.insert(cfg.status_order, k)
        end
    end
    -- Widgets de Inicio: qué hay en cada hueco ("fila:pos" = id) y combinación de cada fila
    -- home_widgets["fila:columna"] = { id, span, invert, swap, hold_tap, period }
    -- Sin nada guardado (primera instalación) se queda en nil: views/widgets/init.lua
    -- pone entonces el preset por defecto. Una tabla vacía guardada = sin widgets.
    cfg.home_widgets = nil
    if type(saved.home_widgets) == "table" then
        cfg.home_widgets = {}
        for key, v in pairs(saved.home_widgets) do
            if type(key) == "string" and key:match("^%d+:%d+$") then
                if type(v) == "string" then v = { id = v } end
                if type(v) == "table" and type(v.id) == "string" then
                    cfg.home_widgets[key] = {
                        id = v.id,
                        span = v.span == 2 and 2 or 1,
                        invert = v.invert == true or nil,
                        swap = v.swap == true or nil,
                        hold_tap = v.hold_tap == true or nil,
                        period = type(v.period) == "string" and v.period or nil,
                    }
                end
            end
        end
    end
    -- Tarjeta "Leyendo ahora": fondo blanco (si no, invertida) y sinopsis
    cfg.card_white = saved.card_white == true
    cfg.card_synopsis = saved.card_synopsis ~= false
    -- El menú guarda square_covers (y rounded_covers); hay que copiarla también,
    -- si no, se perdía en el siguiente guardado y volvían a salir redondeadas
    cfg.rounded_covers = saved.square_covers ~= true and saved.rounded_covers ~= false
    cfg.square_covers = not cfg.rounded_covers
    -- Opciones de diseño (menú: Librería y portadas, Dock, Interfaz)
    cfg.grid_cols = saved.grid_cols == 3 and 3 or 4
    -- Explorador: ruta de la carpeta y botón Ordenar en la cabecera
    cfg.explorer_path = saved.explorer_path ~= false
    cfg.explorer_sort = saved.explorer_sort ~= false
    cfg.series_badge = saved.series_badge ~= false
    cfg.reading_mark = saved.reading_mark ~= false
    cfg.finished_gray = saved.finished_gray ~= false
    cfg.dock_labels = saved.dock_labels ~= false
    -- Comprobar parches y plugins incompatibles al arrancar
    cfg.compat_check = saved.compat_check ~= false
    cfg.compat_known = type(saved.compat_known) == "table" and saved.compat_known or nil
    -- Actualizaciones de Aire (views/update_sheet.lua): comprobación semanal y versiones
    -- beta (la semanal sí por defecto; las beta no), última comprobación, versión omitida y la
    -- versión nueva ya conocida (para el menú y la hoja de energía sin red)
    cfg.update_auto = saved.update_auto ~= false
    cfg.update_beta = saved.update_beta == true
    cfg.update_last_check = tonumber(saved.update_last_check) or nil
    cfg.update_skipped = type(saved.update_skipped) == "string" and saved.update_skipped or nil
    cfg.update_latest = type(saved.update_latest) == "table" and type(saved.update_latest.version) == "string"
        and saved.update_latest or nil
    return cfg
end

return {
    SETTINGS_KEY = SETTINGS_KEY,
    DEFAULTS = DEFAULTS,
    load = loadConfig,
}
