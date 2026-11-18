--[[
    aire.koplugin/views/booksheet.lua
    Se carga una vez desde main.lua.

    Sustituye el menú técnico de pulsación larga sobre un libro por una ficha
    limpia y directa, y añade también una ficha de acciones al mantener pulsada
    una serie (grupos de la Librería de Aire, colecciones, y las carpetas de
    serie del parche de la comunidad "Automatic Book Series" si está instalado).

    1) Al mantener pulsado un LIBRO:
       ╭──────────────────────────────────────────╮
       │  Título del libro                        │
       │  Autor                                   │
       │  Serie #1 · 42% · 215 / 512 págs.        │
       ├──────────────────────────────────────────┤
       │   Leyendo ✓   │   En pausa   │ Terminado │
       ├──────────────────────────────────────────┤
       │       Sinopsis       │  Info del libro   │
       │            Añadir a colección            │
       ├──────────────────────────────────────────┤
       │       Eliminar       │   Más opciones…   │
       ╰──────────────────────────────────────────╯
       ("Más opciones…" abre el diálogo completo original de KOReader).

    2) Al mantener pulsada una SERIE:
       ╭──────────────────────────────────────────╮
       │  Nombre de la serie                      │
       │  Autor                                   │
       │  4 libros · 2 terminados · #3 al 42%     │
       ├──────────────────────────────────────────┤
       │      Continuar: «Juramentada» (#3)       │
       │        Abrir carpeta de la serie         │
       ├──────────────────────────────────────────┤
       │     Marcar toda la serie terminada       │
       │      Reiniciar estado de la serie        │
       ╰──────────────────────────────────────────╯
--]]

local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BookList = require("ui/widget/booklist")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DocumentRegistry = require("document/documentregistry")
local FileManager = require("apps/filemanager/filemanager")
local FileManagerBookInfo = require("apps/filemanager/filemanagerbookinfo")
local Font = require("ui/font")
local Screen = require("device").screen
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local logger = require("logger")
local _ = require("gettext")
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/BookSheet"
local N_ = _.ngettext
local C_ = _.pgettext
local T = require("ffi/util").template

if FileManager._book_hold_sheet_patched then return end
FileManager._book_hold_sheet_patched = true

local SUB_COLOR = Blitbuffer.COLOR_DARK_GRAY
local SEPARATOR = " · "

---------------------------------------------------------------------------
-- Utilidades de metadatos y cabecera
---------------------------------------------------------------------------
local function cleanText(s)
    if type(s) ~= "string" or s == "" or s == "\u{FFFF}" then return nil end
    return s
end

local function formatAuthors(authors)
    authors = cleanText(authors)
    if not authors then return nil end
    if authors:find("\n") then
        authors = authors:gsub("\n+", ", ")
    end
    return BD.auto(authors)
end

local function getBookProps(file_manager, file)
    local props
    if file_manager and file_manager.coverbrowser and file_manager.coverbrowser.getBookInfo then
        local ok, res = pcall(file_manager.coverbrowser.getBookInfo, file_manager.coverbrowser, file)
        if ok and res then props = res end
    end
    if not props then
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if ok_bim and BookInfoManager and BookInfoManager.getDocProps then
            local ok, res = pcall(BookInfoManager.getDocProps, BookInfoManager, file)
            if ok and res then props = res end
        end
    end
    if not (props and props.title) and BookList.hasBookBeenOpened(file) then
        local ok, ds = pcall(BookList.getDocSettings, file)
        local saved = ok and ds and ds:readSetting("doc_props")
        if saved then props = saved end
    end
    if FileManagerBookInfo and FileManagerBookInfo.extendProps then
        local ok, ext = pcall(FileManagerBookInfo.extendProps, props, file)
        if ok and ext then props = ext end
    end
    return props
end

local function getHeaderWidth()
    -- Hoja con el estilo nuevo (styles/ui.lua): el ancho útil lo da ella
    if ButtonDialog.aire_sheetInnerWidth then return ButtonDialog.aire_sheetInnerWidth() end
    -- Mismo ancho que el menú: como hoja inferior (styles/ui.lua, sección 11) ocupa
    -- todo el ancho menos el margen; si no, el 90 % del lado corto
    local margin = (ButtonDialog.aire_sheet_style and ButtonDialog.aire_sheet_style.margin) or 6
    local dlg_w = ButtonDialog._aire_sheet_patched
        and (Screen:getWidth() - 2 * Screen:scaleBySize(margin))
        or math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    local bt_w = dlg_w - 2 * Size.border.window - 2 * Size.padding.button
    return bt_w - 2 * (Size.padding.large + Size.margin.title)
end

local function makeHeaderSubwidget(lines, align)
    if not lines or #lines == 0 then return nil end
    local w = getHeaderWidth()
    local vg = VerticalGroup:new{ align = align or "left" }
    vg.not_focusable = true
    for i, entry in ipairs(lines) do
        if i > 1 then
            table.insert(vg, VerticalSpan:new{ width = Size.span.vertical_default })
        end
        table.insert(vg, TextBoxWidget:new{
            text = entry.text,
            width = w,
            face = Font:getFace("cfont", entry.size or 16),
            fgcolor = entry.color or SUB_COLOR,
            alignment = align or "left",
        })
    end
    return { vg }
end

---------------------------------------------------------------------------
-- 1) Ficha de LIBRO al mantener pulsado
---------------------------------------------------------------------------
-- opts:
--   owner        objeto donde se guarda .file_dialog (FileChooser o BookList)
--   ui           FileManager / ReaderUI (coverbrowser, collections)
--   file, item
--   on_status    tras cambiar el estado (Leyendo / En pausa / Terminado)
--   on_refresh   tras añadir a colección o borrar
--   remove_btn   botón extra junto a "Añadir a colección" (p. ej. Quitar del historial)
--   more         abre el diálogo completo original de KOReader
local function showBookSheetFor(opts)
    local owner, file = opts.owner, opts.file
    local props = getBookProps(opts.ui, file) or {}
    local book_info = BookList.getBookInfo(file) or {}
    local been_opened = book_info.been_opened
    local doc_settings_or_file = been_opened and BookList.getDocSettings(file) or file
    if been_opened and not props.has_cover then
        props.has_cover = true
    end

    local filename = file:match("([^/]+)$") or file
    local title = cleanText(props.title) and BD.auto(props.title) or BD.filename(filename)
    local authors = formatAuthors(props.authors)
    local series = cleanText(props.series)
    local series_idx = tonumber(props.series_index)
    local series_str = series and (series_idx and (BD.auto(series) .. " #" .. series_idx) or BD.auto(series)) or nil

    -- Línea de estado / progreso / páginas
    local meta_parts = {}
    if series_str then
        table.insert(meta_parts, series_str)
    end
    local pf = book_info.percent_finished
    local pages = book_info.pages or tonumber(props.pages)
    local status = been_opened and book_info.status or "new"
    if status == "complete" then
        table.insert(meta_parts, C_("aire", "Finished"))
    elseif status == "abandoned" then
        if pf then
            table.insert(meta_parts, T(_("%1 % (on hold)"), math.floor(pf * 100 + 0.5)))
        else
            table.insert(meta_parts, C_("aire", "On hold"))
        end
    elseif pf then
        local pct = math.floor(pf * 100 + 0.5)
        if pages and pages > 0 then
            local cur_p = math.max(1, math.floor(pages * pf + 0.5))
            table.insert(meta_parts, T(_("%1 % (%2 / %3 pp.)"), pct, cur_p, pages))
        else
            table.insert(meta_parts, string.format("%d%%", pct))
        end
    else
        table.insert(meta_parts, _("Not started"))
    end
    if pages and pages > 0 and not (pf and status == "reading") then
        table.insert(meta_parts, T(_("%1 pp."), pages))
    end

    local sub_lines = {}
    if authors then
        table.insert(sub_lines, { text = authors, size = 16 })
    end
    if #meta_parts > 0 then
        table.insert(sub_lines, { text = table.concat(meta_parts, SEPARATOR), size = 14 })
    end

    local function close_dialog()
        UIManager:close(owner.file_dialog)
    end
    local function close_dialog_status()
        UIManager:close(owner.file_dialog)
        if opts.on_status then opts.on_status() end
    end
    local function refresh()
        if opts.on_refresh then opts.on_refresh() end
    end

    local desc_btn = filemanagerutil.genBookDescriptionButton(file, props, close_dialog)
    desc_btn.text = _("Synopsis")
    local info_btn = filemanagerutil.genBookInformationButton(doc_settings_or_file, props, close_dialog)

    local coll_row = {
        opts.ui.collections:genAddToCollectionButton(file, close_dialog, refresh),
    }
    if opts.remove_btn then
        local rb = opts.remove_btn
        table.insert(coll_row, {
            text = rb.text,
            callback = function()
                UIManager:close(owner.file_dialog)
                rb.callback()
            end,
        })
    end

    local buttons = {
        filemanagerutil.genStatusButtonsRow(doc_settings_or_file, close_dialog_status),
        {},
        {
            desc_btn,
            info_btn,
        },
        coll_row,
        {},
        {
            {
                text = _("Delete"),
                callback = function()
                    UIManager:close(owner.file_dialog)
                    FileManager.showDeleteFileDialog(opts.ui.showDeleteFileDialog and opts.ui or FileManager, file, refresh)
                end,
            },
            {
                text = _("More options…"),
                callback = function()
                    UIManager:close(owner.file_dialog)
                    opts.more()
                end,
            },
        },
    }

    owner.file_dialog = ButtonDialog:new{
        title = title,
        title_align = "left",
        _added_widgets = makeHeaderSubwidget(sub_lines, "left"),
        buttons = buttons,
    }
    UIManager:show(owner.file_dialog)
    return true
end

local function showBookSheet(file_chooser, file_manager, item, orig_showFileDialog)
    local file = item.path
    local has_provider = DocumentRegistry:hasProvider(file)
    if not has_provider and not BookList.hasBookBeenOpened(file) then
        return orig_showFileDialog(file_chooser, item)
    end
    local function refresh() file_chooser:refreshPath() end
    return showBookSheetFor{
        owner = file_chooser,
        ui = file_manager,
        file = file,
        item = item,
        on_status = refresh,
        on_refresh = refresh,
        more = function() orig_showFileDialog(file_chooser, item) end,
    }
end

---------------------------------------------------------------------------
-- 2) Ficha de SERIE AUTOMÁTICA al mantener pulsado
---------------------------------------------------------------------------
-- opts (opcional, para las vistas del plugin): owner, open(), refresh() y
-- textos open_text / all_done_text / all_reading_text / confirm_text
local function showSeriesSheet(file_chooser, file_manager, group_item, opts)
    opts = opts or {}
    local function refresh()
        if opts.refresh then opts.refresh() else file_chooser:refreshPath() end
    end
    local raw_items = group_item.series_items or {}
    local books = {}
    for _, it in ipairs(raw_items) do
        if not it.is_go_up and it.path then
            table.insert(books, it)
        end
    end
    -- Sin libros solo tiene sentido si hay filas extra (p. ej. una colección vacía)
    if #books == 0 and not opts.extra_rows then return true end

    local series_name = group_item.text or _("Series")
    local authors
    local done_count, started_count = 0, 0
    local lastfile = G_reader_settings:readSetting("lastfile")
    local active_book, first_unopened

    for _, b in ipairs(books) do
        local props = getBookProps(file_manager, b.path)
        if not authors and props and cleanText(props.authors) then
            authors = formatAuthors(props.authors)
        end
        b._sheet_title = (props and cleanText(props.title)) or b.text or b.path:match("([^/]+)$")
        b._sheet_idx = tonumber(b._series_index) or (props and tonumber(props.series_index))

        local bi = BookList.getBookInfo(b.path) or {}
        local status = bi.been_opened and bi.status or "new"
        if status == "complete" then
            done_count = done_count + 1
        else
            if bi.been_opened then
                started_count = started_count + 1
                if b.path == lastfile or not active_book then
                    active_book = b
                    active_book._sheet_pf = bi.percent_finished
                end
            elseif not first_unopened then
                first_unopened = b
            end
        end
    end

    local next_book = active_book or first_unopened
    local meta_parts = { #books == 0 and _("Empty") or T(N_("%1 book", "%1 books", #books), #books) }
    if #books == 0 then
        -- nada más que contar
    elseif done_count == #books then
        table.insert(meta_parts, _("All finished"))
    elseif done_count > 0 then
        table.insert(meta_parts, T(N_("%1 finished", "%1 finished", done_count), done_count))
    elseif started_count == 0 then
        table.insert(meta_parts, _("Not started"))
    end
    if active_book and active_book._sheet_pf then
        local idx_prefix = active_book._sheet_idx and ("#" .. active_book._sheet_idx .. " ") or ""
        table.insert(meta_parts, idx_prefix .. T(_("at %1 %"), math.floor(active_book._sheet_pf * 100 + 0.5)))
    end

    local sub_lines = {}
    if authors then
        table.insert(sub_lines, { text = authors, size = 16 })
    end
    table.insert(sub_lines, { text = table.concat(meta_parts, SEPARATOR), size = 14 })

    local dialog
    local function closeDialog()
        if dialog then UIManager:close(dialog) end
    end

    local buttons = {}
    if next_book then
        local action_prefix = active_book and _("Continue") or _("Start")
        local idx_str = next_book._sheet_idx and (" (#" .. next_book._sheet_idx .. ")") or ""
        table.insert(buttons, {
            {
                text = T("%1: «%2»%3", action_prefix, BD.auto(next_book._sheet_title), idx_str),
                font_bold = true,
                callback = function()
                    closeDialog()
                    file_manager:openFile(next_book.path)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = opts.open_text or _("Open series folder"),
            callback = function()
                closeDialog()
                if opts.open then opts.open() else file_chooser:onMenuSelect(group_item) end
            end,
        },
    })
    if #books > 0 then
    table.insert(buttons, {})

    table.insert(buttons, {
        {
            text = opts.all_done_text or _("Mark entire series as finished"),
            enabled = done_count < #books,
            callback = function()
                closeDialog()
                for _, b in ipairs(books) do
                    -- Solo libros reales (los de prueba "demo://" crearían carpetas .sdr basura)
                    if not b.fake and b.path and not b.path:find("^%a+://") then
                        local ds = BookList.getDocSettings(b.path)
                        local summary = ds:readSetting("summary") or {}
                        summary.status = "complete"
                        filemanagerutil.saveSummary(ds, summary)
                        BookList.setBookInfoCacheProperty(b.path, "status", "complete")
                    end
                end
                refresh()
            end,
        },
    })

    table.insert(buttons, {
        {
            text = opts.all_reading_text or _("Mark entire series as reading"),
            enabled = done_count > 0 or started_count > 0,
            callback = function()
                closeDialog()
                UIManager:show(ConfirmBox:new{
                    text = T(opts.confirm_text or _("Mark all books in \"%1\" as reading?"), BD.auto(series_name)),
                    ok_text = _("Mark"),
                    ok_callback = function()
                        for _, b in ipairs(books) do
                            -- Solo libros reales (los de prueba "demo://" crearían carpetas .sdr basura)
                            if not b.fake and b.path and not b.path:find("^%a+://") then
                                local ds = BookList.getDocSettings(b.path)
                                local summary = ds:readSetting("summary") or {}
                                summary.status = "reading"
                                filemanagerutil.saveSummary(ds, summary)
                                BookList.setBookInfoCacheProperty(b.path, "status", "reading")
                            end
                        end
                        refresh()
                    end,
                })
            end,
        },
    })
    end -- #books > 0

    -- Filas extra del que la abre (gestión de la colección, etc.): se cierra
    -- la ficha antes de su acción
    if opts.extra_rows and #opts.extra_rows > 0 then
        table.insert(buttons, {})
        for _i, row in ipairs(opts.extra_rows) do
            local new_row = {}
            for _j, b in ipairs(row) do
                local cb = b.callback
                table.insert(new_row, {
                    text = b.text, enabled = b.enabled,
                    callback = function()
                        closeDialog()
                        if cb then cb() end
                    end,
                })
            end
            table.insert(buttons, new_row)
        end
    end

    dialog = ButtonDialog:new{
        title = BD.auto(series_name),
        title_align = "left",
        _added_widgets = makeHeaderSubwidget(sub_lines, "left"),
        buttons = buttons,
    }
    local owner = opts.owner or file_chooser
    owner.file_dialog = dialog
    UIManager:show(dialog)
    return true
end

---------------------------------------------------------------------------
-- Enganche en FileManager:setupLayout
---------------------------------------------------------------------------
local function patchFileChooserDialogs(file_manager)
    local fc = file_manager.file_chooser
    if not fc or fc._book_hold_sheet_patched then return end
    fc._book_hold_sheet_patched = true

    local orig_showFileDialog = fc.showFileDialog
    fc._aire_orig_showFileDialog = orig_showFileDialog -- para "Más opciones…" desde la Librería
    function fc:showFileDialog(item)
        if item and item.is_file and not file_manager.selected_files then
            local ok, res = pcall(showBookSheet, self, file_manager, item, orig_showFileDialog)
            if ok then return res end
            logger.warn("Aire/BookSheet: error al abrir ficha de libro:", res)
        end
        return orig_showFileDialog(self, item)
    end

    -- Lo llama el parche de la comunidad "Automatic Book Series" (si está
    -- instalado) al mantener pulsada una de sus carpetas de serie
    function fc:onSeriesHold(item)
        if file_manager.selected_files then return true end
        local ok, res = pcall(showSeriesSheet, self, file_manager, item)
        if not ok then
            logger.warn("Aire/BookSheet: error al abrir ficha de serie:", res)
        end
        return true
    end
end

safeWrap(FileManager, "setupLayout", function(orig_setupLayout, self, ...)
    local res = orig_setupLayout(self, ...)
    patchFileChooserDialogs(self)
    return res
end, TAG)

---------------------------------------------------------------------------
-- Misma ficha en Historial y en Favoritos / colecciones
---------------------------------------------------------------------------
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local ReadCollection = require("readcollection")

-- El libro abierto en el lector (Historial desde el lector) usa otra fuente de
-- datos (ui.doc_settings): para ese caso se deja el diálogo original.
local function isCurrentlyOpened(ui, file)
    return ui and ui.document and ui.document.file == file
end

-- En estos onMenuHold, self es el BookList y self._manager el módulo.
safeWrap(FileManagerHistory, "onMenuHold", function(orig_History_onMenuHold, self, item)
    local menu, manager = self, self._manager
    if not (manager and manager.ui and item and item.file) or item.dim
            or isCurrentlyOpened(manager.ui, item.file) then
        return orig_History_onMenuHold(self, item)
    end
    local function update()
        if manager.filter ~= "all" or manager.is_frozen then
            manager:fetchStatuses(false)
        else
            manager.statuses_fetched = false
        end
        manager:updateItemTable()
        manager.files_updated = true
    end
    local ok, res = pcall(showBookSheetFor, {
        owner = menu,
        ui = manager.ui,
        file = item.file,
        item = item,
        on_status = update,
        on_refresh = update,
        remove_btn = {
            text = _("Remove from history"),
            callback = function()
                -- idx solo es válido si la vista no está filtrada (igual que KOReader)
                local index = item.idx
                if manager.search_string or manager.selected_collections or manager.filter ~= "all" then
                    index = nil
                end
                require("readhistory"):removeItem(item, index)
                manager:updateItemTable()
            end,
        },
        more = function() orig_History_onMenuHold(menu, item) end,
    })
    if ok then return res end
    logger.warn("Aire/BookSheet: error en la ficha del historial:", res)
    return orig_History_onMenuHold(self, item)
end, TAG)

safeWrap(FileManagerCollection, "onMenuHold", function(orig_Collection_onMenuHold, self, item)
    local menu, manager = self, self._manager
    if not (manager and manager.ui and item and item.file) or manager.selected_files
            or isCurrentlyOpened(manager.ui, item.file) then
        return orig_Collection_onMenuHold(self, item)
    end
    local function update()
        manager:updateItemTable()
        manager.files_updated = true
    end
    local ok, res = pcall(showBookSheetFor, {
        owner = menu,
        ui = manager.ui,
        file = item.file,
        item = item,
        on_status = update,
        on_refresh = update,
        remove_btn = {
            text = C_("aire", "Remove from collection"),
            callback = function()
                manager.updated_collections[menu.path] = true
                ReadCollection:removeItem(item.file, menu.path, true)
                update()
            end,
        },
        more = function() orig_Collection_onMenuHold(menu, item) end,
    })
    if ok then return res end
    logger.warn("Aire/BookSheet: error en la ficha de la colección:", res)
    return orig_Collection_onMenuHold(self, item)
end, TAG)

-- Para la vista Librería del plugin
FileManager.aire_showBookSheetFor = showBookSheetFor
FileManager.aire_showSeriesSheet = function(file_manager, group_item, opts)
    return showSeriesSheet(file_manager.file_chooser, file_manager, group_item, opts)
end

logger.dbg("Aire/BookSheet: aplicado desde el plugin")
