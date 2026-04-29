# Changelog

All notable changes to Pasture are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Pasture uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-04-29

### Added

- Sort toggle in sidebar: sort files by date (default) or by name.
- Drag & drop export: drag files from Pasture sidebar to attach in AI chats via `Transferable` protocol.
- Collections: organize files in subdirectories inside `~/.pasture/`. Context menus for moving files between collections, creating and deleting collections.
- PastureKit module: extracted `TemplateEngine`, `TokenEstimator`, `FilenameSanitizer`, and `xmlEscapedAttribute` into a testable library target.
- 65 unit tests covering all PastureKit public API (Swift Testing framework).

### Changed

- ContentView refactored from ~700 lines to ~310 lines. Sidebar extracted to `SidebarView`, feed button/template sheet to `FeedAction.swift`.
- Editor derived properties (token count, template detection) now update on save debounce instead of every keystroke.
- Collections cached in `@Published var collections` instead of hitting filesystem on each render.
- Feed button hover state moved to internal `@State` (was unnecessarily exposed as binding).
- Path traversal checks consolidated into single `isInsidePasture()` helper (was repeated 8x inline).
- File listing uses `mdFiles(in:)` and `realSubdirectories(in:)` helpers (eliminates duplicated filtering).

### Fixed

- DispatchSource file watcher crash under Swift 6 strict concurrency — moved to module-level free function to avoid actor isolation propagation.
- `isInsidePasture()` now uses trailing-slash boundary check to prevent `.pasture-evil/` prefix match.
- CDATA injection: `]]>` sequences in file content are now escaped in feed output.
- Removed unused `watchedFileDescriptor` field to reduce `nonisolated(unsafe)` surface.

### Security

- CDATA body content escaped against `]]>` injection before XML wrapping.
- Path traversal check hardened with path component boundary (`base + "/"` instead of bare prefix).
- Symlink filtering verified in both `mdFiles(in:)` and `realSubdirectories(in:)`.

## [1.0.0] - 2026-04-29

### Added

**File management**
- Create, edit, delete, and import `.md` files stored in `~/.pasture/`.
- Drag & drop import for `.md` and `.pdf` files from Finder.
- File watching via `DispatchSource` — the library refreshes automatically when the directory changes on disk.
- Save on file switch to prevent data loss when navigating between files.
- Auto-save with a 1-second Combine debounce on every keystroke.
- `Cmd+S` shortcut for immediate force save.
- `Cmd+Shift+V` shortcut to create a new file from clipboard contents.
- Multi-file selection with `Cmd+click`.
- Merge operation: concatenate selected files (separated by `---`) into a new file.
- Search bar filtering by file name and content with a 300 ms debounce.

**PDF import**
- Extract text from digitally-generated PDFs via PDFKit (zero external dependencies) and save as `.md`.
- Works with reports, papers, and manuals; scanned PDFs without an OCR layer return empty text (documented limitation).

**Template engine**
- `{{VARIABLE}}` syntax to declare variables that are prompted at Feed time.
- `{{VAR=default}}` syntax to declare variables with a pre-filled default value.
- Variable names validated against `[A-Za-z_][A-Za-z0-9_]*`.
- Duplicate variables in a file are prompted only once; first-occurrence default value wins.
- Raw template always shown in the editor — substitution happens only when feeding.

**Feed to AI**
- Copy files to clipboard wrapped in XML `<context>` tags for single-file feeds.
- Copy multiple files wrapped in `<documents><context>…</context></documents>` for multi-file feeds.
- File names XML-escaped in the `name` attribute of context tags.
- Template variable fill sheet shown before copying when variables are detected.
- Clipboard auto-clear after 60 seconds for privacy.

**Token estimation**
- Heuristic token counter (~4 chars/token) shown in the toolbar for rough sizing.

**Design system**
- Design token system covering colors, typography, layout, and visual effects for consistent UI styling.

### Changed

- Minimum target: macOS 14.

### Fixed

- (No bug fixes in initial release — all items above are new.)

### Security

- Path traversal prevention: file paths are validated before any read or write operation.
- Symlink filtering: symlinks inside `~/.pasture/` are excluded from the library listing.
- File name sanitization applied on import and create to block directory-escape sequences.
- XML-escaped file names in context output prevent injection through crafted file names.
- Clipboard auto-clear after 60 seconds reduces exposure of sensitive context copied to the clipboard.

---

[Unreleased]: https://github.com/SeveCod/Pasture/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/SeveCod/Pasture/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/SeveCod/Pasture/releases/tag/v1.0.0
