--[[
    aire.koplugin/views/grid/library.lua
    Caché de sesión de la lista de libros y metadatos de Librería.

    Evita repetir scanBooks (recursivo) + loadMetadataUnder (SQLite) al volver
    de cada libro o al cambiar de pestaña. El progreso y estado de lectura
    vienen aparte de BookList.getBookInfo en makeBook(), así que siempre están
    al día aunque la lista venga de caché.

    Se invalida automáticamente cuando:
      - cambia la carpeta raíz (home_dir),
      - cambia el mtime de la carpeta raíz,
      - caduca el TTL (5 min, cubre cambios en subcarpetas por SSH/Calibre),
      - se llama a Library.invalidate() (onResume, onNotCharging / USB,
        reloadGridView("library"), fin del análisis de CoverBrowser).

    Uso:
      local Library = dofile(GRID_DIR .. "/library.lua")({
          scanBooks = Books.scanBooks,
          loadMetadataUnder = Books.loadMetadataUnder,
      })
      local files, meta = Library.get(root, BIM)
      Library.invalidate()
--]]

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

return function(deps)
    local scanBooks = deps.scanBooks
    local loadMetadataUnder = deps.loadMetadataUnder
    local now_fn = deps.now or os.time
    local mtime_fn = deps.mtime or function(p) return lfs.attributes(p, "modification") or 0 end

    local Library = {}
    Library.TTL = 5 * 60 -- segundos

    local cache = nil -- { root, mtime, loaded_at, files, meta }

    function Library.invalidate()
        cache = nil
    end

    function Library.get(root, BIM)
        local mtime = mtime_fn(root)
        local now = now_fn()
        if cache
            and cache.root == root
            and cache.mtime == mtime
            and (now - cache.loaded_at) < Library.TTL
        then
            return cache.files, cache.meta, true
        end
        local files = {}
        scanBooks(root, files, 1)
        local meta = loadMetadataUnder(BIM, root)
        cache = {
            root = root,
            mtime = mtime,
            loaded_at = now,
            files = files,
            meta = meta,
        }
        logger.dbg("Aire/Library: escaneado", root, #files, "libros")
        return files, meta, false
    end

    return Library
end
