# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Pasture

A native macOS app (SwiftUI, no external dependencies) for managing Markdown context files in `~/.pasture/` and feeding them to AI assistants wrapped in XML `<context>` tags. Supports clipboard and direct file export. Lives in the menu bar for quick access. Built with Swift Package Manager, targets macOS 14+.

The detail panel is a read-only Markdown preview (not an editor). Users edit files in their preferred external editor; Pasture watches the filesystem and reflects changes automatically.

## Build & Run

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run all PastureKit unit tests (103 tests, Swift Testing framework)
swift test --filter TemplateEngineTests                        # Run one test suite
swift test --filter TemplateEngineTests/renderSimpleReplacement # Run a single test
swift run                # Build + launch the app
./scripts/bundle.sh      # Build release + create .app bundle in dist/
```

Zero external dependencies — everything uses Apple frameworks (SwiftUI, PDFKit, Combine, AppKit).

## Architecture

**Two-target SPM layout**: `PastureKit` (library with testable logic) and `Pasture` (executable, UI). Swift 6 strict concurrency.

### Targets

- **PastureKit** (`Sources/PastureKit/`) — Pure logic, no UI: `TemplateEngine` (tokenizer + recursive descent parser + renderer with `#if`/`#unless`/`#each` blocks), `TokenEstimator`, `FilenameSanitizer`, `StringExtensions` (`xmlEscapedAttribute`), `ExportDestination`, `ExportSettings`. All public. This is the testable module.
- **Pasture** (`Sources/Pasture/`) — SwiftUI app. Re-exports PastureKit via `@_exported import PastureKit` in `TemplateEngine.swift`.
- **PastureKitTests** (`Tests/PastureKitTests/`) — 103 tests using Swift Testing framework (`import Testing`, `@Test`, `#expect`).

### Data flow

`MDFileManager` is the single `@StateObject` owned by `PastureApp` and shared via `@EnvironmentObject` to both `ContentView` (main window) and `MenuBarView` (menu bar popover). It manages all file I/O, the file list (`@Published var files`), cached collections (`@Published var collections`), search filtering, directory watching via `DispatchSource`, and file export. Files live as `MDFile` value types (struct, `Identifiable` by URL). The filesystem (`~/.pasture/`) is the source of truth.

### App scenes

`PastureApp` declares three scenes:
- **`Window("Pasture", id: "main")`** — Main window with `ContentView`. Single-instance via `Window` (not `WindowGroup`).
- **`MenuBarExtra`** — Persistent menu bar icon (leaf) with `MenuBarView` popover (`.menuBarExtraStyle(.window)`).
- **`Settings`** — Preferences panel (`SettingsView`) for managing export destinations (Cmd+,).

`AppDelegate` prevents app termination when the main window closes (`applicationShouldTerminateAfterLastWindowClosed → false`) and handles Dock icon reopen.

### Key files

- **`ContentView.swift`** — UI orchestration: navigation split view, Markdown preview panel, toolbar, all sheets (paste/merge/template), Feed action logic with clipboard and file export modes. "Open in Editor" button (Cmd+E) delegates editing to the system default app. Delegates sidebar to `SidebarView` and feed button to `FeedButton`.
- **`MarkdownPreviewView.swift`** — Read-only Markdown preview using `AttributedString(markdown:, options: .init(interpretedSyntax: .full))`. Text selection enabled. Falls back to plain text if parsing fails.
- **`SidebarView.swift`** — Search bar, sort toggle (date/name), file list with collection sections, context menus, selection summary with token count.
- **`FeedAction.swift`** — `FeedButton` (renders as plain button when no export destinations configured, or as `Menu` with `primaryAction` when destinations exist — click = default action, hold = menu with clipboard + export options) and `TemplateSheet` (variable input before feeding, adapts UI for `.scalar` vs `.list` variables).
- **`MDFileManager.swift`** — Also defines `MDFile` struct. All I/O: load, save, create, delete, import (`.md` and `.pdf`), merge, move between collections, feed context generation (CDATA-wrapped), file export (`exportToFile`), directory watching. Calls `setup()` from `init()`. Path traversal consolidated via `isInsidePasture()` (internal visibility, used by ContentView for "Open in Editor" validation).
- **`MenuBarView.swift`** — Compact popover: header with "open window" button, search, file list with checkboxes (`MenuBarFileRow`), footer with Feed button. Independent selection from main window. Supports both clipboard and file export.
- **`SettingsView.swift`** — Form for managing export destinations (add/remove/choose path via `NSSavePanel`). Star marks the default destination. Persists via `ExportSettings` (UserDefaults). Posts `ExportSettings.didChangeNotification` on save.
- **`DesignTokens.swift`** — Complete design system. All UI colors, typography, layout constants, and visual effects.
- **`PastureApp.swift`** — App entry point. Three scenes (Window, MenuBarExtra, Settings). Menu commands: "Open in Default Editor" (Cmd+E), "Paste from Clipboard" (Cmd+Shift+V). `@NSApplicationDelegateAdaptor` for `AppDelegate`.
- **`AppDelegate.swift`** — Prevents quit on last window close, handles Dock icon reopen.

### PastureKit models

- **`TemplateEngine`** — Tokenizer + recursive descent parser + single-pass renderer. Supports `{{VAR}}`, `{{VAR=default}}`, `{{#if VAR}}...{{/if}}`, `{{#unless VAR}}...{{/unless}}`, `{{#each ITEMS}}...{{/each}}` (with `{{.}}` for current value, `{{@index}}` for index). Security limits: `maxNestingDepth=16`, `maxIterations=1000`. No regex — pure character scanning and token-based parsing.
- **`TemplateVariable`** — Identifiable, Hashable, Sendable. Fields: name, defaultValue, value, `kind: VariableKind` (`.scalar` or `.list`). `listItems` computed property splits comma-separated values.
- **`TemplateNode`** — Recursive enum representing the AST: `.text`, `.variable`, `.currentValue`, `.currentIndex`, `.ifBlock`, `.unlessBlock`, `.eachBlock`.
- **`ExportDestination`** — `Codable`, `Sendable` struct: id, name, path, computed `url` and `isWritable`. Represents a file path where Feed can write context directly.
- **`ExportSettings`** — Static namespace for UserDefaults persistence of export destinations and default destination ID. Fires `didChangeNotification` when settings change (consumed by `ContentView` and `MenuBarView` via `.onReceive`).

### Patterns to know

**Menu → View communication**: `PastureApp` posts `.openInEditor` and `.pasteFromClipboard` notifications. `ContentView` subscribes via `.onReceive`.

**Settings → Views communication**: `SettingsView` posts `ExportSettings.didChangeNotification`. Both `ContentView` and `MenuBarView` subscribe to reload export destinations.

**Color scheme adaptation**: Static functions `Color.pastureX(_ scheme: ColorScheme)` resolve light/dark variants. Never hardcode colors directly.

**Feed output format**: Single file → `<context name="file.md"><![CDATA[content]]></context>`. Multiple → wrapped in `<documents>`. Template variables and blocks are substituted only at feed time, never persisted. XML attributes escaped via `xmlEscapedAttribute`.

**Template rendering pipeline**: `parse()` (string → `[TemplateNode]` AST) → `render(nodes:with:)` (AST → string). Single-pass: variable values are never re-parsed as template syntax. The public `render(_:with:)` convenience calls both steps. `extractVariables()` walks the AST to collect variables with correct `kind` (`.scalar` for `#if`/`#unless`, `.list` for `#each`).

**Feed delivery modes**: `deliverFeed(context:targets:destination:)` — if destination is nil, copies to clipboard with 60s auto-clear. If destination is an `ExportDestination`, writes to file via `fm.exportToFile()`. Default destination (starred in Settings) is used as the Feed button's primary action when configured.

**External editing**: "Open in Editor" (Cmd+E or status bar button) calls `NSWorkspace.shared.open(file.url)` after validating `isInsidePasture()`. The file watcher (`DispatchSource` with 0.5s debounce) automatically reloads files when the external editor saves.

**Drag & drop export**: Files are draggable via `Transferable` protocol (`FileTransfer` struct with `FileRepresentation`). Drop import supports `.md` and `.pdf`.

**Clipboard lifecycle**: Auto-clears 60 seconds post-feed if user hasn't copied anything else (tracked via `NSPasteboard.changeCount`). Works from both main window and menu bar.

**Collections**: Subdirectories inside `~/.pasture/`. Cached in `@Published var collections` (refreshed on load, create, delete). Sidebar groups files by collection with context menus for moving files between collections.

### Security invariants

- All file operations validated via `isInsidePasture()` — consolidated path traversal check against `pastureDir.standardizedFileURL.path`. Also applied before `NSWorkspace.shared.open()` in "Open in Editor".
- Export destinations are explicitly outside `~/.pasture/` — `isInsidePasture()` is NOT applied to export paths.
- Symlinks filtered out via `realSubdirectories(in:)` and `mdFiles(in:)`.
- File names sanitized via `FilenameSanitizer.sanitize()` (no `/`, `\0`, `:`, `\`).
- Feed output uses CDATA wrapping to prevent content injection.
- Template engine: single-pass rendering prevents template injection via variable values. Nesting depth capped at 16 (both parser and renderer). Iteration count capped at 1,000 for `#each` blocks.
- Clipboard auto-clears after 60 seconds post-feed.
- App is not sandboxed (SPM build, no entitlements). If sandboxed in the future, export destinations will need security-scoped bookmarks.

### Concurrency model

`MDFileManager` is `@MainActor`. The directory watcher uses a module-level free function `makeDirectoryWatchSource(fd:)` to avoid Swift 6 actor isolation in GCD closures. It posts a notification that the main-actor observer receives and debounces (0.5s). `nonisolated(unsafe)` marks the GCD-managed watcher state.

## Bundle ID & versioning

Bundle ID: `com.sevecod.pasture`. Current version: **1.2.0**. Version is hardcoded in `scripts/bundle.sh` (not derived from git tags). Update the `VERSION` variable there when releasing.
