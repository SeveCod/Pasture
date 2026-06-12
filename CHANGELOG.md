# Changelog

All notable changes to Pasture are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Pasture uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Export file format setting (Markdown `.md` / Plain text `.txt`) in Preferences → Export. Default: `.md`.

### Fixed

- Export panels (toolbar Export and destination picker in Settings) no longer coerce the suggested `.md` filename to `.txt` — the save panel now declares the Markdown UTType first.

### Internal

- `ExportFileFormat` enum in PastureKit with persistence via `ExportSettings.fileFormat()`/`setFileFormat()`; 4 new tests (300 total).

## [1.2.1] - 2026-05-03

### Changed

- Sonnet 4 responses can now be up to 16 384 tokens (previously capped at 4 096). Haiku 3.5 remains at 8 192. Per-model `maxOutputTokens` replaces the old hard-coded limit.

### Fixed

- Ask mode no longer inserts a blank line before the question when no files are selected — the question is sent without any context prefix.
- Markdown preview no longer briefly flashes the previous file's content when switching between files.

### Internal

- `MarkdownPreviewView`: async `AttributedString` render via `.task(id:)` eliminates the flash on file change.
- `AIModel`: new `maxOutputTokens` field per model; `AIClient` passes it as `max_tokens` in the request body.
- `AIClient`: empty-context guard — skips the `\n\n` separator when no files are selected.
- `AskViewModel`: `hasAPIKey` cached as `@Published var` to avoid repeated Keychain reads; `selectedProvider`/`selectedModelID` narrowed to `private(set)`; `TokenEstimator` helpers delegated to PastureKit public API.
- `FeedAction`/`FeedButton`: token label strings extracted to computed properties (DRY).
- `FeedService`: `cancelTemplateFeed()` and private `resetPendingFeed()` helper added.
- `MDFileManager`: `refreshCollections(from:)` overload eliminates a redundant directory scan on load.
- `SidebarView`: file grouping replaced with O(n) `Dictionary(grouping:)` (was O(n²)).
- `TokenEstimator`: `inputTokenEstimate` and `costEstimate` extracted as public helpers; 4 new tests.
- Tests: 2 new empty-context guard tests for Anthropic and OpenRouter (296 tests total).

## [1.2.0] - 2026-04-29

### Added

- **Feed & Ask**: ask questions about selected files directly from the app. Responses stream in real time from Anthropic or OpenRouter APIs.
- AI Settings tab in Preferences (Cmd+,): configure provider, model, and API key.
- API keys stored securely in macOS Keychain via `Security.framework`.
- Toggle between read-only preview and Ask mode with Cmd+Shift+A.
- Context bar showing file count, token estimate, model, and cost estimate before sending.
- Action bar after response: Copy, Save to Pasture, Export as `.md`.
- Scan Folder toolbar button: recursively import `.md` files from any directory into a new collection.
- Export toolbar button: save feed context as `.md` to any location via NSSavePanel.
- New PastureKit components: `AIClient` (streaming actor), `AIProvider`/`AIModel` (provider catalog), `AISettings` (persistence), `KeychainStore` (Keychain wrapper), `SSEParser` (Server-Sent Events).
- `TokenEstimator.estimatedCost()` and `formattedCost()` for pre-send cost display.
- View menu with "Toggle Ask Mode" command.
- 37 new tests (140 total): KeychainStore (8), AIProvider (6), AISettings (7), SSEParser (10), TokenEstimator cost methods (6).

### Changed

- Detail panel now toggles between `MarkdownPreviewView` and `AskView` via `DetailMode` enum.
- `ContentView` gains `@StateObject askViewModel` (survives mode toggle).
- `SettingsView` converted to `TabView` with Export and AI tabs.
- `AskViewModel.saveResponse` uses `FilenameSanitizer` for consistent name sanitization.
- `KeychainStore` items created with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` for device-bound security.
- `AIClient` URLs extracted to static constants (no force-unwrap).
- `mapHTTPError` extracts `Retry-After` header on 429 responses; truncates error messages to 200 chars.

### Security

- API keys stored in macOS Keychain (not UserDefaults or plaintext).
- Keychain items restricted to `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- All network calls use HTTPS with default ATS (TLS 1.2+).
- Error response bodies limited to 2000 bytes to prevent memory abuse.
- Context size validated against model context window before sending.

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

[Unreleased]: https://github.com/SeveCod/Pasture/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/SeveCod/Pasture/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/SeveCod/Pasture/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/SeveCod/Pasture/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/SeveCod/Pasture/releases/tag/v1.0.0
