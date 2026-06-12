# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Pasture

A native macOS app (SwiftUI, no external dependencies) for managing Markdown context files in `~/.pasture/` and feeding them to AI assistants. Supports clipboard copy, direct file export, and built-in AI querying via Anthropic and OpenRouter APIs with streaming responses. Lives in the menu bar for quick access. Built with Swift Package Manager, targets macOS 14+.

The detail panel toggles between a read-only Markdown preview and an Ask mode for querying AI. Users edit files in their preferred external editor; Pasture watches the filesystem and reflects changes automatically.

## Build & Run

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run all PastureKit unit tests (327 tests, Swift Testing framework)
swift test --filter TemplateEngineTests                        # Run one test suite
swift test --filter TemplateEngineTests/renderSimpleReplacement # Run a single test
swift run                # Build + launch the app
./scripts/bundle.sh      # Build release + create .app bundle in dist/
```

Zero external dependencies — everything uses Apple frameworks (SwiftUI, PDFKit, Combine, AppKit, Security).

CI: GitHub Actions (`.github/workflows/ci.yml`) runs debug build, release build, and tests on `macos-15` (required for the Swift 6 toolchain) on every push/PR to `main`.

## Architecture

**Two-target SPM layout**: `PastureKit` (library with testable logic) and `Pasture` (executable, UI). Swift 6 strict concurrency.

### Targets

- **PastureKit** (`Sources/PastureKit/`) — Testable logic: `TemplateEngine` (tokenizer + recursive descent parser + renderer with `#if`/`#unless`/`#each` blocks), `TokenEstimator` (heuristic counter + cost estimation), `FilenameSanitizer`, `StringExtensions` (`xmlEscapedAttribute`), `ExportDestination`, `ExportSettings`, `AIProvider` (`AIProviderKind` enum + `AIModel` struct with pricing catalog), `AISettings` (provider/model persistence in UserDefaults, API keys in Keychain), `KeychainStore` (Security.framework wrapper), `AIClient` (streaming actor for Anthropic/OpenRouter), `SSEParser` (Server-Sent Events line parser), `ContextBuilder` (XML context tag generation for feed output), `DOCXConverter` (NSAttributedString → Markdown with heading/bold/italic/link detection), `CSVConverter` (CSV → Markdown table), `PathValidator` (path containment check for security), `FileLibrary` (filesystem queries: async library scan, dedup URLs, hidden/symlink filtering), `DocumentImporter` (PDF/CSV/DOCX → Markdown conversion, no persistence). All public. This is the testable module.
- **Pasture** (`Sources/Pasture/`) — SwiftUI app. Re-exports PastureKit via `@_exported import PastureKit` in `TemplateEngine.swift`.
- **PastureKitTests** (`Tests/PastureKitTests/`) — 327 tests using Swift Testing framework (`import Testing`, `@Test`, `#expect`).

### Data flow

`MDFileManager` is the single `@StateObject` owned by `PastureApp` and shared via `@EnvironmentObject` to both `ContentView` (main window) and `MenuBarView` (menu bar popover). It manages file CRUD, the file list (`@Published var files`), cached collections (`@Published var collections`), cached search results (`@Published private(set) var filteredFiles`, recomputed only when `files` or `searchQuery` change), and file export. Library scans run asynchronously: `loadFiles()` delegates the disk I/O to `FileLibrary.load(at:)` off the main actor and applies the result back on it (a new call cancels the in-flight one). Directory watching lives in `DirectoryWatcher` (owned by the manager). Files live as `MDFile` value types (defined in PastureKit, `Identifiable` by URL). The filesystem (`~/.pasture/`) is the source of truth.

`AskViewModel` is a `@StateObject` owned by `ContentView` (survives mode toggle). It holds the Ask panel state and coordinates with `AIClient` for streaming responses.

### App scenes

`PastureApp` declares three scenes:
- **`Window("Pasture", id: "main")`** — Main window with `ContentView`. Single-instance via `Window` (not `WindowGroup`).
- **`MenuBarExtra`** — Persistent menu bar icon (leaf) with `MenuBarView` popover (`.menuBarExtraStyle(.window)`).
- **`Settings`** — Preferences panel (`SettingsView`) for managing export destinations and AI configuration (Cmd+,).

`AppDelegate` prevents app termination when the main window closes (`applicationShouldTerminateAfterLastWindowClosed → false`) and handles Dock icon reopen.

### Key files

- **`ContentView.swift`** — UI orchestration: navigation split view, detail panel with `DetailMode` toggle (preview/ask), toolbar, all sheets (paste/merge/template). Delegates subviews to `EditorStatusBar`, `PastureEmptyState`, `FeedbackToast`, `SidebarView`, `FeedButton`, and `FeedService`.
- **`ContentTypes.swift`** — Standalone types used by ContentView: `FileSortOrder` enum, `DetailMode` enum, `FileTransfer` (Transferable for drag & drop).
- **`EditorStatusBar.swift`** — Status bar below the Markdown preview: file name, collection badge, template badge, "Open in Editor" button, token count.
- **`PastureEmptyState.swift`** — Empty state view (no file selected) and `FeedbackToast` (material capsule toast for transient messages).
- **`FeedService.swift`** — `@MainActor final class` shared between `ContentView` and `MenuBarView`. Encapsulates feed execution (template variable detection, clipboard copy with 60s auto-clear, file export), toast feedback, and template confirmation. Eliminates feed logic duplication between main window and menu bar.
- **`AskView.swift`** — Ask panel: context bar (file count, tokens, model, cost), response area with Markdown rendering, input bar (TextEditor + Ask/Stop button), action bar (Copy, Save, Export .md). Includes `PulseModifier` for streaming animation.
- **`AskViewModel.swift`** — `@MainActor final class` managing Ask state: question, responseText, isStreaming, error, provider/model selection. Coordinates `AIClient.ask()` via cancellable `streamTask`. Methods: `send()`, `stop()`, `clear()`, `copyResponse()`, `saveResponse()`, `reloadSettings()`.
- **`MarkdownPreviewView.swift`** — Read-only Markdown preview using `AttributedString(markdown:, options: .init(interpretedSyntax: .full))`. Renders asynchronously via `.task(id:)` to avoid flashing the previous file's content when switching files. Text selection enabled. Falls back to plain text if parsing fails.
- **`SidebarView.swift`** — Search bar, sort toggle (date/name), file list with collection sections, context menus (rename/move/delete for files; rename/delete for collections, deletion confirmed via alert), selection summary with token count.
- **`FeedAction.swift`** — `FeedButton` (renders as plain button when no export destinations configured, or as `Menu` with `primaryAction` when destinations exist — click = default action, hold = menu with clipboard + export options) and `TemplateSheet` (variable input before feeding, adapts UI for `.scalar` vs `.list` variables).
- **`MDFileManager.swift`** — Core file manager: state (`files`, `collections`, `searchQuery`, `filteredFiles`, `lastError`), async library reload via `FileLibrary.load(at:)`, CRUD (save, create, rename, delete), collection management (create/rename/move/delete), feed context delegation to `ContextBuilder`, file export. Owns a `DirectoryWatcher`. Path traversal via `isInsidePasture()` delegates to `PathValidator`. `MDFile` convenience extension for `collection` property using `pastureDir`.
- **`MDFileManager+Import.swift`** — Extension: `importFile` (conversion via `DocumentImporter` in PastureKit; `.md` and unknown types copied as-is), `merge()`, and `scanFolder()` for recursive .md import (max 500 files).
- **`DirectoryWatcher.swift`** — `@MainActor` class encapsulating all DispatchSource file-watching: root + per-collection sub-watchers, GCD→main hop, 0.5s debounce into a single `onChange` callback. All `nonisolated(unsafe)` watcher state lives here.
- **`MenuBarView.swift`** — Compact popover: header with "open window" button, search, file list with checkboxes (`MenuBarFileRow`), footer with Feed button. Independent selection from main window. Feed logic delegated to `FeedService`.
- **`SettingsView.swift`** — `TabView` with two tabs: `ExportSettingsTab` (export destination management via NSSavePanel) and `AISettingsTab` (provider picker, API key SecureField with Keychain save/delete, model picker with pricing, test connection button). Posts `ExportSettings.didChangeNotification` and `AISettings.didChangeNotification` on save.
- **`DesignTokens.swift`** — Complete design system. All UI colors, typography, layout constants, and visual effects.
- **`PastureApp.swift`** — App entry point. Three scenes (Window, MenuBarExtra, Settings). Menu commands: "Open in Default Editor" (Cmd+E), "Paste from Clipboard" (Cmd+Shift+V), "Toggle Ask Mode" (Cmd+Shift+A). `@NSApplicationDelegateAdaptor` for `AppDelegate`.
- **`AppDelegate.swift`** — Prevents quit on last window close, handles Dock icon reopen. Enforces single-instance via `flock` on a lock file in `NSTemporaryDirectory()`: if the lock is already held, the new instance activates the running one and terminates itself.

### PastureKit models

- **`TemplateEngine`** — Tokenizer + recursive descent parser + single-pass renderer. Supports `{{VAR}}`, `{{VAR=default}}`, `{{#if VAR}}...{{/if}}`, `{{#unless VAR}}...{{/unless}}`, `{{#each ITEMS}}...{{/each}}` (with `{{.}}` for current value, `{{@index}}` for index). Security limits: `maxNestingDepth=16`, `maxIterations=1000`. No regex — pure character scanning and token-based parsing.
- **`TemplateVariable`** — Identifiable, Hashable, Sendable. Fields: name, defaultValue, value, `kind: VariableKind` (`.scalar` or `.list`). `listItems` computed property splits comma-separated values.
- **`TemplateNode`** — Recursive enum representing the AST: `.text`, `.variable`, `.currentValue`, `.currentIndex`, `.ifBlock`, `.unlessBlock`, `.eachBlock`.
- **`ExportDestination`** — `Codable`, `Sendable` struct: id, name, path, computed `url` and `isWritable`. Represents a file path where Feed can write context directly.
- **`ExportSettings`** — Static namespace for UserDefaults persistence of export destinations, default destination ID, and export file format (`ExportFileFormat` enum: `.markdown`/`.plainText`, default `.markdown`; read at panel-build time, not cached). Fires `didChangeNotification` when settings change (consumed by `ContentView` and `MenuBarView` via `.onReceive`).
- **`AIProviderKind`** — Enum: `.anthropic`, `.openRouter`. Drives API endpoint and auth header format.
- **`AIModel`** — `Codable`, `Hashable`, `Sendable`, `Identifiable` struct: id, displayName, provider, contextWindow, maxOutputTokens, inputCostPer1M, outputCostPer1M. `maxOutputTokens` is per-model and passed as `max_tokens` in API requests. Static catalog via `defaultModels`, lookup via `models(for:)` and `model(byID:)`. `resolve(id:preferredProvider:)` provides a safe fallback chain: exact match → first model for preferred provider → first default model.
- **`AISettings`** — Static namespace (same pattern as `ExportSettings`). Provider and model ID in UserDefaults; API keys in Keychain via `KeychainStore`. Fires `didChangeNotification`.
- **`KeychainStore`** — Static methods: `save(key:value:service:)` (upsert), `load(key:service:)`, `delete(key:service:)`. Uses Security.framework. Items created with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Defines `KeychainError`.
- **`AIClient`** — `actor` wrapping `URLSession`. `AIClient.shared` is the canonical instance (used by both `AskViewModel` and the Settings connection test, so they exercise the same session configuration). Request building is a single `buildRequest` parameterized by provider (endpoint + auth headers differ; JSON body is shared). `ask(question:context:model:apiKey:) -> AsyncThrowingStream<String, Error>`. Builds provider-specific requests (Anthropic: `x-api-key` + `anthropic-version`, OpenRouter: `Bearer` auth). Uses `model.maxOutputTokens` as `max_tokens`; empty-context guard skips the context prefix when no files are selected. Streams via `URLSession.bytes(for:)` + `SSEParser`. Retries automatically on 429 (rate limited) and 529 (overloaded) with exponential backoff (max 2 retries, respects `Retry-After` header, capped at 30s). HTTP error mapping: 401→invalidAPIKey, 429→rateLimited, 529→serverError.
- **`SSEEvent`** — Sendable struct: event type + data.
- **`SSELineBuffer`** — Sendable stateful accumulator for SSE line parsing.
- **`SSEParser`** — Static `parse(line:buffer:) -> SSEEvent?`. Standard SSE spec: `event:`, `data:`, empty line = dispatch.
- **`AIClientError`** — Sendable enum with 8 cases: noAPIKey, invalidAPIKey, contextTooLarge, rateLimited, timeout, serverError, networkError, invalidResponse. All with `LocalizedError` conformance.
- **`TokenEstimator`** — Heuristic token counter (~4 chars/token). `estimatedCost(inputTokens:outputTokens:model:)` for pre-send cost calculation. `formattedCost(_:)` for display (`"<$0.001"`, `"~$0.003"`). Public helpers `inputTokenEstimate(contextTokens:question:)` and `costEstimate(contextTokens:question:model:assumedOutputTokens:)` used by `AskViewModel`.
- **`ContextBuilder`** — Static `build(files:) -> String`. Takes `[FileEntry]` (name + content) and produces XML context output. Handles CDATA escaping and multi-file wrapping. `MDFileManager.feedContext` delegates to this.
- **`DOCXConverter`** — `convert(url:)` reads .doc/.docx files via `NSAttributedString` and converts to Markdown. `convertAttributedString(_:)` for direct conversion. Detects headings (font size ratio), bold/italic (font traits), and links. Collapses consecutive empty lines.
- **`PathValidator`** — Static `isInside(target:base:) -> Bool`. Validates path containment using `standardizedFileURL.path` with trailing slash guard. `MDFileManager.isInsidePasture` delegates to this.
- **`MDFile`** — `Sendable` struct in PastureKit. Identifiable by URL, Hashable by URL, Equatable by URL. Two inits: memberwise (for testing) and I/O (`init(url:)` reads from disk). `collection(relativeTo:)` computes parent directory name relative to a base URL. `matches(query:)` is the single search predicate shared by the main window and the menu bar. `updateDerivedProperties()` recalculates `tokens` and `hasTemplateVars`. The Pasture app adds a convenience `collection` computed property via extension using `MDFileManager.pastureDir`.
- **`FileLibrary`** — Static filesystem queries: `load(at:)` (async, nonisolated — full library scan off the main actor, files sorted by date desc), `mdFiles(in:)`, `realSubdirectories(in:)`, `visibleContents(of:)` (skips hidden files; basis of the `.DS_Store` collection-deletion fix), `deduplicatedURL(baseName:ext:in:)`.
- **`DocumentImporter`** — Static `markdownContent(for:) -> String?`: PDF (PDFKit; throws `emptyPDF` for scanned PDFs without text instead of producing an empty file), CSV (UTF-8 → Latin-1 fallback), DOCX/DOC. Returns `nil` for non-convertible types (caller copies as-is). Pure conversion, no persistence.
- **`QuestionHistory`** — Static namespace persisting the last 10 Ask questions in UserDefaults (most recent first, trimmed, deduplicated). Surfaced as a clock menu in `AskView`'s input bar; recorded in `AskViewModel.send()`.

### Patterns to know

**Menu → View communication**: `PastureApp` posts `.openInEditor`, `.pasteFromClipboard`, and `.toggleAskMode` notifications. `ContentView` subscribes via `.onReceive`.

**Settings → Views communication**: `SettingsView` posts `ExportSettings.didChangeNotification` and `AISettings.didChangeNotification`. `ContentView`, `MenuBarView`, and `AskView` subscribe to reload state.

**Color scheme adaptation**: Static functions `Color.pastureX(_ scheme: ColorScheme)` resolve light/dark variants (including `pastureAccent(_:)`, `pastureError(_:)`, `pastureTokenBadgeText(_:)`). Never hardcode colors directly. All text/background token pairs meet WCAG AA contrast (≥4.5:1) in both schemes — keep that invariant when adding or changing tokens. Text over the brand gradient uses `pastureTextPrimaryLight` (dark), not white.

**Ask privacy notice**: the first Ask request shows a one-time alert (persisted in `@AppStorage("askPrivacyNoticeAccepted")`) stating that selected file contents are sent to the configured provider. The model badge in the context bar carries a permanent `.help` hint with the same message.

**Feed output format**: Generated by `ContextBuilder.build(files:)` in PastureKit. Single file → `<context name="file.md"><![CDATA[content]]></context>`. Multiple → wrapped in `<documents>`. `MDFileManager.feedContext` maps `MDFile` arrays to `ContextBuilder.FileEntry` and delegates. Template variables and blocks are substituted only at feed time, never persisted. XML attributes escaped via `xmlEscapedAttribute`. CDATA closing sequences (`]]>`) are escaped to prevent injection.

**Template rendering pipeline**: `parse()` (string → `[TemplateNode]` AST) → `render(nodes:with:)` (AST → string). Single-pass: variable values are never re-parsed as template syntax. The public `render(_:with:)` convenience calls both steps. `extractVariables()` walks the AST to collect variables with correct `kind` (`.scalar` for `#if`/`#unless`, `.list` for `#each`).

**Feed delivery modes**: `FeedService.deliverFeed(context:targets:destination:fm:)` — if destination is nil, copies to clipboard with 60s auto-clear. If destination is an `ExportDestination`, writes to file via `fm.exportToFile()`. Default destination (starred in Settings) is used as the Feed button's primary action when configured. `FeedService` is shared between `ContentView` and `MenuBarView` as `@StateObject`; `AskView` receives ContentView's instance and routes its toasts (`showFeedback(_:isError:)`) through it — no view keeps its own toast state.

**Ask mode toggle**: `PastureApp` posts `.toggleAskMode` (Cmd+Shift+A). `ContentView` toggles `detailMode` between `.preview` and `.ask` with animation. `AskViewModel` survives the toggle as `@StateObject`.

**AI streaming pipeline**: `AIClient.ask()` returns `AsyncThrowingStream<String, Error>`. Retries 429/529 errors up to 2 times with exponential backoff before surfacing the error. `AskViewModel` consumes the stream in a cancellable `Task` (`streamTask`). Cancellation propagates via `Task.isCancelled` check in both the retry loop and the SSE reading loop.

**AI settings propagation**: `AISettingsTab` persists to UserDefaults + Keychain. `AISettings.didChangeNotification` is received by `AskView` via `.onReceive`, which calls `viewModel.reloadSettings()`.

**Context window guard**: `AskViewModel.send()` checks `inputTokenEstimate > model.contextWindow` before sending and emits `AIClientError.contextTooLarge`.

**External editing**: "Open in Editor" (Cmd+E or status bar button) calls `NSWorkspace.shared.open(file.url)` after validating `isInsidePasture()`. The file watcher (`DispatchSource` with 0.5s debounce) automatically reloads files when the external editor saves.

**Drag & drop export**: Files are draggable via `Transferable` protocol (`FileTransfer` struct with `FileRepresentation`). Drop import supports `.md` and `.pdf`.

**Clipboard lifecycle**: Auto-clears 60 seconds post-feed if user hasn't copied anything else (tracked via `NSPasteboard.changeCount`). Works from both main window and menu bar.

**Collections**: Subdirectories inside `~/.pasture/`. Cached in `@Published var collections` (refreshed on load, create, delete). Sidebar groups files by collection with context menus for moving files between collections.

### Security invariants

- All file operations validated via `isInsidePasture()` which delegates to `PathValidator.isInside(target:base:)` in PastureKit — uses `standardizedFileURL.path` comparison with trailing slash guard to prevent prefix tricks. Also applied before `NSWorkspace.shared.open()` in "Open in Editor".
- Export destinations are explicitly outside `~/.pasture/` — `isInsidePasture()` is NOT applied to export paths.
- Symlinks filtered out via `realSubdirectories(in:)` and `mdFiles(in:)`.
- File names sanitized via `FilenameSanitizer.sanitize()` (no `/`, `\0`, `:`, `\`). Used in both file creation and Ask response saving.
- Feed output uses CDATA wrapping to prevent content injection.
- Template engine: single-pass rendering prevents template injection via variable values. Nesting depth capped at 16 (both parser and renderer). Iteration count capped at 1,000 for `#each` blocks.
- Clipboard auto-clears after 60 seconds post-feed.
- API keys stored in macOS Keychain via `KeychainStore` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Never stored in UserDefaults or plaintext.
- All network calls use HTTPS with default ATS (TLS 1.2+). No custom URLSession delegates or certificate pinning overrides.
- Error response bodies limited to 2000 bytes. Error messages truncated to 200 chars before display.
- Context size validated against `model.contextWindow` before sending API requests.
- App is not sandboxed (SPM build, no entitlements). If sandboxed in the future, export destinations will need security-scoped bookmarks.

### Concurrency model

`MDFileManager` is `@MainActor`. Directory watching is encapsulated in `DirectoryWatcher` (`@MainActor`): a module-level free function `makeWatchSource(fd:onEvent:)` keeps GCD closures out of actor isolation; events hop to the main queue via `DispatchQueue.main.async` + `MainActor.assumeIsolated` and are debounced (0.5s) into a single `onChange` callback. `nonisolated(unsafe)` marks the GCD-managed watcher state, confined to that one type. Library scans (`FileLibrary.load`) are nonisolated async — they run on the global executor, keeping disk I/O off the main thread.

`AIClient` is an `actor` (Swift 6 safe). `AskViewModel` is `@MainActor`. The streaming bridge uses `AsyncThrowingStream` returned from the actor method and consumed on MainActor via a cancellable `streamTask: Task<Void, Never>?`.

## Bundle ID & versioning

Bundle ID: `com.sevecod.pasture`. Current version: **1.3.0**. Version is hardcoded in `scripts/bundle.sh` (not derived from git tags). When releasing: update the `VERSION` variable there and add an entry to `CHANGELOG.md` (Keep a Changelog format, SemVer).
