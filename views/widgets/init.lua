--[[
    aire.koplugin/views/widgets/init.lua
    Zona de widgets de Inicio (debajo de "Leyendo ahora").

    Cuadrícula de 4 columnas por fila; cada widget ocupa 1 celda (pequeño) o
    2 (grande, si la celda de la derecha está libre). El nº de filas depende del
    espacio entre la tarjeta y el dock (hasta MAX_ROWS); el alto se ajusta.

    Submódulos en views/widgets/:
      parts.lua    formatos, utilidades y piezas (OptionSheet, WidgetSlot, WidgetCell)
      catalog.lua  catálogo de definiciones de widgets (W, ORDER)
      picker.lua   presets, galería de pruebas, selector, opciones y modo edición

    Se guarda en config.home_widgets["fila:columna"] =
        { id, span, invert, swap, hold_tap, period }

    Se carga desde main.lua como "mixin". OJO: no usar "_" como variable.
--]]

local Blitbuffer = require("ffi/blitbuffer")

local BLACK = Blitbuffer.COLOR_BLACK
local WHITE = Blitbuffer.COLOR_WHITE
local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

local COLS = 4
local MAX_ROWS = 3
local MIN_CELL_H = 84   -- por debajo de esto no se añade otra fila
local MAX_CELL_H = 150  -- las celdas no crecen más

-- Colores: normal y con "Colores invertidos"
local THEME_NORMAL = { bg = WHITE, fg = BLACK, fg2 = GRAY_TEXT, border = BLACK, inverted = false }
local THEME_INVERTED = { bg = BLACK, fg = WHITE, fg2 = Blitbuffer.COLOR_GRAY_B, border = BLACK, inverted = true }

local WIDGETS_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)/[^/]*$") or "plugins/aire.koplugin/views/widgets"
-- Formatos, utilidades y piezas (hoja de opciones, hueco, celda)
local Parts = dofile(WIDGETS_DIR .. "/parts.lua")
local fileExists = Parts.fileExists
local themedIcon, OptionSheet, WidgetSlot, WidgetCell = Parts.themedIcon, Parts.OptionSheet, Parts.WidgetSlot, Parts.WidgetCell
local CatalogFactory = dofile(WIDGETS_DIR .. "/catalog.lua")
local PickerFactory = dofile(WIDGETS_DIR .. "/picker.lua")

return function(Aire, ctx)
    -- Módulos que usa el mixin, declarados aquí dentro: así no cuentan como
    -- upvalues de esta función (LuaJIT admite 60). require devuelve el
    -- mismo módulo que arriba.
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local ImageWidget = require("ui/widget/imagewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local logger = require("logger")
    local _ = require("gettext")
    local BLACK = Blitbuffer.COLOR_BLACK
    local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

    local S, face, config, saveConfig, tappable = ctx.S, ctx.face, ctx.config, ctx.saveConfig, ctx.tappable

    function Aire:showOptionSheet(title, rows_fn, buttons, on_close, columns)
        local sheet = OptionSheet:new{
            title = title, rows_fn = rows_fn, buttons = buttons, columns = columns,
            S = S, face = face, tappable = tappable, on_close = on_close,
        }
        UIManager:show(sheet, "ui")
        return sheet
    end

    ---------------------------------------------------------------------
    -- Caché de los widgets costosos (cache = true: estadísticas, serie,
    -- historial) y de sus portadas. Inicio se redibuja a menudo (wifi,
    -- cargador, luz…) sin que esos datos cambien. La caché se vacía:
    --   · al volver a Inicio desde otra pestaña (showHome),
    --   · tras una acción que cambia datos (refreshSoon con invalidate),
    --   · al cambiar de día, y al volver de un libro (FileManager nuevo).
    ---------------------------------------------------------------------
    function Aire:invalidateWidgetData()
        self._w_cache = nil
        if self.freeWidgetCovers then self:freeWidgetCovers() end
    end

    local function widgetData(self, w, opts)
        if not w.cache then return pcall(w.data, self, opts) end
        local day = os.date("%Y-%m-%d")
        local c = self._w_cache
        if not c or c._day ~= day then
            c = { _day = day }
            self._w_cache = c
        end
        local key = w.id .. "|" .. tostring(opts.period or "") .. (config.demo_stats and "|demo" or "")
        if c[key] == nil then
            local ok, d = pcall(w.data, self, opts)
            if not ok then return false, d end -- los errores no se guardan: se reintenta
            c[key] = d or false
        end
        return true, c[key] or nil
    end

    -- Refrescar Inicio. invalidate = true tras una acción que cambia los datos
    -- (estado de un libro…); sin él (wifi, luz, cargador) se reutiliza la caché.
    local function refreshSoon(self, delay, invalidate)
        UIManager:scheduleIn(delay or 0.5, function()
            if self:isHomeVisible() then
                if invalidate then self:invalidateWidgetData() end
                self:apply()
                UIManager:setDirty(self.ui, "ui")
            end
        end)
    end

    local function docProps(self, file)
        local props = {}
        if self.ui.bookinfo and file then
            local ok, p = pcall(self.ui.bookinfo.getDocProps, self.ui.bookinfo, file, nil, true)
            if ok and type(p) == "table" then props = p end
        end
        props.title = props.display_title or props.title or (file and file:match("([^/]+)$")) or "?"
        return props
    end

    local function openBook(self, file)
        if fileExists(file) then filemanagerutil.openFile(self.ui, file) end
    end

    -- Ficha del libro (booksheet.lua) o, si no está, la información del libro
    local function bookSheet(self, file)
        if not fileExists(file) then return end
        local show = require("apps/filemanager/filemanager").aire_showBookSheetFor
        if show then
            local ok = pcall(show, {
                owner = self, ui = self.ui, file = file,
                item = { path = file, is_file = true, text = file:match("([^/]+)$") },
                on_status = function() refreshSoon(self, 0, true) end,
                on_refresh = function() refreshSoon(self, 0, true) end,
                -- "Más opciones…": el menú completo de KOReader (el del explorador)
                more = function()
                    local fc = self.ui.file_chooser
                    if fc and fc._aire_orig_showFileDialog then
                        fc._aire_orig_showFileDialog(fc, { path = file, is_file = true, text = file:match("([^/]+)$") })
                    elseif self.ui.bookinfo then
                        self.ui.bookinfo:show(file)
                    end
                end,
            })
            if ok then return end
        end
        if self.ui.bookinfo then self.ui.bookinfo:show(file) end
    end

    -- Menú del libro (el mismo que al mantener un libro en la Librería)
    function Aire:showBookMenu(file) return bookSheet(self, file) end

    -- Catálogo de widgets (views/widgets/catalog.lua)
    local Catalog = CatalogFactory({
        config = config, saveConfig = saveConfig, Parts = Parts,
        refreshSoon = refreshSoon, docProps = docProps, openBook = openBook, bookSheet = bookSheet,
    })
    local W, ORDER = Catalog.W, Catalog.ORDER

    ---------------------------------------------------------------------
    -- Dibujo
    ---------------------------------------------------------------------
    local function coverThumb(self, path, max_w, max_h, bg)
        local bb = self.getWidgetCover and self:getWidgetCover(path)
        if not bb then return nil end
        local rounded = config.rounded_covers == true
        local border = Size.border.thin
        return FrameContainer:new{
            bordersize = border, color = Blitbuffer.COLOR_GRAY, padding = 0, margin = 0,
            radius = rounded and S(6) or 0, _aire_clip_corners = rounded,
            _aire_clip_bg = bg,
            ImageWidget:new{
                image = bb, image_disposable = false,
                scale_factor = math.min((max_w - 2 * border) / bb:getWidth(), (max_h - 2 * border) / bb:getHeight()),
            },
        }
    end

    local function buildContent(self, w, size, d, cw, ch, theme)
        local pad = S(10)
        local iw, ih = cw - 2 * pad, ch - 2 * pad
        -- Pequeño con libro: portada + etiqueta corta debajo
        if size == "S" and d.file then
            local lbl = TextWidget:new{ text = d.small_sub or d.label or "", face = face(false, 11),
                fgcolor = theme.fg2, max_width = iw, padding = 0 }
            local img_h = math.max(1, ih - lbl:getSize().h - S(4))
            local cover = coverThumb(self, d.file, iw, img_h, theme.bg) or TextBoxWidget:new{
                text = d.title or "?", face = face(true, 12), width = iw, alignment = "center",
                fgcolor = theme.fg, bgcolor = theme.bg,
                height = img_h, height_adjust = true, height_overflow_show_ellipsis = true,
            }
            return CenterContainer:new{
                dimen = Geom:new{ w = cw, h = ch },
                VerticalGroup:new{ align = "center", cover, VerticalSpan:new{ width = S(4) }, lbl },
            }
        end
        -- Pequeño: icono, valor y etiqueta
        if size == "S" then
            local vg = VerticalGroup:new{ align = "center" }
            table.insert(vg, themedIcon(theme, w.icon, S(24)))
            table.insert(vg, VerticalSpan:new{ width = S(4) })
            local main_s = d.value or d.title
            if main_s then
                table.insert(vg, TextWidget:new{ text = main_s, face = face(true, 14), fgcolor = theme.fg, max_width = iw, padding = 0 })
            end
            local lbl = d.small_sub or d.label
            if lbl then
                table.insert(vg, TextWidget:new{ text = lbl, face = face(false, 11), fgcolor = theme.fg2, max_width = iw, padding = 0 })
            end
            return CenterContainer:new{ dimen = Geom:new{ w = cw, h = ch }, vg }
        end
        -- Grande con cita
        if d.quote then
            local src = TextWidget:new{ text = "— " .. (d.sub or ""), face = face(false, 11), fgcolor = theme.fg2, max_width = iw, padding = 0 }
            local box = TextBoxWidget:new{
                text = "«" .. d.quote .. "»", face = Font:getFace("cfont", 13), width = iw,
                fgcolor = theme.fg, bgcolor = theme.bg,
                height = ih - src:getSize().h - S(4), height_overflow_show_ellipsis = true,
            }
            return CenterContainer:new{
                dimen = Geom:new{ w = cw, h = ch },
                VerticalGroup:new{ align = "left", box, VerticalSpan:new{ width = S(4) }, src },
            }
        end
        -- Grande: portada (libros) o icono, y textos a la derecha
        local left
        if d.file then left = coverThumb(self, d.file, math.floor(ih * 0.7), ih, theme.bg) end
        if not left and d.covers and #d.covers > 0 then
            local hg = HorizontalGroup:new{ align = "center" }
            for i = 1, math.min(3, #d.covers) do
                local th = coverThumb(self, d.covers[i].path, math.floor(ih * 0.5), math.floor(ih * 0.8), theme.bg)
                if th then
                    if #hg > 0 then table.insert(hg, HorizontalSpan:new{ width = S(4) }) end
                    table.insert(hg, th)
                end
            end
            if #hg > 0 then left = hg end
        end
        if not left then left = themedIcon(theme, w.icon, S(30)) end
        local tw = iw - left:getSize().w - S(10)
        local col = VerticalGroup:new{ align = "left" }
        if d.label then
            table.insert(col, TextWidget:new{ text = d.label:upper(), face = face(true, 10), fgcolor = theme.fg2, max_width = tw, padding = 0 })
            table.insert(col, VerticalSpan:new{ width = S(2) })
        end
        local main_text = d.title or d.value
        if main_text then
            table.insert(col, TextWidget:new{ text = main_text, face = face(true, d.title and 14 or 17), fgcolor = theme.fg, max_width = tw, padding = 0 })
        end
        if d.sub then
            table.insert(col, VerticalSpan:new{ width = S(2) })
            table.insert(col, TextWidget:new{ text = d.sub, face = face(false, 12), fgcolor = theme.fg2, max_width = tw, padding = 0 })
        end
        return LeftContainer:new{
            dimen = Geom:new{ w = cw, h = ch },
            HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = pad }, left, HorizontalSpan:new{ width = S(10) }, col },
        }
    end

    -- Acciones efectivas según las opciones (Mantener = tocar / Intercambiar)
    local function actionsFor(w, opts)
        local tap, hold = w.tap, w.hold
        if opts.hold_tap and not w.hold then hold = w.tap end
        if opts.swap and not opts.hold_tap then tap, hold = hold, tap end
        return tap, hold
    end

    function Aire:buildWidgetCell(opts, size, width, height, key)
        local w = W[opts.id]
        local ok, d = widgetData(self, w, opts)
        if not ok then
            logger.warn("Aire/Widgets: error en", opts.id, d)
            d = { value = "—", label = w.title }
        end
        -- Pruebas: datos inventados (devtools.lua, "Widgets de prueba")
        if self._demo_widget_data then
            local ok_f, fd = pcall(self._demo_widget_data, opts.id)
            if ok_f and fd then d = fd end
        end
        d = d or {}
        local theme = opts.invert and THEME_INVERTED or THEME_NORMAL
        local border = Size.border.thin
        local cw, ch = width - 2 * border, height - 2 * border
        local ok_c, content = pcall(buildContent, self, w, size, d, cw, ch, theme)
        if not ok_c then
            logger.warn("Aire/Widgets: error dibujando", opts.id, content)
            content = CenterContainer:new{ dimen = Geom:new{ w = cw, h = ch },
                TextWidget:new{ text = w.title, face = face(false, 12), fgcolor = theme.fg2, padding = 0 } }
        end
        local tap, hold = actionsFor(w, opts)
        local function run(fn, what)
            if not fn then return end
            local ok_t, err = pcall(fn, self, d, opts)
            if not ok_t then logger.warn("Aire/Widgets: error al", what, opts.id, err) end
        end
        local cell = WidgetCell:new{
            width = width, height = height,
            on_tap = function()
                if self._widgets_edit then return self:showWidgetOptions(key) end
                run(tap, "tocar")
            end,
            on_hold = function()
                if self._widgets_edit then return self:showWidgetOptions(key) end
                run(hold, "mantener")
            end,
        }
        cell[1] = FrameContainer:new{
            bordersize = border, color = theme.border, background = theme.bg,
            radius = S(12), padding = 0, margin = 0, width = width, height = height,
            content,
        }
        return cell
    end

    ---------------------------------------------------------------------
    -- Zona de widgets
    ---------------------------------------------------------------------
    local Picker
    local function placed()
        if config.home_widgets == nil then
            -- Primera instalación: preset por defecto (se guarda para que no cambie)
            config.home_widgets = Picker.presetWidgets(Picker.DEFAULT_PRESET) or {}
            saveConfig()
        elseif type(config.home_widgets) ~= "table" then
            config.home_widgets = {}
        end
        return config.home_widgets
    end

    local function available(self, w)
        if w.cond and not w.cond(self) then return false end
        return true
    end

    -- Presets, galería, selector, opciones y edición (views/widgets/picker.lua)
    Picker = PickerFactory({
        W = W, ORDER = ORDER, COLS = COLS,
        config = config, saveConfig = saveConfig, ctx = ctx,
        placed = placed, available = available,
    })
    Picker.install(Aire)

    -- Widgets disponibles en este dispositivo, en el orden del selector
    -- (lo usan los tests automáticos de dev/ para comprobar que salen todos)
    function Aire:getWidgetDefs()
        local list = {}
        for _i, id in ipairs(ORDER) do
            local w = W[id]
            if w and available(self, w) then
                table.insert(list, { id = id, title = w.title, icon = w.icon, needs_large = w.needs_large and true or false,
                    has_tap = w.tap ~= nil, has_hold = w.hold ~= nil, has_options = w.options ~= nil })
            end
        end
        return list
    end

    function Aire:buildWidgetArea(w, avail_h)
        -- (Las portadas no se liberan aquí: se reutilizan entre redibujos; ver
        -- invalidateWidgetData)
        local editing = self._widgets_edit
        local area = VerticalGroup:new{ align = "left" }
        if editing then
            local bar_h = S(30)
            local done = TextWidget:new{ text = _("Done"), face = face(true, 14), fgcolor = BLACK, padding = 0 }
            table.insert(area, OverlapGroup:new{
                dimen = Geom:new{ w = w, h = bar_h },
                LeftContainer:new{ dimen = Geom:new{ w = w, h = bar_h },
                    TextWidget:new{ text = _("EDITING WIDGETS"), face = face(true, 12), fgcolor = GRAY_TEXT, padding = 0 } },
                RightContainer:new{ dimen = Geom:new{ w = w, h = bar_h },
                    tappable(done, function() self:setWidgetsEdit(false) end, nil, { h = S(14), v = S(10) }) },
            })
            table.insert(area, VerticalSpan:new{ width = S(8) })
            avail_h = avail_h - bar_h - S(8)
        end
        local gap = S(ctx.WIDGET_GAP or 14)
        local col_w = math.floor((w - (COLS - 1) * gap) / COLS)
        local rem_w = w - (COLS - 1) * gap - COLS * col_w
        local function colWidth(col) return col_w + (col <= rem_w and 1 or 0) end
        local rows = math.min(MAX_ROWS, math.floor((avail_h + gap) / (S(MIN_CELL_H) + gap)))
        if rows < 1 then return nil end
        local cell_h = math.min(S(MAX_CELL_H), math.floor((avail_h - (rows - 1) * gap) / rows))

        local P = placed()
        -- Pruebas: rellenar las celdas libres con widgets (por tandas) y datos inventados
        self._demo_widget_data = nil
        local TEST = self.getTestTools and self:getTestTools()
        if config.demo_widgets and TEST and TEST.fakeWidgetData then
            local books = {}
            for _i, b in ipairs(self.getLibraryBooks and self:getLibraryBooks() or {}) do
                if not b.fake and #books < 6 then table.insert(books, b.path) end
            end
            self._demo_widget_data = function(id) return TEST.fakeWidgetData(id, books) end
            local ids = {}
            for _i, id in ipairs(ORDER) do
                if available(self, W[id]) then table.insert(ids, id) end
            end
            local n = #ids
            local next_i = ((config.demo_widgets_offset or 0) % math.max(1, n)) + 1
            local demo = {}
            for k, v in pairs(P) do demo[k] = v end
            for r = 1, rows do
                local c = 1
                while c <= COLS do
                    local key = r .. ":" .. c
                    local existing = demo[key]
                    if existing and W[existing.id] then
                        c = c + (((existing.span == 2 or W[existing.id].needs_large) and c < COLS) and 2 or 1)
                    else
                        local id = ids[next_i]
                        next_i = next_i % n + 1
                        local wd = W[id]
                        local free_right = c < COLS and not demo[r .. ":" .. (c + 1)]
                        if wd.needs_large and not free_right then
                            id = ids[next_i]; next_i = next_i % n + 1; wd = W[id]
                        end
                        -- alternar: en las filas pares, widgets grandes si caben
                        local span = (wd.needs_large or (r % 2 == 1 and free_right and c % 2 == 1)) and free_right and 2 or 1
                        demo[key] = { id = id, span = span }
                        c = c + span
                    end
                end
            end
            P = demo
        end
        for r = 1, rows do
            if r > 1 then table.insert(area, VerticalSpan:new{ width = gap }) end
            local row = HorizontalGroup:new{ align = "top" }
            local c = 1
            while c <= COLS do
                if c > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                local key = r .. ":" .. c
                local opts = P[key]
                local wdef = opts and W[opts.id]
                if wdef and available(self, wdef) then
                    local span = ((opts.span == 2 or wdef.needs_large) and c < COLS) and 2 or 1
                    local width = span == 2 and (colWidth(c) + colWidth(c + 1) + gap) or colWidth(c)
                    table.insert(row, self:buildWidgetCell(opts, span == 2 and "L" or "S", width, cell_h, key))
                    c = c + span
                else
                    local cw = colWidth(c)
                    if editing then
                        local k = key
                        table.insert(row, WidgetSlot:new{ width = cw, height = cell_h,
                            on_tap = function() self:showWidgetPicker(k) end })
                    else
                        table.insert(row, HorizontalSpan:new{ width = cw }) -- invisible
                    end
                    c = c + 1
                end
            end
            table.insert(area, row)
        end
        return area
    end

    -- La luz cambió (gesto, botón, diálogo): actualizar los widgets
    function Aire:refreshWidgets()
        if self:isHomeVisible() then refreshSoon(self, 0.3) end
    end
end
