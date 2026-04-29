# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Pasture

A native macOS app (SwiftUI, no external dependencies) for managing Markdown context files in `~/.pasture/` and feeding them to AI assistants wrapped in XML `<context>` tags. Built with Swift Package Manager, targets macOS 14+.

## Build & Run

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run PastureKit unit tests (65 tests, Swift Testing framework)
swift run                # Build + launch the app
./scripts/bundle.sh      # Build release + create .app bundle in dist/
```

Zero external dependencies — everything uses Apple frameworks (SwiftUI, PDFKit, Combine, AppKit).

## Architecture

**Two-target SPM layout**: `PastureKit` (library with testable logic) and `Pasture` (executable, UI). Swift 6 strict concurrency.

### Targets

- **PastureKit** (`Sources/PastureKit/`) — Pure logic, no UI: `TemplateEngine`, `TokenEstimator`, `FilenameSanitizer`, `xmlEscapedAttribute`. All public. This is the testable module.
- **Pasture** (`Sources/Pasture/`) — SwiftUI app. Re-exports PastureKit via `@_exported import PastureKit` in `TemplateEngine.swift`.
- **PastureKitTests** (`Tests/PastureKitTests/`) — 65 tests using Swift Testing framework (`import Testing`, `@Test`, `#expect`).

### Data flow

`MDFileManager` is the single `@StateObject` owned by `ContentView`. It manages all file I/O, the file list (`@Published var files`), cached collections (`@Published var collections`), search filtering, and directory watching via `DispatchSource`. Files live as `MDFile` value types (struct, `Identifiable` by URL). The filesystem (`~/.pasture/`) is the source of truth.

### Key files

- **`ContentView.swift`** — UI orchestration: navigation split view, editor panel, toolbar, all sheets (paste/merge/template), Feed action logic. Delegates sidebar to `SidebarView` and feed button to `FeedButton`.
- **`SidebarView.swift`** — Search bar, sort toggle (date/name), file list with collection sections, context menus, selection summary with token count.
- **`FeedAction.swift`** — `FeedButton` (standalone view with internal hover state) and `TemplateSheet` (variable input before feeding).
- **`MDFileManager.swift`** — Also defines `MDFile` struct. All I/O: load, save, create, delete, import (`.md` and `.pdf`), merge, move between collections, feed context generation (CDATA-wrapped), directory watching. Path traversal consolidated via `isInsidePasture()`. File listing uses `mdFiles(in:)` and `realSubdirectories(in:)` helpers.
- **`DesignTokens.swift`** — Complete design system. All UI colors, typography, layout constants, and visual effects.
- **`EditorView.swift`** — TextEditor with debounced auto-save (1s). Derived properties (tokens, template detection) update on the debounce, not per keystroke.
- **`PastureApp.swift`** — App entry point. Menu commands post to `NotificationCenter`.
- **`FileRow.swift`**, **`NameInputSheet.swift`**, **`TemplateBadge.swift`** — Small extracted views.

### Patterns to know

**Menu → View communication**: `PastureApp` posts `.forceSave` and `.pasteFromClipboard` notifications. `ContentView` subscribes via `.onReceive`.

**Color scheme adaptation**: Static functions `Color.pastureX(_ scheme: ColorScheme)` resolve light/dark variants. Never hardcode colors directly.

**Feed output format**: Single file → `<context name="file.md"><![CDATA[content]]></context>`. Multiple → wrapped in `<documents>`. Template variables are substituted only at feed time, never persisted. XML attributes escaped via `xmlEscapedAttribute`.

**Drag & drop export**: Files are draggable via `Transferable` protocol (`FileTransfer` struct with `FileRepresentation`). Drop import supports `.md` and `.pdf`.

**Clipboard lifecycle**: Auto-clears 60 seconds post-feed if user hasn't copied anything else (tracked via `NSPasteboard.changeCount`).

**Collections**: Subdirectories inside `~/.pasture/`. Cached in `@Published var collections` (refreshed on load, create, delete). Sidebar groups files by collection with context menus for moving files between collections.

### Security invariants

- All file operations validated via `isInsidePasture()` — consolidated path traversal check against `pastureDir.standardizedFileURL.path`.
- Symlinks filtered out via `realSubdirectories(in:)` and `mdFiles(in:)`.
- File names sanitized via `FilenameSanitizer.sanitize()` (no `/`, `\0`, `:`, `\`).
- Feed output uses CDATA wrapping to prevent content injection.
- Clipboard auto-clears after 60 seconds post-feed.

### Concurrency model

`MDFileManager` is `@MainActor`. The directory watcher uses a module-level free function `makeDirectoryWatchSource(fd:)` to avoid Swift 6 actor isolation in GCD closures. It posts a notification that the main-actor observer receives and debounces (0.5s). Editor auto-save uses Combine's `debounce(for: 1s)`. `nonisolated(unsafe)` marks the GCD-managed watcher state.

## Bundle ID & versioning

Bundle ID: `com.sevecod.pasture`. Version is hardcoded in `scripts/bundle.sh` (not derived from git tags). Update the `VERSION` variable there when releasing.
