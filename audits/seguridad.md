# Seguridad — score 84/100

## Resumen

Auditoría read-only del código real (no del documento) contra los invariantes SEC-1..SEC-9 y SEC-M1..SEC-M15 declarados en `CLAUDE.md`. La arquitectura de seguridad se sostiene: la doble capa de validación de rutas es real y está aplicada **en todos** los caminos de I/O del MCP, el `.inbox/` es genuinamente inalcanzable por las tools de lectura, el promotor es el único write-path al vault visible y las credenciales nunca salen del Keychain.

Los dos hallazgos que bajan la nota no son fallos de arquitectura sino **huecos en defensas declaradas**: el detector de secretos no reconoce el formato de clave de OpenRouter —uno de los dos proveedores que la propia app soporta— y `PackWriter` trata un destino no-UTF-8 como inexistente, sobrescribiéndolo sin marcar conflicto y sin backup.

No hay secretos hardcodeados, no hay `print(` a stdout desde código alcanzable por el MCP, y el árbol de dependencias externas es literalmente vacío.

---

## Hallazgos críticos

Ninguno.

---

## Hallazgos altos

### A-1. `SecretScanner` no detecta claves de OpenRouter (`sk-or-v1-…`) — el propio proveedor de la app

**Evidencia:** `Sources/PastureKit/SecretScanner.swift:137-160` (catálogo completo de patrones).

Los dos patrones que podrían cubrirla son:
- `sk-proj-[A-Za-z0-9_-]{20,}` (línea 156) — el literal `proj-` no casa.
- `sk-[A-Za-z0-9]{20,}` (línea 159) — la clase exige alfanuméricos **inmediatamente** tras `sk-`; en `sk-or-v1-…` el tercer carácter es un `-`, que corta el match a `or` (2 caracteres, por debajo del `{20,}`).

Resultado: una clave de OpenRouter en una nota **no se detecta**. Y `AIProviderKind.openRouter` existe (`AIProvider.swift`), la app guarda esa clave en el llavero (`AISettings.swift:7`, `keychainKeyOpenRouter`) y el usuario que la pega en una nota de contexto es exactamente el escenario que el escáner existe para cubrir.

**Por qué importa:** el escáner no es cosmético, es un **gate**:
- `HeadlessFeed.build` línea 43: `guard scan.isEmpty else { return .secretsDetected }` — BLOQUEA. Con una clave de OpenRouter, no bloquea.
- `PackWriter.write` líneas 74-76: `hasSecrets && !secretsAllowed` → `.secretsBlocked`. Con una clave de OpenRouter, la escribe en el `CLAUDE.md` del repo del usuario, que acabará commiteado.
- `FeedService.guardSecrets`: el diálogo con default Cancel no llega a aparecer.

Huecos adicionales del mismo catálogo, menos graves pero del mismo tipo: Google API keys (`AIza[0-9A-Za-z_-]{35}`), Stripe (`sk_live_…`/`rk_live_…` — llevan guion **bajo**, que `sk-` no cubre), tokens de GitLab (`glpat-`), y asignaciones genéricas del estilo `api_key = "…"`.

**Fix propuesto:** añadir al array de `patterns` (el orden importa: antes del genérico `sk-`):
```swift
Pattern(kind: .openAIKey, regex: compile("sk-or-v1-[A-Za-z0-9]{20,}")),
Pattern(kind: .openAIKey, regex: compile("sk_(live|test)_[A-Za-z0-9]{20,}")),
Pattern(kind: .openAIKey, regex: compile("AIza[0-9A-Za-z_-]{35}")),
```
Mejor aún: una familia nueva `openRouterKey` con su `displayName`, para que el aviso nombre el proveedor correcto. **Esfuerzo: 30 min** (3 líneas + un test por familia; el test debe construir el literal por concatenación, gotcha ya documentado de GitHub Push Protection).

---

### A-2. `PackWriter` sobrescribe un destino ilegible como UTF-8 sin conflicto y sin backup

**Evidencia:** `Sources/PastureKit/PackWriter.swift:66-90`.

```
66    let existing = try? String(contentsOf: request.targetURL, encoding: .utf8)
67    let state = SyncMarker.state(existingFileContent: existing)
70    if state == .conflict && !request.overwriteConflict { return .conflict }
79    if let existing { ... backup ... }
90    try Data(composed.utf8).write(to: request.targetURL, options: .atomic)
```

Si el fichero destino existe pero **no es UTF-8 válido** (un binario, un `.md` en Latin-1 con acentos, un fichero con un byte corrupto), `try?` devuelve `nil`. Entonces:
- `SyncMarker.state(nil)` → `.targetMissing` (`SyncMarker.swift:92`), **no** `.conflict`.
- El gate de conflicto de la línea 70 no dispara.
- `if let existing` de la línea 79 no entra → **no se hace backup**.
- La línea 90 lo sobrescribe.

**Por qué importa:** el docstring del propio módulo (líneas 4-14) declara que su modelo de amenaza es «la DESTRUCCIÓN de trabajo ajeno» y que nunca sobrescribe sin `overwriteConflict`. Aquí un fichero existente del repo del usuario se destruye sin diálogo, sin marca de conflicto y sin copia de seguridad — el único caso del módulo donde las tres defensas fallan a la vez. No hace falta un atacante: basta apuntar un pack a una ruta equivocada.

**Fix propuesto:** distinguir «no existe» de «existe pero no se puede leer»:
```swift
let fileExists = FileManager.default.fileExists(atPath: request.targetURL.path)
let existing = try? String(contentsOf: request.targetURL, encoding: .utf8)
if fileExists && existing == nil {
    return .conflict   // ilegible ⇒ conflicto, nunca targetMissing
}
```
y, si se fuerza, hacer el backup en `Data` en vez de en `String`. **Esfuerzo: 1 h** (el cambio es de 4 líneas; el test necesita escribir bytes inválidos, p. ej. `Data([0xFF, 0xFE, 0x00])`).

**Mismo patrón, menor impacto, en otro sitio:** `Sources/Pasture/MDFileManager+Sources.swift:83-90` — `SourceImportDecision.decide(existingContent: nil)` devuelve `.create`, así que una nota del vault ilegible como UTF-8 se sobrescribe aunque fuera «no generada» (la protección `skipUnlinked` no llega a evaluarse). Queda dentro del vault y solo afecta a `.md`, de ahí la severidad menor, pero el fix es el mismo.

---

## Hallazgos menores

### M-1. `pasture://new` escribe en el vault sin confirmación ni marca de procedencia

**Evidencia:** `Sources/PastureKit/PastureURLCommand.swift:29` (`case "new": return .new(...)`), despachado en `AppDelegate.application(_:open:)` → `HeadlessActions` → `Sources/Pasture/HeadlessActions.swift:97-99` (`createDirectory` + `write`).

El parser es correcto (rechaza todo lo no reconocido, `QuickCapture` sanea el nombre y `FileLibrary.deduplicatedURL` evita pisar nada). Pero cualquier proceso local —o una página web, si macOS no interpone su diálogo de scheme— puede depositar contenido arbitrario en `Captures/`, que después se alimenta a un modelo. Es un vector de **prompt injection almacenada**, y a diferencia de las propuestas MCP la nota resultante **no lleva frontmatter de procedencia**: nada la distingue de una nota escrita por el usuario.

**Fix propuesto:** escribir `origin: url-scheme` en el frontmatter de las capturas por URL (reutilizando `FrontmatterWriter.setting`, que ya colapsa a una línea), igual que `ProposalPromoter` hace con `origin: agent`. **Esfuerzo: 30 min.** Opcionalmente, un toggle en Settings → General para desactivar el scheme (los hotkeys ya son opt-in; el scheme no).

### M-2. TOCTOU acotado en `promoteAppend`

**Evidencia:** `Sources/PastureKit/ProposalPromoter.swift:76-84` — se lee `current`, se compara su hash con `proposal.targetHash`, y se escribe `current + "\n\n" + payload`.

El `targetHash` hace bien su trabajo declarado: detecta que el destino cambió **entre la propuesta y la aprobación**, que es la ventana larga (días). Pero entre la línea 76 y la 84 hay una ventana de milisegundos en la que una escritura externa (el editor del usuario guardando) se pierde en silencio, porque se reescribe el fichero entero desde el `current` ya leído. Es un TOCTOU real, no una fuga de seguridad: el peor caso es perder una edición concurrente, no escapar del vault. **Teórico en la práctica** (requiere que el usuario guarde en su editor exactamente en ese instante). Cerrarlo de verdad exigiría `O_EXCL`/flock; no compensa.

### M-3. `fallbackErrorLine` interpola un id de tipo string sin escapar

**Evidencia:** `Sources/PastureKit/MCPDispatcher.swift:139-143`.

```swift
case .string(let value): idFragment = "\"\(value)\""
```
Un `id` con comillas o barras invertidas produciría una línea JSON malformada, rompiendo el framing. **Teórico**: esta rama solo se alcanza si `Encodable.mcpLine()` lanza, cosa que los tipos del proyecto no pueden hacer (el propio comentario de las líneas 120-121 lo razona). Fix: serializar el id con `JSONEncoder` también en el fallback, o escapar `"` y `\`. **Esfuerzo: 15 min.**

### M-4. `mask()` revela 11 de los 20 caracteres de una AWS access key

**Evidencia:** `Sources/PastureKit/SecretScanner.swift:235-245` — 7 primeros + 4 últimos.

Para una `AKIA` + 16 (20 caracteres exactos, el patrón de la línea 149) eso es el 55 % del valor. **Hoy no filtra nada**: verificado por grep que `maskedSnippet` no se usa fuera de `SecretScanner.swift` — ni `summaryLines()` ni `alertMessage` ni los warnings del MCP lo incluyen, todos reportan familia + fichero. Es un riesgo latente para el día que alguien lo muestre. Fix: escalar el enmascarado con la longitud (revelar como mucho un tercio). **Esfuerzo: 15 min.**

### M-5. `force` acopla dos consentimientos distintos en un solo botón

**Evidencia:** `Sources/Pasture/PacksSettingsTab.swift:152-158` y `PackSyncRunner.swift:32` — el mismo booleano alimenta `overwriteConflicts` **y** `secretsAllowed`.

Un usuario que solo quiere sobrescribir un destino que editó él mismo autoriza de paso escribir secretos en él. Atenuante importante: la alerta lo declara literalmente («This overwrites targets edited outside Pasture (a backup is kept) **and writes files even if they contain possible secrets**», línea 41) y el default es Cancel, así que es consentimiento informado, no sorpresa. Fix: dos flags y dos botones. **Esfuerzo: 1 h.** Prioridad baja.

### M-6. `collection` de `propose_note` no limita la profundidad

**Evidencia:** `Sources/PastureKit/MCP/MCPTools.swift:156-162`. `collection` se concatena y se valida con `MCPPathResolver` (que rechaza `..`, absolutas y componentes ocultos), pero `"a/b/c/d"` pasa. `ProposalPromoter.promoteNote:42` hace `createDirectory(withIntermediateDirectories: true)`, así que un agente puede crear una jerarquía arbitrariamente profunda dentro del vault. No escapa del vault y `FileLibrary` solo enumera un nivel, de modo que el efecto es ensuciar el disco con directorios invisibles en la UI. Fix: rechazar `collection` con `/`. **Esfuerzo: 15 min.**

---

## Invariantes verificados como CORRECTOS

Cada uno comprobado leyendo el código, no la documentación.

**Rutas (SEC-M1 / SEC-M2 / SEC-9 / AC#4)**
- `MCPPathResolver.resolve` aplica de verdad las dos capas: rechazo de absolutas (`:25-27`), rechazo de **cualquier** componente oculto (`:33-35`, que de paso cubre `.` y `..`), `PathValidator.isInside` sobre el candidato (`:40`) y revalidación tras `resolvingSymlinksInPath()` contra la base **también resuelta** (`:45-49`). Resolver la base es el detalle que suele faltar y aquí está.
- **Todos** los caminos de I/O del MCP pasan por él, sin excepción: `readFile` (`MCPTools.swift:311`), `resolveFileList` (`:481`), `proposeNote` (`:160`), `proposeAppend` (`:194`), `MCPResources.read` (`:91`), `ProposalPromoter.promoteNote` (`:36`), `promoteAppend` (`:72`), `MDFileManager.appendTargetContent` (`:131`). No encontré un solo `contentsOf:`/`write(to:)` del lado MCP que lo esquive.
- `resolveCollection` no usa el resolver pero tampoco lo necesita: enumera con `FileLibrary.realSubdirectories` y compara por `lastPathComponent`, así que no hay path controlado por el cliente.
- `TargetValidator` es el inverso correcto y **cubre el symlink colgante** (`:40-48`, con `destinationOfSymbolicLink` explícito porque `resolvingSymlinksInPath` no resuelve un enlace roto). Ese caso es justo el que se escapa de una implementación ingenua.
- `PresetResolver.resolve` descarta las rutas que escapan y las cuenta como rechazadas (`:24-28`); `missingPaths` las reporta al usuario en vez de tragárselas.
- `MDFileManager` valida con `isInsidePasture` **antes** de cada mutación: `save:195`, `create:244`, `rename:264,275`, `delete:293`, `createCollection:309`, `moveFile:325,330`, `renameCollection:350`, `deleteCollection:368`, e incluso antes del `NSWorkspace.shared.open` (`ContentView.swift:492` tras el guard).

**Servidor MCP**
- **SEC-M11 se cumple.** `MCPTools.run` (`:124-127`) usa `case "propose_note" where config.allowProposals`; sin el flag cae en `default` → «tool desconocida», y `catalog(includingProposals:)` (`:78`) no las lista. `MCPServerConfig.fromEnvironment:41` exige el valor exacto `"1"`.
- El write-path habilitado escribe **solo** en `.inbox/` (`MCPTools.inboxRoot:136-138`) y siempre con nombre `<uuid>.md`/`<uuid>.json` (`ProposalStore:108-114`) — el agente no controla el nombre del fichero que se escribe.
- **El `.inbox/` es genuinamente inalcanzable desde las tools de lectura**, por dos vías independientes: `FileLibrary` enumera con `.skipsHiddenFiles` (`FileLibrary.swift:38,54`) y `MCPPathResolver` rechaza componentes ocultos (`:33`). Ni `read_file`, ni `feed_context`, ni `search`, ni `resources/read` pueden alcanzarlo.
- Caps reales y aplicados: `MCPLineReader` descarta líneas >10 MB **sin acumularlas** (`:49-61`, con modo descarte que no hace crecer el buffer, `:100-111`); `search` acota query a 1.000 y resultados a 100 (`MCPTools:381,397`) y lee cada fichero acotado a 2 MB (`:416`); `read_file`/`resources/read` comprueban el **tamaño en disco antes de leer** y otra vez sobre los bytes cargados (`MCPTools:320,329`; `MCPResources:99,108`); `prompts/get` acota cada argumento a 100.000 chars (`MCPPrompts:159,166`) y el render a 25 MB (`:181`); propuestas ≤1 MB (`MCPTools:151,184`) y ≤50 pendientes (`:220`).
- **SEC-M7 verificado por grep exhaustivo**: el único `standardOutput` de todo el árbol está en `Sources/pasture-mcp/main.swift:22-23`. Cero `print(`, cero `NSLog` en `PastureKit/` y `pasture-mcp/`. Los logs van a `FileHandle.standardError` (`ProposalStore:121`, `MCPPrompts:202`, `SystemNotifier:18`, `GlobalHotkeyManager:96`).
- **SEC-M12**: `MCPDispatcher.handle` no lanza en ninguna rama; `id: null` explícito → -32600 (`:57-59`), JSON malformado → -32700 (`:51-53`), método desconocido → -32601 (`:108-112`). Fallos de tool → `isError` dentro de `result`; fallos de `resources/read` y `prompts/get` → error de protocolo. Los dos canales están efectivamente separados.
- **SEC-M6**: `feed_context` ensambla con `ContextBuilder.build` y **nunca** llama a `TemplateEngine.render` (`MCPTools:449`, verificado por grep: `TemplateEngine` solo aparece en `MCPPrompts`).
- **Inyección de frontmatter vía `clientInfo.name` — cerrada en dos capas independientes**: `ClientInfo.init` colapsa CR/LF y acota a 200 chars en el ingest (`MCPDispatcher:29-35`), y `FrontmatterWriter.setting` vuelve a colapsar el value antes de escribir (`:29,60-65`). Un `name` con `\n---\n` no puede romper el bloque ni inyectar claves.
- **Suplantación de metadatos por el agente — cerrada**: `ProposalPromoter.provenanceFrontmatter:109` **despoja primero** las `recognizedKeys` (`review_after`, `ttl`, `last_reviewed`, `source`, `generated` — `FrontmatterParser.swift:45`) del payload y solo después escribe `origin: agent`. Una propuesta no puede evadir la cola de frescura, marcarse como generada ni disparar una re-importación de `source:`. Probé el caso del payload con bloque frontmatter sin cerrar: el bloque nuevo se antepone y el antiguo queda inerte en el cuerpo.
- Dedupe por `payloadHash + destinationKey` sobre lectura **cruda** sin efectos secundarios (`ProposalStore.contains:83-87` usando `loadRaw`, no `loadPending`) — correcto: el dedupe no debe depender del reloj.
- TTL de 14 días aplicado al listar, con reloj inyectado (`ProposalStore.loadPending:40-51`).
- El orden de escritura y de borrado del par `.md`/`.json` está razonado y es el correcto en ambos sentidos (`:29-32` y `:97-102`): el modo de fallo peor —un `.json` sin payload que reaparece como propuesta fantasma— es imposible.

**Airlock humano (Memory Inbox)**
- `ProposalPromoter` es efectivamente el único write-path al vault visible; verificado por grep de escrituras: ningún fichero de `Sources/PastureKit/MCP/` escribe fuera de `.inbox/`.
- No hay aprobación en lote: `ReviewInboxSheet` renderiza un botón «Approve» por propuesta (`:164`) dentro de un `ForEach` (`:64`). El diff se muestra **antes** y el **payload propuesto se muestra íntegro** (`:199,203`) — lo único truncado es el contenido actual del destino (`:194`, `maxPreviewChars = 20.000`), que es contexto, no lo que se va a escribir. Correcto.
- `hashMismatch` escala a una alerta de confirmación explícita (`:73-84`), no se sobrescribe sola. «Reject» también confirma (`:96-106`).

**Credenciales y red**
- Las claves viven **solo** en el llavero: `AISettings.loadAPIKey/saveAPIKey` delegan en `KeychainStore` (`:29-35`); en `UserDefaults` solo van `aiProvider` y `aiModelID` (`:4-5`). Verificado que no hay ninguna escritura de la clave a defaults.
- `KeychainStore.save` crea con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (`:25`). El `SecItemUpdate` de la rama de actualización no toca el atributo, que se preserva — correcto.
- La clave **no aparece en ningún mensaje de error**: `AIClientError` (`AIClient.swift:13-33`) no interpola nunca `apiKey`; ante un 401 devuelve un literal fijo (`:284`). El cuerpo de error del proveedor se acota a 2.000 bytes al leerlo (`:304`) y a 200 chars al mostrarlo (`:287`).
- Ambos endpoints son `https://` literales y constantes (`:180-181`); no hay ATS relajada (grep de `NSAppTransportSecurity`/`NSAllowsArbitraryLoads` en `scripts/bundle.sh`: cero coincidencias), ni delegados de `URLSession`, ni override de validación de certificado.
- La clave se pasa por cabecera, nunca por URL ni por query (`:194,198`). En la UI se introduce con `SecureField` (`SettingsView.swift:328`).
- Autoclear del portapapeles a los 60 s comprobando `changeCount` para no borrar algo que el usuario copió después (`FeedService.swift:190-198`).

**Otros**
- **Cero dependencias externas confirmado**: `grep -c "\.package(" Package.swift` → **0**. La superficie de CVEs de terceros es literalmente nula (SEC-M10).
- **Cero secretos hardcodeados**: grep de `sk-…`, `ghp_…`, `AKIA…`, `password =`, `secret = "` sobre `Sources/` y `scripts/` → una única coincidencia, y es un falso positivo (`"ask-conversation"` en `AskViewModel.swift:132`).
- `TemplateEngine` tiene los tres caps declarados y son reales: `maxNestingDepth = 16` (`:54`, aplicado en parser `:219` y en renderer `:318,328,338`), `maxIterations = 1.000` (`:55`, aplicado con `.prefix` en `:342`) y además un `maxOutputCharacters = 5.000.000` con presupuesto decreciente (`:59,84`) que no estaba en la lista de invariantes pero es una defensa correcta contra la expansión cuadrática.
- `SourceValidator` rechaza fuente vacía, inexistente, no-directorio y dentro del vault, con la doble comprobación de symlink (`SourceImport.swift:35-39`) — anti-ciclo correcto. Solo carpetas locales: sin red ni ejecución de comandos.
- `HeadlessFeed` **bloquea** ante secretos (`:43`), que es el equivalente conservador correcto al default-Cancel del diálogo GUI.
- `MCPResources.relativePath(fromURI:)` rechaza esquemas ajenos (`:51`) y deja `pasture:////etc` como `/etc`, que la capa siguiente rechaza por absoluta (`:53-57`) — defensa en profundidad real, no decorativa.
- `PackWriter` hace backup fuera del repo y fuera del vault (`~/Library/Application Support/Pasture/backups/`, `:22-28`), con poda a 10 y escritura atómica. Salvo por el caso de A-2, la cadena conflicto→backup→escritura funciona.

---

## Justificación del score

**84/100.** Desglose de lo restado:

- **−8, hallazgo A-1.** No es un descuido de estilo: es un gate de seguridad que no cubre el formato de credencial del propio proveedor que la aplicación integra y guarda en el llavero. La consecuencia (una clave viva escrita en un `CLAUDE.md` que se commitea) es exactamente el daño que el módulo existe para evitar.
- **−5, hallazgo A-2.** Destrucción de datos sin confirmación ni backup, en el único módulo que escribe fuera del vault, contradiciendo su propio modelo de amenaza documentado. No es explotable por un atacante remoto, de ahí que no sea crítico.
- **−3, los seis menores en conjunto.** M-1 (captura por URL sin procedencia) pesa más que el resto; M-2/M-3 son teóricos y M-4 hoy no filtra nada.

**Lo que sostiene el 84 y no un número más bajo:** busqué activamente un camino de I/O que esquivara una de las dos capas de validación y **no lo encontré** — ocho puntos de entrada distintos, todos pasando por `MCPPathResolver`. Busqué una forma de que un agente MCP escribiera en el vault visible sin humano y no la hay. Busqué la clave en logs, en `UserDefaults`, en mensajes de error y en el feed, y no está. Busqué inyección de frontmatter vía `clientInfo.name` y está cerrada por partida doble, con la defensa en el punto de ingest *y* en el de escritura. Y el `.inbox/` está protegido por dos mecanismos independientes, no por uno.

Ese nivel de defensa en profundidad —dos capas donde la mayoría de proyectos pone una, y el caso del symlink colgante de `TargetValidator`, que casi nadie contempla— indica que el modelo de amenaza se pensó antes de escribir el código, no después. Los dos hallazgos altos son huecos concretos y localizados, no grietas estructurales: ambos se cierran en menos de dos horas sin tocar la arquitectura.

---

## Dudas y asunciones

1. **Alcance**: auditoría estática sobre el árbol de trabajo de la rama `feat/v1.11-sidebar-tree-simplify` (HEAD `80a6379`). No ejecuté la aplicación, ni el servidor MCP, ni la suite de tests — la instrucción era read-only y no consta que `swift test` funcione con el toolchain por defecto de esta máquina (la memoria del proyecto indica que hay que usar la toolchain de `~/Library/Developer/Toolchains/`). Todos los hallazgos se sostienen en lectura de código con `fichero:línea` citados; A-1 lo verifiqué razonando el regex carácter a carácter, no ejecutándolo.
2. **Formato de clave de OpenRouter**: asumo `sk-or-v1-<hex>`, que es el formato público documentado. Si cambiara, el hallazgo A-1 sigue en pie en su forma general (el patrón genérico `sk-[A-Za-z0-9]{20,}` no tolera guiones dentro del cuerpo), solo cambiaría el literal del fix.
3. **No auditado**: la carpeta `Tests/` (728 tests) — auditar el código, no su cobertura, era el encargo. Tampoco revisé si existe un test que ya cubra los casos de A-1/A-2; si lo hubiera, estaría verde por vectores mal elegidos, que es un modo de fallo ya documentado en este repositorio.
4. **`scripts/bundle.sh`**: solo comprobé la ausencia de ATS relajada y la firma ad-hoc. La firma ad-hoc no aporta garantía de integridad frente a un atacante local — es una reducción de fricción de Gatekeeper, cosa que el propio `CLAUDE.md` ya declara como pendiente (notarización real). No lo cuento como hallazgo por estar ya reconocido.
5. **`pasture://` (M-1)**: asumo el peor caso razonable, que macOS no interponga su diálogo de confirmación de scheme en todos los contextos (varía por navegador y por si el scheme se ha usado antes). Si siempre lo interpusiera, M-1 baja a informativo — pero la falta de marca de procedencia en la nota resultante se mantiene con independencia de eso.
