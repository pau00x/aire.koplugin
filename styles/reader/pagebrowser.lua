--[[
    aire.koplugin/styles/reader/pagebrowser.lua
    Rediseño moderno (Opción C) de PageBrowserWidget ("Explorador de páginas"):
      - Cabecera unificada de pantalla completa (barra de estado + ‹ Explorador de páginas + menú + subtítulo)
      - Cuadrícula de 4 columnas × 3 filas (estilo Librería) por defecto en vertical
      - Miniaturas con esquinas redondeadas cuando está activa la opción
--]]

local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
local _ = require("gettext")
local T = require("ffi/util").template
local ReaderDogear = require("apps/reader/modules/readerdogear")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local logger = require("logger")
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (ui/screen.lua)
local AireUI = package.loaded.aire_ui
local safeWrap, withTemporaryNew = AireUI.safeWrap, AireUI.withTemporaryNew
local TAG = "Aire/PageBrowser"

-- Miniaturas (explorador de páginas, mapa del libro): sin el dobladillo del
-- lector dentro de la imagen (la marca de marcador la pone el marco: cinta
-- negra, styles/ui/dialogs.lua)
local ok_rt, ReaderThumbnail = pcall(require, "apps/reader/modules/readerthumbnail")
if ok_rt and type(ReaderThumbnail) == "table" and ReaderThumbnail._getPageImage and not ReaderThumbnail._aire_ribbon then
    ReaderThumbnail._aire_ribbon = true
    safeWrap(ReaderThumbnail, "_getPageImage", function(orig_get, self, page, ...)
        local view = self.ui and self.ui.view
        local dg = view and view.dogear
        if not dg then return orig_get(self, page, ...) end
        local had = rawget(dg, "paintTo")
        dg.paintTo = function() end
        local ok, bb = pcall(orig_get, self, page, ...)
        dg.paintTo = had
        if not ok then error(bb, 0) end
        return bb
    end, TAG)
end

if not ReaderDogear._aire_styled then
    ReaderDogear._aire_styled = true
    safeWrap(ReaderDogear, "init", function(orig_dogear_init, self)
        orig_dogear_init(self)
        local min_s = math.min(Screen:getWidth(), Screen:getHeight())
        self.dogear_min_size = math.ceil(min_s * (1 / 28))
        self.dogear_max_size = math.ceil(min_s * (1 / 22))
        self.dogear_size = nil
        self:setupDogear()
        self:resetLayout()
    end, TAG)

    safeWrap(ReaderDogear, "setupDogear", function(orig_setup, self, new_dogear_size)
        if not new_dogear_size then new_dogear_size = self.dogear_max_size end
        if not FrameContainer._aire_draw_top_right_fold then
            return orig_setup(self, new_dogear_size)
        end
        if new_dogear_size ~= self.dogear_size then
            self.dogear_size = new_dogear_size
            if self[1] then self[1]:free() end
            local sz = self.dogear_size
            self.icon = Widget:new{
                dimen = Geom:new{ x = Screen:getWidth() - sz, y = self.dogear_y_offset or 0, w = sz, h = sz },
                paintTo = function(_self, bb, x, y)
                    _self.dimen.x = x
                    _self.dimen.y = y
                    local r = FileManager._aire_rounded_covers and Screen:scaleBySize(8) or 0
                    FrameContainer._aire_draw_top_right_fold(bb, x, y, sz, Size.border.thin, r)
                end,
            }
            self.top_pad = VerticalSpan:new{ width = self.dogear_y_offset or 0 }
            self.vgroup = VerticalGroup:new{ self.top_pad, self.icon }
            self[1] = RightContainer:new{
                dimen = Geom:new{ w = Screen:getWidth(), h = (self.dogear_y_offset or 0) + sz },
                self.vgroup,
            }
        end
    end, TAG)
end

if PageBrowserWidget._aire_styled then return end
PageBrowserWidget._aire_styled = true

safeWrap(PageBrowserWidget, "init", function(orig_init, self)
    local cur = self.ui and self.ui.toc and self.ui.toc.pageno or 1
    local total = self.ui and self.ui.document and self.ui.document:getPageCount() or 1
    local title_str = self.ui and self.ui.doc_props and self.ui.doc_props.display_title or ""
    local sub = title_str ~= ""
        and (title_str .. " · " .. T(_("p. %1 / %2"), cur, total))
        or T(_("p. %1 / %2"), cur, total)

    -- Cabecera de Aire (ui/screen.lua): ‹, ≡ (su menú) y subtítulo
    return package.loaded.aire_screen.withTitleBar({
        only_fullscreen = true,
        back = function() self:onClose() end,
        back_hold = function() self:onClose(true) end,
        menu_icon = "appbar.menu",
        on_menu = function() self:onShowMenu() end,
        on_menu_hold = function()
            if self:updateNbTocSpans(-1, true, true) then
                self:updateLayout()
            end
        end,
        subtitle = sub,
    }, orig_init, self)
end, TAG)

safeWrap(PageBrowserWidget, "updateLayout", function(orig_updateLayout, self)
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local side = Screen:scaleBySize(SIDE)
    local bottom_pad = Screen:scaleBySize(12)
    -- Si no hay preferencia guardada en vertical, usar 4×3 estilo Librería
    if sw <= sh and self.ui and self.ui.doc_settings then
        local has_cols = self.ui.doc_settings:readSetting("page_browser_nb_cols")
            or G_reader_settings:readSetting("page_browser_nb_cols")
        local has_rows = self.ui.doc_settings:readSetting("page_browser_nb_rows")
            or G_reader_settings:readSetting("page_browser_nb_rows")
        -- 4×3 solo mientras se calcula el diseño: se quita después para no
        -- escribirlo en el .sdr de cada libro (si cambias filas o columnas
        -- desde el menú, KOReader ya lo guarda él, también como global)
        if not has_cols then self.ui.doc_settings:saveSetting("page_browser_nb_cols", 4) end
        if not has_rows then self.ui.doc_settings:saveSetting("page_browser_nb_rows", 3) end
        self._aire_tmp_cols, self._aire_tmp_rows = not has_cols, not has_rows
    end
    -- Reservar margen inferior S(12) y márgenes laterales S(SIDE) para la cinta inferior
    self.dimen.h = sh - bottom_pad
    -- updateLayout termina llamando a update(): se aplaza hasta haber puesto
    -- nuestro ancho de cinta, para que la primera pintura ya salga con él
    local had_own_update = rawget(self, "update")
    self.update = function() end
    local ok_l, err_l = pcall(orig_updateLayout, self)
    self.update = had_own_update
    self.dimen.h = sh
    if self._aire_tmp_cols then self.ui.doc_settings:delSetting("page_browser_nb_cols") end
    if self._aire_tmp_rows then self.ui.doc_settings:delSetting("page_browser_nb_rows") end
    self._aire_tmp_cols, self._aire_tmp_rows = nil, nil
    if not ok_l then error(err_l, 0) end
    self.row_width = sw - 2 * side
    self.view_finder_bw = Size.border.thin
    self.view_finder_h = self.row_height + 2 * self.view_finder_bw
    if self[1] and self[1][1] then
        self[1].height = sh
        table.insert(self[1][1], VerticalSpan:new{ width = bottom_pad })
        if self[1][1].resetLayout then self[1][1]:resetLayout() end
    end
    self:update()
end, TAG)

-- La cinta inferior es más estrecha que la pantalla y va centrada, pero
-- KOReader calcula el visor como si empezara en x = 0 (cinta más ancha que la
-- pantalla, bordes fuera): desplazar visor y líneas lo que se ha movido la cinta
local PB_BookMapRow = require("ui/widget/bookmapwidget").BookMapRow
safeWrap(PageBrowserWidget, "update", function(orig_pb_update, self, ...)
    local res = orig_pb_update(self, ...)
    self.view_finder_row_lines = {}
    local w = self.dimen and self.dimen.w
    if w and self.row_width and self.view_finder_x then
        local pfb = PB_BookMapRow and PB_BookMapRow.pages_frame_border or 0
        local shift = math.floor((w - self.row_width) / 2) + pfb
        if shift ~= 0 then
            self.view_finder_x = self.view_finder_x + shift
        end
    end
    return res
end, TAG)

safeWrap(PageBrowserWidget, "clearTile", function(orig_pb_clearTile, self, grid_idx, in_progress, do_refresh)
    local res = orig_pb_clearTile(self, grid_idx, in_progress, do_refresh)
    if in_progress and self.grid and self.grid[grid_idx] then
        local cell = self.grid[grid_idx]
        local cc = cell[1]
        if type(cc) == "table" and cc.dimen then
            if cc[1] and cc[1].free then cc[1]:free() end
            local sz = Screen:scaleBySize(24)
            cc[1] = IconWidget:new{
                icon = "aire.widget.refresh",
                width = sz,
                height = sz,
                alpha = true,
                dim = true,
            }
            if cc.resetLayout then cc:resetLayout() end
        end
    end
    return res
end, TAG)

safeWrap(PageBrowserWidget, "onTap", function(orig_pb_onTap, self, arg, ges)
    if self.row and self.row.dimen and ges.pos and ges.pos.y >= self.row.dimen.y
            and ges.pos.y <= self.row.dimen.y + self.row.dimen.h and self.row[1] then
        local rx = self.row[1].dimen and self.row[1].dimen.x or Screen:scaleBySize(SIDE)
        local page = self.row[1]:getPageAtX(ges.pos.x - rx)
        if page then
            page = page - math.floor(self.nb_grid_items / 2) + self.focus_page_shift
            if self:updateFocusPage(page, false) then
                self:update()
            end
        end
        return true
    end
    return orig_pb_onTap(self, arg, ges)
end, TAG)

safeWrap(PageBrowserWidget, "onHold", function(orig_pb_onHold, self, arg, ges)
    if self.row and self.row.dimen and ges.pos and ges.pos.y >= self.row.dimen.y
            and ges.pos.y <= self.row.dimen.y + self.row.dimen.h and self.row[1] then
        local rx = self.row[1].dimen and self.row[1].dimen.x or Screen:scaleBySize(SIDE)
        local page = self.row[1]:getPageAtX(ges.pos.x - rx)
        if page then
            self:openBookMap(page)
        end
        return true
    end
    return orig_pb_onHold(self, arg, ges)
end, TAG)

local function applyCellThumbStyle(pb, cell)
    local rounded = FileManager._aire_rounded_covers == true
    local r = rounded and Screen:scaleBySize(8) or 0
    local thumb_frame = cell and cell[1] and cell[1][1]
    if type(thumb_frame) == "table" and thumb_frame.is_page_thumbnail then
        thumb_frame.radius = r
        thumb_frame._aire_clip_corners = rounded
        thumb_frame._aire_bookmark_fold = (pb.bookmarked_pages and cell.page_idx and pb.bookmarked_pages[cell.page_idx]) and true or false
        thumb_frame._aire_page_label = (cell.show_pagenum and pb.pagenum_page_texts and cell.page_idx and pb.pagenum_page_texts[cell.page_idx]) or nil
    end
end

-- (el método de KOReader es showTile; onShowTile no existe y nunca se llamaba)
safeWrap(PageBrowserWidget, "showTile", function(orig_pb_showTile, self, grid_idx, page, ...)
    local res = orig_pb_showTile(self, grid_idx, page, ...)
    if self.grid then
        if self.grid[grid_idx] then
            applyCellThumbStyle(self, self.grid[grid_idx])
        end
        for i = (self.nb_grid_items or 0) + 1, #self.grid do
            local w = self.grid[i]
            if w and w.is_page_num_widget and not w._aire_hidden then
                w._aire_hidden = true
                w.paintTo = function() end
            end
        end
    end
    return res
end, TAG)

safeWrap(PageBrowserWidget, "paintTo", function(orig_pb_paintTo, self, bb, x, y)
    if self.grid and self.nb_grid_items then
        for idx = 1, self.nb_grid_items do
            applyCellThumbStyle(self, self.grid[idx])
        end
        for i = self.nb_grid_items + 1, #self.grid do
            local w = self.grid[i]
            if w and w.is_page_num_widget and not w._aire_hidden then
                w._aire_hidden = true
                w.paintTo = function() end
            end
        end
    end
    return orig_pb_paintTo(self, bb, x, y)
end, TAG)

-- Convertir el menú flotante del explorador de páginas en bottom sheet unificada
safeWrap(PageBrowserWidget, "onShowMenu", function(orig_pb_menu, self)
    local ButtonDialog = require("ui/widget/buttondialog")
    return withTemporaryNew(ButtonDialog, function(base_new, cls, o)
        if type(o) == "table" and o.anchor then
            o.anchor = nil
            o.shrink_unneeded_width = nil
            o.width = nil
            o.title = o.title or require("gettext")("Page browser")
            o.title_align = "left"
        end
        return base_new(cls, o)
    end, orig_pb_menu, self)
end, TAG)

logger.dbg("Aire/PageBrowser: aplicado desde el plugin")
