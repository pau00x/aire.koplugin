--[[
    aire.koplugin/styles/ui/progress.lua
    Barras de progreso (ProgressWidget) en forma de cápsula y sin borde.
    Lo carga styles/ui.lua en su orden (recibe la tabla de styles/ui/base.lua).
--]]

local B = ...
local uiOpt = B.uiOpt
local Device = require("device")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local ProgressWidget = require("ui/widget/progresswidget")
local _ = require("gettext")
local Screen = Device.screen
local safeWrap = package.loaded.aire_ui.safeWrap
local TAG = "Aire/UI"

-- stylua: ignore start
local ROUNDED_PROGRESS_BARS     = uiOpt("rounded_bars")   -- barras de progreso en forma de cápsula
local BORDERLESS_PROGRESS_BARS  = true   -- sin borde; si la pista es blanca se pinta en gris claro
-- stylua: ignore end

--===========================================================================
-- 10) BARRAS DE PROGRESO REDONDEADAS (PROGRESSWIDGET)
--===========================================================================
if ROUNDED_PROGRESS_BARS and not ProgressWidget._rounded_capsule_patched then
    ProgressWidget._rounded_capsule_patched = true

    safeWrap(ProgressWidget, "paintTo", function(orig_ProgressWidget_paintTo, self, bb, x, y)
        local my_size = self:getSize()
        if not my_size or my_size.w == 0 or my_size.h == 0 then
            return orig_ProgressWidget_paintTo(self, bb, x, y)
        end
        -- Si la barra ocupa todo el ancho de la pantalla y no tiene borde (pie de
        -- lectura a sangre), mantener el dibujo recto original.
        if (not self.bordersize or self.bordersize == 0) and my_size.w >= Screen:getWidth() then
            return orig_ProgressWidget_paintTo(self, bb, x, y)
        end

        if not self.dimen then
            self.dimen = Geom:new{ x = x, y = y, w = my_size.w, h = my_size.h }
        else
            self.dimen.x, self.dimen.y = x, y
            self.dimen.w, self.dimen.h = my_size.w, my_size.h
        end

        local mirrored = BD.mirroredUILayout()
        if self.invert_direction then mirrored = not mirrored end

        local bw = BORDERLESS_PROGRESS_BARS and 0 or (self.bordersize or 0)
        local mh = self.margin_h or 0
        -- Sin borde, una pista blanca no se vería sobre fondo blanco: gris claro
        local track = self.bgcolor
        if BORDERLESS_PROGRESS_BARS then
            local ok, v = pcall(function() return self.bgcolor:getColor8().a end)
            if not self.bgcolor or (ok and v and v >= 0xF0) then track = Blitbuffer.COLOR_GRAY_D end
        end
        local mv = self.margin_v or 0
        local fill_width = math.max(0, my_size.w - 2 * (mh + bw))
        local fill_y = y + mv + bw
        local fill_height = math.max(1, my_size.h - 2 * (mv + bw))
        local outer_r = math.floor(my_size.h / 2)
        local inner_r = math.floor(fill_height / 2)

        if bw > 0 then
            bb:paintRoundedRect(x, y, my_size.w, my_size.h, track, outer_r)
            bb:paintBorder(math.floor(x), math.floor(y), my_size.w, my_size.h, bw, self.bordercolor, outer_r)
        else
            bb:paintRoundedRect(x, y, my_size.w, my_size.h, track, outer_r)
        end

        if self.alt and self.alt[1] ~= nil and self.last and self.last > 0 then
            for i = 1, #self.alt do
                local tick_x = fill_width * ((self.alt[i][1] - 1) / self.last)
                local width = fill_width * (self.alt[i][2] / self.last)
                if mirrored then tick_x = fill_width - tick_x - width end
                bb:paintRoundedRect(
                    x + mh + bw + math.floor(tick_x),
                    fill_y,
                    math.ceil(width),
                    math.ceil(fill_height),
                    self.altcolor,
                    inner_r
                )
            end
        end

        -- Relleno: si no llega a medio círculo no se dibuja (al 0 % salía una
        -- raya vertical al principio); si llega, como mínimo un círculo
        local min_fw = math.ceil(fill_height)
        local raw_fw = fill_width * (self.percentage or 0)
        if self.percentage and self.percentage > 0 and self.percentage <= 1 and raw_fw >= min_fw / 2 then
            local fw = math.max(min_fw, math.ceil(raw_fw))
            local fx = x + mh + bw
            if self.fill_from_right or (mirrored and not self.fill_from_right) then
                fx = x + mh + bw + math.max(0, math.floor(fill_width - fw))
            end
            bb:paintRoundedRect(fx, fill_y, fw, math.ceil(fill_height), self.fillcolor, inner_r)

            if self.initial_pos_marker and self.initial_percentage and self.initial_percentage >= 0
                    and self.initial_pos_icon then
                local marker_x
                if mirrored then
                    marker_x = x + mh + bw + math.ceil(fill_width - (fill_width * self.initial_percentage))
                else
                    marker_x = x + mh + bw + math.ceil(fill_width * self.initial_percentage)
                end
                local icon_x, icon_y
                if self.height <= Screen:scaleBySize(12) then
                    icon_x = math.floor(marker_x - self.height * 0.25 + 0.5)
                    icon_y = y - math.floor(self.height / 6 + 0.5)
                else
                    icon_x = math.floor(marker_x - self.height * 0.5 + 0.5)
                    icon_y = y
                end
                self.initial_pos_icon:paintTo(bb, icon_x, icon_y)
            end
        end

        if self.ticks and self.last and self.last > 0 then
            for _, tick in ipairs(self.ticks) do
                local tick_x = fill_width * (tick / self.last)
                if mirrored then tick_x = fill_width - tick_x end
                bb:paintRect(
                    x + mh + bw + math.floor(tick_x),
                    fill_y,
                    self.tick_width,
                    math.ceil(fill_height),
                    self.bordercolor
                )
            end
        end
    end, TAG)
end
