# Docs / Drift — score 68/100

## Resumen

El `CLAUDE.md` es exacto donde más se ha tocado últimamente (capa MCP, invariantes de seguridad, `SidebarTree`/`CollectionExpansionStore` de la v1.11, conteo de 728 tests) pero arrastra **tres mentiras estructurales**: describe el panel Ask como de una sola respuesta cuando desde la v1.7 es multi-turno, declara que el Context Compiler "GUI wiring is a follow-up" cuando la pestaña Packs ya existe, y dice que Settings tiene tres pestañas cuando tiene cinco. El `README.md` está **fosilizado en la v1.5.1 (2026-07-04)**: seis releases por detrás, con "501 tests" y un árbol de ficheros que omite Memory Inbox, frescura, Packs e integración macOS. El `CHANGELOG.md` es lo más sano del repo: la entrada 1.11.0 se corresponde commit a commit con la rama. LICENSE **existe** (MIT, raíz) — el pendiente que lo declara ausente es drift.

## Tabla de drift

| Afirmación del doc | Dónde lo dice | Realidad del código | Severidad |
|---|---|---|---|
| "`AskViewModel` … managing Ask state: question, **responseText**, isStreaming … Methods: `send()`, `stop()`, `clear()`, **`copyResponse()`, `saveResponse()`**" | CLAUDE.md:80 | No existe `responseText` ni esos dos métodos. Hay `conversation: AskConversation` (`AskViewModel.swift:10`), `distilledConversation` (:39), `copyConversation()` (:119), `saveAsContext(to:collection:)` (:127) | crítico |
| "`ask(question:context:model:apiKey:) -> AsyncThrowingStream`" | CLAUDE.md:106, 195 | La firma viva es `ask(messages:model:apiKey:)` — `AskViewModel.swift:79` llama `client.ask(messages: wire, …)`; `AIClient.swift:58` y `:70` son dos overloads | crítico |
| Cuatro tipos del núcleo de la v1.7 no aparecen en ninguna parte del doc | CLAUDE.md (0 menciones) | `AskConversation.swift`, `ChatMessage.swift`, `ConversationComposer.swift`, `ConversationTruncator.swift` en `Sources/PastureKit/` | alto |
| "`SettingsView.swift` — `TabView` with **three tabs**: `ExportSettingsTab`, `AISettingsTab`, `MCPSettingsTab`" | CLAUDE.md:88 | Cinco: `GeneralSettingsTab` (`SettingsView.swift:9`), `ExportSettingsTab` (:11), `AISettingsTab` (:13), **`PacksSettingsTab`** (:15), `MCPSettingsTab` (:17) | alto |
| "Context Compiler (v1.6, PastureKit core — **GUI wiring is a follow-up**)" | CLAUDE.md:141 | La GUI está entregada: `Sources/Pasture/PacksSettingsTab.swift`, `PackEditorView.swift`, `PackSyncRunner.swift`, y el comando "Sync All Packs" en `PastureApp.swift:32` | alto |
| "Menu commands: 'Open in Default Editor' (Cmd+E), 'Paste from Clipboard' (Cmd+Shift+V), 'Toggle Ask Mode' (Cmd+Shift+A)" | CLAUDE.md:95 (`PastureApp.swift`) | Faltan dos: **"Sync All Packs" Cmd+Shift+P** (`PastureApp.swift:32-35`) y **"Refresh Sources" Cmd+Shift+R** (:37-40). Cmd+Shift+R sí sale en CLAUDE.md:139; Cmd+Shift+P no sale en ningún documento | alto |
| "Includes **9 MCP test suites**: …" (lista de 9) | CLAUDE.md:38 | 17 ficheros de test MCP en `Tests/PastureKitTests/`: los 9 listados más `MCPConfigGeneratorProposalTests`, `MCPLimitsTests`, `MCPPathResolverHiddenTests`, `MCPProposalDispatchTests`, `MCPProposalToolsTests`, `MCPServerConfigTests`, `MCPServerVersionTests`, `MCPStalenessTests` | menor |
| "Catálogo y ejecución de **las cuatro tools de solo lectura**" (docstring) | `Sources/PastureKit/MCP/MCPTools.swift:3` | El mismo fichero define seis: `catalog(includingProposals:)` añade `propose_note`/`propose_append` (:78-90) y `run` los despacha (:124-126). Es un claim de seguridad ("solo lectura") desmentido 75 líneas más abajo | alto |
| "`awsAccessKey` (`AKIA…`)" y "`githubToken` (`ghp_`/`gho_`/`ghu_`/`ghs_`)" | CLAUDE.md:125 | El scanner cubre además `ASIA` (STS temporal) y `github_pat_` fine-grained — `SecretScanner.swift:7-8` | menor |
| "Current version: **1.5.1** (2026-07-04)" | README.md:225 | `scripts/bundle.sh:7` → `VERSION="1.11.0"` | alto |
| "Tests/PastureKitTests/ — **501 tests**" | README.md:218 | 728 `@Test` medidos (`grep -rho "@Test" Tests/ \| wc -l`) | alto |
| README: árbol de `Sources/` como inventario del proyecto | README.md:155-218 | Omite ~20 ficheros vivos: todo el Memory Inbox (`Proposal`, `ProposalStore`, `ProposalPromoter`, `ReviewInboxSheet`), la frescura (`FrontmatterParser`, `Freshness`, `FrontmatterWriter`, `SourceImport`, `ReviewQueueSheet`), los Packs (5 ficheros), la integración macOS (`PastureURLCommand`, `QuickCapture`, `HeadlessFeed`, `GlobalHotkeyManager`, `ServicesProvider`, `SystemNotifier`, `IntegrationSettings`) y el Ask multi-turno (4 ficheros) | alto |
| README: "Settings (Export destinations, AI config)" y "Export, AI, and MCP settings tabs" | README.md:147, 212 | Cinco pestañas (ver arriba); General y Packs ausentes | menor |
| README describe borrado y funciones sin mencionar Papelera, hotkeys globales, `pasture://`, Servicios ni el árbol plegable de la sidebar | README.md:22-60, 138-148 | v1.9/v1.10/v1.11 entregadas: `MDFileManager.swift:295` y `:385` usan `trashItem`; `GlobalHotkeyManager.swift`; `SidebarView.swift` con `DisclosureGroup` | alto |
| "El borrado" descrito sin decir que va a la Papelera | CLAUDE.md:82 ("deletion confirmed via alert"), 0 menciones de Trash/Papelera en todo el fichero | `MDFileManager.swift:295`, `:385` → `FileManager.default.trashItem` (cambio de la v1.10) | menor |
| `docs/mcp-server.md`: "Prerequisites — Pasture **1.5.0** or later" | docs/mcp-server.md:31 | Correcto como mínimo histórico, pero el documento sí cubre resources/prompts (1.6) y proposals (1.8): la línea induce a pensar que 1.5.0 basta para todo lo documentado | menor |
| CLAUDE.md no documenta que `MCPProtocol.serverVersion` va desacoplado de la versión de la app | CLAUDE.md (0 menciones) | `MCPProtocol.swift:7` → `"1.8.0"` con app en 1.11.0, congelado a propósito y guardado por `MCPServerVersionTests.swift` | menor |

## Hallazgos críticos

**C1 — La sección Ask describe una API que ya no existe.** `CLAUDE.md:80` y `:106` documentan `responseText`, `copyResponse()`, `saveResponse()` y `ask(question:context:model:apiKey:)`. Ninguno existe. Una sesión que lea esto y vaya a tocar el panel Ask escribirá contra una superficie imaginaria y, peor, **no sabrá que hay un historial de conversación que mantener coherente**: `send()` hace `conversation.addUserQuestion(q)` → `requestMessages(context:model:)` → `beginAssistant()` / `appendDelta` / `completeAssistant` (`AskViewModel.swift:70-84`), con tres caminos distintos de `endInterruptedAssistant()` para cancelación y error. Es exactamente el modo de fallo que el encargo describe: el doc manda por la vía equivocada. Toda la "AI streaming pipeline" de `CLAUDE.md:195` y la frase de `docs/adr`-style de `:260` quedan tocadas por lo mismo.

**C2 — El README es un documento de otra app.** Congelado en 1.5.1 con 501 tests, anuncia como completa una app sin Memory Inbox, sin frescura de notas, sin Context Compiler, sin integración de sistema y sin el árbol plegable. Es el único documento que un tercero lee antes que nada, y describe menos de la mitad del producto. Lo clasifico crítico y no alto porque el README es la puerta de entrada pública del repo y aquí no está desactualizado en un detalle: está desactualizado en seis releases.

## Hallazgos altos

**A1 — "GUI wiring is a follow-up" (CLAUDE.md:141).** El Context Compiler tiene GUI desde hace tiempo (`PacksSettingsTab.swift`, `PackEditorView.swift`, `PackSyncRunner.swift`, comando Cmd+Shift+P). Un lector concluirá que hay trabajo pendiente que ya está hecho, o peor, lo reimplementará.

**A2 — Settings: tres pestañas documentadas, cinco reales.** `GeneralSettingsTab` sí aparece suelto en `CLAUDE.md:174` (en español, dentro del bloque v1.9), pero **`PacksSettingsTab` no aparece en ninguna parte**. La línea :88 es la que un lector tomará como inventario.

**A3 — El docstring de `MCPTools` afirma "solo lectura" y el fichero implementa el write-path.** `MCPTools.swift:3`. El `CLAUDE.md` sí documenta bien SEC-M11 redefinido y el gate `PASTURE_ALLOW_PROPOSALS`, así que la contradicción está dentro del código, no entre doc y código — pero es precisamente un comentario de comportamiento de seguridad que ha dejado de ser cierto, que es lo que se pedía cazar. `CLAUDE.md:62` ("Four read-only tools") arrastra el mismo desfase, aunque ahí es defendible: sin la variable de entorno el catálogo es exactamente esas cuatro.

**A4 — Dos atajos de teclado sin documentar.** Cmd+Shift+P ("Sync All Packs") no está en CLAUDE.md, README ni docs. Cmd+Shift+R está en CLAUDE.md:139 pero no en la tabla de atajos del README.

## Hallazgos menores

- `docs/` tiene una capa fosilizada clara: `docs/prd/` y `docs/design/` datan del 2026-06-12 (v1.4/v1.5) y `docs/prd/nivel-2-diferenciacion-real.md` del 2026-04-29. No son falsos —son artefactos históricos de su release— pero nada los marca como cerrados. `docs/roadmap-10x.md` (2026-07-05) sí es útil y sigue siendo el mapa: sus items 1-5 (v1.6-v1.8) están entregados y el documento no lo refleja, así que se lee como plan cuando ya es historia a medias.
- `docs/adr/README.md` está vivo y es correcto: la convención `ADR-QW-00X` / `ADR-MCP-00X` se corresponde con las citas del código y del CLAUDE.md.
- `docs/mcp-server.md` es el documento de referencia mejor mantenido después del CHANGELOG: cubre resources, prompts, límites y proposals con las cifras correctas (25 MB, 100.000 caracteres — coinciden con `MCPLimits.swift:27` y `:33`).
- CLAUDE.md no menciona la Papelera pese a ser el cambio de comportamiento destructivo de la v1.10.

## CHANGELOG.md

**Correcto.** La entrada `[1.11.0] - 2026-09-18` se corresponde con los commits de la rama uno a uno: árbol plegable (`f992f44`, `6bd70b2`), persistencia con override de búsqueda (`cf6c029`), fusión de las dos tiras de aviso (`63d23d0`), retirada de New File con su botón, su Cmd+N y su diálogo (`b91d8fe`), y la vuelta atrás a cuatro iconos separados (`80a6379`) que la línea de "Changed" recoge con precisión. Formato Keep a Changelog respetado (Added / Changed / Removed, enlace a la especificación en la cabecera) y SemVer coherente: cambios de interfaz sin ruptura de API → minor. La línea "Test count: 711 → 728" coincide con la medición (728 `@Test`). Único matiz: la v1.11.0 lleva la fecha de hoy y la rama aún no está mergeada a `main`, cosa normal en una release en vuelo.

## Pendientes declarados: abiertos vs. cerrados

| Pendiente | Origen | Estado real |
|---|---|---|
| **LICENSE ausente ("MIT sería lo natural")** | memoria del proyecto / CLAUDE.md global §Pasture | **CERRADO — drift.** `LICENSE` existe en la raíz (1.064 bytes, 2026-06-24) y el README ya lo enlaza (README.md:231) |
| "El lado GUI del Memory Inbox v1.8 quedó cerrado en v1.10" | CLAUDE.md global | **Confirmado cerrado.** `ReviewInboxSheet.swift` existe con sus confirmaciones |
| QA visual de v1.10 (checklist en PR #6) | memoria `pasture-v110-…` | **Sigue abierto** hasta donde se puede verificar desde el repo: no hay artefacto de QA en `docs/` ni marca en el CHANGELOG. No verificable en código (asunción anotada abajo) |
| Notarización real de la GUI (firma ad-hoc solo reduce fricción) | CLAUDE.md global | **Sigue abierto.** `scripts/bundle.sh` firma ad-hoc; no hay `notarytool` ni perfil |
| "Context Compiler — GUI wiring is a follow-up" | CLAUDE.md:141 | **CERRADO — drift** (ver A1) |
| Decisiones de producto: retirar `Proposal.autoApproved` | CLAUDE.md global | **Sigue abierto.** `Proposal.swift` mantiene el campo reservado para Fase 2, como documenta CLAUDE.md:161 |

## Lo que está correctamente documentado

Conviene decirlo porque delimita dónde hay que mirar y dónde no:

- **Conteo de tests: 728, exacto.** `CLAUDE.md:16` y `:38` coinciden con la medición (`728` ocurrencias de `@Test`). El commit `3dc24f3` ("docs: correct test count to the measured 728") es justo la disciplina que evita este tipo de drift.
- **Versión 1.11.0**, coherente entre `CLAUDE.md`, `CHANGELOG.md` y `scripts/bundle.sh:7`.
- **`SidebarTree` y `CollectionExpansionStore` (CLAUDE.md:126-127): exactos**, incluido el detalle fino del prefijo `"u:"`/`"c:<name>"` y el invariante de que una búsqueda activa nunca escribe el estado de plegado.
- **Toda la capa MCP** (`CLAUDE.md:55-72`): los doce ficheros existen con los nombres y responsabilidades descritos; `MCPProtocol.version = "2025-06-18"` (`MCPProtocol.swift:5`) y los cuatro caps de `MCPLimits` (10 MB / 100 / 1.000 / 25 MB) coinciden literalmente con `MCPLimits.swift:11-27`.
- **Invariantes de seguridad verificados uno a uno:** rechazo de componentes ocultos (`MCPPathResolver.swift:33`), rechazo de rutas absolutas (:25), auto-clear de portapapeles a 60 s en los dos caminos (`FeedService.swift:195`, `HeadlessActions.swift:77`), purga de claves reservadas del frontmatter antes de promover (`ProposalPromoter.swift:109`), `maxNestingDepth = 16` / `maxIterations = 1.000` (`TemplateEngine.swift:54-55`), tope de 100 presets (`SelectionPresetStore.swift:12`) y las seis familias del `SecretScanner`.
- **Las secciones v1.8 y v1.9** (Memory Inbox e integración de sistema) son precisas y están en el nivel de detalle correcto.

## Justificación del score

**68/100.** Reparto: exactitud del CLAUDE.md 70 (excelente en MCP/seguridad/v1.11, con dos zonas muertas — Ask multi-turno y Packs GUI — que son funcionalidad central, no notas al pie), README 25 (seis releases por detrás; no es "mejorable", es incorrecto), CHANGELOG 95, docs/ 65 (referencia MCP y ADR vivos; PRD/design fosilizados sin marcar), comentarios en código 80 (un docstring de seguridad desmentido por su propio fichero), pendientes 60 (uno cerrado que sigue anunciado, uno anunciado que ya está hecho).

No baja de 60 porque lo verificable a granel —cifras, constantes, nombres de tipo, invariantes de seguridad— resiste la comprobación casi sin excepciones, que es donde un documento de este tamaño suele desangrarse. No sube de 70 porque las dos zonas muertas no son detalles: quien lea la sección Ask escribirá contra una API inexistente, y ese es el modo de fallo exacto que el encargo pedía cazar.

## Dudas y asunciones

1. **No ejecuté `swift test`** (auditoría read-only, y el toolchain local requiere el `.xctoolchain` según la memoria del proyecto). El 728 es el recuento estático de anotaciones `@Test`, que coincide con la cifra del doc y con la del CHANGELOG. Asumo que ninguna está desactivada ni parametrizada de forma que el runner reporte otro número.
2. **68 ficheros en `Tests/PastureKitTests/`, no 77 "suites".** Un fichero puede declarar más de un `@Suite`; no los conté por separado porque la afirmación auditada del doc es el número de tests, no el de suites.
3. **La QA visual de la v1.10 la doy por abierta** porque no hay evidencia en el repo de que se cerrara. Es un pendiente que vive en un PR de GitHub y no lo consulté (read-only sobre el repo local).
4. **No juzgo si desacoplar `MCPProtocol.serverVersion` de la versión de la app es correcto** — hay un test que lo fija deliberadamente, así que lo trato como decisión, y el hallazgo es solo que ningún documento la explica.
5. Asumí que `docs/prd/` y `docs/design/` son **archivo histórico por diseño** y no documentación viva; por eso el drift de sus fechas es menor y no alto. Si se pretende que describan el estado actual, suben a alto.
6. No audité `streamdeck-whisper/` ni `.superpowers/`: quedan fuera de lo que el CLAUDE.md dice describir.
