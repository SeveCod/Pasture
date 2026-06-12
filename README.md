# Pasture — Feed your AI

A native macOS app for managing Markdown context files and querying AI models directly. Manages `.md` files in `~/.pasture/`, wraps them as XML context for AI assistants, and includes a built-in Ask mode for sending questions to Anthropic or OpenRouter APIs with streaming responses.

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode 16+) — the package builds with strict concurrency

## Run

```bash
swift run
```

Or open in Xcode:

```bash
open Package.swift
```

## What it does

### Library (sidebar)
- Lists all `.md` files in `~/.pasture/` with name and modification date
- Collections: organize files in subdirectories inside `~/.pasture/`
- Multi-select with `Cmd+click`
- Sort by date (default) or name
- Rename files and collections from the context menu
- Drag & drop `.md` or `.pdf` files from Finder to import them
- Search bar filtering by file name and content

### Preview (right panel)
- Read-only Markdown preview of the selected file
- Text selection enabled
- "Open in Editor" button delegates editing to the system default app
- Pasture watches the filesystem and reflects external changes automatically

### Ask mode (right panel)
Toggle with `Cmd+Shift+A` or the toolbar button. Select files, type a question, and receive a streaming response from Anthropic or OpenRouter.

- Context bar: file count, context window usage (`~Xk / Yk tokens`, colored by occupancy), model name, cost estimate
- Streaming responses with Markdown rendering
- Question history: the last 10 questions are available from the clock menu next to the input
- Action bar: Copy, Save to Pasture, Export as `.md`
- Configure provider, model, and API key in Settings → AI
- The selected files' content is sent to the configured provider (Anthropic or OpenRouter); a one-time notice is shown before the first request
- Context limit indicator: the selection summary warns when the token count exceeds the configured model's context window

### Selection presets
Save and restore named file selections from the toolbar (main window) or the menu bar popover. A preset records the current selection as relative paths, so it stays valid after moving the library directory. If a file referenced by a preset has been deleted, a toast names the missing file(s) and the rest of the selection is applied.

### Feed — toolbar leaf button
Copies the active (or selected) file(s) to the clipboard wrapped for Claude. Before copying, Pasture scans the content for credentials (Anthropic keys, GitHub tokens, AWS keys, PEM keys, OpenAI-style keys, Slack tokens); if any are found a warning dialog lists the affected files with masked snippets and defaults to Cancel.

Single file:

```xml
<context name="filename.md">
...content...
</context>
```

Multiple files:

```xml
<documents>
  <context name="file1.md">...content...</context>
  <context name="file2.md">...content...</context>
</documents>
```

If a file contains template variables, Pasture prompts for their values before copying.

The default output format is XML/CDATA. You can switch to Markdown fences or plain text in Preferences → Export → Feed Output Format.

### MCP server

Pasture ships an embedded [Model Context Protocol](https://modelcontextprotocol.io/) server (`pasture-mcp`). Register it once and your MCP client can read `~/.pasture/` directly — no copy-paste required.

**Four read-only tools:**

| Tool | What it does |
|---|---|
| `list_files` | List all Markdown files and collections in the vault |
| `read_file` | Return the raw content of a single file by relative path |
| `search` | Find files whose name or content contains a literal query (case-insensitive) |
| `feed_context` | Assemble vault context in Pasture's Feed format, from a collection or a list of files |

**Register with Claude Code** — go to Settings → MCP, click "Copy configuration (Claude Code)", paste in your terminal:

```bash
claude mcp add pasture --env PASTURE_FEED_FORMAT=xml -- /Applications/Pasture.app/Contents/MacOS/pasture-mcp
```

**Register with Claude Desktop** — go to Settings → MCP, click "Copy configuration (Claude Desktop)", paste inside the `mcpServers` key in `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "pasture": {
      "command": "/Applications/Pasture.app/Contents/MacOS/pasture-mcp",
      "env": { "PASTURE_FEED_FORMAT": "xml" }
    }
  }
}
```

The `PASTURE_FEED_FORMAT` value matches your current Feed Output Format setting (`xml` / `markdown` / `plainText`). The registration snippets in Settings inject the correct value automatically.

Before registering, use the "Scan vault for secrets" button to check whether `~/.pasture/` contains credential patterns. The MCP channel delivers file contents unchanged — `~/.pasture/` is meant for shareable context, not secrets.

For full tool reference see [`docs/mcp-server.md`](docs/mcp-server.md).

### Scan Folder
Toolbar button. Recursively scans a directory for `.md` files and imports them into a new collection.

### Export
Toolbar button. Saves the feed context as `.md` to any location via save dialog.

### Import PDF / CSV / DOCX
Toolbar button or drag & drop. PDFs: text extracted via PDFKit (native, zero dependencies); scanned PDFs without OCR layer return empty text. CSV: converted to a Markdown table. DOCX/DOC: converted via `NSAttributedString` with heading/bold/italic/link detection.

## Template syntax

Any `.md` file can declare variables using double-brace syntax. When you hit Feed, Pasture collects all variables, prompts for their values, substitutes them, and copies the result. The editor always shows the raw template — substitution happens only at Feed time.

```
{{VARIABLE}}              — declares a variable, prompted before Feed
{{VAR=default}}           — declares a variable with a default value
{{#if VAR}}...{{/if}}     — conditional block
{{#unless VAR}}...{{/unless}} — inverse conditional
{{#each ITEMS}}...{{/each}}   — loop over comma-separated list
```

## Token estimation

The token counter is a heuristic (~4 chars/token). Not the actual tokenizer — accurate enough for rough sizing.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+Shift+A` | Toggle Ask mode |
| `Cmd+Shift+V` | Create new file from clipboard |
| `Cmd+E` | Open file in default editor |
| `Cmd+,` | Settings (Export destinations, AI config) |
| Drag & drop | Import `.md` or `.pdf` files |

## Structure

```
Sources/
├── PastureKit/                — Testable library (pure logic, no UI)
│   ├── TemplateEngine.swift   — Template parser and renderer
│   ├── TokenEstimator.swift   — Heuristic token counter + cost estimation
│   ├── FilenameSanitizer.swift
│   ├── StringExtensions.swift — xmlEscapedAttribute
│   ├── ContextBuilder.swift   — XML context tag generation for feed output
│   ├── MDFile.swift           — File value type (Identifiable by URL)
│   ├── FileLibrary.swift      — Filesystem queries (async scan, dedup, filtering)
│   ├── DocumentImporter.swift — PDF/CSV/DOCX → Markdown conversion
│   ├── PathValidator.swift    — Path containment check (security)
│   ├── DOCXConverter.swift    — DOCX/DOC → Markdown
│   ├── CSVConverter.swift     — CSV → Markdown table
│   ├── ExportDestination.swift
│   ├── ExportSettings.swift
│   ├── AIProvider.swift       — AIProviderKind enum, AIModel catalog
│   ├── AISettings.swift       — AI config persistence (UserDefaults + Keychain)
│   ├── QuestionHistory.swift  — Recent Ask questions (UserDefaults)
│   ├── AIClient.swift         — Streaming AI client actor (Anthropic/OpenRouter)
│   ├── KeychainStore.swift    — macOS Keychain wrapper
│   ├── SSEParser.swift        — Server-Sent Events parser
│   ├── FeedFormat.swift       — Feed payload format enum (XML/Markdown/plain text)
│   ├── FeedFormatSettings.swift — Feed format persistence (UserDefaults)
│   ├── SecretScanner.swift    — Pre-feed credential detector (6 families)
│   ├── ContextLimit.swift     — Context window guard logic (sidebar indicator)
│   ├── SelectionPreset.swift  — Named file selections (relative-path model)
│   ├── SelectionPresetStore.swift — Preset CRUD (UserDefaults)
│   ├── PresetResolver.swift   — Relative-path → URL resolution (path-traversal guard)
│   └── MCP/                   — MCP server protocol layer (testable, no I/O)
│       ├── MCPMessage.swift   — JSON-RPC 2.0 types (JSONRPCID, JSONValue, requests, responses)
│       ├── MCPProtocol.swift  — Protocol constants, InitializeResult, ToolCallResult
│       ├── MCPDispatcher.swift— handle(line:) → response line or nil
│       ├── MCPTools.swift     — Four read-only tools: list_files, read_file, search, feed_context
│       ├── MCPPathResolver.swift — Two-layer path validation (../  + symlink resolution)
│       ├── MCPLimits.swift    — Security caps (line size, query length, results, response size)
│       ├── MCPLineReader.swift— Bounded stdin reader (cap per line, CRLF stripping)
│       ├── MCPServerConfig.swift — Config from environment (vault root, feed format)
│       ├── MCPConfigGenerator.swift — Registration snippet generator (Claude Code + Desktop)
│       └── MCPVaultStats.swift — On-demand vault secret scan for consent UI
├── Pasture/                   — SwiftUI app (executable)
│   ├── PastureApp.swift       — App entry, scenes, menu commands
│   ├── ContentView.swift      — Navigation, preview/ask toggle, toolbar
│   ├── ContentTypes.swift     — FileSortOrder, DetailMode, FileTransfer
│   ├── FeedService.swift      — Shared feed logic (clipboard, export, templates)
│   ├── AskView.swift          — Ask panel UI
│   ├── AskViewModel.swift     — Ask state management
│   ├── SidebarView.swift      — File list with collections
│   ├── FileRow.swift          — Sidebar file row
│   ├── MenuBarFileRow.swift   — Menu bar popover file row
│   ├── FeedAction.swift       — Feed button and template sheet
│   ├── TemplateBadge.swift    — Template indicator badge
│   ├── NameInputSheet.swift   — Name prompt sheet (new file/collection/merge)
│   ├── EditorStatusBar.swift  — Status bar below the preview
│   ├── PastureEmptyState.swift— Empty state + feedback toast
│   ├── MarkdownPreviewView.swift
│   ├── MenuBarView.swift      — Menu bar popover
│   ├── MDFileManager.swift    — File CRUD and library state
│   ├── MDFileManager+Import.swift — Import persistence, merge, scan folder
│   ├── DirectoryWatcher.swift — DispatchSource file watching (debounced)
│   ├── SettingsView.swift     — Export, AI, and MCP settings tabs
│   ├── DesignTokens.swift     — Design system
│   └── AppDelegate.swift
├── pasture-mcp/               — MCP server executable
│   └── main.swift             — Thin transport loop (stdin → MCPLineReader → MCPDispatcher → stdout)
└── Tests/PastureKitTests/     — 491 tests (Swift Testing framework)
```

No CoreData, no SwiftData, no external dependencies.

## Release

**Current version: 1.5.0** (2026-06-12)

See [CHANGELOG.md](CHANGELOG.md) for the full history of changes.
