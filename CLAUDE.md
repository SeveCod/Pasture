# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Pasture

A native macOS app (SwiftUI, no external dependencies) for managing Markdown context files in `~/.pasture/` and feeding them to AI assistants. Supports clipboard copy, direct file export, and built-in AI querying via Anthropic and OpenRouter APIs with streaming responses. Lives in the menu bar for quick access. Built with Swift Package Manager, targets macOS 14+.

The detail panel toggles between a read-only Markdown preview and an Ask mode for querying AI. Users edit files in their preferred external editor; Pasture watches the filesystem and reflects changes automatically.

## Build & Run

```bash
swift build              # Debug build
swift build -c release   # Release build
swift test               # Run all PastureKit unit tests (501 tests, Swift Testing framework)
swift test --filter TemplateEngineTests                        # Run one test suite
swift test --filter TemplateEngineTests/renderSimpleReplacement # Run a single test
swift test --filter MCPDispatcherTests                         # MCP dispatcher tests
swift run                # Build + launch the app
swift run pasture-mcp    # Build + run the MCP server (debug; reads stdin, writes stdout)
./scripts/bundle.sh      # Build release + create .app bundle in dist/
```

Zero external dependencies — everything uses Apple frameworks (SwiftUI, PDFKit, Combine, AppKit, Security).

CI: GitHub Actions (`.github/workflows/ci.yml`) runs debug build, release build, and tests on `macos-15` (required for the Swift 6 toolchain) on every push/PR to `main`.

## Architecture

**Four-target SPM layout**: `PastureKit` (library with testable logic), `Pasture` (executable, UI), `pasture-mcp` (MCP server executable), and `PastureKitTests` (test target). Swift 6 strict concurrency.

### Targets

- **PastureKit** (`Sources/PastureKit/`) — Testable logic: `TemplateEngine` (tokenizer + recursive descent parser + renderer with `#if`/`#unless`/`#each` blocks), `TokenEstimator` (heuristic counter + cost estimation), `FilenameSanitizer`, `StringExtensions` (`xmlEscapedAttribute`), `ExportDestination`, `ExportSettings`, `AIProvider` (`AIProviderKind` enum + `AIModel` struct with pricing catalog), `AISettings` (provider/model persistence in UserDefaults, API keys in Keychain), `KeychainStore` (Security.framework wrapper), `AIClient` (streaming actor for Anthropic/OpenRouter), `SSEParser` (Server-Sent Events line parser), `ContextBuilder` (XML context tag generation for feed output), `DOCXConverter` (NSAttributedString → Markdown with heading/bold/italic/link detection), `CSVConverter` (CSV → Markdown table), `PathValidator` (path containment check for security), `FileLibrary` (filesystem queries: async library scan, dedup URLs, hidden/symlink filtering), `DocumentImporter` (PDF/CSV/DOCX → Markdown conversion, no persistence), `FeedFormat`/`FeedFormatSettings` (feed payload format enum + UserDefaults persistence), `SecretScanner` (pre-feed credential detector), `ContextLimit` (binary context-window guard for sidebar), `SelectionPreset`/`SelectionPresetStore` (named file selections with relative-path persistence), `PresetResolver` (relative-path → URL resolution with path-traversal guard). Also contains the full MCP layer — see **MCP layer** subsection below. All public. This is the testable module.
- **Pasture** (`Sources/Pasture/`) — SwiftUI app. Re-exports PastureKit via `@_exported import PastureKit` in `TemplateEngine.swift`.
- **pasture-mcp** (`Sources/pasture-mcp/`) — MCP server executable. A thin `main.swift` (~30 lines) that wires `FileHandle.standardInput` to `MCPLineReader` and feeds each line to `MCPDispatcher`. All protocol logic lives in PastureKit (ADR-MCP-004). Zero external dependencies beyond PastureKit and Foundation.
- **PastureKitTests** (`Tests/PastureKitTests/`) — 501 tests using Swift Testing framework (`import Testing`, `@Test`, `#expect`). Includes 7 MCP test suites: `MCPDispatcherTests`, `MCPToolsTests`, `MCPProtocolTests`, `MCPLineReaderTests`, `MCPConfigGeneratorTests`, `MCPVaultSecretStatTests`, `MCPEndToEndTests`.

### Data flow

`MDFileManager` is the single `@StateObject` owned by `PastureApp` and shared via `@EnvironmentObject` to both `ContentView` (main window) and `MenuBarView` (menu bar popover). It manages file CRUD, the file list (`@Published var files`), cached collections (`@Published var collections`), cached search results (`@Published private(set) var filteredFiles`, recomputed only when `files` or `searchQuery` change), and file export. Library scans run asynchronously: `loadFiles()` delegates the disk I/O to `FileLibrary.load(at:)` off the main actor and applies the result back on it (a new call cancels the in-flight one). Directory watching lives in `DirectoryWatcher` (owned by the manager). Files live as `MDFile` value types (defined in PastureKit, `Identifiable` by URL). The filesystem (`~/.pasture/`) is the source of truth.

`AskViewModel` is a `@StateObject` owned by `ContentView` (survives mode toggle). It holds the Ask panel state and coordinates with `AIClient` for streaming responses.

### App scenes

`PastureApp` declares three scenes:
- **`Window("Pasture", id: "main")`** — Main window with `ContentView`. Single-instance via `Window` (not `WindowGroup`).
- **`MenuBarExtra`** — Persistent menu bar icon (leaf) with `MenuBarView` popover (`.menuBarExtraStyle(.window)`).
- **`Settings`** — Preferences panel (`SettingsView`) for managing export destinations and AI configuration (Cmd+,).

`AppDelegate` prevents app termination when the main window closes (`applicationShouldTerminateAfterLastWindowClosed → false`) and handles Dock icon reopen.

### MCP layer (PastureKit/MCP/)

Ten files under `Sources/PastureKit/MCP/`. All logic is pure Swift, `Sendable`, no I/O of its own — the executable only wires transport.

- **`MCPMessage.swift`** — JSON-RPC 2.0 types: `JSONRPCID` (`string` | `number`; distinct from absent), `JSONValue` (`Codable`/`Sendable` generic JSON tree replacing `[String: Any]`), `JSONRPCRequest` (with `IDPresence` enum distinguishing absent vs. explicit-null vs. value), `JSONRPCResponse<R>`, `JSONRPCErrorResponse` (forces `id: null` as explicit key per spec). Extension `Encodable.mcpLine()` produces a single-line JSON string with `.sortedKeys` + `.withoutEscapingSlashes` (ADR-MCP-006; the latter is required — without it, `/` is escaped as `\/`, breaking framing).
- **`MCPProtocol.swift`** — Protocol constants (`MCPProtocol.version = "2025-06-18"`, server name/version, JSON-RPC error codes), `InitializeResult` (echoes `protocolVersion`, `capabilities.tools`, `serverInfo`; `capabilities.tools` is always present even if empty — MCP spec gotcha), `EmptyResult` (for `ping`), `ToolCallResult` (tool-level result: `content`, `isError`, optional `warning`; distinct from JSON-RPC `error` object).
- **`MCPDispatcher.swift`** — `struct MCPDispatcher: Sendable`. The testable boundary: `handle(line: String) -> String?`. Returns `nil` for notifications (absent `id`) and empty lines; returns an error line for explicit-null `id` (-32600) or malformed JSON (-32700); dispatches `initialize`, `ping`, `tools/list`, `tools/call` to their handlers. Never throws — all failures become error lines (SEC-M12: an invalid request never drops the connection).
- **`MCPTools.swift`** — `enum MCPTools`. Tool catalog (`tools/list`) and execution (`tools/call`). Four read-only tools: `list_files`, `read_file`, `search`, `feed_context`. Reuses `FileLibrary`, `PathValidator`, `ContextBuilder`, `SecretScanner`, and `MDFile.matches` from the rest of PastureKit. Contains `VaultFile` and `FeedSelection` helper structs, `enumerateVaultFiles` (root + one-level subdirectories via `FileLibrary`, symlinks filtered), and `secretWarning`/`combinedWarning` helpers for SEC-M8.
- **`MCPPathResolver.swift`** — `enum MCPPathResolver`. Two-layer path validation for tool arguments: layer 1 uses `PathValidator.isInside` (resolves `..`), layer 2 calls `resolvingSymlinksInPath()` and re-validates the resolved destination (SEC-M2 — `PathValidator` alone cannot catch a symlink pointing outside the vault). Rejects absolute paths outright. Returns `Result<URL, ResolveError>`.
- **`MCPLimits.swift`** — `enum MCPLimits`. Central security caps: `maxInputLineBytes` (10 MB — SEC-M3), `maxSearchResults` (100 — SEC-M4), `maxQueryLength` (1,000 chars — SEC-M4), `maxResponseBytes` (25 MB — SEC-M5). All constants are public and tested individually.
- **`MCPLineReader.swift`** — `final class MCPLineReader`. Reads lines from a `FileHandle` with a hard cap of `maxLineBytes` per line (SEC-M3). A naive `readLine()` would buffer an unlimited line into RAM; this reader discards lines over the cap (emitting `.oversized`) and recovers at the next `\n` without accumulating. Strips `\r` from CRLF input. Tested via `Pipe` without launching a process.
- **`MCPServerConfig.swift`** — `struct MCPServerConfig: Sendable`. Holds `vaultRoot` (URL) and `feedFormat` (FeedFormat). `fromEnvironment()` builds the live config: vault fixed to `~/.pasture/`, format from `PASTURE_FEED_FORMAT` env var (ADR-MCP-007 — the MCP process does NOT share `UserDefaults.standard` with the GUI app; reading `FeedFormatSettings` from here would always return the default).
- **`MCPConfigGenerator.swift`** — `enum MCPConfigGenerator`. Produces the two registration snippets shown in Settings → MCP: `claudeCodeCommand(binaryPath:feedFormat:)` (a `claude mcp add` shell command) and `claudeDesktopJSON(binaryPath:feedFormat:)` (a JSON block for `claude_desktop_config.json`). Both inject `PASTURE_FEED_FORMAT` so the MCP server uses the same feed format as the app. Built with `JSONEncoder`, not string concatenation, to handle paths with special characters.
- **`MCPVaultStats.swift`** — `enum MCPVaultStats`. `secretStats(vaultRoot:)` scans the entire vault via `MCPTools.enumerateVaultFiles` + `SecretScanner` and returns `SecretStats` (count of files with secrets, summary lines). Powers the "Scan vault for secrets" button in Settings → MCP (SEC-M9: consent-first, on demand only).

### Key files

- **`ContentView.swift`** — UI orchestration: navigation split view, detail panel with `DetailMode` toggle (preview/ask), toolbar, all sheets (paste/merge/template, save preset, rename preset, delete preset confirmation, overwrite-preset confirmation). Delegates subviews to `EditorStatusBar`, `PastureEmptyState`, `FeedbackToast`, `SidebarView`, `FeedButton`, and `FeedService`. Subscribes to `SelectionPresetStore.didChangeNotification` to reload preset state.
- **`ContentTypes.swift`** — Standalone types used by ContentView: `FileSortOrder` enum, `DetailMode` enum, `FileTransfer` (Transferable for drag & drop).
- **`EditorStatusBar.swift`** — Status bar below the Markdown preview: file name, collection badge, template badge, "Open in Editor" button, token count.
- **`PastureEmptyState.swift`** — Empty state view (no file selected) and `FeedbackToast` (material capsule toast for transient messages).
- **`FeedService.swift`** — `@MainActor final class` shared between `ContentView` and `MenuBarView`. Encapsulates feed execution (template variable detection, clipboard copy with 60s auto-clear, file export), pre-feed secret scanning (`guardSecrets` runs `SecretScanner` off the main actor; presents warning dialog with default Cancel; "Continue anyway" proceeds with the original content), toast feedback, and template confirmation. Eliminates feed logic duplication between main window and menu bar. Non-reentrant: a second feed is blocked if a secret-warning dialog is already pending resolution.
- **`AskView.swift`** — Ask panel: context bar (file count, tokens, model, cost), response area with Markdown rendering, input bar (TextEditor + Ask/Stop button), action bar (Copy, Save, Export .md). Includes `PulseModifier` for streaming animation.
- **`AskViewModel.swift`** — `@MainActor final class` managing Ask state: question, responseText, isStreaming, error, provider/model selection. Coordinates `AIClient.ask()` via cancellable `streamTask`. Methods: `send()`, `stop()`, `clear()`, `copyResponse()`, `saveResponse()`, `reloadSettings()`.
- **`MarkdownPreviewView.swift`** — Read-only Markdown preview using `AttributedString(markdown:, options: .init(interpretedSyntax: .full))`. Renders asynchronously via `.task(id:)` to avoid flashing the previous file's content when switching files. Text selection enabled. Falls back to plain text if parsing fails.
- **`SidebarView.swift`** — Search bar, sort toggle (date/name), file list with collection sections, context menus (rename/move/delete for files; rename/delete for collections, deletion confirmed via alert), selection summary with token count and `ContextLimit` indicator (binary warning when total tokens exceed the configured model's context window).
- **`FeedAction.swift`** — `FeedButton` (renders as plain button when no export destinations configured, or as `Menu` with `primaryAction` when destinations exist — click = default action, hold = menu with clipboard + export options) and `TemplateSheet` (variable input before feeding, adapts UI for `.scalar` vs `.list` variables).
- **`MDFileManager.swift`** — Core file manager: state (`files`, `collections`, `searchQuery`, `filteredFiles`, `lastError`), async library reload via `FileLibrary.load(at:)`, CRUD (save, create, rename, delete), collection management (create/rename/move/delete), feed context delegation to `ContextBuilder`, file export. Owns a `DirectoryWatcher`. Path traversal via `isInsidePasture()` delegates to `PathValidator`. `MDFile` convenience extension for `collection` property using `pastureDir`.
- **`MDFileManager+Import.swift`** — Extension: `importFile` (conversion via `DocumentImporter` in PastureKit; `.md` and unknown types copied as-is), `merge()`, and `scanFolder()` for recursive .md import (max 500 files).
- **`DirectoryWatcher.swift`** — `@MainActor` class encapsulating all DispatchSource file-watching: root + per-collection sub-watchers, GCD→main hop, 0.5s debounce into a single `onChange` callback. All `nonisolated(unsafe)` watcher state lives here.
- **`MenuBarView.swift`** — Compact popover: header with "open window" button, search, file list with checkboxes (`MenuBarFileRow`), footer with Feed button. Independent selection from main window. Feed logic delegated to `FeedService`.
- **`SettingsView.swift`** — `TabView` with three tabs: `ExportSettingsTab` (feed format picker via `FeedFormatSettings`, export destination management via NSSavePanel, export file format picker via `ExportSettings`), `AISettingsTab` (provider picker, API key SecureField with Keychain save/delete, model picker with pricing, test connection button), and `MCPSettingsTab` (MCP server registration UI — see below). Posts `FeedFormatSettings.didChangeNotification`, `ExportSettings.didChangeNotification`, and `AISettings.didChangeNotification` on save.
- **`SettingsView.swift` / `MCPSettingsTab`** — Third tab in Settings (Cmd+,). Three sections: (1) description of the MCP capability, (2) vault secret check ("Scan vault for secrets" button, runs `MCPVaultStats.secretStats` off the main actor and displays masked summary — consent-first, SEC-M9), (3) registration snippets — "Copy configuration (Claude Code)" and "Copy configuration (Claude Desktop)" buttons, both disabled when the embedded binary is absent. Binary path derived from `Bundle.main.bundleURL` (never hardcoded). Injects the active `FeedFormat` into the generated snippets (ADR-007).
- **`DesignTokens.swift`** — Complete design system. All UI colors, typography, layout constants, and visual effects.
- **`PastureApp.swift`** — App entry point. Three scenes (Window, MenuBarExtra, Settings). Menu commands: "Open in Default Editor" (Cmd+E), "Paste from Clipboard" (Cmd+Shift+V), "Toggle Ask Mode" (Cmd+Shift+A). `@NSApplicationDelegateAdaptor` for `AppDelegate`.
- **`AppDelegate.swift`** — Prevents quit on last window close, handles Dock icon reopen. Enforces single-instance via `flock` on a lock file in `NSTemporaryDirectory()`: if the lock is already held, the new instance activates the running one and terminates itself.
- **`main.swift`** (`Sources/pasture-mcp/`) — MCP server entry point. Creates `MCPDispatcher(config: .fromEnvironment())` and `MCPLineReader(handle: .standardInput)`, then runs a synchronous sequential loop (ADR-MCP-005): read one line → dispatch → write response + `\n` to stdout. Logs to stderr only (SEC-M7: stdout is sacred — only framed JSON-RPC goes there). Oversized lines (SEC-M3) are logged and discarded. EOF exits cleanly.

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
- **`ContextBuilder`** — Static `build(files:format:) -> String` (`format` defaults to `.xml`). Takes `[FileEntry]` (name + content) and produces context output in the given `FeedFormat` (XML/Markdown/plain text). Handles CDATA escaping and multi-file wrapping. `MDFileManager.feedContext` delegates to this.
- **`DOCXConverter`** — `convert(url:)` reads .doc/.docx files via `NSAttributedString` and converts to Markdown. `convertAttributedString(_:)` for direct conversion. Detects headings (font size ratio), bold/italic (font traits), and links. Collapses consecutive empty lines.
- **`PathValidator`** — Static `isInside(target:base:) -> Bool`. Validates path containment using `standardizedFileURL.path` with trailing slash guard. `MDFileManager.isInsidePasture` delegates to this.
- **`MDFile`** — `Sendable` struct in PastureKit. Identifiable by URL, Hashable by URL, Equatable by URL. Two inits: memberwise (for testing) and I/O (`init(url:)` reads from disk). `collection(relativeTo:)` computes parent directory name relative to a base URL. `matches(query:)` is the single search predicate shared by the main window and the menu bar. `updateDerivedProperties()` recalculates `tokens` and `hasTemplateVars`. The Pasture app adds a convenience `collection` computed property via extension using `MDFileManager.pastureDir`.
- **`FileLibrary`** — Static filesystem queries: `load(at:)` (async, nonisolated — full library scan off the main actor, files sorted by date desc), `mdFiles(in:)`, `realSubdirectories(in:)`, `visibleContents(of:)` (skips hidden files; basis of the `.DS_Store` collection-deletion fix), `deduplicatedURL(baseName:ext:in:)`.
- **`DocumentImporter`** — Static `markdownContent(for:) -> String?`: PDF (PDFKit; throws `emptyPDF` for scanned PDFs without text instead of producing an empty file), CSV (UTF-8 → Latin-1 fallback), DOCX/DOC. Returns `nil` for non-convertible types (caller copies as-is). Pure conversion, no persistence.
- **`QuestionHistory`** — Static namespace persisting the last 10 Ask questions in UserDefaults (most recent first, trimmed, deduplicated). Surfaced as a clock menu in `AskView`'s input bar; recorded in `AskViewModel.send()`.
- **`FeedFormat`** — `Codable`, `CaseIterable`, `Sendable` enum with three cases: `.xml` (default — CDATA wrapping, byte-identical to v1.3 output), `.markdown` (CommonMark `##` heading + dynamic fence per file), `.plainText` (filename header + bare content, separator-only). Drives `ContextBuilder` output format. Orthogonal to `ExportFileFormat` (ADR-QW-005): the two settings are independent.
- **`FeedFormatSettings`** — Static namespace for UserDefaults persistence of the active `FeedFormat`. Same pattern as `ExportSettings`/`AISettings`: `feedFormat(from:)`, `setFeedFormat(_:in:)`, `didChangeNotification`. Default: `.xml`.
- **`SecretScanner`** — Stateless `nonisolated` enum. Detects credentials in feed content before delivery. Six `SecretKind` families: `anthropicKey` (`sk-ant-…`), `openAIKey` (generic `sk-…`, evaluated after Anthropic to avoid misclassification), `githubToken` (`ghp_`/`gho_`/`ghu_`/`ghs_`), `awsAccessKey` (`AKIA…`), `pemPrivateKey` (`-----BEGIN … PRIVATE KEY-----`), `slackToken` (`xox[baprs]-…`). Patterns are precompiled once at startup (no nested quantifiers — no catastrophic backtracking). Cap: 2 MB per file, cut at a valid UTF-8 character boundary. `SecretMatch` carries `maskedSnippet` (first 7 + `…` + last 4 chars) — never the full secret value. `SecretScanResult` provides `grouped()` and `summaryLines()` for the warning dialog.
- **`ContextLimit`** — Pure `nonisolated` enum. `state(totalTokens:contextWindow:)` returns a `State` with `exceeds: Bool` and the denominator for display. Binary rule (ADR-QW-004): fires only when tokens strictly exceed the window; no model configured → never exceeds (no regression on v1.3 behaviour).
- **`SelectionPreset`** — `Codable`, `Sendable`, `Hashable`, `Identifiable` struct. Fields: `id` (UUID), `name` (max 80 chars, control characters stripped by `sanitizedName(_:)`), `relativePaths` ([String] relative to `~/.pasture/`), `createdAt`. Never stores file content, absolute URLs, or API keys (ADR-QW-003). `missingFilesMessage(missingPaths:)` produces the actionable toast string.
- **`SelectionPresetStore`** — Static namespace for UserDefaults CRUD of `[SelectionPreset]`. Methods: `load`, `save`, `upsert`, `delete`, `rename`, `preset(named:)` (case-insensitive, for overwrite confirmation). Cap: 100 presets. Fires `didChangeNotification` on every mutation.
- **`PresetResolver`** — Static `nonisolated` enum. `resolve(relativePaths:base:)` converts relative paths to absolute URLs, silently discarding any that fail `PathValidator.isInside` (path-traversal guard, SEC-9). `missingPaths(relativePaths:base:existing:)` returns the subset not present on disk (or rejected by traversal check), for the actionable toast. `relativePath(for:base:)` converts a URL back to a relative path when saving a new preset from the current selection.

### Patterns to know

**Menu → View communication**: `PastureApp` posts `.openInEditor`, `.pasteFromClipboard`, and `.toggleAskMode` notifications. `ContentView` subscribes via `.onReceive`.

**Settings → Views communication**: `SettingsView` posts `ExportSettings.didChangeNotification` and `AISettings.didChangeNotification`. `ContentView`, `MenuBarView`, and `AskView` subscribe to reload state.

**Color scheme adaptation**: Static functions `Color.pastureX(_ scheme: ColorScheme)` resolve light/dark variants (including `pastureAccent(_:)`, `pastureError(_:)`, `pastureSuccess(_:)`, `pastureTokenBadgeText(_:)`). Never hardcode colors directly. All text/background token pairs meet WCAG AA contrast (≥4.5:1) in both schemes — keep that invariant when adding or changing tokens. Text over the brand gradient uses `pastureTextPrimaryLight` (dark), not white. `pastureSuccess` is used for positive feedback in the AI tab (key-saved checkmark) and the MCP tab (clean vault scan result).

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

**Pre-feed secret scanning**: `FeedService.guardSecrets(inputs:onProceed:)` runs `SecretScanner.scan` off the main actor via `Task.detached`. Clean result → `onProceed()` fires immediately (zero friction). Matches found → `pendingSecretResult` is set, which triggers the warning sheet in the presenting view. "Continue anyway" calls `proceedDespiteSecrets()`; Cancel/Escape calls `cancelSecretDialog()`. The scan targets rendered content (post-template substitution) so a secret injected via a template variable is still caught (ADR-QW-002). Non-reentrant: a second feed while a dialog is pending is blocked with a toast.

**FeedFormat vs ExportFileFormat**: these are orthogonal settings (ADR-QW-005). `FeedFormat` (`.xml`/`.markdown`/`.plainText`) controls the payload structure produced by `ContextBuilder` — what the AI model receives. `ExportFileFormat` (`.markdown`/`.plainText`) controls the file extension suggested when writing to disk. Either can be combined freely.

**Selection presets**: `SelectionPreset` stores a name + list of paths relative to `~/.pasture/`. `SelectionPresetStore` persists them in UserDefaults (max 100). `PresetResolver.resolve` converts relative paths to absolute URLs at apply time, validating each against `PathValidator.isInside` (SEC-9). Missing files (deleted since the preset was saved) surface as an actionable toast via `SelectionPreset.missingFilesMessage`. `ContentView` and `MenuBarView` both subscribe to `SelectionPresetStore.didChangeNotification`.

**FeedFormatSettings → Views communication**: `SettingsView` posts `FeedFormatSettings.didChangeNotification`. `FeedService` and `ContextBuilder` consumers reload via `FeedFormatSettings.feedFormat()` at call time (not cached).

**MCP dispatcher boundary**: `MCPDispatcher.handle(line:)` is the sole testable entry point for the MCP server. It accepts a raw line string, returns a response line or `nil`, and never throws. All tests treat this as the boundary — no process spawning required. The `main.swift` executable is thin by design (ADR-MCP-004): it only handles transport (`FileHandle` I/O, the `MCPLineReader` loop) and delegates everything else to the dispatcher.

**MCP stdout is sacred**: the `pasture-mcp` process writes only framed JSON-RPC messages to stdout (one message per line, terminated by `\n`). Diagnostic output goes exclusively to stderr. Any `print()` or `Swift.print` to stdout from PastureKit code called via the MCP path would corrupt the framing. Logs use `FileHandle.standardError.write` directly (SEC-M7).

**MCP configuration via environment (ADR-MCP-007)**: `pasture-mcp` reads its configuration from `ProcessInfo.processInfo.environment`, not from `UserDefaults.standard`. A CLI process launched by an MCP client does not share the app's UserDefaults domain, so `FeedFormatSettings.feedFormat()` would always return the default there. The feed format is instead controlled by the `PASTURE_FEED_FORMAT` environment variable (`xml`/`markdown`/`plainText`), which the registration snippets inject automatically. `MCPServerConfig.fromEnvironment()` is the canonical factory.

**MCP tool errors vs. protocol errors**: a tool failure (file not found, path outside vault, oversized response) sets `ToolCallResult.isError = true` inside the JSON-RPC `result` object — the AI model sees and can recover from it. A protocol failure (malformed JSON, unknown method, explicit-null id) produces a JSON-RPC `error` object at the top level. These two error channels are distinct and must not be confused (SEC-M12).

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
- `SecretScanner` never logs or displays the raw matched value. `SecretMatch.maskedSnippet` exposes only the first 7 and last 4 characters; for short matches only the first character is shown. The full credential value is discarded immediately after masking.
- Secret scan input is capped at 2 MB per file. Truncation occurs at a valid UTF-8 scalar boundary (no `U+FFFD` from a split multibyte character). Content beyond the cap is not scanned and not silently passed — the dialog default is Cancel, so the user must explicitly choose to proceed.
- Preset relative paths are validated via `PathValidator.isInside` in `PresetResolver.resolve` before any file selection is applied. A stored path containing `../` is silently rejected and counted as missing — it never selects a file outside `~/.pasture/`.
- Feed output escaping is format-dependent: XML uses CDATA (`]]>` escaped); Markdown uses dynamic fence characters chosen to avoid collision with file content; plain text uses a bare header (no structural escaping needed).
- Secret scanning runs on rendered content (post-template substitution), not the raw template source, so a secret injected via a variable value is caught before delivery.
- MCP path validation uses two layers: `PathValidator.isInside` catches `..` traversal (layer 1, SEC-M1); `URL.resolvingSymlinksInPath()` + re-validation catches symlinks pointing outside the vault (layer 2, SEC-M2). Both layers must pass before any file I/O occurs in a tool.
- The MCP server carries zero external dependencies — `pasture-mcp` depends only on PastureKit and Foundation; there is no `.package` in `Package.swift` to audit for CVEs (SEC-M10).
- MCP input lines are capped at 10 MB by `MCPLineReader` before being handed to the dispatcher. Lines exceeding the cap are discarded and logged to stderr; they never reach the JSON decoder (SEC-M3).
- MCP search caps query length at 1,000 characters and result count at 100 files. An empty query returns an explicit empty-result message rather than dumping the entire vault (SEC-M4).
- MCP responses for `read_file` and `feed_context` are capped at 25 MB. Content exceeding the cap returns `isError: true` without serializing the giant payload (SEC-M5).
- The MCP server is strictly read-only. There are no tools that create, modify, or delete files. The `pasture-mcp` executable has no write path to `~/.pasture/` (SEC-M11 by design). (Context assembly going exclusively through `ContextBuilder` — not `TemplateEngine.render` — is the separate SEC-M6 invariant.)
- MCP secret warnings (`ToolCallResult.warning`) carry only the family name and file name, never the matched value. Content is delivered unchanged — the warning is informational, not a gate (SEC-M8, D4).

### Concurrency model

`MDFileManager` is `@MainActor`. Directory watching is encapsulated in `DirectoryWatcher` (`@MainActor`): a module-level free function `makeWatchSource(fd:onEvent:)` keeps GCD closures out of actor isolation; events hop to the main queue via `DispatchQueue.main.async` + `MainActor.assumeIsolated` and are debounced (0.5s) into a single `onChange` callback. `nonisolated(unsafe)` marks the GCD-managed watcher state, confined to that one type. Library scans (`FileLibrary.load`) are nonisolated async — they run on the global executor, keeping disk I/O off the main thread.

`AIClient` is an `actor` (Swift 6 safe). `AskViewModel` is `@MainActor`. The streaming bridge uses `AsyncThrowingStream` returned from the actor method and consumed on MainActor via a cancellable `streamTask: Task<Void, Never>?`.

## Bundle ID & versioning

Bundle ID: `com.sevecod.pasture`. Current version: **1.5.1**. Version is hardcoded in `scripts/bundle.sh` (not derived from git tags). When releasing: update the `VERSION` variable there and add an entry to `CHANGELOG.md` (Keep a Changelog format, SemVer).
