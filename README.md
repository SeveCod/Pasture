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

### Feed — toolbar leaf button
Copies the active (or selected) file(s) to the clipboard wrapped for Claude.

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
│   └── SSEParser.swift        — Server-Sent Events parser
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
│   ├── SettingsView.swift     — Export + AI settings tabs
│   ├── DesignTokens.swift     — Design system
│   └── AppDelegate.swift
└── Tests/PastureKitTests/     — 327 tests (Swift Testing framework)
```

No CoreData, no SwiftData, no external dependencies.

## Release

**Current version: 1.3.0** (2026-06-12)

See [CHANGELOG.md](CHANGELOG.md) for the full history of changes.
