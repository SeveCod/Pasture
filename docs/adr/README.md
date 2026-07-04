# Registro de decisiones de arquitectura (ADR)

Este directorio es el **registro canónico** de los ADR de Pasture. Nace de una
auditoría (2026-07-04) que detectó una colisión: las features v1.4 y v1.5 numeraron
sus ADR de forma independiente (`ADR-001…`), de modo que un mismo número (p. ej.
`ADR-004`) significaba **dos cosas distintas** según el documento de diseño.

Para eliminar la ambigüedad sin reescribir los documentos de diseño originales, cada
serie recibe aquí un **prefijo de espacio de nombres**:

- **`ADR-QW-00X`** — serie *Quick Wins* (v1.4). Fuente: `docs/design/v1.4-quick-wins-design.md`.
- **`ADR-MCP-00X`** — serie *MCP server* (v1.5). Fuentes: `docs/design/v1.5-mcp-server-design.md`
  y `docs/spikes/spike-mcp-server.md`.

Los comentarios en el código fuente que citan `ADR-00X` a secas se interpretan según
el fichero en que viven: los de la capa `SecretScanner`/feed/presets pertenecen a la
serie **QW**; los de `Sources/PastureKit/MCP/` y `Sources/pasture-mcp/`, a la serie **MCP**.
`CLAUDE.md` usa ya los identificadores con prefijo.

## Serie Quick Wins (v1.4)

| ID | Decisión | Estado |
|----|----------|--------|
| **ADR-QW-001** | Catálogo de patrones de secretos como `NSRegularExpression` precompiladas una sola vez (`static let`), no `Regex` de Swift ni compilación por invocación. | Aceptado |
| **ADR-QW-002** | Orden invariante del pipeline de feed: `resolver templates → escanear secretos → generar payload → entregar`. El escaneo va sobre el contenido renderizado. | Aceptado |
| **ADR-QW-003** | Los presets de selección se guardan por **path relativo** a `~/.pasture/`; nunca contenido, URL absoluta ni claves. | Aceptado |
| **ADR-QW-004** | Aviso de límite de contexto **binario**: sólo se dispara al EXCEDER la ventana del modelo; sin modelo configurado, nunca. | Aceptado |
| **ADR-QW-005** | `FeedFormat` (estructura del payload) y `ExportFileFormat` (extensión de fichero) son **ortogonales**: dos settings, dos pickers, combinables libremente. | Aceptado |
| **ADR-QW-006** | `ContextBuilder` retrocompatible: el XML de v1.3 se preserva byte a byte (snapshot test contra fixture). | Aceptado |

## Serie MCP server (v1.5)

| ID | Decisión | Estado |
|----|----------|--------|
| **ADR-MCP-001** | Cero dependencias externas: JSON-RPC implementado a mano; sin `.package` en `Package.swift`. | Aceptado |
| **ADR-MCP-002** | Binario `pasture-mcp` **embebido en el `.app`**; en v1.5 no se firma ni notariza (Gatekeeper no evalúa el camino exec de un cliente MCP). | Aceptado |
| **ADR-MCP-003** | Servidor **solo lectura** sobre una **raíz única** (`~/.pasture/`); sin ninguna operación de escritura. | Aceptado |
| **ADR-MCP-004** | Toda la lógica de protocolo vive en **PastureKit** (testeable con los tests vecinos); el executable es un `main.swift` fino de puro transporte. | Aceptado |
| **ADR-MCP-005** | Loop **secuencial síncrono** en `main.swift`, sin actor ni async: el server es single-threaded por contrato MCP-stdio. | Aceptado |
| **ADR-MCP-006** | Una sola tool `feed_context`; serialización con `JSONEncoder` + `.withoutEscapingSlashes` + `.sortedKeys` (sin el primero, `/`→`\/` rompe el framing). | Aceptado |
| **ADR-MCP-007** | `pasture-mcp` lee su configuración del **entorno** (`PASTURE_FEED_FORMAT`), no de `UserDefaults.standard`, que un proceso CLI separado no comparte con la GUI. | Aceptado |
