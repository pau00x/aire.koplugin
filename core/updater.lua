--[[
    aire.koplugin/core/updater.lua
    Actualizaciones de Aire desde las releases de GitHub (sin interfaz: las
    hojas y el menú están en views/update_sheet.lua).

      fetchLatest(include_beta)   -> info | nil, err     (consulta la API)
      isNewer(a, b)               -> true si la versión a es mayor que b
      download(info, on_progress) -> ruta del zip | nil, err
      install(zip_path, info)     -> true | nil, err

    Instalación: se descomprime en <plugins>/aire.koplugin.new, se comprueba
    (_meta.lua y main.lua, y la versión esperada), la carpeta actual pasa a
    aire.koplugin.old y la nueva a aire.koplugin. Si algo falla, la instalada
    queda como estaba. .old se borra en el siguiente arranque que llega bien
    hasta el explorador (cleanup, desde views/update_sheet.lua). KOReader solo carga carpetas *.koplugin, así que .new y
    .old no se cargan nunca. Los ajustes de Aire están en settings.reader.lua y
    las miniaturas en cache/: nada vive dentro de la carpeta del plugin.
--]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local M = {}

M.REPO = "pau00x/aire.koplugin"
M.API_URL = "https://api.github.com/repos/" .. M.REPO .. "/releases?per_page=10"
local TAG = "Aire/Update:"

-- Carpeta del plugin (la de este archivo, sin /core)
local PLUGIN_DIR = (debug.getinfo(1, "S").source or ""):match("^@(.*)/core/[^/]*$") or "plugins/aire.koplugin"
M.PLUGIN_DIR = PLUGIN_DIR

-- Versión de _meta.lua leída como texto (con dofile se volverían a cargar las traducciones)
local function readVersion(dir)
    local fh = io.open(dir .. "/_meta.lua", "r")
    if not fh then return nil end
    local meta = fh:read("*a") or ""
    fh:close()
    return meta:match('version%s*=%s*"([^"]+)"')
end

function M.installedVersion()
    return readVersion(PLUGIN_DIR) or "0"
end

-- ¿Hay herramientas de desarrollo (dev/) en esta copia? La versión publicada no las trae
function M.hasDevFolder()
    return lfs.attributes(PLUGIN_DIR .. "/dev", "mode") == "directory"
end

---------------------------------------------------------------------------
-- Versiones: "v0.2.0", "0.2.0", "0.2.0-beta.1" (lo que va tras "-" es menor)
---------------------------------------------------------------------------
local function parseVersion(v)
    v = tostring(v or ""):gsub("^[vV]", "")
    local main, pre = v:match("^([%d%.]+)%-?(.*)$")
    local nums = {}
    for n in (main or ""):gmatch("%d+") do table.insert(nums, tonumber(n)) end
    return nums, pre or ""
end

local function comparePre(pa, pb)
    local sa, sb = {}, {}
    for p in pa:gmatch("[^%.]+") do table.insert(sa, p) end
    for p in pb:gmatch("[^%.]+") do table.insert(sb, p) end
    for i = 1, math.max(#sa, #sb) do
        local x, y = sa[i], sb[i]
        if x == nil then return false end
        if y == nil then return true end
        if x ~= y then
            local nx, ny = x:match("^%d+$") and tonumber(x), y:match("^%d+$") and tonumber(y)
            if nx and ny then return nx > ny end
            if nx then return false end
            if ny then return true end
            return x > y
        end
    end
    return false
end

function M.isNewer(a, b)
    local na, pa = parseVersion(a)
    local nb, pb = parseVersion(b)
    for i = 1, math.max(#na, #nb) do
        local x, y = na[i] or 0, nb[i] or 0
        if x ~= y then return x > y end
    end
    -- Mismos números: la versión final es mayor que su beta
    if pa == "" and pb ~= "" then return true end
    if pa ~= "" and pb == "" then return false end
    return comparePre(pa, pb)
end

---------------------------------------------------------------------------
-- Red
---------------------------------------------------------------------------
local function request(url, sink, timeout, maxtime, accept)
    local http = require("socket.http")
    local socket = require("socket")
    local socketutil = require("socketutil")
    socketutil:set_timeout(timeout or 15, maxtime or 60)
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            sink = sink,
            headers = { ["Accept"] = accept or "application/vnd.github+json" },
        })
    end)
    socketutil:reset_timeout()
    if not ok then return nil, tostring(code) end
    if code ~= 200 then return nil, tostring(status or code or "network unreachable") end
    return true, headers
end

-- Última release publicada (con zip aire-*.zip). include_beta: también las pre-releases.
-- info = { version, tag, date, prerelease, notes, url, size, asset }
function M.fetchLatest(include_beta)
    local ltn12 = require("ltn12")
    local chunks = {}
    local ok, err = request(M.API_URL, ltn12.sink.table(chunks), 15, 30)
    if not ok then return nil, err end
    local ok_json, list = pcall(function() return require("rapidjson").decode(table.concat(chunks)) end)
    if not ok_json or type(list) ~= "table" then return nil, "bad json" end
    local best
    for _i, rel in ipairs(list) do
        if type(rel) == "table" and not rel.draft and (include_beta or not rel.prerelease)
                and type(rel.tag_name) == "string" then
            local asset
            for _j, a in ipairs(type(rel.assets) == "table" and rel.assets or {}) do
                if type(a) == "table" and type(a.name) == "string" and a.name:match("^aire%-.+%.zip$")
                        and type(a.browser_download_url) == "string" then
                    asset = a
                    break
                end
            end
            local version = rel.tag_name:gsub("^[vV]", "")
            if asset and (not best or M.isNewer(version, best.version)) then
                best = {
                    version = version,
                    tag = rel.tag_name,
                    date = type(rel.published_at) == "string" and rel.published_at:sub(1, 10) or nil,
                    prerelease = rel.prerelease == true,
                    notes = type(rel.body) == "string" and rel.body or "",
                    url = asset.browser_download_url,
                    size = tonumber(asset.size) or 0,
                    asset = asset.name,
                }
            end
        end
    end
    if not best then return nil, "no release" end
    return best
end

---------------------------------------------------------------------------
-- Novedades: el texto de la release está en Markdown (GitHub)
---------------------------------------------------------------------------
-- Quita las marcas de una línea: [texto](url) -> texto, **x**, __x__, `x`
local function mdInline(s)
    s = s:gsub("!%[([^%]]*)%]%b()", "%1"):gsub("%[([^%]]+)%]%b()", "%1")
    s = s:gsub("%*%*(.-)%*%*", "%1"):gsub("__(.-)__", "%1"):gsub("`([^`]*)`", "%1")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Bloques para mostrarlas: { kind = "heading" | "item" | "text", text, lead, sub }
--   "### Added"                  -> heading "Added"
--   "- **Home**: top bar…"       -> item, lead = "Home", text = "top bar…"
--   "  - detalle"                -> item con sub = true
--   otras líneas                 -> text (las seguidas se juntan en un párrafo)
function M.parseNotes(notes)
    local blocks, para = {}, nil
    local function flush()
        if para then table.insert(blocks, { kind = "text", text = mdInline(table.concat(para, " ")) }) end
        para = nil
    end
    for line in (tostring(notes or "") .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("\r", "")
        local heading = line:match("^%s*#+%s+(.+)$")
        local indent, item = line:match("^(%s*)[%-%*%+]%s+(.+)$")
        if heading then
            flush()
            table.insert(blocks, { kind = "heading", text = mdInline(heading) })
        elseif item and not line:match("^%s*[-*_][-*_][-*_]+%s*$") then
            flush()
            local lead, rest = item:match("^%*%*(.-)%*%*%s*[:.]?%s*(.*)$")
            table.insert(blocks, {
                kind = "item",
                lead = lead and mdInline(lead) or nil,
                text = mdInline(lead and rest or item),
                sub = #indent >= 2 or nil,
            })
        elseif line:match("^%s*$") or line:match("^%s*[-*_][-*_][-*_]+%s*$") then
            flush()
        else
            para = para or {}
            table.insert(para, line)
        end
    end
    flush()
    return blocks
end

-- Las primeras n novedades (líneas "- …"), ya sin marcas
function M.notesSummary(notes, n)
    local out = {}
    for _i, b in ipairs(M.parseNotes(notes)) do
        if b.kind == "item" and not b.sub then
            local line = b.text
            if b.lead then line = b.text ~= "" and (b.lead .. ": " .. b.text) or b.lead end
            table.insert(out, line)
            if #out >= n then break end
        end
    end
    return out
end

-- Descarga el zip en cache/. on_progress(bytes, total) en cada trozo.
function M.download(info, on_progress)
    local dir = DataStorage:getDataDir() .. "/cache"
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local path = dir .. "/aire-update.zip"
    os.remove(path)
    local fh = io.open(path, "wb")
    if not fh then return nil, "cannot write " .. path end
    local got = 0
    local sink = function(chunk, err)
        if chunk then
            fh:write(chunk)
            got = got + #chunk
            if on_progress then pcall(on_progress, got, info.size) end
        else
            fh:close()
        end
        return 1, err
    end
    local ok, err = request(info.url, sink, 20, 300, "application/octet-stream")
    pcall(fh.close, fh)
    if not ok then
        os.remove(path)
        return nil, err
    end
    if info.size and info.size > 0 and lfs.attributes(path, "size") ~= info.size then
        os.remove(path)
        return nil, "size mismatch"
    end
    return path
end

---------------------------------------------------------------------------
-- Instalación
---------------------------------------------------------------------------
local function purge(dir)
    if lfs.attributes(dir, "mode") == "directory" then
        require("ffi/util").purgeDir(dir)
    end
end

local function extract(zip_path, dest)
    local Archiver = require("ffi/archiver")
    local reader = Archiver.Reader:new()
    if not reader:open(zip_path) then return nil, "cannot open zip" end
    lfs.mkdir(dest)
    local n = 0
    local err
    for entry in reader:iterate() do
        -- Solo lo que hay dentro de aire.koplugin/ y sin rutas raras
        local rel = entry.path:match("^aire%.koplugin/(.+)$")
        if rel and not rel:find("%.%.") and not rel:find("^/") then
            rel = rel:gsub("/$", "")
            if entry.mode == "directory" then
                lfs.mkdir(dest .. "/" .. rel)
            elseif entry.mode == "file" then
                if not reader:extractToPath(entry.path, dest .. "/" .. rel) then
                    err = "extract failed: " .. rel .. " " .. tostring(reader.err)
                    break
                end
                n = n + 1
            end
        end
    end
    reader:close()
    if err then return nil, err end
    if n == 0 then return nil, "empty zip" end
    return n
end

function M.install(zip_path, info)
    local parent = PLUGIN_DIR:match("^(.*)/[^/]+$") or "plugins"
    local new_dir = parent .. "/aire.koplugin.new"
    local old_dir = parent .. "/aire.koplugin.old"
    purge(new_dir)
    local n, err = extract(zip_path, new_dir)
    if not n then
        purge(new_dir)
        return nil, err
    end
    -- Comprobar que está completa y que es la versión esperada
    for _i, f in ipairs({ "_meta.lua", "main.lua" }) do
        if lfs.attributes(new_dir .. "/" .. f, "mode") ~= "file" then
            purge(new_dir)
            return nil, "missing " .. f
        end
    end
    local new_version = readVersion(new_dir)
    if info and info.version and new_version ~= info.version then
        purge(new_dir)
        return nil, "unexpected version " .. tostring(new_version)
    end
    -- Cambiar las carpetas (si falla el segundo paso, se deshace el primero)
    purge(old_dir)
    local ok1, e1 = os.rename(PLUGIN_DIR, old_dir)
    if not ok1 then
        purge(new_dir)
        return nil, "rename current: " .. tostring(e1)
    end
    local ok2, e2 = os.rename(new_dir, PLUGIN_DIR)
    if not ok2 then
        os.rename(old_dir, PLUGIN_DIR)
        purge(new_dir)
        return nil, "rename new: " .. tostring(e2)
    end
    os.remove(zip_path)
    logger.dbg(TAG, "installed", new_version, "(" .. n .. " files)")
    return true
end

-- Restos de una actualización: la versión anterior (.old, copia de rescate) y
-- una instalación a medias (.new). Se borran al arrancar bien la versión nueva.
function M.cleanup()
    local parent = PLUGIN_DIR:match("^(.*)/[^/]+$") or "plugins"
    for _i, dir in ipairs({ parent .. "/aire.koplugin.old", parent .. "/aire.koplugin.new" }) do
        if lfs.attributes(dir, "mode") == "directory" then
            local ok, err = require("ffi/util").purgeDir(dir)
            if not ok then logger.warn(TAG, "no se pudo borrar", dir, err) end
        end
    end
end

function M.warn(...)
    logger.warn(TAG, ...)
end

return M
