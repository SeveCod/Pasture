# Changelog

All notable changes to Pasture are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Pasture uses [Semantic Versioning](https://semver.org/).

## [1.8.0] - 2026-07-06

### Added

- **Memory Inbox** — the MCP server can now *propose* vault edits, closing the vault→AI→vault loop without giving an agent write access to your notes. With `PASTURE_ALLOW_PROPOSALS=1`, two new tools appear: `propose_note` (a new note) and `propose_append` (add to an existing file). Neither touches the visible vault: each queues a proposal in a hidden `~/.pasture/.inbox/`. You review each proposal from the GUI — with a mandatory diff for appends and full provenance (which client proposed it, when) — and only then does it land in the vault. There is no bulk "approve all". Rejecting discards it. Promoted notes carry permanent provenance frontmatter (`origin: agent`).
- **Settings → MCP** gains a toggle, *"Allow write proposals (require your approval)"*; enabling it injects the env var into the copied registration snippets. A sidebar **"Inbox (N)"** badge opens the review queue when proposals are pending.

### Security

- **SEC-M11 redefined**: the MCP server still has no write-path to the *visible* vault and defaults to strictly read-only (without the env var, `tools/list` is byte-identical to v1.7). Proposals write exclusively to the hidden `.inbox/`, which stays outside `FileLibrary`, the feed and the read tools. Promotion to the vault is a human-only GUI action. Proposal payloads are capped at 1 MB (SEC-M14), the inbox at 50 pending (SEC-M15), with a 14-day TTL; destinations pass the same two-layer path validation as reads; filenames are sanitized; secrets are scanned and surfaced (masked) without blocking; duplicates are rejected. Stored prompt-injection is a documented residual risk, mitigated by permanent provenance + mandatory diff.
- **Adversarial-review hardening** (pre-merge): `MCPPathResolver` now rejects any hidden path component (`.`-prefixed), so `.inbox/` is neither readable by path nor a valid proposal destination; provenance-frontmatter values are collapsed to a single line and `clientInfo.name` is sanitized on ingest (no frontmatter injection via a hostile client name); reserved frontmatter keys are stripped from a proposal payload on promotion (no freshness/source spoofing); `ProposalStore.delete` removes the metadata before the payload (no phantom proposal after a mid-delete crash).

### Changed

- MCP server version → 1.8.0. `MCPDispatcher` is now a `final class` (captures `clientInfo` for provenance). Test count: 632 → 690 (new `Proposal`, `ProposalStore`, `ProposalPromoter`, proposal-tool, config, dispatcher-provenance, limits, path-resolver and injection-hardening suites).

## [1.7.0] - 2026-07-05

### Added

- **Ask is now a multi-turn conversation** (Fase 1 of "Ask de verdad"). The Ask panel keeps the full transcript instead of a single answer: each question and answer is shown as its own turn, and follow-ups carry the whole history. The file context is embedded into the first user message only and re-sent on every turn (a request is stateless); it never appears more than once in the payload. Before each send the transcript is trimmed by the pure `ConversationTruncator` to fit `floor(0.95 × contextWindow) − maxOutputTokens`, dropping the oldest middle turns but **never** the file context (first message) or the current question (last message). A turn stopped mid-stream — or one whose stream ended before the provider's end event — is kept as an **incomplete answer** (flagged in the UI and when saved) so it still travels back as history.
- **"Save as context"**: the action bar distills the whole conversation into a new Markdown note in the vault (`## Question` / `## Answer` sections, incomplete answers flagged) — the vault→chat→vault flywheel. Copy and Export .md now act on the full conversation.
- New pure, testable PastureKit types: `ChatMessage` (role/content/`isComplete`), `AskConversation` (the transcript state machine), `ConversationTruncator`, and `ConversationComposer` (`wire` embeds context into the first user message; `distill` renders the transcript to Markdown). `AIClient.ask(messages:)`/`buildRequest(messages:)` send a full transcript; the previous single-turn `ask(question:context:)` is kept as a thin wrapper for the Settings "test connection" path.

### Changed

- Test count: 607 → 632 (new `ConversationTruncatorTests`, `ConversationComposerWireTests`, `ConversationDistillerTests`, `AskConversationTests`, and multi-turn cases in `AIClientTests`).

## [1.6.0] - 2026-07-05

### Added

- **Living context — declared freshness**: notes can now carry a YAML-lite frontmatter block (`---` … `---`) with `review_after` (ISO date), `ttl` (e.g. `90d`), and `last_reviewed`. `FrontmatterParser` (hand-rolled, no YAML dependency, tolerant of malformed input, capped at 8 KB/64 lines) and the pure `Freshness` enum (clock injected, same pattern as `ContextLimit`) decide whether a note is fresh or expired. `MDFile` gains a computed `frontmatter` and a `freshness(now:)` helper. In the sidebar, stale notes show a clock badge, and a **review queue** groups everything expired — "Mark reviewed" writes `last_reviewed: <today>` (via the pure `FrontmatterWriter`) so the badge clears. **The MCP `read_file` and `feed_context` responses annotate staleness** in the non-blocking `warning` channel (`"stale: N days since last review"` / a per-file list) so a consuming agent knows how much to trust the context — content is delivered unchanged and the server stays strictly read-only (writing `last_reviewed` lives only in the GUI). A note without any expiry declared is always fresh (no regression).
- **Living context — local re-importable sources** (Fase B): a note with `source: <local folder>` in its frontmatter re-imports that folder's `.md` files into the note's collection, each marked `generated: true`, on demand via "File → Refresh Sources" (Cmd+Shift+R). Non-destructive: a generated note edited by hand that still keeps `generated: true` is overwritten on refresh, but one where the user *removed* the flag (unlinked) — or any hand-authored file with the same name — is never touched (`SourceImportDecision`). Sources are validated (`SourceValidator`) to be existing local directories **outside** `~/.pasture/` (rejecting a file, a missing path, or a symlink resolving into the vault — anti-loop); v1 is local folders only, `.md` only, capped at 500 files, no network or command execution. Generated notes show a "Generated" mark in the editor status bar. The MCP server does not participate (writing stays GUI-only, SEC-M11).
- **Context Compiler (core)**: the vault can now be the single source of truth for a repo's `CLAUDE.md`/`AGENTS.md`. A *pack* = a selection preset + per-project variables + one or more target files in your repos. `PackSyncEngine.sync` resolves the preset (SEC-9 path validation), aborts if any source file is missing, assembles the selected files as Markdown, renders the pack variables single-pass, and writes each target with a `<!-- pasture-pack: … | sha256: … -->` header. The sync is unidirectional and non-destructive: a target edited by hand (its body hash no longer matches the header, or it has no Pasture header) is a **conflict** and is never overwritten without explicit confirmation; every overwrite first backs up the previous content to `Application Support` (max 10 per target, outside the repo and the vault). Compilation is idempotent (no timestamps in the body) so a no-op re-sync produces a byte-identical file. New PastureKit types: `CompilePack`/`CompileTarget`/`TargetKind`, `PackStore` (UserDefaults CRUD, cap 50 packs / 20 targets), `SyncMarker`, `PackEmitter`, `PackCompiler`, `TargetValidator`, `PackWriter`, `PackSyncEngine`. A **Packs tab** in Settings (Cmd+,) creates/edits packs (preset picker, variables editor, target files via `NSSavePanel` with immediate vault-containment validation, auto-resync toggle) and runs sync per pack — safe by default (never overwrites a hand-edited target or writes secrets), with an explicit "Force sync" confirmation (default Cancel) to escalate. **Sync all** is available from the "File → Sync All Packs" menu command (Cmd+Shift+P) and a menu-bar button; results show as a toast. Packs marked **auto-resync** recompile automatically when the vault changes (via the existing `DirectoryWatcher`), always with safe defaults — a conflicted or secret-bearing target is never overwritten unattended.
- **MCP `resources` primitive**: every `.md` in the vault is now exposed as a native MCP resource (`resources/list` + `resources/read`), addressable by `pasture:///<relative-path>` URIs with `mimeType: text/markdown`. Clients that support resources (e.g. Claude Desktop) can attach vault notes by @-mention instead of asking the model to call `read_file`. Read-only: enumeration goes through the same `FileLibrary` path that filters hidden files and symlinks, and every read passes both `MCPPathResolver` layers (`..` traversal + symlink resolution) before any I/O.
- **MCP `prompts` primitive**: every vault file that is a template (contains `{{VAR}}` or blocks) is exposed as a parameterized MCP prompt (`prompts/list` + `prompts/get`). In Claude Code these appear as slash-commands with typed arguments derived from `TemplateEngine.extractVariables` — required when the variable has no default, optional (with the default cited) otherwise, and `#each` variables documented as comma-separated lists. `prompts/get` renders single-pass (an argument value is never re-parsed as template syntax) and returns a single `user` message.
- **`initialize` now declares three capabilities** (`tools`, `resources`, `prompts`), each always present as `{}` per the MCP spec.
- `MCPLimits.maxPromptArgumentLength` (100 000 chars): per-argument cap on `prompts/get` values before rendering (SEC-M13).

### Changed

- `MCPProtocol.serverVersion`: `1.5.0` → `1.6.0`.
- Test count: 501 → 607 (MCP: `MCPResourcesTests`, `MCPPromptsTests`; Context Compiler: `SyncMarkerTests`, `PackCompilerTests`, `TargetValidatorTests`, `PackStoreTests`, `PackWriterTests`, `PackSyncEngineTests`; Living context: `FrontmatterParserTests`, `FreshnessTests`, `FrontmatterWriterTests`, `MCPStalenessTests`, `SourceImportTests`; extended `MCPProtocolTests`, `MCPEndToEndTests`, `MCPToolsTests`).

### Security

- **Context Compiler write-path**: the target is validated to be **outside** `~/.pasture/` before any write — a path inside the vault (direct, via `..`, or via a symlink, including a dangling one) is rejected (`TargetValidator`, double-layer + explicit symlink-destination resolution). The compiled body is scanned by `SecretScanner` post-render; a target with secrets is not written without explicit consent (the generated files are committed to potentially public repos). Packs persist only references (preset UUID, target paths, variables) — never file content, credentials, or keys. Writes are atomic; conflicts are never silently overwritten.
- **`resources/read`** inherits the 25 MB response cap with an on-disk size pre-check, so an oversized file is rejected without being materialized in RAM (SEC-M5). Only the `pasture://` URI scheme is accepted; absolute paths and foreign schemes (`file://`, `https://`) are rejected before any I/O (SEC-M1).
- **`prompts/get`** scans the *rendered* content with `SecretScanner` (post-substitution, ADR-QW-002); a detected secret surfaces as a masked summary in the result's `description` field (family + file, never the value — SEC-M8/D4) while the content is delivered unchanged.
- The server remains strictly read-only (SEC-M11): all four new routes render or read in memory, with no write path to `~/.pasture/`. Failures in `resources/read` and `prompts/get` are JSON-RPC protocol errors (`-32602`), distinct from the tool-level `isError` channel (SEC-M12).

## [1.5.1] - 2026-07-04

### Added

- **MIT LICENSE** file at the repository root, referenced from the README.
- **`docs/adr/`**: canonical Architecture Decision Record registry. Resolves a numbering collision where the v1.4 and v1.5 features had reused the same `ADR-00X` numbers for different decisions; the two series are now namespaced `ADR-QW-00X` (quick wins) and `ADR-MCP-00X` (MCP server).

### Changed

- `KeychainStore.delete` now returns a `@discardableResult Bool` (true if the key was removed or was already absent, false on a real Keychain failure).
- Test count: 491 → 501.

### Fixed

- **Export toolbar button bypassed pre-feed guards**: the "Export" button wrote feed context to disk without running the secret scan or substituting template variables — the only output path in the app that skipped both. It now routes through `FeedService` like every other feed (audit finding 2.1).
- **`TemplateEngine` leaked control syntax past the nesting cap**: templates deeper than `maxNestingDepth` (16) emitted orphan `{{/if}}` tokens into the output, even when the condition was false. The parser now flattens the over-deep block into balanced literal text (audit finding 2.5).
- **`TemplateEngine` variable kind depended on order**: a variable used as both `{{X}}` and `{{#each X}}` took its `.scalar`/`.list` kind from whichever appeared first. It is now `.list` if used in any `#each`, regardless of order.
- **`MCPLineReader` emitted a phantom empty line**: recovering from an oversized line when the recovery `\n` arrived in the same chunk as following data produced a spurious empty line the client never sent.
- **AIClient streamed responses ending without a terminator** (`message_stop` / `[DONE]`) were presented as complete; they now surface a `networkError` so a truncated response is not shown as finished.

### Security

- **`SecretScanner`** now detects modern token formats: OpenAI project keys (`sk-proj-`), GitHub fine-grained tokens (`github_pat_`), and AWS STS temporary keys (`ASIA…`).
- **`TemplateEngine`** gains a global output budget (`maxOutputCharacters`), bounding total render size against multiplicative amplification from nested `#each` blocks (per-level caps alone are multiplicative).
- **MCP `read_file` / `feed_context`** check a file's on-disk size before reading it, so a huge vault file is rejected without being materialized in RAM (audit finding 2.4, hardens SEC-M5).
- **AIClient** cancels the underlying `URLSessionDataTask` when a stream is stopped, closing the HTTP connection instead of leaving it (and its token billing) running until timeout.
- **`MDFileManager.setup`** now surfaces a failure to create `~/.pasture/` via `lastError` instead of failing silently into an empty-looking app.

## [1.5.0] - 2026-06-12

### Added

- **MCP server (`pasture-mcp`)**: Pasture now ships an embedded Model Context Protocol server. Register it once in Claude Code or Claude Desktop; the client can then read your vault without copy-paste. Four read-only tools: `list_files`, `read_file`, `search` (literal, case-insensitive), and `feed_context` (assemble a collection or a file list using Pasture's Feed format). JSON-RPC 2.0 over stdio, MCP spec `2025-06-18`.
- **Settings → MCP tab**: registration UI with step-by-step instructions. "Copy configuration (Claude Code)" generates a `claude mcp add` command; "Copy configuration (Claude Desktop)" generates the `mcpServers` JSON block for `claude_desktop_config.json`. Both snippets are disabled until the embedded binary exists in the app bundle.
- **Vault secret check in MCP tab** (consent-first): before registering the server, users can scan their vault for credential patterns. The scan reuses `SecretScanner` and reports affected files with masked snippets — the raw values are never shown. The check runs on demand, not on every settings open.
- **`PASTURE_FEED_FORMAT` environment variable**: controls the feed output format used by the MCP server (`xml` / `markdown` / `plainText`, default `xml`). Registration snippets inject the user's current setting automatically so the server matches the app.

### Changed

- SPM package gains a fourth target: `pasture-mcp` (executable). The MCP protocol layer (`MCPDispatcher`, `MCPTools`, `MCPMessage`, `MCPPathResolver`, `MCPLimits`, `MCPLineReader`, `MCPServerConfig`, `MCPConfigGenerator`, `MCPVaultStats`, `MCPProtocol`) lives in PastureKit for testability; the executable is a thin `main.swift` that wires transport only.
- Test count: 420 → 491 (71 new MCP tests in 7 suites: `MCPDispatcherTests`, `MCPToolsTests`, `MCPProtocolTests`, `MCPLineReaderTests`, `MCPConfigGeneratorTests`, `MCPVaultSecretStatTests`, `MCPEndToEndTests`). _(Corrected from an earlier "486" figure that predated the final MCPLineReader regression tests.)_
- `DesignTokens`: added `pastureSuccess(_:)` color token (used in Settings → AI key-saved indicator and Settings → MCP scan result).

### Security

- MCP path validation applies two layers: `PathValidator.isInside` blocks `../` traversal; `resolvingSymlinksInPath()` + re-validation blocks symlinks pointing outside `~/.pasture/` (SEC-M2).
- MCP input lines are capped at 10 MB by `MCPLineReader` before reaching the JSON decoder; lines over the cap are discarded and logged to stderr without touching the connection (SEC-M3).
- MCP search caps query length at 1,000 characters and results at 100 files; an empty query returns an explicit empty message rather than dumping the vault (SEC-M4).
- MCP responses are capped at 25 MB; content above the cap returns `isError: true` without serializing the payload (SEC-M5).
- The MCP server is strictly read-only — no tool modifies the filesystem (SEC-M11). (SEC-M6 is the separate invariant that context assembly goes exclusively through `ContextBuilder`.)
- `pasture-mcp` writes only framed JSON-RPC to stdout; all diagnostic output goes to stderr. No `print()` path to stdout exists in the MCP code path (SEC-M7).
- MCP secret warnings report family and file name only, never the matched value; file content is delivered unchanged — the warning is informational, not a gate (SEC-M8).
- The MCP Settings tab scans the vault for secrets before showing registration snippets, so users can make an informed consent decision (SEC-M9).

## [1.4.0] - 2026-06-12

### Added

- **Pre-feed secret scanner**: Pasture scans file content for credentials before copying to clipboard, exporting to file, or sending to Ask (including the question text). Six families detected: Anthropic keys, OpenAI-style keys, GitHub tokens, AWS access keys, PEM private keys, and Slack tokens. A warning dialog lists the affected files and masked snippets; the default action is Cancel. "Continue anyway" proceeds without redacting.
- **Selection presets**: save and restore named file selections from the toolbar and the menu bar popover. Presets store relative paths — they stay valid after renaming the library directory. Missing files (deleted since the preset was saved) surface as an actionable toast naming the first absent file and a count of the rest.
- **Context limit indicator in sidebar**: the selection summary shows a warning when the total token count exceeds the configured model's context window. The tooltip names the model.
- **Feed output format** (Preferences → Export → Feed Output Format): choose between XML/CDATA (default, byte-identical to previous output), Markdown (CommonMark heading + dynamic fence), and Plain text (filename header + bare content). The setting is orthogonal to the export file-format picker.

### Changed

- `SettingsView` Export tab now shows the Feed Output Format picker above the export-destinations list and the file-format picker.

### Security

- Secret scanning runs on rendered content (post-template substitution), so a credential injected via a template variable is detected before delivery.
- Matched secret values are never logged or displayed. `SecretMatch` carries only a masked snippet (first 7 + last 4 characters; shorter secrets show only the first character).
- Scan input capped at 2 MB per file, truncated at a valid UTF-8 character boundary.
- Preset relative paths validated via `PathValidator.isInside` at apply time; a path escaping `~/.pasture/` via `../` is silently rejected and reported as missing.

## [1.3.0] - 2026-06-12

### Added

- Export file format setting (Markdown `.md` / Plain text `.txt`) in Preferences → Export. Default: `.md`.
- Context window usage indicator in Ask mode: the context bar shows `~Xk / Yk tokens` colored green/amber/red by occupancy of the model's context window.
- One-time privacy notice before the first Ask request, plus a persistent hint on the model badge, stating that selected file contents are sent to the configured provider (Anthropic/OpenRouter).
- Confirmation alert before deleting an empty collection (consistent with file deletion).
- Feedback toasts now distinguish errors (warning icon, red) from success (checkmark, green).
- Name input sheets (new file, merge, new collection) focus the text field automatically.
- Rename files and collections from the sidebar context menus (new `Rename…` items with pre-filled name sheet). Renaming keeps the active selection pointing at the renamed file.
- Question history in Ask mode: the last 10 questions are persisted and available from a clock menu next to the input field, including a "Clear Recent Questions" action (GDPR right to erasure).

### Changed

- **Accessibility**: design tokens reworked to meet WCAG AA contrast (≥4.5:1) in both color schemes — tertiary text, token badge text, accent, and error colors are now scheme-adaptive; Feed/Ask button text changed from white to dark over the brand gradient.

### Fixed

- Empty collections containing only hidden files (e.g. `.DS_Store` created by Finder) can now be deleted — emptiness is checked via `FileLibrary.visibleContents` (regression-tested).
- Importing a PDF without extractable text (scanned without OCR) now reports an error instead of silently creating an empty `.md` file.
- Selection reconciliation after external file changes no longer falls back to name matching, which could silently select the wrong file after an external rename.
- Export panels (toolbar Export and destination picker in Settings) no longer coerce the suggested `.md` filename to `.txt` — the save panel now declares the Markdown UTType first.

### Performance

- Library scans no longer block the UI: `loadFiles()` runs disk I/O off the main actor via the new `FileLibrary.load(at:)` (async); a new reload cancels the in-flight one.
- Search results are cached (`filteredFiles` recomputed only when files or the query change, not on every SwiftUI render).

### Internal

- `ExportFileFormat` enum in PastureKit with persistence via `ExportSettings.fileFormat()`/`setFileFormat()`.
- New PastureKit components extracted from the UI target for testability: `FileLibrary` (filesystem queries) and `DocumentImporter` (PDF/CSV/DOCX conversion). 21 new tests (321 total).
- `DirectoryWatcher` extracted from `MDFileManager`: all DispatchSource watching state (`nonisolated(unsafe)`) now lives in one single-responsibility type; the internal NotificationCenter channel was removed.
- `MDFile.matches(query:)` — single search predicate shared by main window and menu bar (removes duplicated filter logic).
- `AIClient.shared` — Ask mode and the Settings connection test now use the same session configuration; the per-provider request builders were unified into one parameterized `buildRequest`.
- `AskView` toasts routed through the shared `FeedService` (removes duplicated toast state/timer).
- `MDFileManager.resolveTargetDirectory` reports directory-creation failures instead of silently swallowing them.
- `TokenEstimator.estimate`: `CharacterSet.alphanumerics` captured once per call instead of being rebuilt in the inner loop.
- `SidebarView.sortedFiles`: removed redundant re-sort in date mode (`fm.files` is already kept sorted by date).
- New adaptive color helpers: `pastureAccent(_:)`, `pastureError(_:)`, `pastureTokenBadgeText(_:)`.

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

[1.5.0]: https://github.com/SeveCod/Pasture/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/SeveCod/Pasture/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/SeveCod/Pasture/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/SeveCod/Pasture/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/SeveCod/Pasture/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/SeveCod/Pasture/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/SeveCod/Pasture/releases/tag/v1.0.0
