# Contributing to Aire

Thanks for your interest in Aire! Every kind of help is welcome: bug reports, ideas, translations, design and code.

## Ways to contribute

| What | How |
|---|---|
| Report a bug | Open an issue with the **Bug report** template. Include the `crash.log` lines. |
| Suggest a feature | Open an issue with the **Feature request** template. Mock-ups help. |
| Improve a translation | Edit `l10n/<language>/aire.po` and open a pull request, or use the **Translation** issue template. |
| Design | Share screenshots or mock-ups in an issue before implementing big visual changes. |
| Code | Open an issue first for anything non-trivial, then a pull request. |

## Development setup

1. Clone the repository as `aire.koplugin`.
2. Optional, for editor completion (LuaLS): add KOReader as a submodule in `koreader/`. `.luarc.json` already points to `./koreader/frontend`, and `koreader/` is git-ignored.
   ```bash
   git submodule add https://github.com/koreader/koreader.git koreader
   ```
3. To test, copy the plugin to `koreader/plugins/aire.koplugin/` on a device (or a KOReader emulator) and restart KOReader.
4. Before copying, run the linter (syntax, undefined globals, `...` misuse, upvalue limit):
   ```bash
   python scripts/lualint.py $(find . -name "*.lua" -not -path "./koreader/*")
   ```
5. Check `crash.log` after every test. Aire's log lines start with `Aire` (`Aire/Grid`, `Aire/UI`, `Aire/BookInfo`…).

The optional `dev/` folder (git-ignored) holds test tools: `dev/devtools.lua` adds **Advanced → Tests** with demo data and swipe galleries of every screen.

## Code guidelines

- **Language**: Lua 5.1 / LuaJIT, as in KOReader. Follow KOReader's style (4 spaces, `local` everything, `require` at the top).
- **File names**: lowercase, no separators, named after what they change (`styles/toc.lua` restyles KOReader's table of contents).
- **Where things go**:
  - `views/`: Aire's own screens.
  - `styles/<screen>.lua`: restyling of one KOReader screen.
  - `styles/ui/`: KOReader-wide changes, loaded **in order** by `styles/ui.lua`. Several parts wrap the same KOReader methods, so do not reorder them without checking.
  - `common/`: helpers shared by the rest.
- **Never edit KOReader or official plugins.** Wrap methods at runtime, keep a reference to the original (`local orig_x = Class.x`) and always call it.
- **Fail safely**: anything that hooks into KOReader internals must survive a missing method or upvalue (`pcall`, nil checks) and log a warning instead of breaking KOReader's startup.
- **LuaJIT limits**: a function can use at most 60 upvalues (variables from outside it); with 61 the whole file fails to load. The view modules (`views/*.lua`, except `booksheet.lua`) and `menu.lua` are one big "mixin" function (`return function(Aire, ctx) … end`): declare the modules it uses **inside** it (they are already there), not as new locals at the top of the file. Check with `python scripts/lualint.py -t <files>`, which lists the functions with most upvalues and fails above 60.
- **Vararg**: never use `...` inside a closure; capture it first (`local args = { ... }`).
- **Log tags**: `logger.warn("Aire/<Module>: …")`.
- **Icons**: bundled icons are `icons/aire.<name>.svg` and are referenced as `"aire.<name>"`.
- **Strings**: wrap every user-visible string (see below).

## Translations

All user-visible text must go through gettext:

```lua
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local T = require("ffi/util").template

_("Library")                                   -- plain string
C_("aire", "Remove")                           -- Aire's own meaning of a common word
T(N_("%1 book", "%1 books", n), n)             -- plurals: always with N_
T(_("of %1"), size)                            -- whole sentences with placeholders
```

Rules:

- **Never build sentences from pieces** (`_("of") .. " " .. size`): translators cannot reorder them.
- **Use `N_` for anything counted**; KOReader's own plural rules are used for every language.
- **Strings that must match KOReader's text** (for example the book information keys) are listed in `KOREADER_ONLY` in `scripts/l10n.py` and are never translated by Aire.
- Aire's `.mo` files never override KOReader's translations: strings KOReader already translates are marked `#, koreader` in the `.po` files and left out of the `.mo`.

Workflow:

```bash
python scripts/l10n.py extract   # after changing strings in the code
python scripts/l10n.py check     # must report 0 missing / 0 bad placeholders / 0 overrides
python scripts/l10n.py compile   # build the .mo files
```

When translating, keep labels short (they appear under icons and on small buttons), keep `%1`/`%2` placeholders, and use the terms KOReader already uses in your language.

## Versioning

The version lives only in `_meta.lua` (`version = "0.2.0"`); `main.lua` reads it and writes `Aire version …` to `crash.log`. Aire follows [Semantic Versioning](https://semver.org/): while it is `0.x`, minor versions may change settings or behaviour. Every release gets an entry in `CHANGELOG.md`.

## Pull requests

- One topic per pull request; small is better.
- Describe what changed and why, and how you tested it (device, KOReader version, orientation).
- Add screenshots for visual changes.
- Run `python scripts/l10n.py check` if you touched strings.
- Mention any new interaction with KOReader internals (which method you wrap and why).

## License

By contributing, you agree that your contributions are licensed under the project's license, the **GNU AGPL-3.0**.
