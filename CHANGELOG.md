# Changelog

All notable changes to Aire are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/) and Aire uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Internal

- Full-screen layout, step 1: new `common/screen.lua` (`package.loaded.aire_screen`) with the shared margins and spacing (`METRICS`) and the only page-dots widget (`Pager`). The Library grid no longer has its own copy (`PageDots` removed), Menu/KeyValuePage/Page lists use the same one, and the side margin hard-coded in `styles/` and `common/pages.lua` comes from `METRICS.SIDE`. No visible changes.
- Full-screen layout, step 2: one status bar, one header and one subtitle row for every full screen (`statusBar`, `header`, `subtitle` in `common/screen.lua`). Aire's own views (`buildTopBar`, `buildViewTitle`, `buildBackHeader`, the file browser title) and KOReader's full screens (`styles/ui/titlebar.lua`) now build them the same way instead of keeping their own copies. No visible changes.
- Full-screen layout, step 3: one screen skeleton and one dock rule. `common/screen.lua` decides when a full screen gets the dock (`fullscreenDock`), how much room it takes (`dockReserve`) and builds the white root with the dock at the bottom (`root`). KOReader's lists, the `Page` screens and Aire's own views (Home, Library, Stats, Calendar, Recap, file browser) use it; the own views share the top part (`Aire:buildScreenTop`). No visible changes.
- Full-screen layout, step 4: one way to give KOReader screens Aire's header. `withTitleBar` in `common/screen.lua` adjusts the title bars a screen creates (full screen, title, subtitle, ‹, menu icon…) and always restores `TitleBar.new`; Book map, Page browser, Image viewer, Calendar, Book information, Sort, Vocabulary builder and full-screen input dialogs use it instead of their own copies. The subtitle is passed to the title bar itself, so the global `TitleBar._aire_pending_subtitle` (and the unused `_aire_pending_default_subtitle`) are gone. No visible changes.

## [0.2.0] - 2026-11-18

### Added

- **Aire updates from the device**: "Update Aire" in the top menu, right below KOReader's update entry (now called "Update KOReader"), in the file browser and in the reader. Check for updates (long-press checks directly) and Settings: weekly check (only when Wi-Fi is already on; Aire never turns it on) and beta versions (off by default: only stable releases are offered). A bottom sheet shows the new version with its main changes (Skip / Later / Update), and all the changes open in a full Aire screen, formatted; the download shows its progress and, once installed, KOReader can be restarted. If anything fails, the installed version is kept. The previous version is kept as `aire.koplugin.old` until the next start that reaches the file browser, then removed.
- **Power sheet**: Aire's version under KOReader's; the Update button asks whether to update KOReader or Aire, and a card appears when a new Aire version is known.

### Internal

- `scripts/kindle_copy.py` writes the device copy to `../device-ready/aire.koplugin` by default.
- `scripts/l10n.py` also finds KOReader's catalog in a reference copy next to the repository (`../koreader/l10n`).

## [0.1.0] - 2026-11-18

First public version (beta).

### Added

- **Home**: top bar, optional large clock, "Currently reading" card (with synopsis and progress) and customizable widgets: Today and streak, Next in series, Previous book, Random book, Quote, Light, Wi-Fi, Battery, Storage, Search, SSH and more. Presets: Reader, Progress, Quick actions, Minimal and Empty.
- **Library, Collections, History and Finished**: cover grids with a bottom dock, filters and sorting. Series and collections are 2×2 mosaics; automatic collections by author and by genre (keyword). Long-press Home switches to KOReader's classic file browser.
- **Fast covers**: covers are kept on disk as small thumbnails already scaled to the grid, and the next page is prepared while the device is idle. Advanced → Clear cover thumbnails if a cover does not update.
- **Stats**: today, streak and finished books, the last 7 days, a reading calendar and a monthly / annual Recap.
- **Long-press sheets** for books and for series / collections: reading status, synopsis, book information, collections, delete and more.
- **KOReader-wide restyling**: rounded dialogs and bottom sheets, dot pagination in every list, cards with a black flash on long-press, SVG checkboxes and radio buttons, capsule progress bars, a cleaner top menu and a reader bottom menu with matching icons.
- **Redesigned screens**: book information (cover header, rating and review cards), table of contents, bookmarks and bookmark details, search results, book map, page browser (bookmarked pages with a ribbon), image viewer, book status, folder shortcuts, collections list, sort screens, the dictionary popup (long-press a highlighted word to delete the highlight; remove words from the vocabulary builder), skim document and note editors.
- **Plugin screens**: Statistics (current book, time range, today's timeline, calendar and reading progress), Gesture overview and Vocabulary builder.
- **Reader status bar**: with "Compact items", the battery shows its percentage.
- **Robust by design**: if Aire's part of a KOReader screen fails, KOReader's own screen is used and a warning is logged; KOReader keeps working.
- **Quiet `crash.log`**: Aire writes a banner with its version on startup; details only with KOReader's verbose logging.
- Startup check for user patches and plugins that overlap with Aire.
- Bundled `aire.*` icons (most based on Lucide) and translations for 44 languages with proper plural forms.
