--[[
    aire.koplugin/styles/shortcuts.lua
    Rediseño moderno de FileManagerShortcuts ("Atajos de carpetas"):
      - Cabecera unificada con subtítulo de conteo ("N atajos") y botón + a la derecha
      - Cada atajo en tarjeta blanca redondeada con icono de carpeta, nombre en negrita
        y ruta debajo en gris
--]]

local Device = require("device")
local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen
local SIDE = package.loaded.aire_screen.METRICS.SIDE -- margen lateral común (common/screen.lua)
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/Shortcuts"
local AireUI = package.loaded.aire_ui
local S, face, BLACK, WHITE, GRAY_DARK, GRAY_LINE = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_LINE

if FileManagerShortcuts._aire_shortcuts_styled then return end
FileManagerShortcuts._aire_shortcuts_styled = true



local function styleShortcutItem(item, item_w, item_h, pad_h)
    local entry = item.entry
    if not entry or item._aire_sc_card_done then return end
    item._aire_sc_card_done = true

    local card_w = math.max(S(120), item_w - 2 * pad_h)
    local gap_b = S(8)
    local card_h = math.max(S(46), item_h - gap_b)
    local inner_pad_h = S(12)
    local icon_sz = S(22)
    local text_w = math.max(S(80), card_w - 2 * inner_pad_h - 2 * Size.border.thin - icon_sz - S(10))

    local title_txt = entry.name or entry.text or ""
    local path_txt = entry.folder or ""

    local text_vg = VerticalGroup:new{
        align = "left",
        TextWidget:new{
            text = title_txt,
            face = face(true, 14),
            fgcolor = BLACK,
            max_width = text_w,
            padding = 0,
        },
    }
    if path_txt ~= "" then
        table.insert(text_vg, VerticalSpan:new{ width = S(2) })
        table.insert(text_vg, TextWidget:new{
            text = path_txt,
            face = face(false, 12),
            fgcolor = GRAY_DARK,
            max_width = text_w,
            truncate_left = true,
            padding = 0,
        })
    end

    local card = FrameContainer:new{
        width = card_w,
        height = card_h,
        bordersize = Size.border.thin,
        color = GRAY_LINE,
        background = WHITE,
        radius = S(10),
        padding = 0,
        padding_left = inner_pad_h,
        padding_right = inner_pad_h,
        HorizontalGroup:new{
            align = "center",
            IconWidget:new{ icon = "aire.folder", width = icon_sz, height = icon_sz, alpha = true },
            HorizontalSpan:new{ width = S(10) },
            text_vg,
        },
    }

    item[1] = FrameContainer:new{
        width = item_w,
        height = item_h,
        bordersize = 0,
        padding = 0,
        padding_left = pad_h,
        padding_right = pad_h,
        padding_bottom = gap_b,
        card,
    }
end

local ITEMS_PER_PAGE = 8 -- (con más, las tarjetas no caben y se tocan entre sí)

safeWrap(FileManagerShortcuts, "onShowFolderShortcutsDialog", function(orig_show, self, select_callback)
    -- El + de Aire: se cambia al crear la lista (la barra de título de Aire ya
    -- está montada cuando KOReader la enseña, y setLeftIcon no surtía efecto)
    local Menu = require("ui/widget/menu")
    local res = AireUI.withTemporaryNew(Menu, function(base_new, cls, o)
        if type(o) == "table" and o.title_bar_left_icon == "plus" then o.title_bar_left_icon = "aire.plus" end
        return base_new(cls, o)
    end, orig_show, self, select_callback)
    local sm = self.shortcuts_menu
    if sm and not sm._aire_sc_hooked then
        sm._aire_sc_hooked = true
        sm.with_dots = false
        sm.is_borderless = true
        sm.items_per_page = ITEMS_PER_PAGE
        sm.items_max_lines = nil
        if sm._recalculateDimen then sm:_recalculateDimen(false) end

        local orig_update = sm.updateItems
        -- (lo de Aire, protegido: si falla, la lista queda como la de KOReader)
        local function styleList(self)
            if self.title_bar and self.title_bar.setSubTitle then
                local n = self.item_table and #self.item_table or 0
                local sub = n == 0 and _("No saved shortcuts")
                    or T(N_("%1 saved shortcut", "%1 saved shortcuts", n), n)
                self.title_bar._aire_default_subtitle = sub
                self.title_bar:setSubTitle(sub, true)
            end
            if not self.item_group then return end
            self.item_group.align = "left"
            local w = self.dimen and self.dimen.w or Screen:getWidth()
            local first_item = self.item_group[1]
            local avail_w = (first_item and first_item.dimen and first_item.dimen.w)
                or (self.inner_dimen and self.inner_dimen.w)
                or w
            local outer_pad = math.floor((w - avail_w) / 2)
            local pad_h = math.max(0, S(SIDE) - outer_pad)
            for _, child in ipairs(self.item_group) do
                if child and child.entry then
                    local ih = (child.dimen and child.dimen.h) or S(64)
                    styleShortcutItem(child, avail_w, ih, pad_h)
                end
            end
            self.item_group:resetLayout()
        end
        function sm:updateItems(select_number, ...)
            orig_update(self, select_number, ...)
            local ok, err = pcall(styleList, self)
            if not ok then logger.warn("Aire/Shortcuts:", err) end
        end
        sm:updateItems(1)
        UIManager:setDirty(sm, "ui")
    end
    return res
end, TAG)

logger.dbg("Aire/Shortcuts: aplicado desde el plugin")
