# Memory Inbox — plan de implementación (v1.8)

Deriva del spec `2026-07-06-memory-inbox-design.md` y de 8 sub-planes TDD
(workflow `memory-inbox-plan`). Un solo PR. TDD estricto con el toolchain
`~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift`.

## Orden de implementación (por dependencias)

1. **Proposal** (`Sources/PastureKit/Proposal.swift`) — tipo base, todos dependen.
2. **MCP config layer** — `MCPLimits` +3 caps, `MCPServerConfig.allowProposals`,
   `MCPConfigGenerator` env-var. (MCPLimits lo necesita ProposalStore/tools.)
3. **ProposalStore** (`Sources/PastureKit/ProposalStore.swift`) — dep: Proposal, MCPLimits, Freshness.
4. **ProposalPromoter** (`Sources/PastureKit/ProposalPromoter.swift`) — dep: Proposal, ProposalStore.
5. **AppendDiff** (`Sources/PastureKit/AppendDiff.swift`) — puro, independiente (lo usa GUI + promoter).
6. **MCP propose tools** (`MCPTools.swift`) — dep: Proposal, ProposalStore, MCPLimits, MCPServerConfig, MCPPathResolver, SecretScanner, FilenameSanitizer.
7. **MCPDispatcher** (struct→final class) — captura clientInfo, pasa `proposedBy` a `run`.
8. **GUI** — ProposalInboxSheet, badge, `.inbox/` watcher, toggle Settings.
9. **Docs + versión** — SEC-M11 redefinido, CLAUDE.md, docs/mcp-server.md, CHANGELOG, bundle.sh 1.8.0, MCPProtocol.serverVersion.

## Reconciliación de openQuestions cruzadas (decisiones firmes)

- **API de ProposalStore = `vaultRoot: URL`** (deriva `.inbox` vía `inboxDirectory(vaultRoot:)`).
  Unifica store/promoter/tools. Firmas: `save(_:payload:vaultRoot:) throws`,
  `loadPending(vaultRoot:now:) -> [Proposal]`, `payload(for:vaultRoot:) -> String?`,
  `pendingCount(vaultRoot:now:) -> Int`, `contains(payloadHash:destination:vaultRoot:now:) -> Bool`,
  `delete(id:vaultRoot:)`. El tool pasa `config.vaultRoot`; la GUI pasa `MDFileManager.pastureDir`.
- **Hash**: `Proposal.payloadHash(for:) = SyncMarker.sha256(content)` (una sola impl, cero deps).
  Dedupe = `payloadHash` **y** `destinationKey` por separado (no se mezcla el destino en el hash).
- **`Proposal.destinationKey: String`** computed: note = `collection.map{ "\($0)/\(filename!)" } ?? filename!`;
  append = `relativePath!`. Fuente única del key de dedupe; el tool lo reusa.
- **Factories** `Proposal.note(...)` / `Proposal.append(...)` — sí (fuerzan el invariante kind↔campos).
- **`MCPTools.run(..., proposedBy: String = "unknown")`** — default para desacoplar del dispatcher.
- **`MCPTools.catalog(allowProposals: Bool = false)`** — default false = catálogo v1.7 byte-idéntico.
- **`MCPDispatcher` → `final class ... @unchecked Sendable`** (runtime secuencial single-thread, ADR-MCP-005).
- **ProposalPromoter outcomes**: `NoteOutcome`/`AppendOutcome` con `.hashMismatch(currentContent:)`;
  la GUI re-diffea contra `currentContent` y pide confirmación inline (alert), luego `confirmOverride: true`.
- **append separator** = `AppendDiff.composed` (fuente única: `existing.isEmpty ? payload : existing+"\n\n"+payload`).
  El promoter llama a `AppendDiff.composed`, no reimplementa el separador.
- **Extensión de filename**: se guarda tras `FilenameSanitizer.sanitize` tal cual (no se fuerza `.md`);
  el promoter deduplica con `FileLibrary.deduplicatedURL`. (Anotado: el agente debe pasar `.md` para que la nota promocionada aparezca en la biblioteca.)
- **append rechaza TODO symlink** (aunque resuelva dentro del vault): check `.isSymbolicLinkKey`
  sobre el candidato pre-resolución, además de las 2 capas de `MCPPathResolver`.
- **SEC ids nuevos**: `maxProposalBytes`=SEC-M14, `maxPendingProposals`=SEC-M15 (comentarios). TTL es política.

## Invariantes que se preservan (tests deben seguir verdes)
SEC-M1/M2 (doble capa, ahora también en escritura, antes de I/O), SEC-M3/M4/M5, SEC-M6
(ensamblado solo por ContextBuilder; las propuestas nunca pasan por TemplateEngine.render),
SEC-M7 (stdout sagrado; logs del store a stderr), SEC-M8 (warning familia+archivo, nunca el valor),
SEC-M9 (consent-first), SEC-M10 (diff en Swift puro), SEC-M12 (tool error vs protocol error),
`.skipsHiddenFiles` de FileLibrary (contrato de invisibilidad de `.inbox/` — test de regresión).

## Cierre
Build debug+release, suite completa (≥660), **workflow de revisión adversarial** del write-path
(path traversal/symlink, atomicidad, fuga de secretos, bypass de caps, prompt injection almacenada),
PR a main.
