# Memory Inbox — diseño (v1.8)

> Feature 4 del roadmap 10x. Escritura MCP con airlock de consentimiento humano.
> Base: v1.7 mergeada (632 tests). Entrega: **un solo PR** (backend MCP + GUI + docs).

## Tesis

Hoy Pasture alimenta a la IA pero la IA no puede alimentar a Pasture: el vault se
estanca porque actualizarlo es 100% manual. Memory Inbox cierra el loop sin
romper la confianza: un agente puede **proponer** notas nuevas o añadidos, pero
nunca escribe en el vault visible — deposita en un staging oculto y **solo el
humano promociona** desde la GUI, con diff obligatorio y sin aprobación en bloque.

## Invariante de seguridad — redefinición de SEC-M11

SEC-M11 pasa de *"El servidor MCP es estrictamente read-only, sin write-path a
`~/.pasture/`"* a:

> **SEC-M11 (redefinido):** El servidor MCP no tiene write-path al vault visible.
> Con `PASTURE_ALLOW_PROPOSALS=1` puede escribir **exclusivamente** en
> `~/.pasture/.inbox/` (oculto, fuera de `FileLibrary`, del feed y de las tools de
> lectura). La promoción al vault visible es una acción **exclusivamente humana**
> desde la GUI, con diff obligatorio y sin aprobación masiva.

Regresión de solo-lectura: **sin** la env var, el catálogo de `tools/list` es
byte-idéntico al de v1.7 (test estructural).

## Arquitectura

### PastureKit (nuevos, públicos, `Sendable`, testeables)

- **`Proposal`** — `Codable` con `schemaVersion` explícito (=1 desde v1). Campos:
  `id: UUID`, `kind: ProposalKind` (`.note`/`.append`), destino
  (`filename` + `collection?` para note; `relativePath` para append),
  `createdAt: Date`, `proposedBy: String`, `secretSummary: String?`,
  `targetHash: String?` (SHA-256 del destino al proponer un append),
  `payloadHash: String` (para dedupe). **Campo reservado** `autoApproved: Bool?`
  para la Fase 2 (auto-approve por colección) — no usado en v1.8, pero el schema
  no debe impedirlo.
- **`ProposalStore`** — enum estático `nonisolated`. I/O sobre `~/.pasture/.inbox/`:
  - `save(_:payload:)` → escribe par `<uuid>.md` (payload) + `<uuid>.json`
    (metadata) de forma **atómica** (temp + rename).
  - `loadPending(now:)` → lista propuestas válidas; una con
    `createdAt` anterior a `now - proposalTTLDays` se mueve a estado `expired`
    (se elimina de la bandeja) sin intervención. Reloj inyectado (patrón `Freshness`).
  - Tolera **pares huérfanos** (`.md` sin `.json` o viceversa): los ignora y
    loguea a stderr, nunca crashea. Metadata corrupta → propuesta ignorada + log.
  - `pendingCount`, `contains(payloadHash:destination:)` (dedupe), `delete(id:)`.
  - `didChangeNotification` (patrón `SelectionPresetStore`).
- **`ProposalPromoter`** — el **único** código con write-path al vault visible;
  invocado solo desde la GUI. Testeable con vault temporal.
  - `promoteNote(_:vaultRoot:)` → crea el archivo en la colección destino con
    nombre deduplicado (`FileLibrary.deduplicatedURL`), **prepend** de frontmatter
    de procedencia (`origin: agent`, `proposed_by`, `proposed_at`, `approved_at`),
    y borra el par de `.inbox/`.
  - `promoteAppend(_:vaultRoot:)` → añade el payload al final del destino con
    separador `\n\n`, **nunca reemplaza**. Si el hash actual del destino ≠
    `targetHash` guardado, devuelve `.hashMismatch(currentContent:)` para que la
    GUI recalcule el diff y pida confirmación explícita antes de anexar.
  - `reject(_:)` → elimina el par de `.inbox/`.
  - Validación de destino con la **misma doble capa** que lectura
    (`MCPPathResolver`: rechazo de absolutas + `PathValidator.isInside` +
    revalidación tras `resolvingSymlinksInPath`) **antes** de cualquier I/O.

### Capa MCP (extensiones)

- **`MCPLimits`** +3 constantes públicas, testeadas individualmente:
  `maxProposalBytes = 1_000_000`, `maxPendingProposals = 50`,
  `proposalTTLDays = 14`. Las existentes (SEC-M3/M4/M5) no cambian.
- **`MCPServerConfig`** +`allowProposals: Bool`, leído de
  `PASTURE_ALLOW_PROPOSALS` en `fromEnvironment()` (ADR-MCP-007: entorno, no
  UserDefaults — el proceso CLI no comparte dominio con la app).
- **`MCPTools`** +2 tools, presentes en el catálogo **solo si**
  `config.allowProposals`:
  - `propose_note` (args: `filename`, `content`, `collection?`).
  - `propose_append` (args: `path`, `content`).
  - Sus `description` declaran explícitamente *"requiere aprobación humana"*.
  - Camino de ejecución, en orden: validar destino (doble capa) →
    `FilenameSanitizer` en el nombre → cap de tamaño (`maxProposalBytes`) →
    cap de pendientes (`maxPendingProposals`) → dedupe (hash payload+destino) →
    `SecretScanner` sobre el contenido entrante (se acepta igual; el summary
    enmascarado va a metadata + `warning` del `ToolCallResult`) → `ProposalStore.save`.
    Cualquier fallo = `isError=true` en el `result` (SEC-M12), nunca corta la conexión.
  - `propose_append`: el destino debe existir y no ser symlink; se guarda el
    `targetHash` SHA-256 del contenido actual.
- **`MCPConfigGenerator`** — inyecta `PASTURE_ALLOW_PROPOSALS=1` junto a
  `PASTURE_FEED_FORMAT` en ambos formatos (claude mcp add / claude_desktop_config)
  cuando el toggle está activo; ausente cuando está inactivo. Sigue con `JSONEncoder`.
- **`MCPDispatcher`** — pasa de `struct` a `final class` para capturar la
  procedencia: `private var clientInfo` se setea en el handler de `initialize`
  (hoy se ignora). `proposedBy = clientInfo?.name ?? "unknown"`. Seguro sin
  cerrojo porque el runtime es secuencial single-thread (ADR-MCP-005).
  `handle(line:)` sigue siendo el boundary testeable (los tests pueden enviar
  `initialize` y luego `tools/call` sobre la misma instancia).

### GUI (Sources/Pasture)

- **Bandeja de revisión** (sheet, patrón de sheets existente en ContentView):
  cada propuesta muestra procedencia (`proposedBy` + `createdAt`), destino, aviso
  de secretos si existe, y contenido. Para `propose_append`, un **diff obligatorio**
  (líneas añadidas resaltadas) contra el estado actual del destino. **Sin botón de
  "aprobar todo"** (decisión anti-"consentimiento teatro").
- **Diff en Swift puro** (SEC-M10, cero deps): como el append siempre añade al
  final, el diff es las líneas nuevas resaltadas sobre el contenido actual — no
  hace falta LCS general.
- **Badge "Inbox (N)"** en `SidebarView` cuando hay ≥1 pendiente; al pulsarlo abre
  la bandeja.
- **Sub-watcher de `.inbox/`** en `DirectoryWatcher` (mismo patrón GCD + debounce
  0.5s, `@MainActor`) para refrescar badge/bandeja al llegar propuestas.
- **Toggle** *"Permitir propuestas de escritura (requieren tu aprobación)"* en
  Settings → MCP; al activarlo, los snippets copiados incluyen la env var.
- Aprobar/rechazar sobre una propuesta ya desaparecida (expirada/borrada) →
  toast de error vía `FeedService.showFeedback`, sin crash.
- UI con `DesignTokens` (WCAG AA ≥4.5:1 en ambos schemes), nunca colores hardcodeados.

## Data flow

```
Agente (Claude Code/Desktop) --propose_note/append--> pasture-mcp
  -> MCPTools valida (path 2 capas, sanitizer, caps, dedupe, secret scan)
  -> ProposalStore.save  =>  ~/.pasture/.inbox/<uuid>.{md,json}   (oculto)
GUI: DirectoryWatcher observa .inbox/ -> badge "Inbox (N)"
Humano abre bandeja -> revisa diff/contenido/procedencia/secretos
  -> Aprobar: ProposalPromoter escribe en la colección visible (+frontmatter) y borra el par
  -> Rechazar: ProposalPromoter borra el par
  -> DirectoryWatcher refresca la lista del vault
```

## Manejo de errores

- Tool errors (`isError=true` en el `result`, SEC-M12): path fuera del vault,
  nombre inválido, cap de tamaño/pendientes alcanzado, duplicado, append a destino
  inexistente/symlink. **Nunca** cortan la conexión.
- Protocol errors (JSON-RPC): solo los ya existentes (parse, id null, método
  desconocido). Las tools de propuesta no introducen errores de protocolo nuevos.
- Store: huérfanos y metadata corrupta se ignoran con log a stderr; nunca crash.
- Concurrencia GUI↔proceso MCP: escrituras atómicas temp+rename; el promoter
  tolera una propuesta que desapareció entre el listado y la acción.

## Testing (Swift Testing, patrón boundary sin spawn)

- `MCPProposalToolsTests` — catálogo condicionado por env, validación de args,
  caps (tamaño/pendientes), dedupe, path traversal/symlink/absolutas en escritura,
  secretos (summary enmascarado + warning).
- `ProposalStoreTests` — CRUD en disco, `schemaVersion`, atomicidad, expiración
  con reloj inyectado, huérfanos, metadata corrupta → ignorada sin crash.
- `ProposalPromoterTests` — aprobar nota (frontmatter + dedup de nombre), aprobar
  append (separador, hash match/mismatch), rechazar.
- `MCPLimitsTests` — los 3 caps nuevos.
- `MCPConfigGeneratorTests` — env var presente/ausente según toggle, ambos formatos.
- `MCPDispatcherTests` / `MCPEndToEndTests` — captura de clientInfo en initialize;
  round-trip propose_note → archivo en `.inbox/` con vault temporal.
- `FileLibraryTests` — **test de regresión de contrato**: `.inbox/` con contenido
  nunca aparece en `load(at:)` (fija `.skipsHiddenFiles` como invariante).
- Regresión de solo-lectura: sin la env var, `tools/list` byte-idéntico a v1.7.
- Meta: suite total ≥ 660 tests; CI macos-15 verde en debug+release+tests.

## Fuera de alcance (Fase 2, no diseñar en contra)

- Allowlist por colección para auto-aprobar en una carpeta "Agent Memory". El
  schema de `Proposal` deja el campo reservado `autoApproved` pero v1.8 no lo usa.

## Riesgo residual asumido

- **Prompt injection almacenada**: una nota aprobada de origen agente puede
  envenenar contexto futuro. Mitigación: procedencia permanente en el frontmatter
  (`origin: agent`) + diff obligatorio en revisión. Se documenta como limitación
  conocida en `docs/mcp-server.md`.

## Entregables del PR

- Código: los tipos nuevos de PastureKit + extensiones MCP + GUI.
- Docs en el **mismo PR**: redefinición de SEC-M11 en `CLAUDE.md` (sección Security
  invariants) y `docs/mcp-server.md`; descripción actualizada de `MCPSettingsTab`;
  `CHANGELOG.md` (Keep a Changelog); limitación conocida.
- `VERSION` en `scripts/bundle.sh`: `1.7.0` → `1.8.0`. `MCPProtocol.serverVersion`
  a `1.8.0`.
- Revisión adversarial del camino de escritura antes del merge (como en v1.5).
