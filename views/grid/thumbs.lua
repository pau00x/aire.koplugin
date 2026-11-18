--[[
    aire.koplugin/views/grid/thumbs.lua
    Miniaturas de portadas en disco, ya escaladas al tamaño de la celda de
    Librería / Colecciones / Historial. La primera vez se hace como siempre
    (leer la portada de CoverBrowser, descomprimirla y escalarla) y se guarda
    aquí; las siguientes solo se lee un archivo pequeño.

    Carpeta: <datos de KOReader>/cache/aire-thumbs/
    Nombre:  md5(ruta | tamaño del archivo | fecha | ancho×alto)  -> si el libro
             cambia o la celda cambia de tamaño, es otra miniatura.
    Formato: "AIRE1 w h tipo stride\n" + datos del Blitbuffer comprimidos con
             zstd (lo mismo que usa CoverBrowser para sus portadas).

    Todo va protegido: si algo falla, se devuelve nil y la portada se hace
    como antes.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local ffi = require("ffi")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local md5 = require("ffi/sha2").md5
local C = ffi.C

local ok_z, zstd = pcall(require, "ffi/zstd")
if not ok_z then zstd = nil end

local DIR = DataStorage:getDataDir() .. "/cache/aire-thumbs"
local MAX_FILES = 600 -- al pasar de aquí se borran las más antiguas

local M = {}

local dir_ready = false
local function ensureDir()
    if dir_ready then return true end
    local cache = DataStorage:getDataDir() .. "/cache"
    if lfs.attributes(cache, "mode") ~= "directory" then lfs.mkdir(cache) end
    if lfs.attributes(DIR, "mode") ~= "directory" then lfs.mkdir(DIR) end
    dir_ready = lfs.attributes(DIR, "mode") == "directory"
    return dir_ready
end

local function fileFor(path, w, h)
    local attr = lfs.attributes(path)
    if not attr then return nil end
    return DIR .. "/" .. md5(table.concat({ path, attr.size or 0, attr.modification or 0, w .. "x" .. h }, "|")) .. ".thumb"
end

--- Miniatura guardada de path para una caja de w×h, o nil.
-- El Blitbuffer devuelto es del que llama (hay que liberarlo).
function M.get(path, w, h)
    if not zstd or not path then return nil end
    local ok, res = pcall(function()
        local f = fileFor(path, w, h)
        if not f then return nil end
        local fh = io.open(f, "rb")
        if not fh then return nil end
        local head = fh:read("*l")
        local data = fh:read("*a")
        fh:close()
        local bw, bh, btype, stride = (head or ""):match("^AIRE1 (%d+) (%d+) (%d+) (%d+)$")
        bw, bh, btype, stride = tonumber(bw), tonumber(bh), tonumber(btype), tonumber(stride)
        if not (bw and bh and btype and stride and data and #data > 0) then return nil end
        local buf, size = zstd.zstd_uncompress_ctx(ffi.cast("const void *", data), #data)
        if tonumber(size) ~= stride * bh then
            C.free(buf)
            return nil
        end
        local bb = Blitbuffer.new(bw, bh, btype, buf, stride)
        bb:setAllocated(1)
        return bb
    end)
    if ok then return res end
    logger.dbg("Aire/Thumbs: no se pudo leer", path, res)
    return nil
end

--- Guarda bb (ya escalado) como miniatura de path para una caja de w×h.
function M.put(path, w, h, bb)
    if not zstd or not path or not bb or not ensureDir() then return end
    local ok, err = pcall(function()
        local f = fileFor(path, w, h)
        if not f then return end
        local size = bb.stride * bb.h
        local cbuf, clen = zstd.zstd_compress(bb.data, size)
        local fh = io.open(f .. ".tmp", "wb")
        if not fh then
            C.free(cbuf)
            return
        end
        fh:write(string.format("AIRE1 %d %d %d %d\n", bb:getWidth(), bb:getHeight(), bb:getType(), bb.stride))
        fh:write(ffi.string(cbuf, tonumber(clen)))
        fh:close()
        C.free(cbuf)
        os.rename(f .. ".tmp", f)
    end)
    if not ok then logger.dbg("Aire/Thumbs: no se pudo guardar", path, err) end
end

--- Si hay demasiadas, borrar las más antiguas (por fecha de acceso/cambio).
function M.trim()
    if not ensureDir() then return end
    pcall(function()
        local list = {}
        for name in lfs.dir(DIR) do
            if name:match("%.thumb$") then
                local p = DIR .. "/" .. name
                local attr = lfs.attributes(p)
                if attr then table.insert(list, { p = p, t = attr.access or attr.modification or 0 }) end
            elseif name:match("%.tmp$") then
                os.remove(DIR .. "/" .. name)
            end
        end
        if #list <= MAX_FILES then return end
        table.sort(list, function(a, b) return a.t < b.t end)
        for i = 1, #list - MAX_FILES do os.remove(list[i].p) end
    end)
end

--- Borrar todas (p. ej. desde el menú de pruebas).
function M.clear()
    if lfs.attributes(DIR, "mode") ~= "directory" then return end
    pcall(function()
        for name in lfs.dir(DIR) do
            if name ~= "." and name ~= ".." then os.remove(DIR .. "/" .. name) end
        end
    end)
end

M.DIR = DIR
return M
