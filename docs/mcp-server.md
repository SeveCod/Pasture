# pasture-mcp — MCP Server Reference

`pasture-mcp` is a [Model Context Protocol](https://modelcontextprotocol.io/) server embedded in
Pasture.app. It exposes `~/.pasture/` as a read-only vault to MCP clients such as Claude Code and
Claude Desktop. The server speaks JSON-RPC 2.0 over stdio (MCP spec `2025-06-18`), has zero
external dependencies, and is a pure Swift executable built from the same package as the app.

---

## Contents

1. [Registration](#registration)
2. [Tools](#tools)
   - [list_files](#list_files)
   - [read_file](#read_file)
   - [search](#search)
   - [feed_context](#feed_context)
3. [Limits](#limits)
4. [Secret warnings](#secret-warnings)
5. [Environment variables](#environment-variables)
6. [Troubleshooting](#troubleshooting)

---

## Registration

### Prerequisites

- Pasture 1.5.0 or later installed as `Pasture.app`.
- The MCP client must be able to launch the embedded binary:
  `Pasture.app/Contents/MacOS/pasture-mcp`.

The binary path is displayed in Settings → MCP (Cmd+,). The snippets below use the default
installation path; if you installed Pasture elsewhere, copy the exact path from Settings.

Before registering, use the **"Scan vault for secrets"** button in Settings → MCP to check
whether `~/.pasture/` contains credential patterns. The MCP channel delivers file contents
unchanged — `~/.pasture/` is intended for shareable context, not secrets.

### Claude Code

Run the command shown in Settings → MCP → "Copy configuration (Claude Code)" in your terminal.
The generic form is:

```bash
claude mcp add pasture --env PASTURE_FEED_FORMAT=xml -- /Applications/Pasture.app/Contents/MacOS/pasture-mcp
```

Verify that the server is registered:

```bash
claude mcp list
```

You should see `pasture` in the output. The client will start the server automatically on the
next session.

### Claude Desktop

1. Open `~/Library/Application Support/Claude/claude_desktop_config.json` (create it if it does
   not exist).
2. Paste the JSON block shown in Settings → MCP → "Copy configuration (Claude Desktop)" inside
   the `mcpServers` object. The generic form:

```json
{
  "mcpServers": {
    "pasture": {
      "command": "/Applications/Pasture.app/Contents/MacOS/pasture-mcp",
      "env": {
        "PASTURE_FEED_FORMAT": "xml"
      }
    }
  }
}
```

3. Restart Claude Desktop. The server starts when the application launches.

---

## Tools

All tools are read-only. No tool modifies, creates, or deletes files.

### list_files

Lists all Markdown files in the vault, grouped with their collection (subdirectory) name.

**Input schema**

```json
{
  "type": "object",
  "properties": {},
  "required": []
}
```

No parameters.

**Example request**

```json
{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "list_files", "arguments": {}}}
```

**Example response — vault with files**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "root-notes.md  [root]\nproject-alpha/spec.md  [collection: project-alpha]\nproject-alpha/design.md  [collection: project-alpha]"
      }
    ],
    "isError": false
  }
}
```

Each line is `<relative-path>  [root]` for files at the vault root, or
`<relative-path>  [collection: <name>]` for files in a subdirectory.

**Example response — empty vault**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [{"type": "text", "text": "(vault is empty: no Markdown files found)"}],
    "isError": false
  }
}
```

---

### read_file

Returns the raw Markdown content of a single file. The path is relative to `~/.pasture/`.

Template variables (`{{VAR}}`) and blocks are returned as-is — no substitution is performed
(by design; substitution is a Feed-time operation in the app).

**Input schema**

```json
{
  "type": "object",
  "properties": {
    "path": {"type": "string"}
  },
  "required": ["path"]
}
```

| Parameter | Type   | Required | Description                                         |
|-----------|--------|----------|-----------------------------------------------------|
| `path`    | string | Yes      | Path relative to `~/.pasture/`. Example: `notes.md` or `project-alpha/spec.md`. |

**Example request**

```json
{"jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": {"name": "read_file", "arguments": {"path": "project-alpha/spec.md"}}}
```

**Example response — success**

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [{"type": "text", "text": "# Specification\n\nContent of the file..."}],
    "isError": false
  }
}
```

**Example response — file contains a secret pattern** (content still delivered)

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "content": [{"type": "text", "text": "# Notes\n\napi_key: sk-ant-api03-..."}],
    "isError": false,
    "warning": "possible secrets detected (content delivered unchanged): Anthropic key in spec.md (sk-ant-a…3XYZ)"
  }
}
```

**Error cases**

| Condition | `isError` | Example `text` |
|-----------|-----------|----------------|
| Path outside vault (`../`, absolute, symlink escaping) | `true` | `"ruta fuera del vault"` |
| File not found | `true` | `"fichero no encontrado"` |
| `path` argument missing | `true` | `"se requiere el argumento 'path'"` |
| File exceeds 25 MB response cap | `true` | `"fichero demasiado grande, no se puede entregar"` |

---

### search

Finds files whose name or content contains a literal, case-insensitive query. Returns relative
paths of matching files, one per line. Results are capped at 100 files.

**Input schema**

```json
{
  "type": "object",
  "properties": {
    "query": {"type": "string"}
  },
  "required": ["query"]
}
```

| Parameter | Type   | Required | Description                                               |
|-----------|--------|----------|-----------------------------------------------------------|
| `query`   | string | Yes      | Literal search string. Maximum 1,000 characters. Case-insensitive. |

**Example request**

```json
{"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "search", "arguments": {"query": "OAuth2"}}}
```

**Example response — matches found**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [{"type": "text", "text": "project-alpha/spec.md\nauthentication/oauth-notes.md"}],
    "isError": false
  }
}
```

**Example response — no matches**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [{"type": "text", "text": "(no files match \"OAuth2\")"}],
    "isError": false
  }
}
```

**Example response — empty query**

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [{"type": "text", "text": "(empty query: no results)"}],
    "isError": false
  }
}
```

An empty query deliberately returns no results rather than dumping the full vault.

**Error cases**

| Condition | `isError` | Example `text` |
|-----------|-----------|----------------|
| Query exceeds 1,000 characters | `true` | `"query demasiado larga (máximo 1000 caracteres)"` |
| `query` argument missing | `true` | `"se requiere el argumento 'query'"` |

---

### feed_context

Assembles vault context using Pasture's Feed format — the same XML, Markdown, or plain-text
wrapping that the app produces for clipboard and export. Accepts either a collection name or a
list of file paths; if both are provided, the file list takes precedence.

**Input schema**

```json
{
  "type": "object",
  "properties": {
    "collection": {"type": "string"},
    "files": {"type": "array", "items": {"type": "string"}}
  },
  "required": []
}
```

| Parameter    | Type            | Required  | Description                                                   |
|--------------|-----------------|-----------|---------------------------------------------------------------|
| `collection` | string          | See note  | Name of a collection (subdirectory) in `~/.pasture/`.         |
| `files`      | array of string | See note  | Relative paths of individual files. If both parameters are provided, `files` wins. |

At least one of `collection` or `files` must be provided.

**Example request — by collection**

```json
{"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "feed_context", "arguments": {"collection": "project-alpha"}}}
```

**Example response — XML format (default)**

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "<documents>\n<context name=\"spec.md\"><![CDATA[# Specification\n\nContent...]]></context>\n<context name=\"design.md\"><![CDATA[# Design\n\nContent...]]></context>\n</documents>"
      }
    ],
    "isError": false
  }
}
```

**Example request — by file list**

```json
{"jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": {"name": "feed_context", "arguments": {"files": ["project-alpha/spec.md", "root-notes.md"]}}}
```

**Example response — files list with a missing file**

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "content": [{"type": "text", "text": "<context name=\"spec.md\"><![CDATA[...]]></context>"}],
    "isError": false,
    "warning": "files not found (omitted): root-notes.md"
  }
}
```

Missing or inaccessible files in a `files` list are omitted from the output and listed in the
`warning` field. The tool does not fail in bulk when some files are missing.

**Error cases**

| Condition | `isError` | Example `text` |
|-----------|-----------|----------------|
| Neither `collection` nor `files` provided | `true` | `"se requiere 'collection' o 'files'"` |
| Collection name not found in vault | `true` | `"colección no encontrada: nonexistent"` |
| All requested files missing or outside vault | `true` | `"no se encontró ningún fichero para ensamblar"` |
| Assembled payload exceeds 25 MB | `true` | `"contexto demasiado grande, refina la selección"` |

---

## Limits

| Limit | Value | Purpose |
|-------|-------|---------|
| Max input line size | 10 MB | Prevents OOM from malformed input without a newline |
| Max query length (`search`) | 1,000 characters | Bounds search cost |
| Max search results | 100 files | Bounds response size |
| Max content read per file in `search` | 2 MB | Matches `SecretScanner.maxScanBytes`; truncated at a valid UTF-8 boundary |
| Max response payload (`read_file`, `feed_context`) | 25 MB | Prevents serializing giant payloads |

Lines over the input cap are discarded silently (from the client's perspective) and logged to
stderr. The connection is not dropped.

---

## Secret warnings

When `read_file` or `feed_context` detects a credential pattern in the content it is about to
return, it attaches a `warning` field to the result. The content is delivered unchanged — the
warning is informational, not a gate.

Six families are detected:

| Family | Pattern |
|--------|---------|
| Anthropic key | `sk-ant-…` |
| OpenAI-style key | `sk-…` (evaluated after Anthropic to avoid misclassification) |
| GitHub token | `ghp_`, `gho_`, `ghu_`, `ghs_` prefixes |
| AWS access key | `AKIA…` |
| PEM private key | `-----BEGIN … PRIVATE KEY-----` |
| Slack token | `xox[baprs]-…` |

The `warning` value contains the family name, the file name, and a masked snippet of the first
match (first 7 + last 4 characters). The raw credential value is never included.

Example warning value:

```
possible secrets detected (content delivered unchanged): Anthropic key in notes.md (sk-ant-a…3XYZ)
```

For `feed_context` with multiple files, secret warnings and missing-file notices are combined in
the same `warning` string, separated by ` | `.

---

## Environment variables

| Variable | Values | Default | Description |
|----------|--------|---------|-------------|
| `PASTURE_FEED_FORMAT` | `xml`, `markdown`, `plainText` | `xml` | Controls the feed payload format produced by `feed_context`. `xml` wraps content in CDATA tags (robust for model parsing); `markdown` uses CommonMark headings and dynamic fences; `plainText` uses a filename header with bare content. |

The registration snippets in Settings → MCP inject your current Feed Output Format setting
automatically. If you change the format in Settings → Export → Feed Output Format, re-copy the
registration snippet and re-register to keep them in sync.

---

## Troubleshooting

**"Server binary not found" in Settings → MCP**

The buttons are disabled because `Pasture.app/Contents/MacOS/pasture-mcp` does not exist.
This happens when running via `swift run` (development mode) instead of from a bundled `.app`.
Build the bundle with `./scripts/bundle.sh` and run from `dist/Pasture.app`.

**`claude mcp list` shows pasture but tools are not available**

Start a new Claude Code session after registering. The MCP server list is read at session start.

**`feed_context` returns an empty result for a collection I can see in the app**

Collection names are case-sensitive and must match the subdirectory name exactly. Use
`list_files` first to see the exact name as returned by the server.

**The server exits immediately after registration**

`pasture-mcp` only runs while the MCP client holds the stdin pipe open. It is not a daemon — it
starts on demand and exits when the client session ends. This is the expected behavior for
MCP-over-stdio servers.

**Responses contain `\/` instead of `/`**

This would indicate a build of the server from before v1.5.0. The current build uses
`JSONEncoder.OutputFormatting.withoutEscapingSlashes`; upgrade to v1.5.0 or later.

**The vault scan in Settings → MCP reports secrets I do not recognise**

`SecretScanner` uses prefix/pattern matching and may produce false positives for strings that
resemble credential formats. Review the files listed in the warning. The scan result does not
block registration — it is advisory only.
