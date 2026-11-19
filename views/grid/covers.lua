--[[
    aire.koplugin/views/grid/covers.lua
    Caché LRU de portadas escaladas por pestaña de cuadrícula (Librería,
    Colecciones, Historial, Terminados).

    Cada entrada guarda el Blitbuffer escalado al tamaño de la celda; el
    original de CoverBrowser se libera en cuanto se escala (salvo que
    scaleBlitBuffer devuelva el mismo buffer). Las entradas de la página
    visible actual pueden marcarse como fijadas (pin=true) para garantizar que
    el desalojo nunca libere un buffer en uso en pantalla.

    Uso:
      local Covers = dofile(GRID_DIR .. "/covers.lua")({
          getBIM = getBIM, Thumbs = Thumbs, RenderImage = RenderImage,
      })
      local cache = Covers.new(48)
      cache:clearPins()
      local bb = cache:get(path, w, h, slow, pin)
      cache:freeAll()
--]]

return function(deps)
    local getBIM = deps.getBIM
    local Thumbs = deps.Thumbs
    local RenderImage = deps.RenderImage or require("ui/renderimage")

    local Covers = {}
    Covers.DEFAULT_MAX = 48 -- por pestaña (~3 páginas de 4 columnas)

    local Cache = {}
    Cache.__index = Cache

    function Covers.new(max)
        return setmetatable({
            max = max or Covers.DEFAULT_MAX,
            items = {},   -- key -> { bb = Blitbuffer, seq = number, pinned = bool }
            missing = {}, -- path -> true (libros sin portada en CoverBrowser)
            aux = {},     -- escaladas auxiliares (GridCell:coverImage en modo demo)
            _count = 0,
            _seq = 0,
        }, Cache)
    end

    function Cache:_touch(entry, pin)
        self._seq = self._seq + 1
        entry.seq = self._seq
        if pin then entry.pinned = true end
    end

    function Cache:_evictOne()
        local victim_key, victim
        for k, entry in pairs(self.items) do
            if not entry.pinned and (not victim or entry.seq < victim.seq) then
                victim_key, victim = k, entry
            end
        end
        if not victim then return false end
        pcall(victim.bb.free, victim.bb)
        self.items[victim_key] = nil
        self._count = self._count - 1
        return true
    end

    function Cache:_put(key, bb, pin)
        local old = self.items[key]
        if old then
            if not rawequal(old.bb, bb) then pcall(old.bb.free, old.bb) end
            old.bb = bb
            self:_touch(old, pin)
            return
        end
        while self._count >= self.max do
            if not self:_evictOne() then break end
        end
        self._seq = self._seq + 1
        self.items[key] = { bb = bb, seq = self._seq, pinned = pin == true }
        self._count = self._count + 1
    end

    function Cache:clearPins()
        for _k, entry in pairs(self.items) do
            entry.pinned = false
        end
    end

    function Cache:count()
        return self._count
    end

    --- Portada ya escalada a w×h.
    -- slow=false: memoria o miniatura en disco (Thumbs).
    -- slow=true: además CoverBrowser + escalar + guardar en Thumbs.
    -- pin=true: protege la entrada frente a desalojo mientras sea visible.
    function Cache:get(path, w, h, slow, pin)
        if not path or not w or not h then return nil end
        local key = "t|" .. path .. "|" .. w .. "x" .. h
        local entry = self.items[key]
        if entry then
            self:_touch(entry, pin)
            return entry.bb
        end
        local sbb = Thumbs.get(path, w, h)
        if sbb then
            self:_put(key, sbb, pin)
            return sbb
        end
        if not slow or self.missing[path] then return nil end
        local BIM = getBIM and getBIM()
        if not BIM then return nil end
        local ok, bi = pcall(BIM.getBookInfo, BIM, path, true)
        local cbb = ok and bi and bi.has_cover and bi.cover_bb or nil
        if not cbb then
            self.missing[path] = true
            return nil
        end
        local iw, ih = cbb:getWidth(), cbb:getHeight()
        local s = math.min(w / iw, h / ih)
        local ok2, res = pcall(RenderImage.scaleBlitBuffer, RenderImage, cbb,
            math.max(1, math.floor(iw * s + 0.5)), math.max(1, math.floor(ih * s + 0.5)), false)
        if not ok2 or not res then
            pcall(cbb.free, cbb)
            return nil
        end
        Thumbs.put(path, w, h, res)
        if not rawequal(res, cbb) then pcall(cbb.free, cbb) end
        self:_put(key, res, pin)
        return res
    end

    function Cache:freeAll()
        for _k, entry in pairs(self.items) do
            pcall(entry.bb.free, entry.bb)
        end
        for _k, sbb in pairs(self.aux) do
            pcall(sbb.free, sbb)
        end
        self.items = {}
        self.missing = {}
        self.aux = {}
        self._count = 0
        self._seq = 0
    end

    return Covers
end
