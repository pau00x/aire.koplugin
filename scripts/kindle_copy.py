"""
Copia de Aire lista para el Kindle: solo lo que KOReader usa.

    python scripts/kindle_copy.py              -> ../dist/aire.koplugin
    python scripts/kindle_copy.py --out RUTA   -> RUTA/aire.koplugin
    python scripts/kindle_copy.py --no-dev     -> sin dev/ (sin tests ni devtools)
    python scripts/kindle_copy.py --zip        -> además, aire-<versión>.zip de publicación
                                                  (siempre sin dev/), junto a la carpeta

Se quedan fuera: las fuentes de las traducciones (l10n/**/*.po, aire.pot: en el
Kindle solo hacen falta los .mo), scripts/, docs/, .github/, la documentación
de desarrollo y los archivos de editor/git. dev/ va con los tests y devtools
(los .lua y fixtures/), salvo con --no-dev.

La carpeta de salida se vacía antes de copiar.
"""
import argparse
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
PLUGIN = Path(__file__).resolve().parent.parent
STRICT_L10N_LANGS = "es,ca"

SKIP_DIRS = {"scripts", "docs", ".github", "__pycache__", ".git", ".vscode"}
SKIP_ROOT_FILES = {".gitignore", ".luarc.json", "CONTRIBUTING.md"}
DEV_KEEP_SUFFIXES = {".lua", ".epub"}


def wanted(rel: Path, with_dev: bool) -> bool:
    parts = rel.parts
    if any(p in SKIP_DIRS for p in parts):
        return False
    if len(parts) == 1 and parts[0] in SKIP_ROOT_FILES:
        return False
    if parts[0] == "l10n" and rel.suffix in (".po", ".pot"):
        return False
    if parts[0] == "dev":
        return with_dev and rel.suffix in DEV_KEEP_SUFFIXES
    if rel.suffix in (".pyc", ".pyo", ".swp"):
        return False
    return True


def run_release_checks():
    lua_files = sorted(
        str(p) for p in PLUGIN.rglob("*.lua")
        if "dev" not in p.relative_to(PLUGIN).parts
        and "koreader" not in p.relative_to(PLUGIN).parts
    )
    lint = subprocess.run(
        [sys.executable, str(PLUGIN / "scripts" / "lualint.py"), *lua_files],
        capture_output=True, text=True, encoding="utf-8",
    )
    if lint.returncode != 0:
        print(lint.stdout, end="")
        print(lint.stderr, end="", file=sys.stderr)
        sys.exit("Release bloqueada: lualint.py encontró errores (usa --force para omitir).")

    l10n = subprocess.run(
        [sys.executable, str(PLUGIN / "scripts" / "l10n.py"), "check", f"--strict={STRICT_L10N_LANGS}"],
        capture_output=True, text=True, encoding="utf-8",
    )
    if l10n.returncode != 0:
        print(l10n.stdout, end="")
        print(l10n.stderr, end="", file=sys.stderr)
        sys.exit(f"Release bloqueada: l10n.py check falló en {STRICT_L10N_LANGS} o en placeholders/overrides (usa --force para omitir).")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(PLUGIN.parent / "dist"))
    ap.add_argument("--no-dev", action="store_true")
    ap.add_argument("--zip", action="store_true")
    ap.add_argument("--force", action="store_true", help="Omitir comprobaciones previas de release (--zip)")
    a = ap.parse_args()
    if a.zip and not a.force:
        run_release_checks()
    dest = Path(a.out).resolve() / PLUGIN.name
    if PLUGIN in dest.parents or dest == PLUGIN:
        sys.exit("La salida no puede estar dentro del plugin")
    if dest.exists():
        shutil.rmtree(dest)
    n, size = 0, 0
    for src in sorted(PLUGIN.rglob("*")):
        if not src.is_file():
            continue
        rel = src.relative_to(PLUGIN)
        if not wanted(rel, not a.no_dev):
            continue
        out = dest / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, out)
        n += 1
        size += src.stat().st_size
    print(f"{n} archivos, {size / 1024:.0f} KB -> {dest}")
    if a.zip:
        meta = (PLUGIN / "_meta.lua").read_text(encoding="utf-8")
        m = re.search(r'version\s*=\s*"([^"]+)"', meta)
        version = m.group(1) if m else "dev"
        zpath = dest.parent / f"aire-{version}.zip"
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
            for src in sorted(PLUGIN.rglob("*")):
                if src.is_file():
                    rel = src.relative_to(PLUGIN)
                    if wanted(rel, False):
                        z.write(src, PLUGIN.name + "/" + rel.as_posix())
        print(f"Paquete de publicación: {zpath}")


if __name__ == "__main__":
    main()
