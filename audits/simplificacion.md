# Simplificación / deuda — score 88/100

## Resumen (3 líneas)
El código está inusualmente limpio para 11.713 líneas: **cero TODO/FIXME/HACK**, **cero casos de enum sin usar**, ninguna función por encima de 69 líneas y sólo **3 símbolos públicos que únicamente tocan los tests**. El hallazgo que el encargo anticipaba como más gordo —el Context Compiler como "funcionalidad fantasma"— **es falso**: las 1.031 líneas están conectadas a la GUI por tres vías (pestaña Settings, menú/atajo y auto-resync); lo que está muerto es la frase del `CLAUDE.md` que dice lo contrario. Lo realmente eliminable son **~36 líneas de producción** y **~320 líneas de ficheros que no pintan nada en este repo**.

## Código muerto confirmado

| Símbolo | file:line | Usos reales en producción | Líneas que se ahorran |
|---|---|---|---|
| `Proposal.autoApproved` | `Sources/PastureKit/Proposal.swift:45,59,72` | **0** (sólo declaración, parámetro de init y asignación) | 4 en Sources + 16 en `ProposalTests.swift:75-90` |
| `AIClient.buildRequest(question:context:model:apiKey:)` | `Sources/PastureKit/AIClient.swift:218-221` | **0** | 9 (docstring incluido) |
| `PastureLayout.fileRowHorizontalPadding` | `Sources/Pasture/DesignTokens.swift:334` | **0** (1 sola ocurrencia en todo el repo) | 1 |
| `PastureLayout.tokenBadgeRadius` | `DesignTokens.swift:340` | **0** | 1 |
| `PastureLayout.toastRadius` | `DesignTokens.swift:393` | **0** | 1 |
| `PastureLayout.askInputMinHeight` | `DesignTokens.swift:412` | **0** | 1 |
| `PastureLayout.askInputMaxHeight` | `DesignTokens.swift:413` | **0** | 1 |
| `PastureLayout.askContextBarHeight` | `DesignTokens.swift:415` | **0** | 1 |
| `PastureLayout.cornerRadiusLarge` | `DesignTokens.swift:433` | **0** | 1 |
| `SecretScanResult.kinds` | `Sources/PastureKit/SecretScanner.swift:56` | **0** (19 usos, todos en tests) | 1 + doc |
| `SidebarTree.CollectionNode.isUncategorized` | `Sources/PastureKit/SidebarTree.swift:30` | **0** (2 usos, ambos en tests) | 1 + doc |

**Total producción: ~22 líneas de símbolos + ~14 de docstrings = ~36.**

Dos matices que importan:

1. **`autoApproved` no aporta la compatibilidad que su comentario promete.** El `Codable` sintetizado **ignora las claves desconocidas al decodificar**, así que borrar el campo no rompe ningún `.json` ya escrito en `.inbox/`. Lo único que se pierde es la capacidad de *volver a escribir* la clave, que nadie escribe. Es dead code puro con coartada.
2. **El docstring de `buildRequest(question:context:)` miente**: dice *"Used by the Settings 'test connection' path (no history)"* (`AIClient.swift:215-217`). Falso — `SettingsView.swift:439` llama a `AIClient.shared.ask(question:context:…)`, que es un método distinto (`AIClient.swift:58`) y **ése sí está vivo**. El overload de `buildRequest` es un gemelo de 2 líneas del cuerpo de `ask(question:context:)`, mantenido sólo para que 10 tests no tengan que escribir `ChatMessage(role:.user, …)`.

## Funcionalidad implementada pero no conectada a la GUI

**Ninguna. El "Context Compiler fantasma" no existe — la doc está desactualizada.**

Medido: **1.031 líneas** entre los 7 ficheros de PastureKit (`CompilePack` 95, `PackStore` 57, `PackCompiler`+`PackEmitter` 60, `PackWriter` 158, `PackSyncEngine` 92, `SyncMarker` 96, `TargetValidator` 51) y los 3 de la GUI (`PackSyncRunner` 48, `PacksSettingsTab` 194, `PackEditorView` 180). Está enchufado por **cuatro caminos independientes**:

- `Sources/Pasture/SettingsView.swift:15` → `PacksSettingsTab()` (pestaña completa con CRUD, editor y botón de sync).
- `Sources/Pasture/ContentView.swift:65-70` → notificación `.syncAllPacks` → `PackSyncRunner.syncAll()`.
- `Sources/Pasture/MenuBarView.swift:228` → mismo runner desde el popover, con `hasPacks` reactivo (`MenuBarView.swift:13,46`).
- `Sources/Pasture/MDFileManager.swift:184-185` → auto-resync tras cambios en el vault.

La frase de `CLAUDE.md` —*"Context Compiler (v1.6, PastureKit core — **GUI wiring is a follow-up**)"*— es deuda **documental**, no de código. Corregirla es la acción; borrar código sería un error.

**Fase B de Local sources: también conectada.** `MDFileManager+Sources.swift:37` (`refreshSources`) se invoca desde `ContentView.swift:71-73` vía la notificación `.refreshSources` que emite `PastureApp.swift:38` (Cmd+Shift+R). `SourceValidator` (`+Sources.swift:45,98`) y `SourceImportDecision` (`:84`) se usan dentro de ese flujo. Aquí la doc **sí** acierta.

Lo mismo verificado para el resto de módulos recientes, todos con consumidor en `Sources/Pasture`: `ConversationComposer`/`AskConversation` (`AskViewModel`), `QuickCapture`/`HeadlessFeed` (`HeadlessActions`), `PastureURLCommand` (`AppDelegate`), `SidebarTree`/`ContextLimit` (`SidebarView`). `ConversationTruncator` se usa dentro de `AskConversation.swift` — no es huérfano.

## Duplicación

### 1. `applyPreset` duplicado entre ventana y menu bar — **~9 líneas**
`Sources/Pasture/ContentView.swift:415-424` y `Sources/Pasture/MenuBarView.swift:235-243` son idénticos salvo **una línea**: `if files.count == 1 { activeFile = files.first }`, que sólo existe en la ventana principal.

Propuesta: mover el cuerpo a `FeedService` (que ya es el sitio compartido entre ambas vistas) como `applyPreset(_:fm:) -> Set<MDFile>`, devolviendo los ficheros para que `ContentView` decida sobre `activeFile`. Ahorro: 9 líneas, y sobre todo una fuente única para el texto del toast, que hoy hay que cambiar en dos sitios.

### 2. `syncAllPacks` duplicado — **~5 líneas**
`ContentView.swift:65-70` y `MenuBarView.swift:226-231` ejecutan el mismo `Task { let summary = await PackSyncRunner.syncAll(); feedService.showFeedback(summary) }`. El mismo tratamiento que el anterior lo cierra.

### 3. Los 8 namespaces de UserDefaults — **NO abstraer** (recomendación en contra)
Medido: `ExportSettings` 56 + `AISettings` 52 + `FeedFormatSettings` 21 + `IntegrationSettings` 47 + `SelectionPresetStore` 62 + `PackStore` 57 + `CollectionExpansionStore` 37 + `QuestionHistory` 28 = **360 líneas**.

El patrón compartido real es de 2 líneas por par get/set (`defaults.data(forKey:)` + `JSONDecoder().decode`, y su inverso). Un helper genérico `CodableDefault<T>` ahorraría en el mejor caso ~40 líneas de las 360 — el otro 89 % es firma pública, nombre de clave, notificación propia, y reglas específicas (el tope de 100 presets en `SelectionPresetStore`, el de 50 packs en `PackStore:18`, el `upsert`/`rename` que sólo tiene uno, la regla pura de `effectiveExpansion` que sólo tiene otro). **Introducir la capa costaría más comprensión de la que ahorra en líneas**, y contradice la regla de la casa. Lo dejo consignado como medido y descartado, no como pendiente.

### 4. Fixtures de test reinventadas — **~30 líneas**
`Tests/PastureKitTests/TestHelpers.swift` ya ofrece `makeTempDirectory()` (36 usos) y `makeIsolatedUserDefaults()` (13 usos). Pero **15 sitios construyen el directorio temporal a mano** (`MCPDispatcherTests:11,150,171`, `MCPPromptsTests:14,197`, `MCPResourcesTests:14,167`, `MCPStalenessTests:12,80`, `MCPToolsTests:14`, `MCPEndToEndTests:13`, `MCPVaultSecretStatTests:11`, `MCPProposalToolsTests:13`, `MCPProposalDispatchTests:12`, `HeadlessFeedTests:9`) y **6 crean su propio suite de UserDefaults a mano** (`AISettingsTests`, `CollectionExpansionStoreTests`, `ExportSettingsTests`, `FeedFormatSettingsTests`, `IntegrationSettingsTests`, `SelectionPresetTests`), reimplementando lo que el helper ya hace — incluido el `removePersistentDomain` defensivo, que quien lo escribe a mano puede olvidar.

Ahorro ~30 líneas, pero el valor es que el `UUID` de aislamiento y la limpieza defensiva dejen de depender de que cada suite se acuerde. Prioridad baja.

(Los 2 usos de `temporaryDirectory` en `FileLibraryTests:103,135` **no** entran aquí: construyen a propósito una ruta que no existe.)

## Complejidad injustificada

**Nada que proponer.** Medido con un recorrido de llaves sobre las 96 funciones de `Sources`: la más larga es `MCPDispatcher.handle` con **69 líneas**, y es un `switch` plano de despacho JSON-RPC — exactamente la forma en que debe leerse un dispatcher. Le siguen `MCPPrompts.get` (65), `CSVConverter.parse` (57), `FrontmatterParser.parse` (55) y `AskViewModel.send` (55). Ninguna tiene anidamiento que justifique tocarla, y las cuatro últimas son parsers/máquinas de estado donde partir en trozos empeora la lectura.

Único apunte menor, y no lo propongo como cambio: `DOCXConverter.attributedStringToMarkdown` (53 líneas, `DOCXConverter.swift:47`) es la función con más densidad de decisión del repo (pesos de fuente, detección de encabezados, inline). Está bien escrita; si algún día da un bug, ése es el sitio a partir — hoy no.

## Restos y ficheros huérfanos

### `streamdeck-whisper/` — **278 líneas, intruso confirmado**
`streamdeck-whisper/INSTALL.md` (117), `whisper-ptt.sh` (99), `hammerspoon-snippet.lua` (62). Es un botón push-to-talk de Stream Deck con whisper.cpp y Hammerspoon: **no tiene ninguna relación con Pasture**, ni Swift, ni referencia desde el proyecto. Entró en un único commit `137986d auto-sync: iMac-31155 2026-09-04 09:28` — el mismo patrón de `git add -A` automático que en este ecosistema ya coló `alfred-memory.db` en prompt-lab/rentabano/worklog y un `.venv` como symlink en moneySeve. **Está trackeado** (`git ls-files` lo lista) y **no** cubierto por `.gitignore`.
Propuesta: `git rm -r --cached streamdeck-whisper` y moverlo a su propio sitio (o a `~/Desktop/Claude/archive/`). No es borrado destructivo: el contenido se conserva fuera del repo.

### `.superpowers/sdd-cifix-report.md` — **42 líneas**
Informe de una sesión de arreglo de CI, trackeado en git. `.superpowers/` no está en `.gitignore`. Es el artefacto de una herramienta de proceso, no del producto.

### Lo que NO es resto
- **0 ocurrencias** de `TODO`, `FIXME`, `HACK`, `XXX` en `Sources`, `Tests` y `scripts`. Notable.
- **0 bloques de código comentado** encontrados.
- `scripts/` sólo tiene `bundle.sh` y `generate_icon.py`, ambos vivos.
- `docs/` (16 ficheros: ADR, PRD, diseños, threat models, planes) es historial deliberado del proyecto, no basura.
- `dist/` (44 MB) y `.build/` (1,5 GB) están correctamente gitignorados. No son deuda del repo, pero el `.build` es la razón por la que este directorio ocupa lo que ocupa en disco.

## Falsos positivos descartados

- **Context Compiler (1.031 líneas).** Era el candidato estrella del encargo y **no procede**: cuatro puntos de entrada en la GUI, verificados por grep. La doc mentía, el código no.
- **Fase B de Local sources.** Conectada vía Cmd+Shift+R → `.refreshSources` → `ContentView.swift:71`.
- **`DOCXConverter.convertAttributedString`** (`DOCXConverter.swift:40`, 6 líneas, 11 usos y todos en tests). Técnicamente es solo-tests, pero **no propongo borrarlo**: es la única forma de ejercitar el conversor sin fabricar un `.docx` binario real en el repo. Es una costura de test deliberada, no una abstracción sobrante. Lo mismo, con menos convicción, se puede decir de `buildRequest(question:context:)` — pero ahí el equivalente vivo (`ask(question:context:)`) ya existe y el docstring está mal, así que sí lo propongo.
- **`errorDescription`** en `ConversionError`, `KeychainError`, `AIClientError`, `SourceError`. Aparece "sin llamantes" en cualquier barrido: es la conformidad con `LocalizedError`, la invoca el runtime.
- **`applicationDidFinishLaunching`, `applicationWillTerminate`, `applicationShouldTerminateAfterLastWindowClosed`, `applicationShouldHandleReopen`** (`AppDelegate.swift:8,75,81,85`) y **`transferRepresentation`** (`ContentTypes.swift:29`): conformidades con `NSApplicationDelegate` y `Transferable`, invocadas por AppKit/SwiftUI.
- **`from defaults: UserDefaults = .standard`** repetido en los 8 namespaces. Parece un parámetro por defecto decorativo; **se sobrescribe de verdad** en las suites de tests (19 sitios). Es inyección de dependencia legítima y barata.
- **`Sources/Pasture/TemplateEngine.swift`** (4 líneas). Parece un fichero vacío; es el `@_exported import PastureKit` que evita 40 imports en el target de la app.
- **Los ~40 tipos anidados "usados en un solo fichero"** (`SyncSummary`, `ParseResult`, `Parsed`, `Resolution`, `TargetResult`, `Capabilities`, `Item`…). Son tipos de retorno de la función que los acompaña: vivir en un solo fichero es su forma correcta, no un síntoma.
- **Los 8 namespaces de UserDefaults como duplicación.** Medida arriba: la abstracción no se paga.

## Justificación del score

**88/100.** No es una nota de cortesía; sale de restar sobre lo medido.

Lo que suma (base alta): cero TODO/FIXME en 19.368 líneas entre fuentes y tests; cero casos de enum muertos sobre el total de casos de `PastureKit`; sólo 3 símbolos públicos solo-tests y los 3 defendibles o de 1 línea; ninguna función que pida trocearse; cero abstracciones de un solo uso de las que se buscaban (ni un protocolo con una sola conformidad, ni una capa con un llamante que no se justifique); y la disciplina de "sin dependencias" intacta.

Lo que resta:
- **−5, la deuda documental que induce a error.** Que `CLAUDE.md` declare "GUI wiring is a follow-up" sobre 1.031 líneas ya conectadas es peor que un comentario obsoleto: manda a cualquier auditoría —ésta incluida— a buscar código fantasma donde no lo hay, y podría llevar a alguien a "terminar" lo que ya está hecho. El docstring de `buildRequest` falla del mismo modo a pequeña escala.
- **−4, el intruso.** 278 líneas de un proyecto ajeno viviendo en el repo por un `git add -A` automático. No hace daño al binario, pero es exactamente el modo de fallo que este ecosistema ya ha pagado varias veces.
- **−2, código muerto real.** ~36 líneas, casi todas de una línea. Poco, pero es lo que hay.
- **−1, la duplicación de `applyPreset`/`syncAllPacks`** entre las dos vistas, con `FeedService` ya creado al lado justo para eso.

No bajo más porque ninguno de los hallazgos afecta al comportamiento del producto ni a su seguridad: es higiene.

## Dudas y asunciones

1. **Asumo que "usos reales" excluye tests**, según la instrucción explícita del encargo. Con ese criterio, `SecretScanResult.kinds` (19 usos en tests) es muerto. Si el dueño considera que una API pública de `PastureKit` ejercitada por tests está viva por serlo, esos 3 símbolos salen de la lista y el ahorro de producción baja a ~28 líneas.
2. **No he compilado ni ejecutado los tests** (encargo de sólo lectura). Todo el análisis es estático sobre el árbol de trabajo de la rama `feat/v1.11-sidebar-tree-simplify`. Borrar los símbolos que propongo exige, como mínimo, retocar los tests que los usan (16 líneas en `ProposalTests`, 10 llamadas en `AIClientTests`).
3. **Asumo que `streamdeck-whisper/` no pertenece al proyecto.** Es una lectura de su contenido, no una confirmación del dueño: puede ser una herramienta personal que se quiso versionar aquí a propósito. Por eso propongo `git rm --cached` + mover, nunca `rm`.
4. **El recuento de líneas de función** viene de un recorrido de llaves, no del AST de Swift; en funciones con llaves dentro de cadenas podría desviarse un par de líneas. Ninguna conclusión depende del dígito exacto.
5. **No he auditado la duplicación dentro de `Tests/`** más allá de las fixtures, por dos razones: la instrucción prioriza `Sources`, y la repetición literal en tests suele ser una virtud (cada test legible por sí solo), no deuda.
6. **`audits/PLAN.md` ya existía** en el directorio cuando empecé; no lo he tocado ni leído como insumo.
