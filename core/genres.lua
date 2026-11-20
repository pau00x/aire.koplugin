--[[
    aire.koplugin/core/genres.lua
    Normalización UTF-8 de géneros y autores para Colecciones automáticas,
    Estadísticas y Recaps. Sin dependencias externas (usa utf8proc de KOReader
    cuando está disponible y una tabla de diacríticos latinos como respaldo).
--]]

local _ = require("gettext")
local C_ = _.pgettext

local M = {}

local ok_u8, utf8proc = pcall(require, "ffi/utf8proc")
if not ok_u8 then utf8proc = nil end

-- Mapa de diacríticos y caracteres latinos frecuentes a su base ASCII
local DIACRITICS = {
    ["á"] = "a", ["à"] = "a", ["â"] = "a", ["ä"] = "a", ["ã"] = "a", ["å"] = "a", ["ā"] = "a", ["ă"] = "a", ["ą"] = "a",
    ["Á"] = "a", ["À"] = "a", ["Â"] = "a", ["Ä"] = "a", ["Ã"] = "a", ["Å"] = "a", ["Ā"] = "a", ["Ă"] = "a", ["Ą"] = "a",
    ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e", ["ē"] = "e", ["ĕ"] = "e", ["ė"] = "e", ["ę"] = "e", ["ě"] = "e",
    ["É"] = "e", ["È"] = "e", ["Ê"] = "e", ["Ë"] = "e", ["Ē"] = "e", ["Ĕ"] = "e", ["Ė"] = "e", ["Ę"] = "e", ["Ě"] = "e",
    ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["ĩ"] = "i", ["ī"] = "i", ["ĭ"] = "i", ["į"] = "i", ["ı"] = "i",
    ["Í"] = "i", ["Ì"] = "i", ["Î"] = "i", ["Ï"] = "i", ["Ĩ"] = "i", ["Ī"] = "i", ["Ĭ"] = "i", ["Į"] = "i", ["İ"] = "i",
    ["ó"] = "o", ["ò"] = "o", ["ô"] = "o", ["ö"] = "o", ["õ"] = "o", ["ø"] = "o", ["ō"] = "o", ["ŏ"] = "o", ["ő"] = "o",
    ["Ó"] = "o", ["Ò"] = "o", ["Ô"] = "o", ["Ö"] = "o", ["Õ"] = "o", ["Ø"] = "o", ["Ō"] = "o", ["Ŏ"] = "o", ["Ő"] = "o",
    ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ü"] = "u", ["ũ"] = "u", ["ū"] = "u", ["ŭ"] = "u", ["ů"] = "u", ["ű"] = "u", ["ų"] = "u",
    ["Ú"] = "u", ["Ù"] = "u", ["Û"] = "u", ["Ü"] = "u", ["Ũ"] = "u", ["Ū"] = "u", ["Ŭ"] = "u", ["Ů"] = "u", ["Ű"] = "u", ["Ų"] = "u",
    ["ñ"] = "n", ["Ñ"] = "n", ["ń"] = "n", ["Ń"] = "n", ["ņ"] = "n", ["Ņ"] = "n", ["ň"] = "n", ["Ň"] = "n",
    ["ç"] = "c", ["Ç"] = "c", ["ć"] = "c", ["Ć"] = "c", ["ĉ"] = "c", ["Ĉ"] = "c", ["ċ"] = "c", ["Ċ"] = "c", ["č"] = "c", ["Č"] = "c",
    ["ý"] = "y", ["ÿ"] = "y", ["Ý"] = "y", ["Ÿ"] = "y",
    ["ž"] = "z", ["Ž"] = "z", ["ź"] = "z", ["Ź"] = "z", ["ż"] = "z", ["Ż"] = "z",
    ["š"] = "s", ["Š"] = "s", ["ś"] = "s", ["Ś"] = "s", ["ş"] = "s", ["Ş"] = "s", ["ș"] = "s", ["Ș"] = "s", ["ß"] = "ss",
    ["ł"] = "l", ["Ł"] = "l", ["ĺ"] = "l", ["Ĺ"] = "l", ["ľ"] = "l", ["Ľ"] = "l",
    ["ř"] = "r", ["Ř"] = "r", ["ŕ"] = "r", ["Ŕ"] = "r",
    ["ď"] = "d", ["Ď"] = "d", ["đ"] = "d", ["Đ"] = "d",
    ["ť"] = "t", ["Ť"] = "t", ["ţ"] = "t", ["Ţ"] = "t", ["ț"] = "t", ["Ț"] = "t",
    ["ğ"] = "g", ["Ğ"] = "g", ["æ"] = "ae", ["Æ"] = "ae", ["œ"] = "oe", ["Œ"] = "oe",
}

local function stripDiacritics(s)
    -- Reemplaza secuencias UTF-8 de 2 bytes presentes en DIACRITICS
    return (s:gsub("[\194-\223][\128-\191]", DIACRITICS))
end

--- Normaliza un texto a clave comparable: minúsculas UTF-8, sin tildes,
-- guiones/puntuación ligera colapsados a espacio único.
function M.normalize(s)
    if type(s) ~= "string" or s == "" then return "" end
    local out = stripDiacritics(s)
    if utf8proc and utf8proc.lowercase then
        local ok, low = pcall(utf8proc.lowercase, out)
        if ok and type(low) == "string" then out = low end
    else
        out = out:lower()
    end
    out = out:gsub("[_%-–—]+", " ")
    out = out:gsub("[%s]+", " ")
    return out:match("^%s*(.-)%s*$") or ""
end

--- Clave normalizada para agrupar autores: ignora mayúsculas, tildes,
-- puntos en iniciales ("J. R. R. Tolkien" == "J.R.R. Tolkien") y espacios extra.
function M.authorKey(name)
    if type(name) ~= "string" or name == "" then return "" end
    local k = M.normalize(name)
    k = k:gsub("%.", " ")
    k = k:gsub("%s+", " ")
    return k:match("^%s*(.-)%s*$") or ""
end

-- Puntuación de calidad visual de una etiqueta: prefiere tildes/UTF-8 reales
-- y capitalización mixta frente a todo minúsculas o todo mayúsculas.
local function labelScore(s)
    if type(s) ~= "string" or s == "" then return 0 end
    local score = 0
    if s:find("[\194-\244]") then score = score + 4 end -- conserva tildes/ñ/ç
    local has_upper = s:find("[A-Z]") ~= nil
    local has_lower = s:find("[a-z]") ~= nil
    if has_upper and has_lower then
        score = score + 3
    elseif has_upper then
        score = score + 1
    end
    return score
end

--- Devuelve la etiqueta visualmente mejor entre dos variantes de la misma clave.
function M.betterLabel(cur, cand)
    if not cur or cur == "" then return cand end
    if not cand or cand == "" then return cur end
    return labelScore(cand) > labelScore(cur) and cand or cur
end

-- 26 géneros canónicos: clave interna -> etiqueta traducible (gettext)
local CANONICAL_LABELS = {
    fantasy      = function() return C_("genre", "Fantasy") end,
    scifi        = function() return C_("genre", "Science fiction") end,
    mystery      = function() return C_("genre", "Mystery") end,
    thriller     = function() return C_("genre", "Thriller") end,
    horror       = function() return C_("genre", "Horror") end,
    romance      = function() return C_("genre", "Romance") end,
    historical   = function() return C_("genre", "Historical") end,
    adventure    = function() return C_("genre", "Adventure") end,
    classics     = function() return C_("genre", "Classics") end,
    contemporary = function() return C_("genre", "Contemporary") end,
    young_adult  = function() return C_("genre", "Young adult") end,
    children     = function() return C_("genre", "Children") end,
    humor        = function() return C_("genre", "Humor") end,
    history      = function() return C_("genre", "History") end,
    biography    = function() return C_("genre", "Biography") end,
    science      = function() return C_("genre", "Science") end,
    technology   = function() return C_("genre", "Technology") end,
    philosophy   = function() return C_("genre", "Philosophy") end,
    psychology   = function() return C_("genre", "Psychology") end,
    self_help    = function() return C_("genre", "Self-help") end,
    business     = function() return C_("genre", "Business") end,
    non_fiction  = function() return C_("genre", "Non-fiction") end,
    poetry       = function() return C_("genre", "Poetry") end,
    comics       = function() return C_("genre", "Comics") end,
    manga        = function() return C_("genre", "Manga") end,
    short_stories = function() return C_("genre", "Short stories") end,
}

-- Sinónimos multilingües ya normalizados (sin tildes, minúsculas, espacios simples)
local ALIAS_GROUPS = {
    fantasy = {
        "fantasy", "fantasia", "fantastique", "fantastico", "fantastica",
        "high fantasy", "epic fantasy", "urban fantasy", "dark fantasy",
        "sword and sorcery", "fantasia epica", "fantasia urbana", "fantasia oscura",
        "fantazy", "фэнтези", "фантастика",
    },
    scifi = {
        "science fiction", "sci fi", "scifi", "sf", "ciencia ficcion", "ciencia ficcio",
        "fantascienza", "ficcao cientifica", "dystopia", "dystopian", "distopia",
        "cyberpunk", "space opera", "steampunk", "post apocalyptic", "postapocaliptica",
        "научная фантастика",
    },
    mystery = {
        "mystery", "misterio", "mystere", "detective", "policiaca", "policiaco",
        "novela negra", "crime", "crime fiction", "crimen", "policier", "roman policier",
        "krimi", "kriminalroman", "giallo", "noir", "whodunit", "детектив",
    },
    thriller = {
        "thriller", "suspense", "suspenso", "psychological thriller", "thriller psicologico",
        "espionage", "espionaje", "spy", "action thriller", "триллер",
    },
    horror = {
        "horror", "terror", "miedo", "horreur", "horrore", "gothic", "gotica", "gotico",
        "supernatural", "sobrenatural", "ghosts", "fantasmas", "ужасы",
    },
    romance = {
        "romance", "romantica", "romantico", "novela romantica", "love", "amor",
        "liebesroman", "romanzo rosa", "romantasy", "роман",
    },
    historical = {
        "historical", "historical fiction", "historica", "novela historica",
        "roman historique", "historischer roman", "storico", "romanzo storico",
        "ficcao historica", "war", "guerra",
    },
    adventure = {
        "adventure", "aventura", "aventuras", "aventure", "abenteuer", "avventura",
        "action", "accion", "action and adventure", "accion y aventura", "приключения",
    },
    classics = {
        "classic", "classics", "clasico", "clasicos", "classique", "classiques",
        "klassiker", "classici", "classicos", "literatura clasica", "classic literature",
        "классика",
    },
    contemporary = {
        "contemporary", "contemporanea", "contemporaneo", "literary", "literary fiction",
        "ficcion literaria", "narrativa", "narrativa contemporanea", "drama",
        "modern fiction", "ficcion contemporanea",
    },
    young_adult = {
        "young adult", "ya", "juvenil", "juvenile", "adolescente", "adolescentes",
        "teen", "teens", "jeunesse", "jugendbuch", "ragazzi", "literatura juvenil",
    },
    children = {
        "children", "childrens", "children s", "childrens fiction", "kids",
        "infantil", "literatura infantil", "ninos", "kinderbuch", "enfants", "bambini",
        "middle grade", "fairy tales", "cuentos infantiles",
    },
    humor = {
        "humor", "humour", "comedy", "comedia", "satire", "satira", "parody", "parodia",
        "funny", "юмор",
    },
    history = {
        "history", "historia", "histoire", "geschichte", "storia", "world history",
        "historia universal", "ancient history", "modern history", "история",
    },
    biography = {
        "biography", "biografia", "biographies", "biografias", "autobiography",
        "autobiografia", "memoir", "memoirs", "memorias", "biographie", "biografie",
        "diaries", "diarios", "биография",
    },
    science = {
        "science", "ciencia", "divulgacion", "divulgacion cientifica", "popular science",
        "physics", "fisica", "biology", "biologia", "astronomy", "astronomia",
        "mathematics", "matematicas", "nature", "naturaleza", "chemistry", "quimica",
        "wissenschaft", "scienza", "наука",
    },
    technology = {
        "technology", "tecnologia", "computing", "computers", "informatica",
        "programming", "programacion", "software", "tech", "ai", "artificial intelligence",
        "inteligencia artificial", "engineering", "ingenieria", "computer science",
    },
    philosophy = {
        "philosophy", "filosofia", "philosophie", "ethics", "etica",
        "stoicism", "estoicismo", "metaphysics", "философия",
    },
    psychology = {
        "psychology", "psicologia", "psychologie", "psychologia", "neuroscience",
        "neurociencia", "cognitive science", "psychiatry", "psiquiatria", "психология",
    },
    self_help = {
        "self help", "autoayuda", "desarrollo personal", "personal development",
        "personal growth", "crecimiento personal", "productivity", "productividad",
        "habits", "habitos", "mindfulness", "self improvement", "ratgeber",
    },
    business = {
        "business", "negocios", "economics", "economia", "finance", "finanzas",
        "management", "gestion", "leadership", "liderazgo", "marketing",
        "entrepreneurship", "emprendimiento", "wirtschaft",
    },
    non_fiction = {
        "non fiction", "nonfiction", "no ficcion", "ensayo", "ensayos", "essay", "essays",
        "politics", "politica", "sociology", "sociologia", "journalism", "periodismo",
        "society", "sociedad", "culture", "cultura", "sachbuch", "saggistica",
    },
    poetry = {
        "poetry", "poesia", "poems", "poemas", "poesie", "lyrik", "verse", "verso", "поэзия",
    },
    comics = {
        "comics", "comic", "graphic novel", "graphic novels", "novela grafica",
        "bande dessinee", "bd", "fumetti", "tebeo", "tebeos", "comic book", "superheroes",
    },
    manga = {
        "manga", "manhwa", "manhua", "shonen", "seinen", "shojo", "josei", "light novel",
        "манга",
    },
    short_stories = {
        "short stories", "short story", "relatos", "relato", "cuentos", "cuento",
        "antologia", "anthology", "nouvelles", "kurzgeschichten", "racconti", "рассказы",
    },
}

local ALIASES = {}
for key, list in pairs(ALIAS_GROUPS) do
    for _i, alias in ipairs(list) do
        ALIASES[alias] = key
    end
end

-- Etiquetas genéricas/ruido que se descartan si el libro tiene algún género real
local NOISE = {
    ["fiction"] = true, ["ficcion"] = true, ["general"] = true,
    ["novel"] = true, ["novela"] = true, ["roman"] = true,
    ["book"] = true, ["books"] = true, ["libro"] = true, ["libros"] = true,
    ["ebook"] = true, ["ebooks"] = true, ["epub"] = true,
    ["literature"] = true, ["literatura"] = true,
    ["spanish"] = true, ["espanol"] = true, ["english"] = true, ["ingles"] = true,
    ["french"] = true, ["german"] = true, ["italian"] = true, ["portuguese"] = true,
}

local function cleanSegment(raw)
    local kw = raw:match("^%s*(.-)%s*$")
    if not kw or kw == "" then return nil end
    -- Quitar sufijos tipo "Fantasy -- General"
    kw = kw:match("^(.-)%s*%-%-") or kw
    kw = kw:match("^%s*(.-)%s*$")
    return (kw and kw ~= "") and kw or nil
end

--- Resuelve una etiqueta individual a { key, label, canonical, noise }.
function M.resolveGenre(raw)
    local kw = cleanSegment(raw)
    if not kw then return nil end
    local norm = M.normalize(kw)
    if norm == "" then return nil end
    local canon = ALIASES[norm]
    if canon then
        return { key = canon, label = CANONICAL_LABELS[canon](), canonical = true, noise = false }
    end
    return { key = norm, label = kw, canonical = false, noise = NOISE[norm] == true }
end

--- Extrae los géneros normalizados y deduplicados de una cadena `keywords`
-- (soporta separadores \n, coma, punto y coma, y jerarquías Calibre/BISAC con "/").
function M.extractGenres(keywords)
    if type(keywords) ~= "string" or keywords == "" then return {} end
    local sep = keywords:find("\n", 1, true) and "[^\n]+" or "[^,;]+"
    local results, noise_fallback, seen = {}, {}, {}

    local function addResolved(g)
        if not g or seen[g.key] then return end
        seen[g.key] = true
        if g.noise then
            table.insert(noise_fallback, g)
        else
            table.insert(results, g)
        end
    end

    for raw in keywords:gmatch(sep) do
        if raw:find("/", 1, true) then
            -- Jerarquía tipo "Fiction / Fantasy / Epic": probar del más específico al más general
            local segs = {}
            for seg in raw:gmatch("[^/]+") do
                local c = cleanSegment(seg)
                if c then table.insert(segs, c) end
            end
            local matched_canon = false
            for i = #segs, 1, -1 do
                local g = M.resolveGenre(segs[i])
                if g and g.canonical then
                    addResolved(g)
                    matched_canon = true
                    break
                end
            end
            if not matched_canon and #segs > 0 then
                for i = #segs, 1, -1 do
                    local g = M.resolveGenre(segs[i])
                    if g and not g.noise then
                        addResolved(g)
                        break
                    end
                end
            end
        else
            addResolved(M.resolveGenre(raw))
        end
    end

    return #results > 0 and results or noise_fallback
end

--- Etiqueta localizada para una clave canónica (si existe).
function M.canonicalLabel(key)
    local fn = CANONICAL_LABELS[key]
    return fn and fn() or key
end

return M
