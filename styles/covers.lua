--[[
    aire.koplugin/styles/covers.lua
    Portadas del explorador (plugin CoverBrowser), se carga una vez desde main.lua:
      - Sin los indicadores de CoverBrowser (su barra de progreso,
        la marca de descripción y su esquina de estado) ni el subrayado del
        último visitado. La marca de colección sigue la opción de KOReader
        ("Mostrar marca de colección").
      - Mosaico con las mismas columnas y márgenes que la Librería de Aire.
      - Vistas de lista en tarjetas, con la información del archivo legible.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local logger = require("logger")
local userpatch = require("userpatch")
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Covers"

---------------------------------------------------------------------------
local function patchCoverBrowser(plugin)
    local MosaicMenu = require("mosaicmenu")
    -- CoverBrowser se crea de nuevo al abrir cada libro y al volver al
    -- explorador. Los cambios son de clase y ya están puestos desde la primera
    -- vez; además, este archivo envuelve _updateItemsBuildUI más abajo, así que
    -- en las siguientes llamadas ya no se encontraría MosaicMenuItem en ella.
    if MosaicMenu._aire_covers_patched then return end
    local MosaicMenuItem = package.loaded.aire_ui.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then
        logger.warn("Aire/Covers: no se encontró MosaicMenuItem")
        return
    end
    MosaicMenu._aire_covers_patched = true
    if MosaicMenuItem._aire_covers then return end
    MosaicMenuItem._aire_covers = true

    local BookInfoManager = package.loaded.aire_ui.getUpValue(MosaicMenuItem.update, "BookInfoManager")
        or require("bookinfomanager")

    -- Funciones vacías para desactivar lo original solo durante su dibujo
    local noop = function() end
    local orig_getSetting = BookInfoManager.getSetting
    local getSettingNoHint = function(bim, name, ...)
        if name == "no_hint_description" then return true end
        return orig_getSetting(bim, name, ...)
    end

    -- 0) Carpetas del mosaico: mismo tamaño que libros/colecciones (100% celda), centradas, fondo gris muy claro
    local FileManager = require("apps/filemanager/filemanager")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local LineWidget = require("ui/widget/linewidget")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Font = require("ui/font")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    if MosaicMenuItem.update then
        safeWrap(MosaicMenuItem, "update", function(orig_update, self, ...)
            local res = orig_update(self, ...)
            if self.is_directory and self._underline_container and self._underline_container[1] then
                local fc = self._underline_container[1]
                local cell_w = self.width or fc.width
                local cell_h = self.height or fc.height
                local dir_pad = Screen:scaleBySize(5)
                local border = Size.border.thin
                local dir_bg = Blitbuffer.COLOR_GRAY_E
                local in_w = math.max(1, cell_w - 2 * (dir_pad + border))
                local in_h = math.max(1, cell_h - 2 * (dir_pad + border))
                fc.margin = 0
                fc.padding = dir_pad
                fc.width = cell_w
                fc.height = cell_h
                fc.bordersize = border
                fc.background = dir_bg
                fc.radius = FileManager._aire_rounded_covers and Screen:scaleBySize(8) or 0
                local og = fc[1]
                if type(og) == "table" and og.dimen then
                    og.dimen = Geom:new{ w = in_w, h = in_h }
                    og._size = nil
                    local nbitems = og[2] and og[2][1]
                    if nbitems then
                        local nb_text, nb_face = nbitems.text, nbitems.face
                        if nbitems.free then nbitems:free() end
                        nbitems = TextBoxWidget:new{
                            text = nb_text,
                            face = nb_face,
                            width = in_w,
                            alignment = "center",
                            bgcolor = dir_bg,
                        }
                        og[2][1] = nbitems
                    end
                    local dir_w = og[1] and og[1][1]
                    if dir_w then
                        local dir_text = dir_w.text or ""
                        if dir_w.free then dir_w:free() end
                        local avail_h = math.max(1, in_h - 3 * (nbitems and nbitems:getSize().h or 0))
                        local chosen
                        for fs = 20, 10, -1 do
                            local face = Font:getFace("cfont", fs)
                            local words_fit = true
                            if fs > 10 then
                                for word in dir_text:gmatch("%S+") do
                                    local tw = TextWidget:new{ text = word, face = face, bold = true }
                                    local ww = tw:getSize().w
                                    tw:free()
                                    if ww > in_w then
                                        words_fit = false
                                        break
                                    end
                                end
                            end
                            if words_fit or fs == 10 then
                                local tb = TextBoxWidget:new{
                                    text = dir_text,
                                    face = face,
                                    width = in_w,
                                    alignment = "center",
                                    bold = true,
                                    bgcolor = dir_bg,
                                }
                                if tb:getSize().h <= avail_h then
                                    chosen = tb
                                    break
                                elseif fs == 10 then
                                    tb:free()
                                    chosen = TextBoxWidget:new{
                                        text = dir_text,
                                        face = face,
                                        width = in_w,
                                        height = avail_h,
                                        height_adjust = true,
                                        height_overflow_show_ellipsis = true,
                                        alignment = "center",
                                        bold = true,
                                        bgcolor = dir_bg,
                                    }
                                    break
                                else
                                    tb:free()
                                end
                            end
                        end
                        og[1][1] = chosen
                    end
                    for _i, child in ipairs(og) do
                        if type(child) == "table" and child.dimen then
                            child.dimen = Geom:new{ w = in_w, h = in_h }
                            if child.resetLayout then child:resetLayout() end
                        end
                    end
                    if og.init then og:init() end
                    if og.resetLayout then og:resetLayout() end
                end
                fc._size = nil
                fc.dimen = nil
                if fc.resetLayout then fc:resetLayout() end
                self._underline_container[1] = CenterContainer:new{
                    dimen = Geom:new{ w = cell_w, h = cell_h },
                    fc,
                }
                if self._underline_container.resetLayout then self._underline_container:resetLayout() end
            elseif not self.is_directory and not self._has_cover_image and self._underline_container and self._underline_container[1] then
                local cc = self._underline_container[1]
                local fk = cc and cc[1]
                if fk and fk.filename and self.width and self.height then
                    if fk.free then fk:free() end
                    fk.width = self.width
                    fk.height = self.height
                    fk.title_font_max = 20
                    fk.title_font_min = 10
                    fk.sizedec_step = Screen:scaleBySize(1)
                    fk._size = nil
                    fk.dimen = nil
                    if fk.init then fk:init() end
                    -- Sin autores: centrar el título a la misma altura que las carpetas
                    local fk_cc = fk[1]
                    local vg = not fk.authors and fk_cc and fk_cc[1]
                    if vg and vg[2] and fk_cc.dimen then
                        local d = fk_cc.dimen
                        local title_wg = vg[2]
                        local filename_wg = vg[4]
                        vg[2] = nil
                        vg[4] = nil
                        if fk_cc.free then fk_cc:free() end
                        local og = OverlapGroup:new{
                            dimen = d,
                            CenterContainer:new{ dimen = d, title_wg },
                        }
                        if filename_wg then
                            table.insert(og, BottomContainer:new{
                                dimen = d,
                                VerticalGroup:new{
                                    align = "center",
                                    filename_wg,
                                    VerticalSpan:new{ width = Screen:scaleBySize(5) },
                                },
                            })
                        end
                        fk[1] = og
                        fk._size = nil
                        if fk.resetLayout then fk:resetLayout() end
                    end
                    if cc.resetLayout then cc:resetLayout() end
                end
            end
            return res
        end, TAG)
    end

    safeWrap(MosaicMenuItem, "paintTo", function(orig_paintTo, self, bb, x, y)
        -- 1) Dibujo original sin barra / marca de descripción / esquina de CoverBrowser.
        --    La marca de colección se deja: KOReader la pinta solo si está activada
        --    "Mostrar marca de colección" (Aire → Explorador → Configuración).
        local saved_progress = ProgressWidget.paintTo
        local saved_getSetting = BookInfoManager.getSetting
        local saved_been_opened = self.been_opened
        ProgressWidget.paintTo = noop
        BookInfoManager.getSetting = getSettingNoHint
        self.been_opened = false
        local ok, err = pcall(orig_paintTo, self, bb, x, y)
        self.been_opened = saved_been_opened
        ProgressWidget.paintTo = saved_progress
        BookInfoManager.getSetting = saved_getSetting
        if not ok then error(err) end
        -- Esquinas redondeadas en portadas del explorador cuando la opción está activa
        if FileManager._aire_rounded_covers and not self.is_directory and not self.file_deleted and self._underline_container then
            local cc = self._underline_container[1]
            local frame = cc and cc[1]
            local d = frame and frame.dimen
            if d and d.x and d.w and d.h and d.w > 20 and d.h > 20 then
                local r = Screen:scaleBySize(8)
                for dy = 0, r - 1 do
                    local dx = r - math.floor(math.sqrt(r * r - (r - dy - 0.5) ^ 2) + 0.5)
                    if dx > 0 then
                        bb:paintRect(d.x, d.y + dy, dx, 1, Blitbuffer.COLOR_WHITE)
                        bb:paintRect(d.x + d.w - dx, d.y + dy, dx, 1, Blitbuffer.COLOR_WHITE)
                        bb:paintRect(d.x, d.y + d.h - 1 - dy, dx, 1, Blitbuffer.COLOR_WHITE)
                        bb:paintRect(d.x + d.w - dx, d.y + d.h - 1 - dy, dx, 1, Blitbuffer.COLOR_WHITE)
                    end
                end
                bb:paintBorder(d.x, d.y, d.w, d.h, Size.border.thin, Blitbuffer.COLOR_BLACK, r)
            end
        end
    end, TAG)

    -- 2) Subrayado del último visitado: siempre oculto, en todas partes
    safeWrap(MosaicMenuItem, "onFocus", function(_orig, self)
        if self._underline_container then
            self._underline_container.color = Blitbuffer.COLOR_WHITE
        end
        return true
    end, TAG)

    -- 3) Mosaico del explorador: mismas 4 columnas, márgenes (16) y alto de filas que grid.lua
    local orig_recalc = MosaicMenu._recalculateDimen
    if orig_recalc and not MosaicMenu._aire_grid_dims then
        MosaicMenu._aire_grid_dims = true
        local function patched_recalc(self, ...)
            local portrait = self.name == "filemanager" and self.inner_dimen and Screen:getWidth() <= Screen:getHeight()
            local side = Screen:scaleBySize(SIDE)
            local gap = Screen:scaleBySize(10)
            local oh = 0
            local cols = 4
            if portrait then
                -- 3 columnas solo si se eligió en el menú (Explorador > Cuadrícula),
                -- que lo guarda en CoverBrowser; si no, 4 como la Librería
                local ok_b, BIM = pcall(require, "bookinfomanager")
                if ok_b and type(BIM) == "table" and BIM.getSetting
                        and BIM:getSetting("nb_cols_portrait") == 3 then
                    cols = 3
                end
                local gw = Screen:getWidth() - 2 * side
                local cw = math.floor((gw - (cols - 1) * gap) / cols)
                local ideal_h = cw * 1.5
                if self.title_bar then
                    if not self.is_borderless then oh = oh + 2 end
                    if not self.no_title then oh = oh + self.title_bar.dimen.h end
                    if self.page_info then oh = oh + self.page_info:getSize().h end
                end
                local avail_h = self.inner_dimen.h - oh - Screen:scaleBySize(6)
                local r1 = math.max(1, math.floor((avail_h + gap) / (ideal_h + gap)))
                local function hFor(r) return math.floor((avail_h - (r - 1) * gap) / r) end
                local h1, h2 = hFor(r1), hFor(r1 + 1)
                self.nb_cols_portrait = cols
                self.nb_rows_portrait = (h2 > 0 and math.abs(h2 - ideal_h) < math.abs(h1 - ideal_h)) and (r1 + 1) or r1
            end
            local res = orig_recalc(self, ...)
            if portrait then
                self.item_margin = gap
                self.item_width = math.floor((self.inner_dimen.w - 2 * side - (self.nb_cols - 1) * gap) / self.nb_cols)
                self.item_height = math.floor((self.inner_dimen.h - oh - Screen:scaleBySize(6) - (self.nb_rows - 1) * gap) / self.nb_rows)
                self.item_dimen = Geom:new{ x = 0, y = 0, w = self.item_width, h = self.item_height }
            end
            return res
        end
        MosaicMenu._recalculateDimen = patched_recalc
        local FileChooser = require("ui/widget/filechooser")
        if FileChooser._recalculateDimen == orig_recalc then
            FileChooser._recalculateDimen = patched_recalc
        end

        local orig_build = MosaicMenu._updateItemsBuildUI
        if orig_build then
            local function patched_build(self, ...)
                local res = orig_build(self, ...)
                if self.name == "filemanager" and self.item_group and Screen:getWidth() <= Screen:getHeight() then
                    -- Quitar el margen superior antes de la fila 1 (igual que grid.lua)
                    if #self.item_group > 0 and self.item_group[1].width and not self.item_group[1][1] then
                        table.remove(self.item_group, 1)
                    end
                    -- Margen izquierdo S(SIDE) en cada fila (en vez de S(10))
                    local side = Screen:scaleBySize(SIDE)
                    for _i, child in ipairs(self.item_group) do
                        local hg = child[1]
                        if type(hg) == "table" and type(hg[1]) == "table" and hg[1].width and not hg[1][1] then
                            hg[1].width = side
                            if hg.resetLayout then hg:resetLayout() end
                        end
                    end
                    if self.item_group.resetLayout then self.item_group:resetLayout() end
                end
                return res
            end
            MosaicMenu._updateItemsBuildUI = patched_build
            if FileChooser._updateItemsBuildUI == orig_build then
                FileChooser._updateItemsBuildUI = patched_build
            end
        end
    end

    -- 4) Vistas de lista de CoverBrowser (Lista con/sin portadas, nombre de archivo)
    local ok_lm, ListMenu = pcall(require, "listmenu")
    if ok_lm and type(ListMenu) == "table" and not ListMenu._aire_list_modernized then
        ListMenu._aire_list_modernized = true
        local ListMenuItem = package.loaded.aire_ui.getUpValue(ListMenu._updateItemsBuildUI, "ListMenuItem")
        local FileChooser = require("ui/widget/filechooser")

        if ListMenuItem then
            local FILE_INFO_FACE = Font:getFace("cfont", 13)
            local FAKE_COVER_GLYPH = "\u{26F6}" -- "⛶" de la portada vacía (no se toca)
            safeWrap(ListMenuItem, "update", function(orig_lm_update, self, ...)
                if not (self.menu and self.menu.name == "filemanager") then
                    return orig_lm_update(self, ...)
                end
                local orig_w = self.width
                local orig_h = self.height
                local pad_h = Screen:scaleBySize(SIDE)
                local gap_b = orig_h >= Screen:scaleBySize(60) and Screen:scaleBySize(8) or Screen:scaleBySize(6)
                local pad_in = Screen:scaleBySize(4)
                local border = Size.border.thin
                local card_w = math.max(Screen:scaleBySize(120), orig_w - 2 * pad_h)
                local card_h = math.max(Screen:scaleBySize(42), orig_h - gap_b)
                local inner_w = math.max(Screen:scaleBySize(80), card_w - 2 * border)
                local inner_h = math.max(Screen:scaleBySize(32), card_h - 2 * border)
                self.width = math.max(Screen:scaleBySize(80), inner_w - 2 * pad_in)
                self.height = math.max(Screen:scaleBySize(32), inner_h - 2 * pad_in)

                local is_dir = not (self.entry and (self.entry.is_file or self.entry.file))
                local orig_mand = self.mandatory

                local own_tbw_new, orig_tbw_new = rawget(TextBoxWidget, "new"), TextBoxWidget.new
                local own_tw_new, orig_tw_new = rawget(TextWidget, "new"), TextWidget.new
                if not is_dir then
                    TextBoxWidget.new = function(cls, o)
                        if type(o) == "table" and o.bold then o.bold = false end
                        return orig_tbw_new(cls, o)
                    end
                    -- Columna derecha (tipo y tamaño, páginas: "Información del
                    -- archivo" en el menú de CoverBrowser). KOReader escala su letra
                    -- con el alto de la fila y dentro de la tarjeta quedaba diminuta.
                    -- (Antes Aire añadía además el tipo en mayúsculas: salía repetido.)
                    TextWidget.new = function(cls, o)
                        if type(o) == "table" and type(o.text) == "string" and o.text ~= FAKE_COVER_GLYPH then
                            o.face = FILE_INFO_FACE
                            o.fgcolor = Blitbuffer.COLOR_DARK_GRAY
                        end
                        return orig_tw_new(cls, o)
                    end
                elseif orig_mand and orig_mand ~= "" then
                    TextWidget.new = function(cls, o)
                        if type(o) == "table" and o.text == orig_mand then
                            o.face = Font:getFace("infont", 14)
                        end
                        return orig_tw_new(cls, o)
                    end
                end
                local ok_u, res = pcall(orig_lm_update, self, ...)
                rawset(TextBoxWidget, "new", own_tbw_new)
                rawset(TextWidget, "new", own_tw_new)
                self.width = orig_w
                self.height = orig_h
                if not ok_u then error(res, 0) end
                if self._underline_container and self._underline_container[1] then
                    local content = self._underline_container[1]
                    -- ListMenuItem envuelve `widget` en VerticalGroup{ VerticalSpan(underline_h), widget }:
                    -- quitamos el span superior para centrar de verdad dentro de la tarjeta.
                    if type(content) == "table" and content[2] and not content[3] then
                        content = content[2]
                    end
                    local card = FrameContainer:new{
                        width = card_w,
                        height = card_h,
                        bordersize = border,
                        color = Blitbuffer.COLOR_GRAY_D,
                        background = Blitbuffer.COLOR_WHITE,
                        radius = Screen:scaleBySize(10),
                        padding = 0,
                        CenterContainer:new{
                            dimen = Geom:new{ w = inner_w, h = inner_h },
                            content,
                        },
                    }
                    self._underline_container[1] = FrameContainer:new{
                        width = orig_w,
                        height = orig_h,
                        bordersize = 0,
                        padding = 0,
                        padding_left = pad_h,
                        padding_right = pad_h,
                        padding_bottom = gap_b,
                        card,
                    }
                end
                return res
            end, TAG)

            safeWrap(ListMenuItem, "paintTo", function(orig_lm_paint, self, bb, x, y)
                if not (self.menu and self.menu.name == "filemanager") then
                    return orig_lm_paint(self, bb, x, y)
                end
                local saved_opened = self.been_opened
                local saved_shortcut = self.shortcut_icon
                local saved_getSetting = BookInfoManager.getSetting
                self.been_opened = false
                self.shortcut_icon = nil
                BookInfoManager.getSetting = getSettingNoHint
                local ok, err = pcall(orig_lm_paint, self, bb, x, y)
                self.been_opened = saved_opened
                self.shortcut_icon = saved_shortcut
                BookInfoManager.getSetting = saved_getSetting
                if not ok then error(err) end
            end, TAG)

            safeWrap(ListMenuItem, "onFocus", function(orig_lm_focus, self, ...)
                if self.menu and self.menu.name == "filemanager" then
                    if self._underline_container then
                        self._underline_container.color = Blitbuffer.COLOR_WHITE
                    end
                    return true
                end
                return orig_lm_focus(self, ...)
            end, TAG)
        end

        local orig_lm_build = ListMenu._updateItemsBuildUI
        if orig_lm_build then
            local function patched_lm_build(self, ...)
                local res = orig_lm_build(self, ...)
                if self.name == "filemanager" and self.item_group then
                    for i = #self.item_group, 1, -1 do
                        local child = self.item_group[i]
                        if getmetatable(child) == LineWidget then
                            table.remove(self.item_group, i)
                        end
                    end
                    if self.item_group.resetLayout then self.item_group:resetLayout() end
                end
                return res
            end
            ListMenu._updateItemsBuildUI = patched_lm_build
            if FileChooser._updateItemsBuildUI == orig_lm_build then
                FileChooser._updateItemsBuildUI = patched_lm_build
            end
        end
    end

    if type(plugin) == "table" and plugin.addToMainMenu and not plugin._aire_hide_dm_menu then
        plugin._aire_hide_dm_menu = true
        safeWrap(plugin, "addToMainMenu", function(orig_add, self, menu_items, ...)
            local res = orig_add(self, menu_items, ...)
            if type(menu_items) == "table" then
                menu_items.filemanager_display_mode = nil
            end
            return res
        end, TAG)
    end

    logger.dbg("Aire/Covers: aplicado desde el plugin")
end

-- Protegido: los parches de plugins se ejecutan dentro de FileManager:init y
-- un error sin pcall impediría arrancar KOReader
userpatch.registerPatchPluginFunc("coverbrowser", function(plugin)
    local ok, err = pcall(patchCoverBrowser, plugin)
    if not ok then logger.warn("Aire/Covers: no se pudo aplicar:", err) end
end)
