--[[
    aire.koplugin/styles/imageviewer.lua
    Rediseño moderno (Opción A) de ImageViewer ("Visor de imagen / portada"):
      - Cabecera unificada de pantalla completa (barra de estado + ‹ Imagen + dimensiones)
      - Imagen centrada con marco fino y esquinas redondeadas (si opción activa)
      - Barra inferior estilo dock con los controles (1:1 Original, Rotar, Guardar)
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageViewer = require("ui/widget/imageviewer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local AireUI = package.loaded.aire_ui
local S = AireUI.S
local safeWrap = AireUI.safeWrap
local TAG = "Aire/ImageViewer"

if ImageViewer._aire_styled then return end
ImageViewer._aire_styled = true


safeWrap(ImageViewer, "init", function(orig_init, self)
    self.fullscreen = true
    self.with_title_bar = true
    self.buttons_visible = true
    self.image_padding = S(4)
    self.button_padding = S(16)
    if not self.title_text or self.title_text == "" then
        self.title_text = require("gettext")("Image")
    end

    -- self.image puede ser un Blitbuffer (cdata), una lista de imágenes
    -- (tabla) o una función (SVG de crengine): indexar una función da error.
    -- El pie de imagen va primero: con la flecha cambiada por "atrás" ya no
    -- hay otra forma de verlo.
    local sub
    local img = self.image
    if self.caption and self.caption ~= "" then
        sub = self.caption
    elseif img and type(img) ~= "function" and img.getWidth then
        sub = string.format("%d × %d px", img:getWidth(), img:getHeight())
    end

    -- Cabecera de Aire (common/screen.lua): ‹ y, de subtítulo, el pie o el tamaño
    package.loaded.aire_screen.withTitleBar({
        fullscreen = true,
        back = function() self:onClose() end,
        clear = { "subtitle" },
        subtitle = sub,
    }, orig_init, self)

    if self.button_table and self.button_container then
        local sw = Screen:getWidth()
        local total_w = sw - 2 * S(SIDE)
        local gap = S(10)
        local btn_w = math.floor((total_w - gap) / 2)
        local btn_h = S(44)

        local dock_row = HorizontalGroup:new{ align = "center" }
        local function makeBtn(label, on_tap)
            local pill = FrameContainer:new{
                width = btn_w,
                height = btn_h,
                bordersize = Size.border.thin,
                color = Blitbuffer.COLOR_GRAY_B,
                background = Blitbuffer.COLOR_WHITE,
                radius = S(10),
                padding = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = btn_w - 2 * Size.border.thin, h = btn_h - 2 * Size.border.thin },
                    TextWidget:new{
                        text = label,
                        face = Font:getFace("tfont", 14),
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        max_width = btn_w - S(12),
                        padding = 0,
                    },
                },
            }
            return AireUI.tappable(pill, on_tap)
        end

        self._aire_rebuild_dock = function()
            dock_row:clear()
            local scale_lbl = self._scale_to_fit and _("Original size") or _("Fit")
            local rot_lbl = self.rotated and _("No rotation") or _("Rotate")
            table.insert(dock_row, makeBtn(scale_lbl, function()
                self.scale_factor = self._scale_to_fit and 1 or 0
                self._scale_to_fit = not self._scale_to_fit
                self._center_x_ratio = 0.5
                self._center_y_ratio = 0.5
                self:update()
            end))
            table.insert(dock_row, HorizontalSpan:new{ width = gap })
            table.insert(dock_row, makeBtn(rot_lbl, function()
                self.rotated = not self.rotated and true or false
                self:update()
            end))
            dock_row:resetLayout()
        end
        self._aire_rebuild_dock()

        local dummy_btn = { setText = function() end }
        self.button_table = {
            getButtonById = function() return dummy_btn end,
            free = function() end,
        }

        local dock_vg = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = S(6) },
            CenterContainer:new{ dimen = Geom:new{ w = sw, h = dock_row:getSize().h }, dock_row },
            VerticalSpan:new{ width = S(12) },
        }
        self.button_container = dock_vg
        self:update()
    end
end, TAG)

safeWrap(ImageViewer, "_new_image_wg", function(orig_new_image_wg, self)
    if self.buttons_visible or self.with_title_bar then
        local full_w = Screen:getWidth()
        self.width = full_w - S(24) -- con image_padding = S(4) deja S(16) a cada lado
        local ok, err = pcall(orig_new_image_wg, self)
        self.width = full_w
        if not ok then error(err) end
        if self.image_container and self.image_container.dimen then
            self.image_container.dimen.w = full_w
        end
        return
    end
    return orig_new_image_wg(self)
end, TAG)

safeWrap(ImageViewer, "onTap", function(orig_onTap, self, arg, ges)
    local was_visible = self.buttons_visible
    local res = orig_onTap(self, arg, ges)
    if self.buttons_visible ~= was_visible then
        self.with_title_bar = self.buttons_visible
        self.image_padding = self.buttons_visible and S(4) or 0
        self:update()
    end
    return res
end, TAG)

safeWrap(ImageViewer, "update", function(orig_update, self)
    if self._aire_rebuild_dock then self._aire_rebuild_dock() end
    orig_update(self)
    if self.main_frame then
        self.main_frame.bordersize = 0
        self.main_frame.radius = nil
    end
    if (self.buttons_visible or self.with_title_bar) and self.image_container and self.image_container[1] then
        local img = self.image_container[1]
        if img and not img._aire_wrapped then
            local rounded = FileManager._aire_rounded_covers == true
            local wrapped = FrameContainer:new{
                bordersize = Size.border.thin,
                color = Blitbuffer.COLOR_GRAY,
                radius = rounded and S(10) or 0,
                _aire_clip_corners = rounded,
                padding = 0,
                margin = 0,
                img,
            }
            wrapped._aire_wrapped = true
            self.image_container[1] = wrapped
            if self.image_container.resetLayout then self.image_container:resetLayout() end
        end
    end
end, TAG)

logger.dbg("Aire/ImageViewer: aplicado desde el plugin")
