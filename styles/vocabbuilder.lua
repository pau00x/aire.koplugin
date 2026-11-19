--[[
    aire.koplugin/styles/vocabbuilder.lua
    Rediseño moderno (Opción C) de VocabularyBuilderWidget ("Constructor de vocabulario"):
      - Primera palabra pendiente destacada arriba como tarjeta "SIGUIENTE REPASO"
        con botones grandes Olvidada / La sé
      - Resto de palabras en tarjetas con los mismos márgenes y separación que
        las listas de Aire (Índice, Marcadores…)
      - Cabecera unificada con subtítulo dinámico (número de palabras)
    La paginación por puntos la pone styles/ui/pagination.lua, como en el resto de listas.
--]]

local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local logger = require("logger")
local userpatch = require("userpatch")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template
local Screen = Device.screen
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/VocabBuilder"
local AireUI = package.loaded.aire_ui
local S, face, BLACK, WHITE, GRAY_DARK, GRAY_CARD, GRAY_BORDER, GRAY_LINE = AireUI.S, AireUI.face, AireUI.BLACK, AireUI.WHITE, AireUI.GRAY_DARK, AireUI.GRAY_CARD, AireUI.GRAY_BORDER, AireUI.GRAY_LINE


-- Mismos espacios que las listas de Aire: el margen lateral común
-- (common/screen.lua), S(8) entre tarjetas, la primera pegada al título y lo
-- que sobra, abajo (KOReader repartía el sobrante entre las filas y dejaba
-- medio margen arriba).
local SIDE_PAD, GAP = package.loaded.aire_screen.METRICS.SIDE, 8


local function makePill(w, h, label, black, on_tap)
    local pill = FrameContainer:new{
        width = w,
        height = h,
        bordersize = Size.border.thin,
        color = black and BLACK or GRAY_BORDER,
        background = black and BLACK or WHITE,
        radius = S(8),
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = w - 2 * Size.border.thin, h = h - 2 * Size.border.thin },
            TextWidget:new{
                text = label,
                face = face(true, 13),
                fgcolor = black and WHITE or BLACK,
                max_width = w - S(10),
                padding = 0,
            },
        },
    }
    local ic = InputContainer:new{ pill }
    ic.ges_events = {
        AireTap = { GestureRange:new{
            ges = "tap",
            range = function() return ic.dimen or Geom:new{ x = 0, y = 0, w = 0, h = 0 } end,
        } },
    }
    ic.onAireTap = function()
        if on_tap then on_tap() end
        return true
    end
    return ic
end

local getUpValue = package.loaded.aire_ui.getUpValue -- (seguro: comprueba el tipo)

local function showEmptyVocab(vb)
    if not (vb and vb.main_content) then return end
    if vb.item_table and #vb.item_table > 0 then return end
    vb.main_content:clear()
    local title_h = vb.title_bar and vb.title_bar:getHeight() or S(56)
    local foot_h = vb.footer_height or S(36)
    local h = math.max(S(120), (vb.dimen and vb.dimen.h or Screen:getHeight()) - title_h - foot_h)
    local w_mc = vb.dimen and vb.dimen.w or Screen:getWidth()
    table.insert(vb.main_content, CenterContainer:new{
        dimen = Geom:new{ w = w_mc, h = h },
        TextWidget:new{
            text = _("No vocabulary words"),
            face = face(false, 15),
            fgcolor = GRAY_DARK,
            padding = 0,
        },
    })
    if vb.main_content.resetLayout then vb.main_content:resetLayout() end
end

local function patchItemClass(VocabItemWidget)
    if not VocabItemWidget or VocabItemWidget._aire_styled then return end
    VocabItemWidget._aire_styled = true
    safeWrap(VocabItemWidget, "initItemWidget", function(orig_item_init, self)
        orig_item_init(self)
        local sp = self.show_parent
        if not (self.item and self.width and self.height) then return end
        local is_hero = (self.index == 1 and sp and (sp.show_page or 1) == 1
            and self.has_review_buttons)
        local card_w = self.width
        local card_h = self.height
        local pad = S(11)
        local in_w = card_w - 2 * pad - 2 * Size.border.thin
        local gap = S(8)
        local btn_w, btn_h = S(78), S(30)
        local btns_w = self.has_review_buttons and (2 * btn_w + gap) or 0
        local text_w = math.max(S(60), in_w - btns_w - (btns_w > 0 and gap or 0))
        local book_title = self.item.book_title or ""

        local text_col = VerticalGroup:new{ align = "left" }
        if is_hero then
            table.insert(text_col, TextWidget:new{
                text = _("NEXT REVIEW"), face = face(true, 10), fgcolor = GRAY_DARK,
                max_width = text_w, padding = 0,
            })
        end
        table.insert(text_col, TextWidget:new{
            text = self.item.word or "", face = face(true, 15), fgcolor = BLACK,
            max_width = text_w, padding = 0,
        })
        table.insert(text_col, TextWidget:new{
            text = book_title ~= "" and book_title or _("Tap to view definition"),
            face = face(false, 11), fgcolor = GRAY_DARK, max_width = text_w, padding = 0,
        })

        local inner_h = card_h - 2 * Size.border.thin
        local tap_word = InputContainer:new{
            LeftContainer:new{ dimen = Geom:new{ w = text_w, h = inner_h }, text_col },
        }
        tap_word.ges_events = {
            AireTap = { GestureRange:new{
                ges = "tap",
                range = function() return tap_word.dimen or Geom:new{ x = 0, y = 0, w = 0, h = 0 } end,
            } },
        }
        tap_word.onAireTap = function()
            if self.item.callback then self.item.callback(self.item) end
            return true
        end

        local row_hg = HorizontalGroup:new{ align = "center", tap_word }
        if self.has_review_buttons then
            table.insert(row_hg, HorizontalSpan:new{ width = gap })
            table.insert(row_hg, makePill(btn_w, btn_h, _("Forgot"), false, function() self:onForgot() end))
            table.insert(row_hg, HorizontalSpan:new{ width = gap })
            table.insert(row_hg, makePill(btn_w, btn_h, _("Got it"), true, function() self:onGotIt() end))
        end

        self[1] = FrameContainer:new{
            width = card_w,
            height = card_h,
            bordersize = Size.border.thin,
            color = is_hero and GRAY_BORDER or GRAY_LINE,
            background = is_hero and GRAY_CARD or WHITE,
            radius = S(10),
            padding = 0,
            padding_left = pad,
            padding_right = pad,
            row_hg,
        }
    end, TAG)
end

local function patchMenuDialog(MenuDialog)
    if not MenuDialog or MenuDialog._aire_sheet_patched then return end
    MenuDialog._aire_sheet_patched = true
    safeWrap(MenuDialog, "init", function(orig_md_init, self)
        orig_md_init(self)
        self.covers_fullscreen = false
        local frame = self[1] and self[1][1]
        if frame and type(frame) == "table" then
            frame.width = package.loaded.aire_screen.sheetWidth()
            frame.bordersize = Size.border.thin
            frame.color = BLACK
            frame.background = WHITE
            frame.radius = S(14)
            frame.padding = S(14)
            self[1] = BottomContainer:new{
                dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() - S(6) },
                frame,
            }
        end
    end, TAG)
end

-- Pie del widget (frame → OverlapGroup → BottomContainer → VerticalGroup
-- {línea, page_info}): sin la línea gruesa encima de la paginación y con el
-- tamaño recalculado si page_info ha cambiado
local function fixFooter(vb)
    local og = vb[1] and vb[1][1]
    local bc = og and og[#og]
    local vf = bc and bc[1]
    if vf and vf[1] and vf[2] == vb.page_info then
        vf[1].background = WHITE
        if vf.resetLayout then vf:resetLayout() end
    end
end

-- La clase del widget se parchea al cargar el plugin, antes de abrirlo: así
-- init, alturas y filas usan los espacios de Aire desde la primera vez.
local function patchWidgetClass(VBW)
    if not VBW or VBW._aire_vb_layout then return end
    VBW._aire_vb_layout = true

    safeWrap(VBW, "refreshFooter", function(orig_rf, self, ...)
        local r = orig_rf(self, ...)
        -- KOReader vuelve a poner aquí el ancho de las filas
        if self.dimen then self.item_width = self.dimen.w - 2 * S(SIDE_PAD) end
        return r
    end, TAG)

    safeWrap(VBW, "setupItemHeight", function(orig_setup, self, ...)
        local r = orig_setup(self, ...)
        if self.dimen and self.title_bar and self.item_height and self.item_table then
            local gap = S(GAP)
            self.item_width = self.dimen.w - 2 * S(SIDE_PAD)
            self.item_margin = gap
            local content_h = self.dimen.h - self.title_bar:getHeight() - (self.footer_height or 0) - gap
            self.items_per_page = math.max(1, math.floor((content_h + gap) / (self.item_height + gap)))
            self.pages = math.ceil(#self.item_table / self.items_per_page)
            self.show_page = math.max(1, math.min(self.pages, self.show_page or 1))
        end
        return r
    end, TAG)

    local orig_pop = VBW._populateItems
    patchItemClass(getUpValue(orig_pop, "VocabItemWidget"))
    safeWrap(VBW, "_populateItems", function(_orig, self, ...)
        local r = _orig(self, ...)
        -- Sin el medio margen que KOReader pone antes de la primera fila
        local mc = self.main_content
        local first = mc and mc[1]
        if first and #mc > 1 and first.width and first.width > 0 and first[1] == nil then
            first.width = 0
            mc:resetLayout()
        end
        showEmptyVocab(self)
        return r
    end, TAG)

    safeWrap(VBW, "init", function(orig_init, self, ...)
        local r = orig_init(self, ...)
        pcall(fixFooter, self)
        return r
    end, TAG)

    patchMenuDialog(getUpValue(VBW.onShowMenu, "MenuDialog"))

    -- Paginación por puntos (styles/ui/pagination.lua; se carga después, pero
    -- este parche se ejecuta más tarde, al crear el plugin)
    local Menu = require("ui/widget/menu")
    if Menu._aire_patch_vocab_footer then Menu._aire_patch_vocab_footer(VBW) end
end

local function patchPlugin(VocabBuilder)
    if not VocabBuilder or VocabBuilder._aire_vb_styled then return end
    local orig_show = VocabBuilder.onShowVocabBuilder
    if orig_show == nil then return end
    VocabBuilder._aire_vb_styled = true
    VocabBuilder._aire_orig_onShowVocabBuilder = orig_show

    local VBW = getUpValue(orig_show, "VocabularyBuilderWidget")
    if VBW then
        patchWidgetClass(VBW)
    else
        logger.dbg("Aire/VocabBuilder: clase del widget no encontrada al cargar (onShowVocabBuilder es "
            .. type(orig_show) .. "); se aplicará al abrirlo")
    end

    safeWrap(VocabBuilder, "onShowVocabBuilder", function(_orig, self, ...)
        local res = _orig(self, ...)
        local w = self.widget
        if w and not VBW then
            -- Plan B: parchear la clase al abrirlo la primera vez y rehacer la lista
            local mt = getmetatable(w)
            local cls = mt and mt.__index
            if type(cls) == "table" and not cls._aire_vb_layout then
                local ok, err = pcall(patchWidgetClass, cls)
                if ok then
                    -- Con la clase ya parcheada, se vuelve a abrir entera: rehacer
                    -- solo la lista dejaba el resto con las medidas de KOReader
                    -- (márgenes mal la primera vez, bien a partir de la segunda).
                    -- Es antes de que se pinte nada, así que no se ve el cambio.
                    -- Se reabre por self:onShowVocabBuilder (no _orig) para pasar
                    -- también por lo que envuelve a esta función por fuera (la
                    -- cabecera de Aire, styles/ui/titlebar.lua, que solo ajusta
                    -- la primera barra de título que se crea).
                    local UIManager = require("ui/uimanager")
                    UIManager:close(w)
                    self.widget = nil
                    return self:onShowVocabBuilder(...)
                else
                    logger.warn("Aire/VocabBuilder:", err)
                end
            end
        end
        if w and w.title_bar and w.title_bar.setSubTitle then
            local total = (w.item_table and #w.item_table) or 0
            w.title_bar:setSubTitle(T(N_("Vocabulary review · %1 word", "Vocabulary review · %1 words", total), total), true)
        end
        return res
    end, TAG)

    logger.dbg("Aire/VocabBuilder: aplicado desde el plugin")
end

-- Protegido: este parche se ejecuta dentro de FileManager:init; si falla sin
-- pcall, KOReader no llega a arrancar
userpatch.registerPatchPluginFunc("vocabbuilder", function(VocabBuilder)
    local ok, err = pcall(patchPlugin, VocabBuilder)
    if not ok then logger.warn("Aire/VocabBuilder: no se pudo aplicar:", err) end
end)
