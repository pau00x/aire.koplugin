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
    -- Quitar punto volado catalán (l·l -> ll) y comillas/apóstrofes tipográficos
    out = out:gsub("\194\183", "")
    out = out:gsub("\226\128[\152\153]", " ")
    if utf8proc and utf8proc.lowercase then
        local ok, low = pcall(utf8proc.lowercase, out)
        if ok and type(low) == "string" then out = low end
    else
        out = out:lower()
    end
    out = out:gsub("[_%-–—']+", " ")
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
    fantasy       = function() return C_("aire", "Fantasy") end,
    scifi         = function() return C_("aire", "Science fiction") end,
    mystery       = function() return C_("aire", "Mystery") end,
    thriller      = function() return C_("aire", "Thriller") end,
    horror        = function() return C_("aire", "Horror") end,
    romance       = function() return C_("aire", "Romance") end,
    historical    = function() return C_("aire", "Historical") end,
    adventure     = function() return C_("aire", "Adventure") end,
    classics      = function() return C_("aire", "Classics") end,
    contemporary  = function() return C_("aire", "Contemporary") end,
    young_adult   = function() return C_("aire", "Young adult") end,
    children      = function() return C_("aire", "Children") end,
    humor         = function() return C_("aire", "Humor") end,
    history       = function() return C_("aire", "History") end,
    biography     = function() return C_("aire", "Biography") end,
    science       = function() return C_("aire", "Science") end,
    technology    = function() return C_("aire", "Technology") end,
    philosophy    = function() return C_("aire", "Philosophy") end,
    psychology    = function() return C_("aire", "Psychology") end,
    self_help     = function() return C_("aire", "Self-help") end,
    business      = function() return C_("aire", "Business") end,
    non_fiction   = function() return C_("aire", "Non-fiction") end,
    poetry        = function() return C_("aire", "Poetry") end,
    comics        = function() return C_("aire", "Comics") end,
    manga         = function() return C_("aire", "Manga") end,
    short_stories = function() return C_("aire", "Short stories") end,
}

-- Sinónimos multilingües ya normalizados (sin tildes, minúsculas, espacios simples)
local ALIAS_GROUPS = {
    fantasy = {
        "fantasy", "fantasia", "fantastique", "fantastico", "fantastica",
        "high fantasy", "epic fantasy", "urban fantasy", "dark fantasy",
        "sword and sorcery", "fantasia epica", "fantasia urbana", "fantasia oscura",
        "fantasia fosca", "magic", "magia", "mythology", "mitologia",
        "fantazy", "фэнтези", "фантастика",
    },
    scifi = {
        "science fiction", "sci fi", "scifi", "sf", "ciencia ficcion", "ciencia ficcio",
        "fantascienza", "ficcao cientifica", "dystopia", "dystopian", "distopia",
        "cyberpunk", "space opera", "steampunk", "post apocalyptic", "postapocaliptica",
        "speculative fiction", "ficcion especulativa", "ficcio especulativa",
        "hard science fiction", "time travel", "viajes en el tiempo", "alternate history",
        "научная фантастика",
    },
    mystery = {
        "mystery", "misterio", "misteri", "mystere", "detective", "detective fiction",
        "policiaca", "policiaco", "novela policiaca", "novella policiaca",
        "novela negra", "novella negra", "crime", "crime fiction", "crimen", "crim",
        "policier", "roman policier", "krimi", "kriminalroman", "giallo", "noir",
        "whodunit", "cozy mystery", "true crime", "детектив",
    },
    thriller = {
        "thriller", "thrillers", "suspense", "suspenso", "suspens",
        "psychological thriller", "thriller psicologico", "thriller psicologic",
        "espionage", "espionaje", "espionatge", "spy", "action thriller",
        "crime thriller", "intriga", "триллер",
    },
    horror = {
        "horror", "terror", "miedo", "por", "horreur", "horrore", "gothic", "gotica", "gotico",
        "gotic", "supernatural", "sobrenatural", "ghosts", "fantasmas", "fantasmes", "ужасы",
    },
    romance = {
        "romance", "romantica", "romantico", "romantic", "novela romantica", "novella romantica",
        "historical romance", "contemporary romance", "paranormal romance",
        "love", "amor", "liebesroman", "romanzo rosa", "romantasy", "роман",
    },
    historical = {
        "historical", "historical fiction", "historica", "historic",
        "novela historica", "novella historica", "ficcion historica", "ficcio historica",
        "roman historique", "historischer roman", "storico", "romanzo storico",
        "ficcao historica", "war", "guerra",
    },
    adventure = {
        "adventure", "adventures", "aventura", "aventuras", "aventures",
        "aventure", "abenteuer", "avventura", "action", "accion", "accio",
        "action and adventure", "accion y aventura", "accio i aventura", "приключения",
    },
    classics = {
        "classic", "classics", "clasico", "clasicos", "classique", "classiques",
        "klassiker", "classici", "classicos", "literatura clasica", "literatura classica",
        "classic literature", "классика",
    },
    contemporary = {
        "contemporary", "contemporanea", "contemporaneo", "contemporania", "contemporani",
        "literary", "literary fiction", "ficcion literaria", "ficcio literaria",
        "narrativa", "narrativa contemporanea", "narrativa contemporania", "drama",
        "modern fiction", "ficcion contemporanea", "ficcio contemporania",
        "coming of age", "bildungsroman",
    },
    young_adult = {
        "young adult", "young adult fiction", "ya", "juvenil", "juvenile",
        "adolescente", "adolescentes", "adolescents", "teen", "teens",
        "jeunesse", "jugendbuch", "ragazzi", "literatura juvenil",
    },
    children = {
        "children", "childrens", "children s", "childrens fiction", "children s books",
        "kids", "infantil", "literatura infantil", "ninos", "nens", "kinderbuch",
        "enfants", "bambini", "middle grade", "fairy tales", "fairy tale",
        "cuentos infantiles", "contes infantils",
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
        "biography", "biografia", "biographies", "biografias", "biografies",
        "autobiography", "autobiografia", "memoir", "memoirs", "memorias", "memories",
        "biographie", "biografie", "diaries", "diarios", "diaris", "биография",
    },
    science = {
        "science", "ciencia", "divulgacion", "divulgacion cientifica", "divulgacio",
        "divulgacio cientifica", "popular science", "physics", "fisica",
        "biology", "biologia", "astronomy", "astronomia", "mathematics", "matematicas",
        "matematiques", "nature", "naturaleza", "natura", "chemistry", "quimica",
        "medicine", "medicina", "wissenschaft", "scienza", "наука",
    },
    technology = {
        "technology", "tecnologia", "computing", "computers", "computer", "informatica",
        "programming", "programacion", "programacio", "software", "tech",
        "ai", "artificial intelligence", "inteligencia artificial", "intelligencia artificial",
        "engineering", "ingenieria", "enginyeria", "computer science",
        "data science", "machine learning",
    },
    philosophy = {
        "philosophy", "filosofia", "philosophie", "ethics", "etica",
        "stoicism", "estoicismo", "estoicisme", "metaphysics", "metafisica",
        "religion", "religio", "spirituality", "espiritualidad", "espiritualitat",
        "философия",
    },
    psychology = {
        "psychology", "psicologia", "psychologie", "psychologia", "neuroscience",
        "neurociencia", "cognitive science", "psychiatry", "psiquiatria", "психология",
    },
    self_help = {
        "self help", "autoayuda", "autoajuda", "desarrollo personal", "desenvolupament personal",
        "personal development", "personal growth", "crecimiento personal", "creixement personal",
        "productivity", "productividad", "productivitat", "habits", "habitos",
        "mindfulness", "self improvement", "health", "salud", "salut", "wellness", "ratgeber",
    },
    business = {
        "business", "negocios", "negocis", "economics", "economia", "finance", "finanzas",
        "finances", "personal finance", "management", "gestion", "gestio",
        "leadership", "liderazgo", "lideratge", "marketing",
        "entrepreneurship", "emprendimiento", "emprenedoria", "wirtschaft",
    },
    non_fiction = {
        "non fiction", "nonfiction", "no ficcion", "no ficcio", "ensayo", "ensayos",
        "assaig", "assajos", "essay", "essays", "politics", "politica",
        "sociology", "sociologia", "journalism", "periodismo", "periodisme",
        "society", "sociedad", "societat", "culture", "cultura",
        "travel", "viajes", "viatges", "art", "arte", "music", "musica",
        "cooking", "cocina", "cuina", "gastronomia", "sachbuch", "saggistica",
    },
    poetry = {
        "poetry", "poesia", "poems", "poemas", "poemes", "poesie", "lyrik",
        "verse", "verso", "vers", "поэзия",
    },
    comics = {
        "comics", "comic", "graphic novel", "graphic novels", "novela grafica",
        "novella grafica", "bande dessinee", "bd", "fumetti", "tebeo", "tebeos",
        "comic book", "superheroes", "superherois",
    },
    manga = {
        "manga", "manhwa", "manhua", "shonen", "seinen", "shojo", "josei", "light novel",
        "манга",
    },
    short_stories = {
        "short stories", "short story", "relatos", "relato", "relats", "relat",
        "cuentos", "cuento", "contes", "conte", "antologia", "anthology",
        "nouvelles", "kurzgeschichten", "racconti", "рассказы",
    },
}

local ALIASES = {}
for key, list in pairs(ALIAS_GROUPS) do
    for _i, alias in ipairs(list) do
        ALIASES[alias] = key
    end
end

-- Etiquetas genéricas de respaldo: se ignoran si el libro tiene algún género concreto;
-- si son la ÚNICA etiqueta del libro, salen traducidas al idioma activo de KOReader.
local FALLBACK_LABELS = {
    novel   = function() return C_("aire", "Novel") end,
    fiction = function() return C_("aire", "Fiction") end,
}

local FALLBACK_GROUPS = {
    novel = {
        "novel", "novels", "novela", "novelas", "novella", "novelles",
        "roman", "romans", "romanzo", "romanzi", "роман", "романы",
        "powiesc",
    },
    fiction = {
        "fiction", "general fiction", "adult fiction", "ficcion", "ficcio",
        "ficcao", "fiktion", "narrativa general",
        "literature", "literatura", "litterature", "literatur", "letteratura",
        "литература", "художественная литература",
    },
}

local FALLBACK_ALIASES = {}
for key, list in pairs(FALLBACK_GROUPS) do
    for _i, alias in ipairs(list) do
        FALLBACK_ALIASES[alias] = key
    end
end

-- Ruido puro multilingüe: formatos, palabras vacías y nombres de idiomas.
-- Se descartan siempre (nunca crean colección ni aparecen en estadísticas).
local PURE_NOISE = {
    -- Genéricos y formatos
    ["general"] = true, ["other"] = true, ["otros"] = true, ["altres"] = true,
    ["autres"] = true, ["andere"] = true, ["altri"] = true, ["outros"] = true,
    ["unknown"] = true, ["desconocido"] = true, ["desconegut"] = true, ["untagged"] = true,
    ["book"] = true, ["books"] = true, ["libro"] = true, ["libros"] = true,
    ["llibre"] = true, ["llibres"] = true, ["livre"] = true, ["livres"] = true,
    ["buch"] = true, ["bucher"] = true, ["libri"] = true, ["livro"] = true, ["livros"] = true,
    ["boek"] = true, ["boeken"] = true, ["ksiazka"] = true, ["книга"] = true, ["книги"] = true,
    ["ebook"] = true, ["ebooks"] = true, ["e book"] = true, ["epub"] = true,
    ["pdf"] = true, ["mobi"] = true, ["azw"] = true, ["azw3"] = true, ["fb2"] = true,
    -- Nombres de idiomas (para que no contaminen géneros; tienen sus propias colecciones por idioma)
    ["spanish"] = true, ["espanol"] = true, ["espanyol"] = true, ["castellano"] = true, ["castella"] = true,
    ["espagnol"] = true, ["spanisch"] = true, ["spagnolo"] = true, ["espanhol"] = true, ["испанский"] = true,
    ["catalan"] = true, ["catala"] = true, ["katalanisch"] = true, ["catalano"] = true,
    ["english"] = true, ["ingles"] = true, ["angles"] = true, ["anglais"] = true,
    ["englisch"] = true, ["inglese"] = true, ["английский"] = true,
    ["french"] = true, ["frances"] = true, ["francais"] = true, ["franzosisch"] = true,
    ["francese"] = true, ["французский"] = true,
    ["german"] = true, ["aleman"] = true, ["alemany"] = true, ["allemand"] = true,
    ["deutsch"] = true, ["tedesco"] = true, ["alemao"] = true, ["немецкий"] = true,
    ["italian"] = true, ["italiano"] = true, ["italia"] = true, ["italien"] = true,
    ["italienisch"] = true, ["итальянский"] = true,
    ["portuguese"] = true, ["portugues"] = true, ["portugais"] = true, ["portugiesisch"] = true,
    ["portoghese"] = true, ["португальский"] = true,
    ["russian"] = true, ["ruso"] = true, ["rus"] = true, ["russe"] = true,
    ["russisch"] = true, ["russo"] = true, ["русский"] = true,
    ["japanese"] = true, ["japones"] = true, ["japonais"] = true, ["japanisch"] = true, ["giapponese"] = true,
    ["chinese"] = true, ["chino"] = true, ["xines"] = true, ["chinois"] = true, ["chinesisch"] = true, ["cinese"] = true,
    ["dutch"] = true, ["neerlandes"] = true, ["holandes"] = true, ["nederlands"] = true, ["neerlandais"] = true,
    ["polish"] = true, ["polaco"] = true, ["polones"] = true, ["polski"] = true, ["polonais"] = true, ["polnisch"] = true,
    ["galician"] = true, ["gallego"] = true, ["galego"] = true,
    ["basque"] = true, ["euskera"] = true, ["euskara"] = true, ["vasco"] = true, ["basc"] = true,
}

local function cleanSegment(raw)
    local kw = raw:match("^%s*(.-)%s*$")
    if not kw or kw == "" then return nil end
    -- Quitar sufijos tipo "Fantasy -- General"
    kw = kw:match("^(.-)%s*%-%-") or kw
    kw = kw:match("^%s*(.-)%s*$")
    return (kw and kw ~= "") and kw or nil
end

--- Resuelve una etiqueta individual a { key, label, canonical, fallback }.
-- Devuelve nil si la etiqueta es ruido puro (formato, idioma, palabra vacía).
function M.resolveGenre(raw)
    local kw = cleanSegment(raw)
    if not kw then return nil end
    local norm = M.normalize(kw)
    if norm == "" or PURE_NOISE[norm] then return nil end
    local canon = ALIASES[norm]
    if canon then
        return { key = canon, label = CANONICAL_LABELS[canon](), canonical = true, fallback = false }
    end
    local fb = FALLBACK_ALIASES[norm]
    if fb then
        return { key = fb, label = FALLBACK_LABELS[fb](), canonical = true, fallback = true }
    end
    return { key = norm, label = kw, canonical = false, fallback = false }
end

--- Extrae los géneros normalizados y deduplicados de una cadena `keywords`
-- (soporta separadores \n, coma, punto y coma, "&" y jerarquías Calibre/BISAC con "/").
function M.extractGenres(keywords)
    if type(keywords) ~= "string" or keywords == "" then return {} end
    local sep = keywords:find("\n", 1, true) and "[^\n]+" or "[^,;]+"
    local results, fallbacks, seen = {}, {}, {}

    local function addResolved(g)
        if not g or seen[g.key] then return end
        seen[g.key] = true
        if g.fallback then
            table.insert(fallbacks, g)
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
                if g and g.canonical and not g.fallback then
                    addResolved(g)
                    matched_canon = true
                    break
                end
            end
            if not matched_canon and #segs > 0 then
                for i = #segs, 1, -1 do
                    local g = M.resolveGenre(segs[i])
                    if g then
                        addResolved(g)
                        if not g.fallback then break end
                    end
                end
            end
        else
            local resolved = M.resolveGenre(raw)
            if resolved and not resolved.canonical and raw:find("&", 1, true) then
                -- Etiquetas compuestas tipo "Mystery & Thriller" o "Science Fiction & Fantasy"
                local any_canon = false
                for part in raw:gmatch("[^&]+") do
                    local pg = M.resolveGenre(part)
                    if pg and pg.canonical and not pg.fallback then
                        addResolved(pg)
                        any_canon = true
                    end
                end
                if not any_canon then addResolved(resolved) end
            else
                addResolved(resolved)
            end
        end
    end

    return #results > 0 and results or fallbacks
end

--- Etiqueta localizada para una clave canónica (si existe).
function M.canonicalLabel(key)
    local fn = CANONICAL_LABELS[key] or FALLBACK_LABELS[key]
    return fn and fn() or key
end

---------------------------------------------------------------------------
-- Normalización de idiomas (ISO 639-1 / 639-2 / 639-3 / nombres) -> idioma de KOReader
---------------------------------------------------------------------------
local ok_iso, IsoLanguage = pcall(require, "ui/data/isolanguage")
if not ok_iso then IsoLanguage = nil end

-- ISO-639-1 (2 letras) y variantes bibliográficas ISO-639-2B -> código ISO-639-3 de isolanguage.lua
local LANG_TO_ISO3 = {
    -- ISO 639-1 más frecuentes en bibliotecas
    af = "afr", ar = "ara", be = "bel", bg = "bul", bn = "ben", bs = "bos",
    ca = "cat", cs = "ces", cy = "cym", da = "dan", de = "deu", el = "ell",
    en = "eng", eo = "epo", es = "spa", et = "est", eu = "eus", fa = "fas",
    fi = "fin", fr = "fra", ga = "gle", gl = "glg", he = "heb", hi = "hin",
    hr = "hrv", hu = "hun", hy = "hye", id = "ind", is = "isl", it = "ita",
    ja = "jpn", ka = "kat", kk = "kaz", ko = "kor", la = "lat", lt = "lit",
    lv = "lav", mk = "mkd", ms = "msa", nb = "nob", nl = "nld", nn = "nno",
    no = "nor", oc = "oci", pl = "pol", pt = "por", ro = "ron", ru = "rus",
    sk = "slk", sl = "slv", sq = "sqi", sr = "srp", sv = "swe", th = "tha",
    tr = "tur", uk = "ukr", ur = "urd", vi = "vie", zh = "zho",
    -- Variantes bibliográficas ISO 639-2/B
    alb = "sqi", arm = "hye", baq = "eus", bur = "mya", chi = "zho",
    cze = "ces", dut = "nld", fre = "fra", geo = "kat", ger = "deu",
    gre = "ell", ice = "isl", mac = "mkd", mao = "mri", may = "msa",
    per = "fas", rum = "ron", slo = "slk", tib = "bod", wel = "cym",
    -- Nombres frecuentes escritos a mano en metadatos EPUB/Calibre
    spanish = "spa", espanol = "spa", espanyol = "spa", castellano = "spa", castella = "spa",
    catalan = "cat", catala = "cat", valenciano = "cat", valencia = "cat",
    english = "eng", ingles = "eng", angles = "eng",
    french = "fra", frances = "fra", francais = "fra",
    german = "deu", aleman = "deu", alemany = "deu", deutsch = "deu",
    italian = "ita", italiano = "ita", italia = "ita",
    portuguese = "por", portugues = "por",
    russian = "rus", ruso = "rus", rus = "rus",
    japanese = "jpn", japones = "jpn",
    chinese = "zho", chino = "zho", xines = "zho",
    korean = "kor", coreano = "kor", corea = "kor",
    dutch = "nld", neerlandes = "nld", holandes = "nld", nederlands = "nld",
    polish = "pol", polaco = "pol", polski = "pol",
    galician = "glg", gallego = "glg", galego = "glg",
    basque = "eus", euskera = "eus", euskara = "eus", vasco = "eus", basc = "eus",
    latin = "lat",
}

local LANG_IGNORE = {
    und = true, mul = true, zxx = true, mis = true, unknown = true, none = true,
}

--- Resuelve un código o nombre de idioma a { key = iso3, label = nombre en idioma de KOReader }.
function M.resolveLanguage(raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    local norm = M.normalize(raw)
    if norm == "" then return nil end
    -- Quitar subetiqueta de región ("es-ES", "en_US", "pt-BR" -> "es", "en", "pt")
    local base = norm:match("^([a-z][a-z][a-z]?)%s+") or norm
    if LANG_IGNORE[base] or LANG_IGNORE[norm] then return nil end
    local iso3 = LANG_TO_ISO3[norm] or LANG_TO_ISO3[base]
    if not iso3 and #base == 3 then
        iso3 = base
    end
    if not iso3 then return nil end
    local label = IsoLanguage and IsoLanguage:getLocalizedLanguage(iso3) or nil
    if not label or label == iso3 then
        -- Si no está en isolanguage.lua, ignorar códigos basura de 3 letras desconocidos
        if not LANG_TO_ISO3[norm] and not LANG_TO_ISO3[base] then return nil end
        label = iso3:upper()
    end
    return { key = iso3, label = label }
end

--- Extrae los idiomas normalizados y deduplicados de una cadena `language`.
function M.extractLanguages(raw)
    if type(raw) ~= "string" or raw == "" then return {} end
    local sep = raw:find("\n", 1, true) and "[^\n]+" or "[^,;]+"
    local results, seen = {}, {}
    for part in raw:gmatch(sep) do
        local lang = M.resolveLanguage(part)
        if lang and not seen[lang.key] then
            seen[lang.key] = true
            table.insert(results, lang)
        end
    end
    return results
end

return M
