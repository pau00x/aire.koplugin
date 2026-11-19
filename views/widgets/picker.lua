--[[
    aire.koplugin/views/widgets/picker.lua
    Presets de widgets, galería de pruebas, selector de widgets, diálogo de
    opciones y modo edición.

    Lo carga views/widgets/init.lua pasando las dependencias compartidas.
    OJO: no usar "_" como variable de bucle (tapa a gettext).
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template
local C_ = _.pgettext

local Screen = Device.screen
local BLACK = Blitbuffer.COLOR_BLACK
local GRAY_TEXT = Blitbuffer.COLOR_DARK_GRAY

return function(deps)
    local W = deps.W
    local ORDER = deps.ORDER
    local COLS = deps.COLS
    local config = deps.config
    local saveConfig = deps.saveConfig
    local ctx = deps.ctx
    local S, face = ctx.S, ctx.face
    local placed = deps.placed
    local available = deps.available

    -- Presets: combinaciones listas para Inicio (Aire → Inicio y widgets →
    -- Presets de widgets). "reader" se pone solo en la primera instalación.
    -- Claves "fila:columna" (4 columnas, hasta 3 filas: las que no quepan no se
    -- ven); los widgets que el dispositivo no tiene (luz, wifi…) se saltan solos.
    local L2 = function(id, extra)
        local t = { id = id, span = 2 }
        for k, v in pairs(extra or {}) do t[k] = v end
        return t
    end
    local S1 = function(id) return { id = id, span = 1 } end
    local PRESETS = {
        { id = "reader", name = _("Reader"), widgets = {
            ["1:1"] = L2("next_series"), ["1:3"] = S1("light"), ["1:4"] = S1("search"),
            ["2:1"] = S1("wifi"),        ["2:2"] = S1("ssh"),   ["2:3"] = L2("finished", { period = "year" }),
        } },
        { id = "progress", name = _("Progress"), widgets = {
            ["1:1"] = L2("today"),       ["1:3"] = L2("finished", { period = "month" }),
            ["2:1"] = L2("next_series"), ["2:3"] = L2("previous"),
            ["3:1"] = L2("quote"),       ["3:3"] = L2("random"),
        } },
        { id = "quick", name = C_("aire", "Quick actions"), widgets = {
            ["1:1"] = S1("light"),   ["1:2"] = S1("wifi"),    ["1:3"] = S1("night"),     ["1:4"] = S1("refresh"),
            ["2:1"] = S1("search"),  ["2:2"] = S1("dict"),    ["2:3"] = S1("wiki"),      ["2:4"] = S1("folders"),
            ["3:1"] = S1("battery"), ["3:2"] = S1("storage"), ["3:3"] = S1("bookmarks"), ["3:4"] = S1("screenshot"),
        } },
        { id = "minimal", name = C_("aire", "Minimal"), widgets = {
            ["1:1"] = L2("next_series"), ["1:3"] = S1("today"), ["1:4"] = S1("light"),
        } },
        { id = "empty", name = C_("aire", "Empty"), widgets = {} },
    }
    local DEFAULT_PRESET = "reader"

    local function presetWidgets(id)
        for _i, p in ipairs(PRESETS) do
            if p.id == id then
                local copy = {}
                for key, v in pairs(p.widgets) do
                    local w = {}
                    for k, x in pairs(v) do w[k] = x end
                    copy[key] = w
                end
                return copy
            end
        end
    end

    local function redraw(self)
        saveConfig()
        self:apply()
        UIManager:setDirty(self.ui, "ui")
    end

    -- ¿Está libre la celda de la derecha de key?
    local function rightFree(key)
        local r, c = key:match("^(%d+):(%d+)$")
        r, c = tonumber(r), tonumber(c)
        if not r or c >= COLS then return false end
        local right = placed()[r .. ":" .. (c + 1)]
        return not (right and W[right.id])
    end

    local M = {
        DEFAULT_PRESET = DEFAULT_PRESET,
        presetWidgets = presetWidgets,
    }

    function M.install(Aire)
        -- Para el menú (menu.lua): { id, name } de cada preset, en orden
        function Aire:getWidgetPresets()
            local list = {}
            for _i, p in ipairs(PRESETS) do table.insert(list, { id = p.id, name = p.name }) end
            return list
        end

        -- Sustituye los widgets de Inicio por los del preset
        function Aire:applyWidgetPreset(id)
            local w = presetWidgets(id)
            if not w then return false end
            config.home_widgets = w
            self._widgets_edit = nil
            if self.invalidateWidgetData then self:invalidateWidgetData() end
            saveConfig()
            if self.isOwnView and self:isOwnView() then
                self.view = "home"
                self:apply()
                UIManager:setDirty(self.ui, "ui")
            end
            return true
        end

        ---------------------------------------------------------------------
        -- Pruebas (galería de widgets, devtools.lua): cada widget en grande, en
        -- pequeño y en pequeño invertido, con datos inventados. Los toques no
        -- hacen nada (la galería no debe encender la wifi, la luz…).
        -- Devuelve las páginas como funciones que montan cada una.
        ---------------------------------------------------------------------
        function Aire:widgetGalleryPages()
            local ids = {}
            for _i, id in ipairs(ORDER) do
                if W[id] and available(self, W[id]) then table.insert(ids, id) end
            end
            local sw, sh = Screen:getWidth(), Screen:getHeight()
            local side = S(ctx.SIDE_PAD)
            local w = sw - 2 * side
            local gap = S(ctx.WIDGET_GAP or 14)
            local col_w = math.floor((w - (COLS - 1) * gap) / COLS)
            local large_w = 2 * col_w + gap
            local cell_h = S(112)
            local label_h = S(22)
            local head_h = S(70)
            local per_page = math.max(1, math.floor((sh - head_h - S(20)) / (label_h + cell_h + gap)))
            local pages = {}
            local n_pages = math.ceil(#ids / per_page)
            for pi = 1, n_pages do
                local from = (pi - 1) * per_page + 1
                local to = math.min(#ids, from + per_page - 1)
                table.insert(pages, {
                    T(_("Widgets %1–%2"), from, to),
                    function(covers_out)
                        local TEST = self.getTestTools and self:getTestTools()
                        local books = {}
                        for _i, b in ipairs(self.getLibraryBooks and self:getLibraryBooks() or {}) do
                            if not b.fake and #books < 6 then table.insert(books, b.path) end
                        end
                        -- Portadas de esta página: propias (no las libera Inicio al redibujarse)
                        local saved_covers = self._widget_covers
                        self._widget_covers = {}
                        self._demo_widget_data = (TEST and TEST.fakeWidgetData)
                            and function(id) return TEST.fakeWidgetData(id, books) end or nil
                        local content = VerticalGroup:new{ align = "left" }
                        table.insert(content, VerticalSpan:new{ width = S(16) })
                        table.insert(content, TextWidget:new{
                            text = T(_("Widget gallery · %1 / %2"), pi, n_pages),
                            face = face(true, 17), fgcolor = BLACK, padding = 0 })
                        table.insert(content, TextWidget:new{
                            text = _("Large · small · small inverted — swipe ← →, tap to exit"),
                            face = face(false, 12), fgcolor = GRAY_TEXT, max_width = w, padding = 0 })
                        table.insert(content, VerticalSpan:new{ width = S(14) })
                        local function cell(opts, size, width)
                            local c = self:buildWidgetCell(opts, size, width, cell_h, "gallery")
                            c.on_tap, c.on_hold = nil, nil
                            return c
                        end
                        for i = from, to do
                            local id = ids[i]
                            local wd = W[id]
                            table.insert(content, TextWidget:new{
                                text = ("%d · %s"):format(i, wd.title or id), face = face(true, 12),
                                fgcolor = GRAY_TEXT, max_width = w, padding = 0 })
                            table.insert(content, VerticalSpan:new{ width = S(4) })
                            local row = HorizontalGroup:new{ align = "top" }
                            table.insert(row, cell({ id = id, span = 2 }, "L", large_w))
                            table.insert(row, HorizontalSpan:new{ width = gap })
                            if wd.needs_large then
                                table.insert(row, cell({ id = id, span = 2, invert = true }, "L", large_w))
                            else
                                table.insert(row, cell({ id = id, span = 1 }, "S", col_w))
                                table.insert(row, HorizontalSpan:new{ width = gap })
                                table.insert(row, cell({ id = id, span = 1, invert = true }, "S", col_w))
                            end
                            table.insert(content, row)
                            table.insert(content, VerticalSpan:new{ width = gap })
                        end
                        self._demo_widget_data = nil
                        for _i, bb in ipairs(self._widget_covers) do table.insert(covers_out, bb) end
                        self._widget_covers = saved_covers
                        return HorizontalGroup:new{ HorizontalSpan:new{ width = side }, content }
                    end,
                })
            end
            return pages
        end

        -- Elegir widget: hoja en dos columnas con icono; al tocar uno se coloca
        -- directamente (sus opciones, tocándolo en edición)
        function Aire:showWidgetPicker(key)
            local can_large = rightFree(key)
            self:showOptionSheet(_("Add widget"), function()
                local rows = {}
                for _i, id in ipairs(ORDER) do
                    local w = W[id]
                    if available(self, w) and (not w.needs_large or can_large) then
                        table.insert(rows, {
                            text = w.title, icon = w.icon,
                            callback = function(sheet)
                                placed()[key] = { id = id, span = w.needs_large and 2 or 1 }
                                sheet:close()
                                redraw(self)
                            end,
                        })
                    end
                end
                return rows
            end, { { text = _("Cancel"), callback = function(sheet) sheet:close() end } }, nil, 2)
        end

        function Aire:showWidgetOptions(key)
            local opts = placed()[key]
            if not opts or not W[opts.id] then return end
            local w = W[opts.id]
            local function set(field, value, sheet)
                opts[field] = value
                redraw(self)
                if sheet then sheet:rebuild() end
            end
            self:showOptionSheet(w.title, function()
                local rows = {}
                local is_large = opts.span == 2 or w.needs_large
                table.insert(rows, {
                    text = _("Large (also occupies the right cell)"),
                    checked = is_large and true or false,
                    enabled = (not w.needs_large) and (is_large or rightFree(key)),
                    callback = function(sheet) set("span", is_large and 1 or 2, sheet) end,
                })
                table.insert(rows, {
                    text = _("Inverted colors"), checked = opts.invert and true or false,
                    callback = function(sheet) set("invert", (not opts.invert) or nil, sheet) end,
                })
                if w.tap and not w.hold then
                    table.insert(rows, {
                        text = _("Hold does the same as tap"), checked = opts.hold_tap and true or false,
                        callback = function(sheet)
                            opts.swap = nil -- no se puede con "Intercambiar"
                            set("hold_tap", (not opts.hold_tap) or nil, sheet)
                        end,
                    })
                end
                if w.tap or w.hold then
                    table.insert(rows, {
                        text = _("Swap tap and hold"), checked = opts.swap and true or false,
                        enabled = not opts.hold_tap,
                        callback = function(sheet) set("swap", (not opts.swap) or nil, sheet) end,
                    })
                end
                if w.options then
                    for _i, r in ipairs(w.options(opts, set)) do table.insert(rows, r) end
                end
                return rows
            end, {
                { text = _("Change"), callback = function(sheet) sheet:close(); self:showWidgetPicker(key) end },
                { text = C_("aire", "Remove"), callback = function(sheet)
                    sheet:close()
                    placed()[key] = nil
                    redraw(self)
                end },
                { text = _("Done"), primary = true, callback = function(sheet) sheet:close() end },
            })
        end

        -- Entrar / salir del modo edición (se abre en Inicio)
        function Aire:setWidgetsEdit(on)
            self._widgets_edit = on and true or nil
            if self:isHomeVisible() then
                self:apply()
                UIManager:setDirty(self.ui, "ui")
            else
                self:showHome()
            end
        end
    end

    return M
end
