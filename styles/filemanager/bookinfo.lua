--[[
    aire.koplugin/styles/filemanager/bookinfo.lua
    Se carga una vez desde main.lua.

    "Información del libro" y demás pantallas de datos (KeyValuePage).

    A) Jerarquía visual en todas las KeyValuePage (Información del libro,
       Estadísticas, Estado del sistema…): nombres de campo en texto normal y
       gris oscuro, valores en negro, líneas separadoras finas en gris.

    B) Información del libro reorganizada:
         ┌───────┐ Título del libro
         │portada│ Autor
         │       │ Serie #2.5
         │       │ Español
         └───────┘ Palabras clave
         Sinopsis en gris, 3 líneas…            (toca: texto completo)
         LECTURA  Leyendo · 42 % · pág. 215 de 512
                  Última lectura: hace 2 días
                  Subrayados: 12 subrayados · 3 notas
                  Tiempo de lectura: 3 h 25 min   (plugin Estadísticas)
                  Páginas · Página actual · Reseña (si la hay)
         ARCHIVO  Nombre · Formato · Tamaño "1,2 MB" · Fecha "15 nov 2026" ·
                  Carpeta · Cuaderno
       - Cabecera: tocar la portada la abre y tocar la sinopsis la muestra entera;
         mantener pulsado título, autor, serie, idioma, palabras clave, sinopsis
         o portada permite editarlos, como en las filas originales.
       - Serie e índice en una sola fila (mantener pulsado: editar cualquiera).
       - Se ocultan las filas sin dato ("N/D"), la reseña vacía y la valoración.

    La paginación por puntos de estas pantallas está en styles/ui/pagination.lua.
    Este archivo se carga antes que styles/ui/init.lua (ver main.lua), así que lee
    KeyValueItem de la función original de KeyValuePage, sin envolver.
--]]

-- stylua: ignore start
local CLEAN_HIERARCHY     = true   -- A) campos en gris, valores en negro, líneas finas
local BOOK_INFO_LAYOUT    = true   -- B) secciones Libro / Lectura / Archivo
local MERGE_SERIES        = true   -- "Serie #2.5" en una sola fila
local HIDE_EMPTY_ROWS     = true   -- ocultar filas "N/D" y la reseña vacía
local HIDE_RATING         = true   -- sin fila de valoración (va en una tarjeta de la cabecera)
local ITEMS_PER_PAGE      = 24     -- filas por página en esta pantalla (más = filas más bajas)
local COMPACT_FILE_ROWS   = true   -- "EPUB · 2,4 MB · 18 feb 2026" en una sola fila
local HIDE_MISSING_NOTEBOOK = true -- ocultar "Archivo de notas" si no se ha creado
local CLEAN_VALUES        = true   -- tamaño sin bytes y fecha corta
local READING_ROWS        = true   -- estado/progreso, última lectura, subrayados, tiempo
local COVER_HEADER        = true   -- cabecera con portada, título, autor y serie
local DESCRIPTION_LINES   = 3      -- líneas de sinopsis en la cabecera (0 = sin sinopsis)
local COVER_MAX_HEIGHT    = 160    -- alto máximo de la portada (se escala)
-- stylua: ignore end

local Blitbuffer = require("ffi/blitbuffer")
local BookInfo = require("apps/filemanager/filemanagerbookinfo")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local N_ = _.ngettext
local C_ = _.pgettext
local T = require("ffi/util").template
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (ui/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/BookInfo"

if KeyValuePage._clean_hierarchy_patched then return end
KeyValuePage._clean_hierarchy_patched = true

local SEPARATOR = " · "

--===========================================================================
-- A) JERARQUÍA VISUAL EN TODAS LAS KEYVALUEPAGE
--===========================================================================
local KeyValueItem
if type(KeyValuePage._populateItems) == "function" then
    KeyValueItem = package.loaded.aire_ui.getUpValue(KeyValuePage._populateItems, "KeyValueItem")
end

if CLEAN_HIERARCHY then

    if KeyValueItem and not KeyValueItem._clean_hierarchy_patched then
        KeyValueItem._clean_hierarchy_patched = true
        -- Filas sin valor: con acción son "abre otra página" (Estadísticas →
        -- Intervalo de tiempo…); sin acción, cabeceras de sección (Resumen de gestos…)
        local function isBlank(v) return v == nil or v == "" or v == " " end
        local ok_up, Utf8Proc = pcall(require, "ffi/utf8proc")
        local function upper(str)
            if ok_up and Utf8Proc and Utf8Proc.uppercase_dumb then
                local ok, res = pcall(Utf8Proc.uppercase_dumb, str)
                if ok and type(res) == "string" then return res end
            end
            return str:upper()
        end
        -- Letra de las filas clave / valor de las listas (ui/screen.lua, LIST)
        local LIST = package.loaded.aire_screen.LIST
        safeWrap(KeyValueItem, "init", function(_orig, self)
            local blank = isBlank(self.value)
            local is_header = blank and not self.callback
            local is_nav = blank and self.callback ~= nil
            local explicit_bold = rawget(self, "key_bold")
            if not blank and explicit_bold == nil then
                self.key_bold = false
            end
            -- Clave y valor a LIST.VALUE (KOReader llegaba a 22 según el alto)
            self.font_size = LIST.VALUE
            self.value_font_name = "cfont"
            if self.key_bold ~= false then self.key_font_name = "tfont" end
            _orig(self)
            -- Estructura: FrameContainer > HorizontalGroup > LeftContainer > TextWidget
            local hg = self[1] and self[1][1]
            local left_c = hg and hg[1]
            local key_w = left_c and left_c[1]
            if type(key_w) ~= "table" or getmetatable(key_w) ~= TextWidget then return end
            if is_header then
                -- Cabecera: mayúsculas pequeñas en gris (como LECTURA / ARCHIVO)
                key_w.face = Font:getFace("cfont", LIST.META)
                key_w.bold = true
                key_w.fgcolor = Blitbuffer.COLOR_DARK_GRAY
                key_w.text = upper(tostring(self.key or ""))
                key_w:free() -- vuelve a medir con la fuente nueva
            elseif is_nav then
                -- Abre otra página: título en negro y › a la derecha
                local OverlapGroup = require("ui/widget/overlapgroup")
                local LeftContainer = require("ui/widget/container/leftcontainer")
                local RightContainer = require("ui/widget/container/rightcontainer")
                local d = hg.dimen
                if d and d.w and d.h then
                    local chevron = TextWidget:new{ text = "›", face = Font:getFace("cfont", LIST.TITLE),
                        fgcolor = Blitbuffer.COLOR_DARK_GRAY }
                    -- (abre otra página: en negrita, como en las demás listas)
                    key_w.fgcolor = Blitbuffer.COLOR_BLACK
                    key_w.bold = true
                    key_w:free()
                    key_w:setMaxWidth(math.max(10, d.w - chevron:getWidth() - Size.padding.default))
                    self[1][1] = OverlapGroup:new{
                        dimen = Geom:new{ w = d.w, h = d.h },
                        LeftContainer:new{ dimen = Geom:new{ w = d.w, h = d.h }, key_w },
                        RightContainer:new{ dimen = Geom:new{ w = d.w, h = d.h }, chevron },
                    }
                end
            elseif explicit_bold ~= true then
                -- Dato: etiqueta en gris oscuro; el valor se queda en negro
                key_w.fgcolor = Blitbuffer.COLOR_DARK_GRAY
            end
        end, TAG)
    else
        logger.warn("Aire/BookInfo: no se encontró KeyValueItem, solo se aplican las líneas finas")
    end

    -- Filas por página por defecto: las que caben con el alto común (LIST.ROW_H);
    -- si el usuario eligió otro número en KOReader, se usa el suyo
    KeyValuePage.getDefaultItemsPerPage = function()
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        if sw > sh then sw, sh = sh, sw end
        local row_h = Screen:scaleBySize(package.loaded.aire_screen.LIST.ROW_H)
        return math.floor(sw / row_h) - 3, math.floor(sh / row_h) - 3
    end

    safeWrap(KeyValuePage, "_populateItems", function(orig_KeyValuePage_populateItems, self, ...)
        orig_KeyValuePage_populateItems(self, ...)
        if self.main_content then
            for _, w in ipairs(self.main_content) do
                if type(w) == "table" and getmetatable(w) == LineWidget and w.dimen then
                    w.dimen.h = Size.line.thin
                    w.background = Blitbuffer.COLOR_LIGHT_GRAY
                end
            end
        end
    end, TAG)
end

--===========================================================================
-- B) INFORMACIÓN DEL LIBRO EN SECCIONES
--===========================================================================
if not BOOK_INFO_LAYOUT then
    logger.dbg("Aire/BookInfo: aplicado desde el plugin (solo jerarquía)")
    return
end

-- Meses abreviados traducidos por KOReader (datetime.lua)
local MONTHS = {}
do
    local tr = require("datetime").shortMonthTranslation
    for i, m in ipairs({ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }) do
        MONTHS[i] = tr[m] or m
    end
end

local function shortDate(t)
    local d = os.date("*t", t)
    return string.format("%d %s %d", d.day, MONTHS[d.month], d.year)
end

local LANGUAGES = {
    es = _("Spanish"), en = _("English"), ca = _("Catalan"), gl = _("Galician"), eu = _("Basque"),
    fr = _("French"), de = _("German"), it = _("Italian"), pt = _("Portuguese"), nl = _("Dutch"),
    ru = _("Russian"), ja = _("Japanese"), zh = _("Chinese"), ko = _("Korean"), la = _("Latin"),
}

-- "es", "es-ES", "spa"… -> "Español"; si no se conoce, se deja tal cual
local function languageName(code)
    code = tostring(code)
    local base = code:lower():match("^(%a%a%a?)")
    local three = { spa = "es", eng = "en", cat = "ca", fra = "fr", fre = "fr", ger = "de", deu = "de",
                    ita = "it", por = "pt", glg = "gl", eus = "eu", baq = "eu" }
    base = base and (three[base] or base)
    return (base and LANGUAGES[base]) or code
end


local function relativeDate(t)
    local now = os.time()
    local today = os.date("*t", now)
    today.hour, today.min, today.sec = 0, 0, 0
    local midnight = os.time(today)
    if t >= midnight then return C_("aire", "today") end
    if t >= midnight - 86400 then return C_("aire", "yesterday") end
    local days = math.floor((midnight - t) / 86400) + 1
    if days < 7 then return T(N_("%1 day ago", "%1 days ago", days), days) end
    if days < 30 then
        local n = math.floor(days / 7)
        return T(N_("%1 week ago", "%1 weeks ago", n), n)
    end
    if days < 365 then
        local n = math.floor(days / 30)
        return T(N_("%1 month ago", "%1 months ago", n), n)
    end
    return shortDate(t)
end

local function formatDuration(secs)
    secs = math.floor(secs or 0)
    if secs < 60 then return nil end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return m > 0 and string.format("%d h %d min", h, m) or string.format("%d h", h)
    end
    return string.format("%d min", m)
end

-- Datos de lectura de un libro (sidecar, historial y estadísticas) ----------
local function getDocSettings(book_info_module, file)
    local ui = book_info_module.ui
    if ui and ui.document and ui.document.file == file and ui.doc_settings then
        return ui.doc_settings, true
    end
    if BookList.hasBookBeenOpened(file) then
        return BookList.getDocSettings(file), false
    end
end

local STATUS_TEXT = {
    reading = C_("aire", "Reading"),
    abandoned = C_("aire", "On hold"),
    complete = C_("aire", "Finished"),
    new = _("Not started"),
}

local function lastReadText(file, is_current)
    if is_current then return _("now") end
    local ok, ReadHistory = pcall(require, "readhistory")
    if not ok or not ReadHistory.hist then return nil end
    for _, v in ipairs(ReadHistory.hist) do
        if v.file == file and v.time then
            return relativeDate(v.time)
        end
    end
end

-- Tiempo total de lectura según el plugin Estadísticas (solo lectura de la BD)
local function readingTimeText(file, ds)
    local db = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(db, "mode") ~= "file" then return nil end
    local md5 = ds and ds:readSetting("partial_md5_checksum")
    if not md5 then
        local ok, res = pcall(util.partialMD5, file)
        md5 = ok and res or nil
    end
    if not md5 then return nil end
    local SQ3 = require("lua-ljsqlite3/init")
    local ok_open, conn = pcall(SQ3.open, db)
    if not ok_open or not conn then
        logger.warn("Aire/BookInfo: no se pudo abrir statistics.sqlite3:", conn)
        return nil
    end
    local ok, secs = pcall(function()
        local stmt = conn:prepare("SELECT id FROM book WHERE md5 = ? ORDER BY last_open DESC LIMIT 1;")
        local row = stmt:reset():bind(md5):step()
        if stmt.close then stmt:close() end
        local id_book = row and tonumber(row[1])
        if not id_book then return nil end
        local _pages, total = conn:rowexec(string.format(
            "SELECT count(DISTINCT page), sum(duration) FROM page_stat WHERE id_book = %d;", id_book))
        return tonumber(total)
    end)
    conn:close()
    if not ok then
        logger.warn("Aire/BookInfo: no se pudo leer el tiempo de lectura:", secs)
        return nil
    end
    return formatDuration(secs)
end

-- Identificar cada fila por su etiqueta original ---------------------------
local CUSTOM_MARK = "\u{F040} " -- lápiz que KOReader antepone a los metadatos editados

local function buildKeyIds()
    local ids = {
        [_("Filename:")] = "filename",
        [_("Format:")] = "format",
        [_("Size:")] = "size",
        [_("File date:")] = "file_date",
        [_("Folder:")] = "folder",
        [_("Metadata:")] = "metadata",
        [_("Current page:")] = "current_page",
        [_("Rating:")] = "rating",
        [_("Review:")] = "review",
        [_("Notebook file:")] = "notebook",
    }
    for prop_key, text in pairs(BookInfo.prop_text) do
        ids[text] = prop_key
    end
    return ids
end

local SECTION_OF = {
    title = "book", authors = "book", series = "book", series_index = "book",
    language = "book", keywords = "book", description = "book", cover = "book",
    pages = "reading", current_page = "reading", rating = "reading", review = "reading",
    filename = "file", format = "file", size = "file", file_date = "file",
    folder = "file", metadata = "file", notebook = "file",
}

local SECTIONS = {
    { id = "book", title = _("BOOK") },
    { id = "reading", title = _("READING") },
    { id = "file", title = _("FILE") },
}

local function stripMark(key)
    if type(key) ~= "string" then return key, false end
    if key:sub(1, #CUSTOM_MARK) == CUSTOM_MARK then
        return key:sub(#CUSTOM_MARK + 1), true
    end
    return key, false
end

local function showSeriesEditChoice(series_hold, index_hold)
    local dialog
    dialog = ButtonDialog:new{
        title = _("Edit series"),
        title_align = "center",
        buttons = {
            {{ text = _("Series name"), callback = function() UIManager:close(dialog); series_hold() end }},
            {{ text = _("Number in series"), callback = function() UIManager:close(dialog); index_hold() end }},
        },
    }
    UIManager:show(dialog)
end

local function rebuildKvPairs(book_info_module, kv_pairs, file, header_out)
    local key_ids = buildKeyIds()
    local n_a = _("N/A")
    local by_section = { book = {}, reading = {}, file = {} }
    local entries = {}

    for _, entry in ipairs(kv_pairs) do
        if type(entry) == "table" then
            local plain = stripMark(entry[1])
            local id = key_ids[plain]
            entry.separator = nil -- las líneas las ponen las secciones
            entries[id or entry] = entry
            local section = id and SECTION_OF[id] or "book"
            table.insert(by_section[section], { id = id, entry = entry })
        end
    end

    -- Serie + índice en una sola fila
    local series, index = entries.series, entries.series_index
    if MERGE_SERIES and series and series[2] ~= n_a then
        if index and index[2] ~= n_a and index[2] ~= "" then
            series[2] = tostring(series[2]) .. " #" .. tostring(index[2])
            local s_hold, i_hold = series.hold_callback, index.hold_callback
            if s_hold and i_hold then
                series.hold_callback = function() showSeriesEditChoice(s_hold, i_hold) end
            end
        end
        if index then index._hidden = true end
    end

    if CLEAN_VALUES then
        local size = entries.size
        if size and type(size[2]) == "string" then
            size[2] = size[2]:gsub("%s*%(.-%)%s*$", "")
        end
        local fdate = entries.file_date
        if fdate and type(fdate[2]) == "string" then
            local y, mo, d = fdate[2]:match("^(%d+)-(%d+)-(%d+)")
            if y then
                fdate[2] = string.format("%d %s %d", tonumber(d), MONTHS[tonumber(mo)] or mo, tonumber(y))
            end
        end
    end

    -- Cabecera: título, autor, serie, sinopsis y portada salen de la lista
    if COVER_HEADER and header_out and entries.title then
        local function val(e)
            if e and not e._hidden and e[2] ~= n_a and e[2] ~= "" then return e[2] end
        end
        local h = header_out
        h.file = file
        h.title = tostring(val(entries.title) or val(entries.filename) or "")
        h.title_hold = entries.title.hold_callback
        local authors = val(entries.authors)
        h.authors = authors and (tostring(authors):gsub("\n+", ", ")) or nil
        h.authors_hold = entries.authors and entries.authors.hold_callback
        h.series = series and val(series)
        h.series_hold = series and series.hold_callback
        local desc = DESCRIPTION_LINES > 0 and val(entries.description) or nil
        if desc then
            -- Limpiar HTML, entidades y espacios raros (NBSP, ZWSP, tabulaciones, saltos, dobles espacios)
            desc = tostring(desc)
                :gsub("<[Bb][Rr]%s*/?>", " "):gsub("</[PpDd][^>]*>", " "):gsub("<[^>]+>", " ")
                :gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&#39;", "'")
                :gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&mdash;", "—"):gsub("&ndash;", "–"):gsub("&hellip;", "…")
                :gsub("\194\160", " "):gsub("\226\128\139", "")
                :gsub("[%s]+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.%.%.+$", "…")
        end
        h.description = desc
        h.desc_tap = entries.description and entries.description.callback
        h.desc_hold = entries.description and entries.description.hold_callback
        h.cover_tap = entries.cover and entries.cover.callback
        h.cover_hold = entries.cover and entries.cover.hold_callback
        local lang = val(entries.language)
        h.language = lang and languageName(lang) or nil
        h.language_hold = entries.language and entries.language.hold_callback
        local keywords = val(entries.keywords)
        h.keywords = keywords and (tostring(keywords):gsub("\n+", ", ")) or nil
        h.keywords_hold = entries.keywords and entries.keywords.hold_callback
        -- Si la cabecera fallara, estas filas se vuelven a poner arriba
        h.fallback = {}
        for _, e in ipairs({ entries.title, entries.authors, series, entries.language,
                             entries.keywords, entries.description, entries.cover }) do
            if e and not e._hidden then
                table.insert(h.fallback, e)
                e._hidden = true
            end
        end
        h.ok = true
    end

    -- Valoración y reseña: van en dos tarjetas de la cabecera (como en Estado
    -- del libro), no como filas. Mantener pulsado / tocar abre el editor de
    -- KOReader (estrellas + reseña); desde el lector KOReader no lo ofrece.
    if header_out then
        local summary_cb = (entries.rating and entries.rating.hold_callback)
            or (entries.review and entries.review.hold_callback)
        -- Desde el lector: abrir Estado del libro (ahí se editan) cerrando esta página
        if not summary_cb and book_info_module and book_info_module.ui and book_info_module.ui.document
                and book_info_module.ui.status and book_info_module.ui.status.onShowBookStatus then
            local ui = book_info_module.ui
            summary_cb = function()
                local kvp = book_info_module.kvp_widget
                if kvp and kvp.onClose then kvp:onClose() end
                ui.status:onShowBookStatus()
            end
        end
        header_out.summary_edit = summary_cb
        local ok_s, ds = pcall(getDocSettings, book_info_module, file)
        local summary = ok_s and ds and ds:readSetting("summary") or {}
        header_out.rating = tonumber(summary.rating) or 0
        header_out.review = type(summary.note) == "string" and summary.note ~= "" and summary.note or nil
        header_out.show_summary = true
    end
    if (HIDE_RATING or header_out) and entries.rating then
        entries.rating._hidden = true
    end
    if header_out and entries.review then
        entries.review._hidden = true
    end

    -- Formato, tamaño y fecha en una sola fila
    if COMPACT_FILE_ROWS and entries.format then
        local parts = { tostring(entries.format[2]) }
        for _, id in ipairs({ "size", "file_date" }) do
            local e = entries[id]
            if e and e[2] ~= n_a and e[2] ~= nil and e[2] ~= "" then
                local v = tostring(e[2])
                if id == "size" then v = v:gsub("(%d)%.(%d)", "%1,%2") end
                table.insert(parts, v)
                e._hidden = true
            end
        end
        entries.format[2] = table.concat(parts, SEPARATOR)
        -- Etiqueta corta: con "Nombre de archivo:" la columna de valores se iba
        -- muy a la derecha y el nombre quedaba pegado al borde.
        if entries.filename then entries.filename[1] = _("Name:") end
        entries.format[1] = _("Format:")
    end

    -- "Archivo de notas" solo si existe de verdad
    if HIDE_MISSING_NOTEBOOK and entries.notebook and file then
        local ok, path = pcall(function()
            local ds = getDocSettings(book_info_module, file)
            return book_info_module:getNotebookFile(ds or file)
        end)
        if ok and type(path) == "string" and lfs.attributes(path, "mode") ~= "file" then
            entries.notebook._hidden = true
        end
    end

    if HIDE_EMPTY_ROWS then
        for _, list in pairs(by_section) do
            for _, row in ipairs(list) do
                local e = row.entry
                if e[2] == n_a or e[2] == nil or e[2] == "" then
                    e._hidden = true
                end
            end
        end
    end

    -- Tarjeta ARCHIVO en cabecera (Opción A)
    if COVER_HEADER and header_out then
        local l1, l2 = {}, {}
        if entries.format and not entries.format._hidden and entries.format[2] then
            table.insert(l1, tostring(entries.format[2]))
            entries.format._hidden = true
        end
        local real_dir = type(file) == "string" and file:match("^(.*)/[^/]+$") or nil
        if real_dir and real_dir ~= "" then
            table.insert(l2, real_dir)
            if entries.folder then entries.folder._hidden = true end
        elseif entries.folder and not entries.folder._hidden and entries.folder[2] then
            table.insert(l2, tostring(entries.folder[2]))
            entries.folder._hidden = true
        end
        local fname = entries.filename and entries.filename[2]
            or (type(file) == "string" and file:match("([^/]+)$"))
        if fname then
            header_out.subtitle = tostring(fname)
            if entries.filename then entries.filename._hidden = true end
        end
        if #l1 > 0 then header_out.file_line1 = table.concat(l1, SEPARATOR) end
        if #l2 > 0 then header_out.file_line2 = table.concat(l2, SEPARATOR) end
        header_out.file_tap = (entries.folder and entries.folder.callback)
            or (entries.filename and entries.filename.callback)
        header_out.file_hold = (entries.filename and entries.filename.hold_callback)
            or (entries.folder and entries.folder.hold_callback)
    end

    -- Métricas para las 4 tarjetas de la cabecera (Opción A)
    if READING_ROWS and file then
        local ok, err = pcall(function()
            local ds, is_current = getDocSettings(book_info_module, file)
            local summary = ds and ds:readSetting("summary") or {}
            local pf = ds and ds:readSetting("percent_finished")
            local status = summary.status or (pf and "reading") or "new"
            local pct = (status == "complete") and 100 or (pf and math.floor(pf * 100 + 0.5) or 0)
            local pages_num = ds and tonumber(ds:readSetting("doc_pages"))
            if not pages_num and entries.pages and tonumber(entries.pages[2]) then
                pages_num = tonumber(entries.pages[2])
            end
            local cur_page = (pf and pages_num and pages_num > 0) and math.max(1, math.floor(pages_num * pf + 0.5)) or nil
            if header_out then
                header_out.m_pct = pct
                header_out.m_prog_val = (status == "complete") and "100 %" or (pf and (pct .. " %") or C_("aire", "New"))
                if status == "complete" then
                    header_out.m_prog_sub = pages_num and T(_("%1 pp."), pages_num) or C_("aire", "Finished")
                elseif cur_page and pages_num then
                    header_out.m_prog_sub = cur_page .. " / " .. pages_num
                elseif pages_num then
                    header_out.m_prog_sub = T(_("%1 pp."), pages_num)
                else
                    header_out.m_prog_sub = STATUS_TEXT[status] or STATUS_TEXT.new
                end
                header_out.prog_tap = (entries.pages and entries.pages.callback)
                    or (entries.current_page and entries.current_page.callback)
                    or nil
                if entries.current_page then entries.current_page._hidden = true end
                header_out.m_time_val = readingTimeText(file, ds) or "—"
                -- Anotaciones compactas ("12 · 3" o "0")
                local anns = ds and ds:readSetting("annotations")
                local hl, nt, bm = 0, 0, 0
                if type(anns) == "table" then
                    for _, a in ipairs(anns) do
                        if a.drawer then
                            hl = hl + 1
                            if a.note and a.note ~= "" then nt = nt + 1 end
                        else
                            bm = bm + 1
                        end
                    end
                end
                if hl > 0 or nt > 0 then
                    header_out.m_notes_val = hl .. " · " .. nt
                elseif bm > 0 then
                    header_out.m_notes_val = tostring(bm)
                else
                    header_out.m_notes_val = "0"
                end
                header_out.m_last_val = lastReadText(file, is_current) or "—"
            end
            if entries.pages and not entries.pages._hidden then
                entries.pages._hidden = true
            end
        end)
        if not ok then logger.warn("Aire/BookInfo: métricas de lectura:", err) end
    end

    -- Montar de nuevo: cabecera + filas visibles + línea al final de cada sección.
    -- Desde el lector no va la sección "Lectura" (página, valoración, reseña):
    -- el progreso ya está en las tarjetas de arriba y lo demás en Estado del libro.
    local in_reader = book_info_module and book_info_module.ui and book_info_module.ui.document ~= nil
    local result = {}
    for _, sec in ipairs(SECTIONS) do
        local visible = {}
        if not (in_reader and sec.id == "reading") then
            for _, row in ipairs(by_section[sec.id]) do
                if not row.entry._hidden then table.insert(visible, row.entry) end
            end
        end
        if #visible > 0 then
            table.insert(result, { sec.title, "", key_bold = true })
            for _, e in ipairs(visible) do table.insert(result, e) end
            result[#result].separator = true
        end
    end
    if #result > 0 then result[#result].separator = nil end
    if header_out then header_out.has_extra_rows = (#result > 0) end
    return result
end

safeWrap(BookInfo, "show", function(orig_BookInfo_show, self, doc_settings_or_file, book_props)
    local file = doc_settings_or_file
    if type(file) == "table" then
        file = file.readSetting and file:readSetting("doc_path")
    end
    local book_info_module = self

    -- KeyValuePage se crea dentro de show(): interceptar solo esa creación
    local own_new = rawget(KeyValuePage, "new")
    local base_new = KeyValuePage.new
    local done = false
    rawset(KeyValuePage, "new", function(cls, o)
        if not done and cls == KeyValuePage and type(o) == "table" and type(o.kv_pairs) == "table" then
            done = true
            local header = {}
            local ok, res = pcall(rebuildKvPairs, book_info_module, o.kv_pairs,
                type(file) == "string" and file or nil, header)
            if ok and type(res) == "table" and (#res > 0 or header.ok) then
                o.kv_pairs = res
                if header.ok then o._bi_header = header end
            elseif not ok then
                logger.warn("Aire/BookInfo: no se pudo reorganizar:", res)
            end
            -- Filas más bajas solo en esta pantalla (para que quepa en una página)
            local orig_items = KeyValuePage.getCurrentItemsPerPage
            if ITEMS_PER_PAGE and type(orig_items) == "function" then
                KeyValuePage.getCurrentItemsPerPage = function(...)
                    local landscape, portrait = orig_items(...)
                    return math.max(landscape or 0, ITEMS_PER_PAGE), math.max(portrait or 0, ITEMS_PER_PAGE)
                end
            end
            -- Subtítulo de la cabecera de Aire (ui/screen.lua)
            local ok_new, res_new = pcall(package.loaded.aire_screen.withTitleBar, {
                subtitle = o._bi_header and o._bi_header.subtitle or nil,
            }, base_new, cls, o)
            KeyValuePage.getCurrentItemsPerPage = orig_items
            if not ok_new then error(res_new) end
            return res_new
        end
        return base_new(cls, o)
    end)
    local ok, err = pcall(orig_BookInfo_show, self, doc_settings_or_file, book_props)
    rawset(KeyValuePage, "new", own_new)
    if not ok then error(err) end
end, TAG)

--===========================================================================
-- CABECERA CON PORTADA (dentro de la KeyValuePage)
-- Para no romper la paginación, la cabecera ocupa el sitio de k filas vacías
-- que se añaden al principio de la lista; en la página 1 se sustituyen por ella.
--===========================================================================
local TapHold = InputContainer:extend{
    on_tap = nil,
    on_hold = nil,
}

function TapHold:init()
    local sz = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = sz.w, h = sz.h }
    self.ges_events = {
        BITap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } },
        BIHold = { GestureRange:new{ ges = "hold", range = function() return self.dimen end } },
    }
end

function TapHold:onBITap()
    if self.on_tap then self.on_tap() return true end
end

function TapHold:onBIHold()
    if self.on_hold then self.on_hold() return true end
end

local function wrapGestures(widget, on_tap, on_hold)
    if not on_tap and not on_hold then return widget end
    return TapHold:new{ on_tap = on_tap, on_hold = on_hold, widget }
end

-- La portada se lee una vez de la caché de CoverBrowser y se guarda hasta
-- cerrar la página (false = ya se buscó y no hay).
local function getCoverBB(kvp, file)
    if kvp._bi_cover_bb ~= nil then return kvp._bi_cover_bb or nil end
    kvp._bi_cover_bb = false
    if not file then return nil end
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok or type(BookInfoManager) ~= "table" then return nil end
    local ok2, bi = pcall(BookInfoManager.getBookInfo, BookInfoManager, file, true)
    if ok2 and bi and bi.has_cover and bi.cover_bb then
        kvp._bi_cover_bb = bi.cover_bb
    end
    return kvp._bi_cover_bb or nil
end

local function buildMetricBar(bar_w, pct)
    local bar_h = Screen:scaleBySize(5)
    local r = math.floor(bar_h / 2)
    local Widget = require("ui/widget/widget")
    return Widget:new{
        dimen = Geom:new{ w = bar_w, h = bar_h },
        paintTo = function(self, bb, x, y)
            bb:paintRoundedRect(x, y, bar_w, bar_h, Blitbuffer.COLOR_GRAY_D, r)
            local fill_w = math.floor(bar_w * math.max(0, math.min(100, pct or 0)) / 100)
            if fill_w > 0 then
                bb:paintRoundedRect(x, y, math.max(bar_h, fill_w), bar_h, Blitbuffer.COLOR_BLACK, r)
            end
        end,
    }
end

local function buildHeaderWidget(kvp, h)
    local dock_w = Screen:getWidth() - 2 * Screen:scaleBySize(SIDE)
    local width = math.min(kvp.item_width, dock_w)
    local gap = Size.padding.large
    local small_gap = Size.span.vertical_default
    local TextWidget = require("ui/widget/textwidget")

    -- Columna de la derecha: título, autor, serie, idioma, géneros y
    -- DESCRIPTION_LINES líneas de sinopsis. La portada se escala a su altura.
    local function buildCol(text_w)
        local col = VerticalGroup:new{ align = "left" }
        table.insert(col, wrapGestures(TextBoxWidget:new{
            text = h.title,
            face = Font:getFace("cfont", 19),
            bold = true,
            width = text_w,
        }, nil, h.title_hold))
        if h.authors then
            table.insert(col, VerticalSpan:new{ width = small_gap })
            table.insert(col, wrapGestures(TextBoxWidget:new{
                text = h.authors,
                face = Font:getFace("cfont", 15),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                width = text_w,
            }, nil, h.authors_hold))
        end
        -- Serie e idioma: texto gris (mantener pulsado: editar, como antes)
        for _i, it in ipairs({ { h.series, h.series_hold }, { h.language, h.language_hold } }) do
            if it[1] then
                table.insert(col, VerticalSpan:new{ width = small_gap })
                table.insert(col, wrapGestures(TextBoxWidget:new{
                    text = tostring(it[1]),
                    face = Font:getFace("cfont", 14),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    width = text_w,
                }, nil, it[2]))
            end
        end
        local function clipped(text, face, lines, color, tap, hold, gap_before)
            local probe = TextBoxWidget:new{ text = "M", face = face, width = text_w }
            local line_h = probe:getLineHeight()
            probe:free()
            table.insert(col, VerticalSpan:new{ width = gap_before })
            table.insert(col, wrapGestures(TextBoxWidget:new{
                text = text,
                face = face,
                fgcolor = color,
                width = text_w,
                height = line_h * lines,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            }, tap, hold))
        end
        if h.keywords then
            clipped(h.keywords, Font:getFace("cfont", 13), 2, Blitbuffer.COLOR_DARK_GRAY, nil, h.keywords_hold, small_gap)
        end
        if h.description then
            clipped(h.description, Font:getFace("cfont", 14), DESCRIPTION_LINES, Blitbuffer.COLOR_DARK_GRAY,
                h.desc_tap, h.desc_hold, Screen:scaleBySize(8))
        end
        return col
    end

    -- Portada: alta como la columna (con un mínimo y sin pasar del 40 % del ancho)
    local cover, col
    local bb = getCoverBB(kvp, h.file)
    if bb then
        local bw, bh = bb:getWidth(), bb:getHeight()
        local min_h = Screen:scaleBySize(110)
        local max_w = width * 0.4
        local function coverWidthFor(target_h)
            local sc = math.min(math.max(target_h, min_h) / bh, max_w / bw)
            return math.floor(bw * sc), sc
        end
        -- 1ª pasada con el alto de siempre; 2ª con el alto real de la columna
        local cw = coverWidthFor(Screen:scaleBySize(COVER_MAX_HEIGHT))
        col = buildCol(width - cw - gap)
        local cw2 = coverWidthFor(col:getSize().h)
        if math.abs(cw2 - cw) > Screen:scaleBySize(4) then
            col:free()
            col = buildCol(width - cw2 - gap)
            cw = cw2
        end
        local _w, scale = coverWidthFor(col:getSize().h)
        -- (sin pasar del hueco que se dejó a la columna)
        scale = math.min(scale, cw / bw)
        local rounded = require("apps/filemanager/filemanager")._aire_rounded_covers == true
        cover = FrameContainer:new{
            bordersize = Size.border.thin,
            radius = rounded and Screen:scaleBySize(8) or 0,
            _aire_clip_corners = rounded,
            padding = 0,
            margin = 0,
            ImageWidget:new{
                image = bb,
                image_disposable = false, -- el original se libera al cerrar la página
                scale_factor = scale,
            },
        }
        cover = wrapGestures(cover, h.cover_tap, h.cover_hold)
    else
        col = buildCol(width)
    end

    local top = HorizontalGroup:new{ align = "top" }
    if cover then
        table.insert(top, cover)
        table.insert(top, HorizontalSpan:new{ width = gap })
    end
    table.insert(top, col)

    local vg = VerticalGroup:new{
        align = "left",
        top,
    }

    -- 4 Mini-tarjetas métricas (Progreso, Tiempo, Notas, Última)
    if h.m_prog_val then
        local LeftContainer = require("ui/widget/container/leftcontainer")
        local c_gap = Screen:scaleBySize(8)
        local c_pad = Screen:scaleBySize(8)
        local c_w = math.floor((width - 3 * c_gap) / 4)
        local in_c_w = math.max(10, c_w - 2 * (c_pad + Size.border.thin))
        local function makeInner(val_str, sub_str, with_bar_pct, tap_cb)
            local inner = VerticalGroup:new{ align = "left" }
            table.insert(inner, TextWidget:new{
                text = val_str,
                face = Font:getFace("cfont", 15),
                bold = true,
                max_width = in_c_w,
            })
            if with_bar_pct ~= nil then
                table.insert(inner, VerticalSpan:new{ width = Screen:scaleBySize(4) })
                table.insert(inner, buildMetricBar(in_c_w, with_bar_pct))
                table.insert(inner, VerticalSpan:new{ width = Screen:scaleBySize(4) })
            else
                table.insert(inner, VerticalSpan:new{ width = Screen:scaleBySize(3) })
            end
            table.insert(inner, TextWidget:new{
                text = sub_str,
                face = Font:getFace("cfont", 11),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                max_width = in_c_w,
            })
            return inner, tap_cb
        end
        local specs = {
            { makeInner(h.m_prog_val, h.m_prog_sub, h.m_pct or 0, h.prog_tap) },
            { makeInner(h.m_time_val or "—", _("Time read")) },
            { makeInner(h.m_notes_val or "0", C_("aire", "Notes")) },
            { makeInner(h.m_last_val or "—", _("Last")) },
        }
        local max_in_h = 0
        for _, sp in ipairs(specs) do
            max_in_h = math.max(max_in_h, sp[1]:getSize().h)
        end
        local row = HorizontalGroup:new{ align = "top" }
        for i, sp in ipairs(specs) do
            if i > 1 then table.insert(row, HorizontalSpan:new{ width = c_gap }) end
            local ih = sp[1]:getSize().h
            if ih < max_in_h then
                table.insert(sp[1], VerticalSpan:new{ width = max_in_h - ih })
                sp[1]:resetLayout()
            end
            local card = FrameContainer:new{
                bordersize = Size.border.thin,
                color = Blitbuffer.COLOR_GRAY,
                background = Blitbuffer.COLOR_GRAY_E,
                radius = Screen:scaleBySize(10),
                padding = c_pad,
                LeftContainer:new{
                    dimen = Geom:new{ w = in_c_w, h = max_in_h },
                    sp[1],
                },
            }
            table.insert(row, sp[2] and wrapGestures(card, sp[2], nil) or card)
        end
        table.insert(vg, VerticalSpan:new{ width = gap })
        table.insert(vg, row)
    end

    -- Valoración y reseña (mismo estilo que Estado del libro): van debajo de la sinopsis
    local summary_group
    if h.show_summary then
        local IconWidget = require("ui/widget/iconwidget")
        local LeftContainer = require("ui/widget/container/leftcontainer")
        local RightContainer = require("ui/widget/container/rightcontainer")
        local OverlapGroup = require("ui/widget/overlapgroup")
        local pad = Screen:scaleBySize(10)
        local in_w = math.max(10, width - 2 * (pad + Size.border.thin))
        local n = math.max(0, math.min(5, math.floor(h.rating or 0)))
        local rating_lbl
        if n <= 0 then rating_lbl = _("Not rated")
        elseif n == 1 then rating_lbl = _("1 of 5 stars")
        else rating_lbl = string.format(_("%d of 5 stars"), n) end
        local left = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = _("RATING"), face = Font:getFace("cfont", 11), bold = true,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY },
            VerticalSpan:new{ width = Screen:scaleBySize(2) },
            TextWidget:new{ text = rating_lbl, face = Font:getFace("cfont", 12),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY },
        }
        local star_sz = Screen:scaleBySize(22)
        local stars = HorizontalGroup:new{ align = "center" }
        for i = 1, 5 do
            if i > 1 then table.insert(stars, HorizontalSpan:new{ width = Screen:scaleBySize(3) }) end
            table.insert(stars, IconWidget:new{ icon = i <= n and "star.full" or "star.empty",
                width = star_sz, height = star_sz, alpha = true })
        end
        local row_h = math.max(left:getSize().h, star_sz)
        local rating_card = FrameContainer:new{
            width = width,
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_GRAY,
            background = Blitbuffer.COLOR_GRAY_E,
            radius = Screen:scaleBySize(10),
            padding = pad,
            OverlapGroup:new{
                dimen = Geom:new{ w = in_w, h = row_h },
                LeftContainer:new{ dimen = Geom:new{ w = in_w, h = row_h }, left },
                RightContainer:new{ dimen = Geom:new{ w = in_w, h = row_h }, stars },
            },
        }
        local rv_face = Font:getFace("cfont", 13)
        local probe = TextBoxWidget:new{ text = "M", face = rv_face, width = in_w }
        local rv_line = probe:getLineHeight()
        probe:free()
        local review_card = FrameContainer:new{
            width = width,
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            radius = Screen:scaleBySize(10),
            padding = pad,
            VerticalGroup:new{
                align = "left",
                TextWidget:new{ text = _("REVIEW / NOTES"), face = Font:getFace("cfont", 11), bold = true,
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY },
                VerticalSpan:new{ width = Screen:scaleBySize(4) },
                TextBoxWidget:new{
                    text = h.review or (h.summary_edit and _("Tap to add or edit your review of this book…") or "—"),
                    face = rv_face,
                    fgcolor = h.review and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
                    width = in_w,
                    height = rv_line * 2,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                },
            },
        }
        local edit = h.summary_edit
        summary_group = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            wrapGestures(rating_card, edit, edit),
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            wrapGestures(review_card, edit, edit),
        }
    end

    -- Tarjeta ARCHIVO (Opción A) — se construye antes para descontar su alto de fixed_h
    local file_card
    if h.file_line1 or h.file_line2 then
        local f_pad = Screen:scaleBySize(10)
        local in_fw = math.max(10, width - 2 * (f_pad + Size.border.thin))
        local f_vg = VerticalGroup:new{
            align = "left",
            TextWidget:new{
                text = _("FILE"),
                face = Font:getFace("cfont", 11),
                bold = true,
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        }
        if h.file_line1 then
            table.insert(f_vg, VerticalSpan:new{ width = Screen:scaleBySize(4) })
            table.insert(f_vg, TextBoxWidget:new{
                text = h.file_line1,
                face = Font:getFace("cfont", 13),
                fgcolor = Blitbuffer.COLOR_BLACK,
                bgcolor = Blitbuffer.COLOR_GRAY_E,
                width = in_fw,
            })
        end
        if h.file_line2 then
            table.insert(f_vg, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            table.insert(f_vg, TextBoxWidget:new{
                text = h.file_line2,
                face = Font:getFace("cfont", 12),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                bgcolor = Blitbuffer.COLOR_GRAY_E,
                width = in_fw,
            })
        end
        file_card = FrameContainer:new{
            width = width,
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_GRAY,
            background = Blitbuffer.COLOR_GRAY_E,
            radius = Screen:scaleBySize(10),
            padding = f_pad,
            f_vg,
        }
        file_card = wrapGestures(file_card, h.file_tap, h.file_hold)
    end
    local file_card_h = file_card and (gap + file_card:getSize().h) or 0

    -- Espacio inferior: un poco de aire y la línea gris que separa secciones
    local bottom_h = Size.padding.large + Size.line.medium

    if summary_group then
        table.insert(vg, summary_group)
        vg:resetLayout()
    end

    local needed_h = vg:getSize().h + file_card_h + (h.has_extra_rows and bottom_h or 0)
    local k = kvp._bi_header_k or math.ceil(needed_h / kvp.item_height)
    if not h.has_extra_rows and kvp.items_per_page then
        k = kvp.items_per_page
    end
    local total_h = k * kvp.item_height
    if not h.has_extra_rows and kvp.dimen and kvp.title_bar then
        local avail_h = kvp.dimen.h - kvp.title_bar:getHeight() - Size.padding.large
        if avail_h > total_h then total_h = avail_h end
    end
    local side_off = math.max(0, math.floor((kvp.item_width - width) / 2))
    local function hAlign(w)
        if side_off <= 0 then return w end
        return HorizontalGroup:new{ align = "top", HorizontalSpan:new{ width = side_off }, w }
    end
    local inner_vg = VerticalGroup:new{
        align = "left",
        hAlign(vg),
    }
    if file_card then
        local bottom_pad = h.has_extra_rows and bottom_h or 0
        local spacer = math.max(gap, total_h - vg:getSize().h - file_card:getSize().h - bottom_pad)
        table.insert(inner_vg, VerticalSpan:new{ width = spacer })
        table.insert(inner_vg, hAlign(file_card))
    end
    if h.has_extra_rows then
        local used_h = inner_vg:getSize().h
        table.insert(inner_vg, VerticalSpan:new{ width = math.max(0, total_h - used_h - Size.line.thin) })
        table.insert(inner_vg, LineWidget:new{
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            dimen = Geom:new{ w = kvp.item_width, h = Size.line.thin },
        })
        inner_vg:resetLayout()
    end
    local widget = WidgetContainer:new{
        dimen = Geom:new{ w = kvp.item_width, h = total_h },
        inner_vg,
    }
    return widget, k
end

safeWrap(KeyValuePage, "init", function(orig_KVP_init, self, ...)
    orig_KVP_init(self, ...)
    local h = rawget(self, "_bi_header")
    if not h then return end
    local ok, err = pcall(function()
        -- Quitar el span_height aleatorio de KeyValuePage para que la separación
        -- bajo el subtítulo sea exactamente el S(12) del TitleBar (como en el resto)
        local vg_root = self[1] and self[1][1] and self[1][1][1]
        if vg_root and vg_root[2] and vg_root[2].width and not vg_root[2][1] then
            vg_root[2].width = 0
            if vg_root.resetLayout then vg_root:resetLayout() end
        end
        local widget, k = buildHeaderWidget(self, h)
        if k > self.items_per_page or (k == self.items_per_page and #self.kv_pairs > 0) then
            widget:free()
            error("cabecera demasiado alta: " .. k .. " filas")
        end
        -- Se reutiliza en el _populateItems de justo debajo (antes se tiraba y se
        -- volvía a construir, escalando la portada dos veces al abrir)
        self._bi_header_widget = widget
        for i = 1, k do
            table.insert(self.kv_pairs, i, { "", "", _bi_placeholder = true })
        end
        self._bi_header_k = k
        self.pages = math.ceil(#self.kv_pairs / self.items_per_page)
        self:_populateItems()
    end)
    if not ok then
        -- Sin cabecera: volver a poner las filas de título, autor, etc. arriba
        logger.warn("Aire/BookInfo: cabecera con portada:", err)
        if self._bi_header_widget then
            self._bi_header_widget:free()
            self._bi_header_widget = nil
        end
        self._bi_header = nil
        self._bi_header_k = nil
        for i = #self.kv_pairs, 1, -1 do
            local e = self.kv_pairs[i]
            if type(e) == "table" and e._bi_placeholder then table.remove(self.kv_pairs, i) end
        end
        for i = #h.fallback, 1, -1 do
            local e = h.fallback[i]
            e._hidden = nil
            table.insert(self.kv_pairs, 1, e)
        end
        self.pages = math.ceil(#self.kv_pairs / self.items_per_page)
        local ok2, err2 = pcall(self._populateItems, self)
        if not ok2 then logger.warn("Aire/BookInfo: al restaurar las filas:", err2) end
    end
end, TAG)

safeWrap(KeyValuePage, "_populateItems", function(orig_KVP_populateItems_header, self, ...)
    orig_KVP_populateItems_header(self, ...)
    local k = self._bi_header_k
    if not k or self.show_page ~= 1 or not self.main_content then return end
    local ok, err = pcall(function()
        local first_pos
        local removed = {}
        for i = #self.main_content, 1, -1 do
            local w = self.main_content[i]
            if type(w) == "table" and w.kv_pairs_idx and w.kv_pairs_idx <= k then
                removed[w] = true
                if w.free then w:free() end
                table.remove(self.main_content, i)
                first_pos = i
            end
        end
        if not first_pos then return end
        -- La primera vez, la cabecera ya medida en init; después (al volver a
        -- la página 1) una nueva: KOReader libera lo que había en la página
        local widget = self._bi_header_widget
        self._bi_header_widget = nil
        if not widget then widget = buildHeaderWidget(self, self._bi_header) end
        table.insert(self.main_content, first_pos, widget)
        self.main_content:resetLayout()
        if self.layout then
            for i = #self.layout, 1, -1 do
                local row = self.layout[i]
                if row and removed[row[1]] then table.remove(self.layout, i) end
            end
        end
    end)
    if not ok then logger.warn("Aire/BookInfo: no se pudo pintar la cabecera:", err) end
end, TAG)

safeWrap(KeyValuePage, "onCloseWidget", function(orig_KVP_onCloseWidget, self, ...)
    if self._bi_header_widget then -- (medida pero sin llegar a usarse)
        self._bi_header_widget:free()
        self._bi_header_widget = nil
    end
    if self._bi_cover_bb then
        self._bi_cover_bb:free()
    end
    self._bi_cover_bb = nil
    if orig_KVP_onCloseWidget then return orig_KVP_onCloseWidget(self, ...) end
end, TAG)

logger.dbg("Aire/BookInfo: aplicado desde el plugin")
