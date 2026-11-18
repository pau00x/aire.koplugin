# Changelog

All notable changes to Aire are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/) and Aire uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
