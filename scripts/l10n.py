#!/usr/bin/env python3
"""
Localization maintenance script for aire.koplugin.

Commands:
    python scripts/l10n.py extract   # Extract strings from *.lua -> l10n/aire.pot & update *.po
    python scripts/l10n.py compile   # Compile l10n/<lang>/aire.po -> l10n/<lang>/aire.mo
    python scripts/l10n.py check     # Check missing translations, placeholders and KOReader conflicts

How it fits with KOReader
-------------------------
KOReader keeps ONE global translation table. The plugin's .mo is merged into
it (l10n.lua -> GetText.loadMO), so any msgid that KOReader already translates
would be overwritten for the WHOLE app (e.g. "left" = margin side in KOReader).
Therefore:
  * msgids that KOReader already translates are marked "#, koreader" in the .po
    and are never written to the plugin's .mo: KOReader's translation is used.
  * when the plugin needs its own wording for a common word, use a context:
        local C_ = _.pgettext
        C_("aire", "Remove")
    Context entries never collide with KOReader.
The KOReader catalog is read from <koreader>/l10n/<lang>/koreader.mo (the
plugin lives in <koreader>/plugins/aire.koplugin, or next to a reference copy
in ../koreader). If it is not there,
the "#, koreader" marks already stored in the .po are kept.
"""

import re
import struct
import sys
from pathlib import Path

PLUGIN_DIR = Path(__file__).resolve().parent.parent
L10N_DIR = PLUGIN_DIR / "l10n"
POT_PATH = L10N_DIR / "aire.pot"
# Catálogo de KOReader: dentro de KOReader (<koreader>/plugins/aire.koplugin) o,
# con el repositorio aparte, en la copia de referencia de al lado (../koreader)
KOREADER_L10N = next((p for p in (PLUGIN_DIR.parent.parent / "l10n", PLUGIN_DIR.parent / "koreader" / "l10n")
                      if p.is_dir()), PLUGIN_DIR.parent.parent / "l10n")
CONTEXT = "aire"
# Herramienta de pruebas (galerías con datos inventados): traducirla es opcional
# (todo lo de dev/: devtools, test_runner y tests; no se publica)
TEST_ONLY_FILES = {"dev/devtools.lua"}
TEST_ONLY_PREFIX = "dev/"
# Frases que el código COMPARA con el texto que muestra KOReader (claves de la
# ficha de libro, títulos de diálogo, entradas de menú que se ocultan). Tienen
# que valer exactamente lo mismo que en KOReader, así que el plugin no las
# traduce nunca, en ningún idioma (si KOReader no las traduce, quedan en inglés).
KOREADER_ONLY = {
    (None, m) for m in (
        "Filename:", "Format:", "Size:", "File date:", "Folder:", "Metadata:", "Current page:",
        "Rating:", "Review:", "Notebook file:", "Description",
        "Show progress in mosaic mode", "Show parent folder",
        "Show all files from subfolders", "Show filename in Open last/previous menu items",
        "Show collection mark",
        # Estadísticas (styles/plugins/statspages.lua): se usan para reconocer las filas de
        # KOReader, tienen que ser exactamente su texto
        "Current statistics", "Time spent reading this session", "Pages read this session",
        "Time spent reading today", "Pages read today", "Total time spent on this book",
        "Time spent reading", "Estimated reading time left", "Days reading this book",
        "Average time per day", "Book start date", "Estimated finish date", "Book marked as finished",
        "Current page/Total pages", "Pages read", "Average time per page",
        # Textos de KOReader que Aire muestra igual que KOReader (si no los
        # traduce, en inglés como en el resto de KOReader)
        "Time range statistics", "All books", "Books by week", "Books by month", "Today's timeline",
        "Add note", "Edit note", "Edit text", "Go to bookmark", "Remove bookmark", "Remove this bookmark?",
        "Previous chapter", "Next chapter", "Delete highlight",
        "Gestures in file browser", "Gestures in reader", "Remove from vocabulary builder",
    )
}

_STR = r'"((?:[^"\\]|\\.)*)"'
STRING_PATTERNS = [
    (re.compile(r'(?:^|[^A-Za-z0-9_.])_\(\s*' + _STR + r'\s*\)'), False),
    (re.compile(r"(?:^|[^A-Za-z0-9_.])_\(\s*'((?:[^'\\]|\\.)*)'\s*\)"), False),
    (re.compile(r'require\("gettext"\)\(\s*' + _STR + r'\s*\)'), False),
    (re.compile(r'(?:^|[^A-Za-z0-9_.])C_\(\s*"' + CONTEXT + r'"\s*,\s*' + _STR + r'\s*\)'), True),
]

# N_("singular", "plural", n) -> plural entry (msgid + msgid_plural)
N_PATTERN = re.compile(r'(?:^|[^A-Za-z0-9_.])N_\(\s*' + _STR + r'\s*,\s*' + _STR + r'\s*,')
PLURALS = {}  # (ctx, msgid) -> msgid_plural

PLACEHOLDER_RE = re.compile(r"%(?:\d+|\.\d+[dfs]|[%dfs])")

# Plural-Forms headers per language (matching KOReader / GNU gettext)
PLURAL_FORMS = {
    "ar": "nplurals=6; plural=n==0 ? 0 : n==1 ? 1 : n==2 ? 2 : n%100>=3 && n%100<=10 ? 3 : n%100>=11 ? 4 : 5;",
    "cs": "nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;",
    "fa": "nplurals=2; plural=(n > 1);",
    "fr": "nplurals=2; plural=(n > 1);",
    "ga": "nplurals=5; plural=n==1 ? 0 : n==2 ? 1 : (n>2 && n<7) ? 2 : (n>6 && n<11) ? 3 : 4;",
    "he": "nplurals=4; plural=(n == 1) ? 0 : ((n == 2) ? 1 : ((n > 10 && n % 10 == 0) ? 2 : 3));",
    "hi": "nplurals=2; plural=(n != 1);",
    "hr": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "ja": "nplurals=1; plural=0;",
    "ka": "nplurals=2; plural=(n != 1);",
    "ko_KR": "nplurals=1; plural=0;",
    "lt_LT": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "lv": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n != 0 ? 1 : 2);",
    "pl": "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "pt_BR": "nplurals=2; plural=(n > 1);",
    "ro": "nplurals=3; plural=(n==1 ? 0 : (n==0 || (n%100 > 0 && n%100 < 20)) ? 1 : 2);",
    "ro_MD": "nplurals=3; plural=(n==1 ? 0 : (n==0 || (n%100 > 0 && n%100 < 20)) ? 1 : 2);",
    "ru": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "sk": "nplurals=3; plural=(n==1) ? 0 : (n>=2 && n<=4) ? 1 : 2;",
    "sl": "nplurals=4; plural=(n%100==1 ? 0 : n%100==2 ? 1 : n%100==3 || n%100==4 ? 2 : 3);",
    "sr": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "tr": "nplurals=2; plural=(n > 1);",
    "uk": "nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);",
    "vi": "nplurals=1; plural=0;",
    "zh_CN": "nplurals=1; plural=0;",
    "zh_TW": "nplurals=1; plural=0;",
}


def unescape_lua(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "'": "'", "\\": "\\"}.get(n, "\\" + n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def escape_po(s: str) -> str:
    return s.replace("\\", r"\\").replace('"', r'\"').replace("\t", r"\t").replace("\n", r"\n")


def unescape_po(s: str) -> str:
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, s[i:i + 2]))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


# Keys are (msgctxt or None, msgid)
def extract_strings():
    refs = {}
    for path in sorted(PLUGIN_DIR.rglob("*.lua")):
        rel = path.relative_to(PLUGIN_DIR).as_posix()
        if rel in ("l10n.lua", "core/l10n.lua") or rel.startswith("koreader/"):
            continue
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for pat, has_ctx in STRING_PATTERNS:
                for m in pat.finditer(line):
                    key = (CONTEXT if has_ctx else None, unescape_lua(m.group(1)))
                    refs.setdefault(key, []).append(f"{rel}:{lineno}")
            for m in N_PATTERN.finditer(line):
                key = (None, unescape_lua(m.group(1)))
                PLURALS[key] = unescape_lua(m.group(2))
                refs.setdefault(key, []).append(f"{rel}:{lineno}")
    return refs


def parse_po(po_path: Path):
    """Returns header, {key: msgstr}, {key: set(flags)}"""
    entries, flags = {}, {}
    header = ""
    if not po_path.exists():
        return header, entries, flags
    cur = {"ctx": None, "id": None, "str": None, "flags": set(), "pl": None, "forms": {}}
    mode = None

    def flush():
        nonlocal header
        if cur["id"] is not None and cur["forms"]:
            key = (cur["ctx"], cur["id"])
            entries[key] = [cur["forms"][i] for i in sorted(cur["forms"])]
            flags[key] = cur["flags"]
        elif cur["id"] is not None and cur["str"] is not None:
            if cur["id"] == "" and cur["ctx"] is None:
                header = cur["str"]
            else:
                key = (cur["ctx"], cur["id"])
                entries[key] = cur["str"]
                flags[key] = cur["flags"]
        cur.update(ctx=None, id=None, str=None, flags=set(), pl=None, forms={})

    for raw in po_path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            flush()
            mode = None
            continue
        if line.startswith("#,"):
            cur["flags"] |= {f.strip() for f in line[2:].split(",") if f.strip()}
            continue
        if line.startswith("#"):
            continue
        if line.startswith("msgctxt "):
            if cur["id"] is not None:
                flush()
            mode = "ctx"
            cur["ctx"] = unescape_po(line[8:].strip()[1:-1])
        elif line.startswith("msgid "):
            if cur["id"] is not None:
                flush()
            mode = "id"
            cur["id"] = unescape_po(line[6:].strip()[1:-1])
        elif line.startswith("msgid_plural "):
            mode = "pl"
            cur["pl"] = unescape_po(line[13:].strip()[1:-1])
        elif line.startswith("msgstr["):
            idx = int(line[7:line.index("]")])
            mode = ("form", idx)
            cur["forms"][idx] = unescape_po(line[line.index("]") + 1:].strip()[1:-1])
        elif line.startswith("msgstr "):
            mode = "str"
            cur["str"] = unescape_po(line[7:].strip()[1:-1])
        elif line.startswith('"') and line.endswith('"'):
            val = unescape_po(line[1:-1])
            if isinstance(mode, tuple):
                cur["forms"][mode[1]] += val
            elif mode in ("ctx", "id", "str", "pl") and cur[mode] is not None:
                cur[mode] += val
    flush()
    return header, entries, flags


def read_mo(path: Path):
    """KOReader catalog -> {(ctx, msgid): msgstr} (singular forms only)"""
    out = {}
    if not path.exists():
        return None
    d = path.read_bytes()
    _magic, _rev, n, o, t = struct.unpack("<5I", d[:20])
    for i in range(n):
        ol, oo = struct.unpack("<2I", d[o + 8 * i:o + 8 * i + 8])
        tl, to = struct.unpack("<2I", d[t + 8 * i:t + 8 * i + 8])
        k = d[oo:oo + ol].decode("utf-8", "replace")
        v = d[to:to + tl].decode("utf-8", "replace")
        ctx = None
        if "\x04" in k:
            ctx, k = k.split("\x04", 1)
        out[(ctx, k.split("\x00")[0])] = v.split("\x00")[0]
    return out


def koreader_catalog(lang):
    return read_mo(KOREADER_L10N / lang / "koreader.mo")


def plural_forms(lang):
    """Plural-Forms of KOReader's own catalog for this language (so that the
    plugin uses exactly the same number and order of forms); fallback table."""
    cat = koreader_catalog(lang)
    hdr = cat.get((None, "")) if cat else None
    if hdr:
        m = re.search(r"Plural-Forms:\s*(.+)", hdr)
        if m:
            return m.group(1).strip()
    return PLURAL_FORMS.get(lang, "nplurals=2; plural=(n != 1);")


def nplurals(lang):
    m = re.search(r"nplurals\s*=\s*(\d+)", plural_forms(lang))
    return int(m.group(1)) if m else 2


def is_done(v, n):
    if isinstance(v, list):
        return len(v) == n and all(v)
    return bool(v)


def format_po_str(key: str, val: str) -> str:
    if "\n" not in val:
        return f'{key} "{escape_po(val)}"'
    parts = val.split("\n")
    lines = [f'{key} ""']
    for idx, p in enumerate(parts):
        suffix = r"\n" if idx < len(parts) - 1 else ""
        if p or suffix:
            lines.append(f'"{escape_po(p)}{suffix}"')
    return "\n".join(lines)


def sort_key(key):
    return (key[1], key[0] or "")


def write_po(po_path: Path, lang: str, refs: dict, translations: dict, koreader_keys: set):
    po_path.parent.mkdir(parents=True, exist_ok=True)
    plural = plural_forms(lang) if lang != "en" else "nplurals=2; plural=(n != 1);"
    np = nplurals(lang) if lang != "en" else 2
    header_val = (
        f"Project-Id-Version: aire.koplugin\n"
        f"Language: {lang}\n"
        f"MIME-Version: 1.0\n"
        f"Content-Type: text/plain; charset=UTF-8\n"
        f"Content-Transfer-Encoding: 8bit\n"
        f"Plural-Forms: {plural}\n"
    )
    out = [
        f"# {lang} translations for aire.koplugin.",
        "# Entries marked '#, koreader' are translated by KOReader itself and are",
        "# NOT compiled into the plugin's .mo (it would override KOReader everywhere).",
        'msgid ""',
        format_po_str("msgstr", header_val),
        "",
    ]
    for key in sorted(refs.keys(), key=sort_key):
        ctx, msg = key
        out.append("#: " + " ".join(refs[key][:5]))
        if key in koreader_keys:
            out.append("#, koreader")
        if ctx is not None:
            out.append(format_po_str("msgctxt", ctx))
        out.append(format_po_str("msgid", msg))
        if key in PLURALS:
            out.append(format_po_str("msgid_plural", PLURALS[key]))
            forms = translations.get(key)
            if not isinstance(forms, list) or key in koreader_keys:
                forms = []
            for i in range(np):
                out.append(format_po_str(f"msgstr[{i}]", forms[i] if i < len(forms) else ""))
        else:
            val = translations.get(key, "")
            if isinstance(val, list) or key in koreader_keys:
                val = ""
            out.append(format_po_str("msgstr", val))
        out.append("")
    po_path.write_text("\n".join(out), encoding="utf-8")


def write_mo(mo_path: Path, header: str, entries: dict):
    items = {"": header}
    for (ctx, msgid), v in entries.items():
        if not v:
            continue
        k = (ctx + "\x04" + msgid) if ctx else msgid
        if isinstance(v, list):
            if not all(v):
                continue
            k = k + "\x00" + PLURALS.get((ctx, msgid), msgid)
            v = "\x00".join(v)
        items[k] = v
    keys = sorted(items.keys(), key=lambda s: s.encode("utf-8"))
    n = len(keys)
    orig_table_offset = 28
    trans_table_offset = orig_table_offset + n * 8
    data_offset = trans_table_offset + n * 8
    orig_blobs = [k.encode("utf-8") for k in keys]
    trans_blobs = [items[k].encode("utf-8") for k in keys]
    orig_entries, trans_entries = [], []
    cur = data_offset
    for b in orig_blobs:
        orig_entries.append((len(b), cur))
        cur += len(b) + 1
    for b in trans_blobs:
        trans_entries.append((len(b), cur))
        cur += len(b) + 1
    buf = bytearray(struct.pack("<7I", 0x950412DE, 0, n, orig_table_offset, trans_table_offset, 0, 0))
    for length, off in orig_entries + trans_entries:
        buf += struct.pack("<2I", length, off)
    for b in orig_blobs + trans_blobs:
        buf += b + b"\x00"
    mo_path.parent.mkdir(parents=True, exist_ok=True)
    mo_path.write_bytes(bytes(buf))


def koreader_keys_for(lang, refs, flags):
    cat = koreader_catalog(lang)
    fixed = {k for k in refs if k in KOREADER_ONLY}
    if cat is None:
        # Sin catálogo de KOReader a mano: conservar las marcas guardadas
        return {k for k in refs if "koreader" in flags.get(k, set())} | fixed, False
    return {k for k in refs if k[0] is None and cat.get(k)} | fixed, True


def cmd_extract():
    refs = extract_strings()
    L10N_DIR.mkdir(parents=True, exist_ok=True)
    write_po(POT_PATH, "en", refs, {}, set())
    print(f"Wrote {POT_PATH.relative_to(PLUGIN_DIR)} ({len(refs)} strings)")
    for po_path in sorted(L10N_DIR.glob("*/aire.po")):
        lang = po_path.parent.name
        _, existing, flags = parse_po(po_path)
        kk, found = koreader_keys_for(lang, refs, flags)
        write_po(po_path, lang, refs, existing, kk)
        src = "KOReader catalog" if found else "stored marks"
        print(f"Updated {po_path.relative_to(PLUGIN_DIR)} ({len(kk)} left to KOReader, from {src})")


def cmd_compile():
    count = 0
    for po_path in sorted(L10N_DIR.glob("*/aire.po")):
        lang = po_path.parent.name
        header, entries, flags = parse_po(po_path)
        cat = koreader_catalog(lang)
        keep = {}
        for k, v in entries.items():
            if "koreader" in flags.get(k, set()) or k in KOREADER_ONLY:
                continue
            if cat is not None and k[0] is None and cat.get(k):
                continue  # ya lo traduce KOReader: no pisarlo
            keep[k] = v
        extract_strings()  # rellena PLURALS
        plural = plural_forms(lang)
        if not header:
            header = f"Content-Type: text/plain; charset=UTF-8\nPlural-Forms: {plural}\n"
        else:
            header = re.sub(r"Plural-Forms:[^\n]*", "Plural-Forms: " + plural, header)
        mo_path = po_path.with_suffix(".mo")
        write_mo(mo_path, header, keep)
        print(f"Compiled {mo_path.relative_to(PLUGIN_DIR)} ({sum(1 for v in keep.values() if is_done(v, nplurals(lang)))} strings)")
        count += 1
    print(f"Compiled {count} .mo files")


def show(key):
    return (f"[{key[0]}] " if key[0] else "") + repr(key[1])


def cmd_check():
    refs = extract_strings()
    status = 0
    for po_path in sorted(L10N_DIR.glob("*/aire.po")):
        lang = po_path.parent.name
        _, entries, flags = parse_po(po_path)
        kk, _found = koreader_keys_for(lang, refs, flags)
        # Las frases que solo usa la herramienta de pruebas son opcionales
        optional = {k for k, locs in refs.items()
                    if all(loc.split(":")[0] in TEST_ONLY_FILES or loc.startswith(TEST_ONLY_PREFIX) for loc in locs)}
        np = nplurals(lang)
        missing = [k for k in refs if k not in kk and not is_done(entries.get(k), np if k in PLURALS else 1) and k not in optional]
        stale_marks = [k for k in refs if k in kk and entries.get(k) and entries.get(k) != [""] * len(entries.get(k))]
        bad_ph = []
        for k in refs:
            v = entries.get(k, "")
            if not v or k in kk:
                continue
            if k in PLURALS:
                allowed = (sorted(PLACEHOLDER_RE.findall(k[1])), sorted(PLACEHOLDER_RE.findall(PLURALS[k])))
                if not isinstance(v, list) or any(f and sorted(PLACEHOLDER_RE.findall(f)) not in allowed for f in v):
                    bad_ph.append(k)
            elif isinstance(v, list) or sorted(PLACEHOLDER_RE.findall(k[1])) != sorted(PLACEHOLDER_RE.findall(v)):
                bad_ph.append(k)
        unused = [k for k in entries if k not in refs and entries[k]]
        translated = sum(1 for k in refs if k not in kk and is_done(entries.get(k), np if k in PLURALS else 1))
        print(f"[{lang}] {len(refs)} strings: {translated} translated, "
              f"{len(kk)} by KOReader, {len(missing)} missing, {len(bad_ph)} bad placeholders, "
              f"{len(stale_marks)} would override KOReader, {len(unused)} unused")
        for k in missing:
            print("  missing:", show(k))
        for k in bad_ph:
            print("  placeholders:", show(k), "->", repr(entries[k]))
        for k in stale_marks:
            print("  overrides KOReader (run extract):", show(k))
        if missing or bad_ph or stale_marks:
            status = 1
    return status


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    cmd = sys.argv[1] if len(sys.argv) > 1 else "compile"
    if cmd == "extract":
        cmd_extract()
    elif cmd == "compile":
        cmd_compile()
    elif cmd == "check":
        sys.exit(cmd_check())
    else:
        print("Usage: l10n.py [extract|compile|check]")
        sys.exit(1)
