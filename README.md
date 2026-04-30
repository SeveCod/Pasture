# Pasture — Feed your AI

A native macOS app for managing Markdown context files and querying AI models directly. Manages `.md` files in `~/.pasture/`, wraps them as XML context for AI assistants, and includes a built-in Ask mode for sending questions to Anthropic or OpenRouter APIs with streaming responses.

## Requirements

- macOS 14+
- Xcode 15+ or Swift 5.9+

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
- Drag & drop `.md` or `.pdf` files from Finder to import them
- Search bar filtering by file name and content

### Preview (right panel)
- Read-only Markdown preview of the selected file
- Text selection enabled
- "Open in Editor" button delegates editing to the system default app
- Pasture watches the filesystem and reflects external changes automatically

### Ask mode (right panel)
Toggle with `Cmd+Shift+A` or the toolbar button. Select files, type a question, and receive a streaming response from Anthropic or OpenRouter.

- Context bar: file count, token estimate, model name, cost estimate
- Streaming responses with Markdown rendering
- Action bar: Copy, Save to Pasture, Export as `.md`
- Configure provider, model, and API key in Settings → AI

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

### Import PDF
Toolbar button or drag & drop. Extracts text via PDFKit (native, zero dependencies) and saves as `.md`. Scanned PDFs without OCR layer return empty text.

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
│   ├── ExportDestination.swift
│   ├── ExportSettings.swift
│   ├── AIProvider.swift       — AIProviderKind enum, AIModel catalog
│   ├── AISettings.swift       — AI config persistence (UserDefaults + Keychain)
│   ├── AIClient.swift         — Streaming AI client actor (Anthropic/OpenRouter)
│   ├── KeychainStore.swift    — macOS Keychain wrapper
│   └── SSEParser.swift        — Server-Sent Events parser
├── Pasture/                   — SwiftUI app (executable)
│   ├── PastureApp.swift       — App entry, scenes, menu commands
│   ├── ContentView.swift      — Navigation, preview/ask toggle, toolbar
│   ├── FeedService.swift      — Shared feed logic (clipboard, export, templates)
│   ├── AskView.swift          — Ask panel UI
│   ├── AskViewModel.swift     — Ask state management
│   ├── SidebarView.swift      — File list with collections
│   ├── FeedAction.swift       — Feed button and template sheet
│   ├── MarkdownPreviewView.swift
│   ├── MenuBarView.swift      — Menu bar popover
│   ├── MDFileManager.swift    — File I/O and directory watching
│   ├── SettingsView.swift     — Export + AI settings tabs
│   ├── DesignTokens.swift     — Design system
│   └── AppDelegate.swift
└── Tests/PastureKitTests/     — 140 tests (Swift Testing framework)
```

No CoreData, no SwiftData, no external dependencies.

## Release

**Current version: 1.2.0** (2026-04-29)

See [CHANGELOG.md](CHANGELOG.md) for the full history of changes.
