# Pasture — Feed your AI

A minimal macOS app for managing Markdown context files to feed to AI assistants like Claude.

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

Pasture manages `.md` files in `~/.pasture/` and makes it fast to compose context for AI sessions.

### Library (sidebar)
- Lists all `.md` files in `~/.pasture/` with name and modification date
- Multi-select with `Cmd+click`
- Drag & drop `.md` or `.pdf` files from Finder to import them

### Editor (right panel)
- Edit selected file in a monospaced TextEditor
- Auto-save with 1-second debounce on every change
- `Cmd+S` to force save immediately

### New from Clipboard — `Cmd+Shift+V`
Reads the clipboard, asks for a file name, and saves a new `.md` in `~/.pasture/`.

### Merge
With multiple files selected, the **Merge** toolbar button concatenates them (separated by `\n---\n`) into a new file.

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

### Import PDF
Toolbar button or drag & drop. Extracts text via PDFKit (native, zero dependencies) and saves as `.md`. Works with any digitally-generated PDF (reports, papers, manuals). Scanned PDFs without OCR layer return empty text.

### Search
The search bar filters by file name and content in real time.

## Template syntax

Any `.md` file can declare variables using double-brace syntax. When you hit Feed, Pasture collects all variables, prompts for their values, substitutes them, and copies the result. The editor always shows the raw template — substitution happens only at Feed time.

```
{{VARIABLE}}              — declares a variable, prompted before Feed
{{VAR=default}}           — declares a variable with a default value
```

Variable names must start with a letter or underscore and may contain letters, numbers, and underscores (`[A-Za-z_][A-Za-z0-9_]*`).

If the same variable appears more than once in a file, it is only prompted once. The default value of the first occurrence wins.

Example: a file containing

```
Hello {{NAME}}, welcome to {{PROJECT=Pasture}}.
```

prompts for `NAME` (no default) and `PROJECT` (default: `Pasture`).

## Token estimation

The token counter in the toolbar is an approximation based on a heuristic of ~4 characters per token. It is not the actual Claude tokenizer. It is accurate enough for rough sizing but may diverge for code-heavy files or non-English content.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+Shift+V` | Create new file from clipboard |
| `Cmd+S` | Force save current file |
| Drag & drop | Import `.md` or `.pdf` files |

## Structure

```
Sources/Pasture/
├── PastureApp.swift      — App entry point, menu commands
├── ContentView.swift     — Main UI (sidebar, editor, toolbar)
├── MDFileManager.swift   — File model and I/O operations
├── DesignTokens.swift    — Design system (colors, typography, layout)
├── TemplateEngine.swift  — Template variable extraction and rendering
└── TokenEstimator.swift  — Heuristic token counter
```

No CoreData, no SwiftData, no external dependencies.

## Release

**Current version: 1.0.0** (2026-04-29)

See [CHANGELOG.md](CHANGELOG.md) for the full history of changes.
