--[[
    aire.koplugin/views/home.lua
    Pantalla de Inicio: libro en curso, portada, tarjeta "Leyendo ahora"
    y montaje de la pantalla (los widgets están en views/widgets/init.lua).
    Se carga desde main.lua como "mixin" (añade métodos a Aire).
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

return function(Aire, ctx)
    -- Módulos y valores compartidos declarados aquí dentro: así no cuentan
    -- como upvalues de esta función (LuaJIT admite 60).
    local Blitbuffer = require("ffi/blitbuffer")
    local BookList = require("ui/widget/booklist")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local ImageWidget = require("ui/widget/imagewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local ProgressWidget = require("ui/widget/progresswidget")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local lfs = require("libs/libkoreader-lfs")
    local logger = require("logger")
    local util = require("util")
    local _ = require("gettext")
    local C_ = _.pgettext
    local T = require("ffi/util").template
    local Screen = Device.screen
    local S = ctx.S
    local face = ctx.face
    local tappable = ctx.tappable
    local config = ctx.config
    local saveConfig = ctx.saveConfig
    local BLACK = ctx.BLACK
    local WHITE = ctx.WHITE
    local GRAY_TEXT = ctx.GRAY_TEXT
    local TOP_PAD = ctx.TOP_PAD
    local SIDE_PAD = ctx.SIDE_PAD
    local DOCK_MARGIN_BOTTOM = ctx.DOCK_MARGIN_BOTTOM
    local WIDGET_GAP = ctx.WIDGET_GAP

    ---------------------------------------------------------------------------
    -- Libro en curso
    ---------------------------------------------------------------------------
    local function formatSeriesIndex(idx)
        local n = tonumber(idx)
        if not n then return tostring(idx) end
        if n == math.floor(n) then return ("%d"):format(n) end
        return tostring(n)
    end

    local function getCurrentBook(fm)
        local file = G_reader_settings:readSetting("lastfile")
        if not file or lfs.attributes(file, "mode") ~= "file" then return nil end

        local props
        if fm.bookinfo then
            local ok, p = pcall(fm.bookinfo.getDocProps, fm.bookinfo, file, nil, true)
            if ok and type(p) == "table" then props = p end
        end
        props = props or {}

        -- Releer el sidecar una vez por libro y FileManager (al volver del lector
        -- el FileManager es nuevo). Después KOReader mantiene la caché al día
        -- (estado, progreso del pie) y no hace falta leer el .sdr en cada redibujo.
        if fm._aire_card_fresh ~= file then
            BookList.resetBookInfoCache(file)
            fm._aire_card_fresh = file
        end
        local info = BookList.getBookInfo(file) or {}

        local percent = tonumber(info.percent_finished) or 0
        if info.status == "complete" then percent = 1 end
        local pages = tonumber(info.pages) or tonumber(props.pages)

        local authors = props.authors
        if type(authors) == "string" then
            authors = authors:gsub("\n", ", ")
            if authors == "" then authors = nil end
        else
            authors = nil
        end

        local series
        if type(props.series) == "string" and props.series ~= "" then
            series = props.series
            if props.series_index then
                series = series .. " #" .. formatSeriesIndex(props.series_index)
            end
        end

        local filename = filemanagerutil.splitFileNameType(file)
        return {
            file = file,
            title = props.display_title or props.title or filename or file,
            authors = authors,
            series = series,
            percent = math.max(0, math.min(1, percent)),
            pages = pages,
            status = info.status,
            description = props.description,
        }
    end

    -- La portada se lee de la caché de CoverBrowser y se guarda mientras sea el
    -- mismo libro (no se libera en cada redibujado).
    local cover_cache = { file = nil, bb = nil }

    local function getCoverBB(file)
        if cover_cache.file == file then return cover_cache.bb end
        if cover_cache.bb then
            cover_cache.bb:free()
            cover_cache.bb = nil
        end
        cover_cache.file = nil
        local ok, BookInfoManager = pcall(require, "bookinfomanager")
        if not ok or type(BookInfoManager) ~= "table" then return nil end
        local ok2, bi = pcall(BookInfoManager.getBookInfo, BookInfoManager, file, true)
        if ok2 and bi then
            cover_cache.file = file -- ya se buscó (haya portada o no)
            if bi.has_cover and bi.cover_bb then
                cover_cache.bb = bi.cover_bb
            end
        end
        return cover_cache.bb
    end

    function Aire:buildCover(book, max_w, max_h, theme)
        local bb = getCoverBB(book.file)
        local border = Size.border.thin
        if bb then
            local scale = math.min((max_w - 2 * border) / bb:getWidth(), (max_h - 2 * border) / bb:getHeight())
            -- Marco muy fino y claro alrededor de la portada
            return FrameContainer:new{
                bordersize = border,
                color = Blitbuffer.COLOR_LIGHT_GRAY,
                radius = config.rounded_covers and S(8) or 0,
                _aire_clip_corners = config.rounded_covers == true,
                _aire_clip_bg = theme.bg,
                padding = 0,
                margin = 0,
                ImageWidget:new{
                    image = bb,
                    image_disposable = false,
                    scale_factor = scale,
                },
            }
        end
        -- Sin portada: recuadro con el título (colores contrarios a la tarjeta)
        local cw = math.floor(max_h * 2 / 3)
        local box_bg = theme.dark and WHITE or BLACK
        local box_fg = theme.dark and BLACK or WHITE
        return FrameContainer:new{
            bordersize = 0,
            padding = 0,
            margin = 0,
            background = box_bg,
            radius = config.rounded_covers and S(8) or S(4),
            width = cw,
            height = max_h,
            CenterContainer:new{
                dimen = Geom:new{ w = cw, h = max_h },
                TextBoxWidget:new{
                    text = book.title,
                    face = face(true, 14),
                    fgcolor = box_fg,
                    bgcolor = box_bg,
                    alignment = "center",
                    width = cw - 2 * S(8),
                    height = max_h - 2 * S(8),
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                },
            },
        }
    end

    -- Sinopsis sin HTML ni espacios raros (saltos, tabuladores, espacios dobles)
    local function cleanSynopsis(text)
        if type(text) ~= "string" or text == "" then return nil end
        local ok, plain = pcall(util.htmlToPlainTextIfHtml, text)
        text = ok and plain or text
        text = text:gsub("\u{00A0}", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then return nil end
        return text
    end

    -- Opciones de la tarjeta en el modo edición
    function Aire:showCardOptions()
        if not self.showOptionSheet then return end
        local function set(field, value, sheet)
            config[field] = value
            saveConfig()
            self:apply()
            UIManager:setDirty(self.ui, "ui")
            if sheet then sheet:rebuild() end
        end
        self:showOptionSheet(_("Currently reading"), function()
            return {
                -- Igual que en los widgets: "Colores invertidos" (por defecto activado)
                { text = _("Inverted colors"), checked = not config.card_white,
                  callback = function(sheet) set("card_white", not config.card_white, sheet) end },
                { text = _("Show synopsis"), checked = config.card_synopsis and true or false,
                  callback = function(sheet) set("card_synopsis", not config.card_synopsis, sheet) end },
            }
        end, { { text = _("Done"), primary = true, callback = function(sheet) sheet:close() end } })
    end

    function Aire:buildCard(w)
        local fm = self.ui
        local pad = S(14)
        -- Colores: por defecto invertida (fondo negro); se cambia con "Colores invertidos" en edición
        local dark = not config.card_white
        local border = dark and 0 or Size.border.thin
        local inner_w = w - 2 * (pad + border)
        local theme = {
            dark = dark,
            bg = dark and BLACK or WHITE,
            fg = dark and WHITE or BLACK,
            fg2 = dark and Blitbuffer.COLOR_GRAY_B or GRAY_TEXT,
            track = dark and Blitbuffer.colorFromString("#4A4A4A") or Blitbuffer.COLOR_GRAY_D,
            fill = dark and Blitbuffer.COLOR_GRAY_D or Blitbuffer.COLOR_DARK_GRAY,
        }
        local book = getCurrentBook(fm)

        local function frame(content)
            return FrameContainer:new{
                bordersize = border,
                color = BLACK,
                background = theme.bg,
                radius = S(12),
                padding = pad,
                content,
            }
        end

        if not book then
            local empty = VerticalGroup:new{
                align = "center",
                TextWidget:new{ text = _("No book in progress"), face = face(true, 18), fgcolor = theme.fg, padding = 0 },
                VerticalSpan:new{ width = S(6) },
                TextWidget:new{ text = _("Tap to open the library"), face = face(false, 14), fgcolor = theme.fg2, padding = 0 },
            }
            return tappable(frame(CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = S(120) }, empty }), function()
                if self._widgets_edit then return self:showCardOptions() end
                self:showGridView("library")
            end)
        end

        local cover_h = S(170)
        local cover = self:buildCover(book, math.floor(inner_w * 0.38), cover_h, theme)
        local cover_w = cover:getSize().w
        local gap = S(16)
        local col_w = inner_w - cover_w - gap

        -- Arriba: título, autor y serie
        local top = VerticalGroup:new{ align = "left" }
        table.insert(top, TextBoxWidget:new{
            text = book.title,
            face = face(true, 18),
            fgcolor = theme.fg,
            bgcolor = theme.bg,
            width = col_w,
            height = face(true, 18).size * 3, -- como mucho ~2 líneas
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        })
        if book.authors then
            table.insert(top, VerticalSpan:new{ width = S(2) })
            table.insert(top, TextWidget:new{ text = book.authors, face = face(false, 15), fgcolor = theme.fg2, max_width = col_w, padding = 0 })
        end
        if book.series then
            table.insert(top, VerticalSpan:new{ width = S(2) })
            table.insert(top, TextWidget:new{ text = book.series, face = face(false, 13), fgcolor = theme.fg2, max_width = col_w, padding = 0 })
        end

        -- Abajo: barra sin borde (grises) y "54% leído · Pág. x / y"
        local bar_h = S(8)
        local progress = ProgressWidget:new{
            width = col_w,
            height = bar_h,
            percentage = book.percent,
            fillcolor = theme.fill,
            bgcolor = theme.track,
            bordersize = 0,
            radius = math.floor(bar_h / 2),
            margin_h = 0,
            margin_v = 0,
        }
        local pct_text = book.status == "complete" and C_("aire", "Finished")
            or T(_("%1 % read"), math.floor(book.percent * 100 + 0.5))
        local info_left = TextWidget:new{ text = pct_text, face = face(true, 13), fgcolor = theme.fg, padding = 0 }
        local info_h = info_left:getSize().h
        local info_row = OverlapGroup:new{
            dimen = Geom:new{ w = col_w, h = info_h },
            LeftContainer:new{ dimen = Geom:new{ w = col_w, h = info_h }, info_left },
        }
        if book.pages and book.pages > 0 then
            local cur = math.max(1, math.min(book.pages, math.floor(book.percent * book.pages + 0.5)))
            table.insert(info_row, RightContainer:new{
                dimen = Geom:new{ w = col_w, h = info_h },
                TextWidget:new{ text = T(C_("aire", "Page %1 / %2"), cur, book.pages), face = face(false, 13), fgcolor = theme.fg2, padding = 0 },
            })
        end
        local bottom = VerticalGroup:new{ align = "left", progress, VerticalSpan:new{ width = S(6) }, info_row }

        -- En medio: la sinopsis que quepa encima de la barra
        local top_h, bottom_h = top:getSize().h, bottom:getSize().h
        local col_h = math.max(cover:getSize().h, top_h + bottom_h + S(8))
        local column = VerticalGroup:new{ align = "left", top }
        local free_h = col_h - top_h - bottom_h
        local syn = config.card_synopsis and cleanSynopsis(book.description)
        local syn_gap = S(8)
        if syn and free_h > syn_gap * 2 + S(16) then
            local box = TextBoxWidget:new{
                text = syn,
                face = Font:getFace("cfont", 12),
                fgcolor = theme.fg2,
                bgcolor = theme.bg,
                width = col_w,
                height = free_h - 2 * syn_gap,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            }
            local bh = box:getSize().h
            table.insert(column, VerticalSpan:new{ width = syn_gap })
            table.insert(column, box)
            table.insert(column, VerticalSpan:new{ width = math.max(0, free_h - syn_gap - bh) })
        else
            table.insert(column, VerticalSpan:new{ width = math.max(0, free_h) })
        end
        table.insert(column, bottom)

        local row = HorizontalGroup:new{
            align = "top",
            cover,
            HorizontalSpan:new{ width = gap },
            column,
        }

        local file = book.file
        -- Tocar: seguir leyendo. Mantener: menú del libro. En edición: opciones.
        return tappable(frame(row), function()
            if self._widgets_edit then return self:showCardOptions() end
            filemanagerutil.openFile(fm, file)
        end, function()
            if self._widgets_edit then return self:showCardOptions() end
            if self.showBookMenu then return self:showBookMenu(file) end
            if fm.bookinfo then fm.bookinfo:show(file) end
        end)
    end

    function Aire:buildHome()
        Aire._active_instance = self
        local sw, sh = Screen:getWidth(), Screen:getHeight()
        local side = S(SIDE_PAD)
        local w = sw - 2 * side

        local content = VerticalGroup:new{ align = "left" }
        table.insert(content, VerticalSpan:new{ width = S(TOP_PAD) })
        table.insert(content, self:buildTopBar(w))
        if config.big_clock then
            table.insert(content, VerticalSpan:new{ width = S(18) })
            table.insert(content, self:buildClock(w))
        else
            self._clock_w, self._date_w = nil, nil
        end
        self._header_h = content:getSize().h + S(4)

        table.insert(content, VerticalSpan:new{ width = S(22) })
        table.insert(content, TextWidget:new{ text = _("CURRENTLY READING"), face = face(true, 12), fgcolor = GRAY_TEXT, padding = 0 })
        table.insert(content, VerticalSpan:new{ width = S(8) })
        local ok, card = pcall(self.buildCard, self, w)
        if ok then
            table.insert(content, card)
        else
            logger.warn("Aire: error construyendo la tarjeta del libro:", card)
        end
        -- getSize() de arriba dejó cacheada la disposición sin los últimos hijos
        content:resetLayout()

        -- Zona de widgets (widgets.lua): lo que quede entre la tarjeta y el dock
        local dock = self:buildNavBar(w)
        if self.buildWidgetArea then
            -- Mismo aire arriba (tarjeta -> widgets), entre filas y abajo (widgets -> dock)
            local gap_above = S(WIDGET_GAP)
            local dock_block = dock:getSize().h + S(DOCK_MARGIN_BOTTOM)
            local avail = sh - content:getSize().h - gap_above - dock_block - S(WIDGET_GAP)
            local ok_w, area = pcall(self.buildWidgetArea, self, w, avail)
            if ok_w and area then
                table.insert(content, VerticalSpan:new{ width = gap_above })
                table.insert(content, area)
                content:resetLayout()
            elseif not ok_w then
                logger.warn("Aire: error en la zona de widgets:", area)
            end
        end

        return package.loaded.aire_screen.root(HorizontalGroup:new{
            HorizontalSpan:new{ width = side },
            content,
        }, dock)
    end
end
