# Arquitectura — score 78/100

## Resumen

La arquitectura de fondo es sólida y poco común: PastureKit concentra la lógica pura y testeable, el ejecutable MCP es transporte fino de verdad, la concurrencia Swift 6 está confinada en dos tipos y cada `nonisolated(unsafe)` tiene una razón declarada. No encontré ninguna carrera de memoria real.

Lo que sí encontré es un **defecto funcional crítico verificado en la barra de búsqueda de la ventana principal**: `Just(x).debounce(...)` nunca entrega valor, así que `fm.searchQuery` jamás recibe un texto no vacío y el filtrado del sidebar está muerto. Junto a él, la relectura íntegra del vault en cada evento del watcher y varios O(n) recalculados en cada evaluación de `body` son la deuda de rendimiento que importa a 673 notas.

El resto son asimetrías de mantenimiento: la raíz del vault y el nombre de `.inbox/` viven duplicados entre el Kit y la app, y `SettingsView` es un contenedor de cuatro pestañas sin relación entre sí.

---

## Hallazgos críticos

### C1 — La búsqueda de la ventana principal no filtra nada (`ContentView.swift:135-137`)

```swift
.onReceive(Just(searchText).debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { value in
    if !value.isEmpty { fm.searchQuery = value }
}
```

`fm.searchQuery` es la **única** entrada de `updateFilteredFiles()` (`MDFileManager.swift:46-48`), y el grep de todas sus escrituras deja tres sitios: `ContentView.swift:131` (solo cuando queda vacío), `SidebarView.swift:139` (botón de limpiar) y esta línea 137. Es decir: **la única vía por la que un texto escrito puede llegar al filtro es este `onReceive`**.

Y ese `onReceive` no dispara nunca. `Debounce` de Combine propaga la finalización del upstream de inmediato y **descarta el valor pendiente**; `Just` termina justo después de emitir, así que el temporizador de 300 ms nunca llega a vencer. Medido, no razonado:

```
$ swift deb.swift        # Just("hola").debounce(300ms, RunLoop.main).sink{…}
completion: finished
RESULTADO: recibidos = []
```

Consecuencias encadenadas:
- El sidebar sigue mostrando `fm.filteredFiles` == `fm.files` mientras se teclea.
- `isSearching` (`SidebarView.swift:190`) es siempre `false`, así que `hidingEmpty` nunca se activa y el invariante «durante una búsqueda no se escribe el estado de plegado» — el que `searchDoesNotWriteState` protege con un test — **nunca se ejerce en producción**.
- `pasture://search?q=…` (v1.9, `ContentView.swift:81-86`) escribe en `searchText` confiando en «el debounce existente propaga a `fm.searchQuery`» (comentario textual de la línea 82): también es inerte.
- La búsqueda del **menu bar** sí funciona, porque `MenuBarView.swift:18-21` filtra por su cuenta sin pasar por el manager. Eso explica que el defecto haya sobrevivido a la QA: hay dos búsquedas y solo una está rota.

**Por qué importa además del síntoma**: el comentario del código y el test de expansión afirman un comportamiento que el runtime no tiene. Es el patrón «guardia que vigila una región inalcanzable» que ya costó caro en este repo.

**Fix** (bajo, ~15 min): sustituir el par 131/137 por un único debounce sobre un `PassthroughSubject`, o más simple y sin Combine:

```swift
@State private var searchDebounce: Task<Void, Never>?
…
.onChange(of: searchText) { _, value in
    searchDebounce?.cancel()
    if value.isEmpty { fm.searchQuery = ""; return }
    searchDebounce = Task {
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        fm.searchQuery = value
    }
}
```

**Test de guardia obligatorio** (o esto se revierte en silencio): el predicado ya es testeable (`MDFile.matches`), pero el cableado no. Extraer el debounce a un tipo del Kit con reloj inyectado y cubrir «tras N ms con texto, el destino recibe el texto». Sin eso, el arreglo no tiene red.

---

## Hallazgos altos

### A1 — Cada evento del watcher relee el vault entero desde disco (`FileLibrary.swift:21-31` + `MDFile.swift:25-34`)

`FileLibrary.load` construye un `MDFile(url:)` por fichero, y ese init **lee el contenido completo**, estima tokens, escanea plantillas y parsea frontmatter. Con 673 notas eso es 673 lecturas + 4 pasadas de string por nota, y se dispara en cada ráfaga del `DirectoryWatcher` (0,5 s de debounce) — incluidas las que provoca la propia app al guardar (`markReviewed`, `promote`, `capture`, `importFile`).

Está bien que corra fuera del main actor (`load` es `nonisolated async`), así que no congela la UI; el coste es I/O y CPU repetidos, y latencia hasta que `apply` publica. Mitiga que `loadFiles()` cancela la tarea en vuelo (`MDFileManager.swift:168-176`).

**Fix** (medio): comparar `contentModificationDate` contra el `MDFile` ya en memoria y reutilizar el valor cacheado cuando no ha cambiado. `contentsOfDirectory` ya pide `.contentModificationDateKey`, así que el dato está disponible sin `stat` extra.

### A2 — `MenuBarView` reimplementa el filtrado sin caché y en el main actor (`MenuBarView.swift:18-21`)

```swift
private var filteredFiles: [MDFile] {
    guard !searchText.isEmpty else { return fm.files }
    return fm.files.filter { $0.matches(query: searchText) }
}
```

Propiedad computada de una `View`: se recalcula en **cada evaluación de `body`**, y `matches` hace `localizedCaseInsensitiveContains` sobre el contenido completo de las 673 notas. `localizedCaseInsensitiveContains` es de las comparaciones de string más caras de Foundation.

La ventana principal resolvió exactamente esto con `filteredFiles` cacheado en el manager (`MDFileManager.swift:34-48`); el popover se quedó fuera. Es el mismo trabajo hecho dos veces con dos calidades distintas.

**Fix** (bajo): darle al manager una segunda consulta cacheada, o —mejor, y de paso cierra C1— unificar ambas búsquedas contra `fm.filteredFiles` con `searchQuery` como único estado.

### A3 — Tres O(n) por evaluación de `body` en el sidebar (`SidebarView.swift:73, 179-188, 194-201`)

- `statusStrip` llama a `fm.staleFiles()`: filtra las 673 notas evaluando `Freshness` en cada render.
- `sortedFiles` con orden por nombre: ordena 673 con `localizedCaseInsensitiveCompare` en cada render.
- `nodes` llama a `SidebarTree.build`, que hace `collection(relativeTo:)` por fichero, y eso son dos `standardizedFileURL.path` + `hasPrefix` por nota (`MDFile.swift:50-57`).

Ninguna es cuadrática y ninguna bloquea de forma perceptible por sí sola, pero las tres corren juntas en el main actor en cada cambio de selección, de búsqueda o de hover.

**Fix** (bajo): `staleFiles` cacheado como `@Published` en el manager (se recalcula en `apply`), y `nodes`/`sortedFiles` memoizados contra `(files.count, sortOrder, searchQuery)`.

### A4 — La raíz del vault y el nombre de `.inbox/` están definidos dos y tres veces

| Concepto | Sitios |
|---|---|
| `~/.pasture/` | `MDFileManager.swift:5-8` (app) y `MCPServerConfig.swift:36-38` (Kit) |
| `.inbox` | `MDFileManager.swift:44` y `MCPTools.swift:137-139` |
| `com.sevecod.pasture` | `KeychainStore.swift:6,38,59` y `AppDelegate.swift:18` |

Los dos procesos (GUI y `pasture-mcp`) tienen que coincidir **exactamente** en estas rutas o el airlock del Memory Inbox deja de funcionar: la GUI promocionaría de un directorio donde el servidor no deposita. Hoy coinciden, pero nada lo garantiza — no hay un test que compare las dos constantes.

Detalle menor pero real del mismo hallazgo: la app construye `.pasture` **sin** `isDirectory: true` y el Kit **con**. `standardizedFileURL.path` normaliza la barra final, así que `PathValidator` no se rompe; es suerte, no diseño.

**Fix** (bajo): `PastureVault.root` y `PastureVault.inboxName` en PastureKit, consumidos por ambos targets. El defecto de fondo es que la app define una constante que el Kit ya necesita.

---

## Hallazgos menores

### M1 — `createCollection` traga el error sin decírselo a nadie (`MDFileManager.swift:314-321`)

```swift
} catch {
    return false
}
```

Es el único `catch` de todo `MDFileManager` que no fija `lastError`. Todos sus hermanos (`save`, `create`, `rename`, `delete`, `moveFile`, `renameCollection`, `deleteCollection`) sí lo hacen, y `ContentView.swift:124-129` convierte `lastError` en toast. El llamante (`ContentView.swift:108-113`) solo muestra feedback en el camino de éxito, así que un fallo de permisos al crear una colección **no produce ninguna señal**: la hoja se cierra y no pasa nada.

**Fix** (trivial): `lastError = "Failed to create collection '\(name)': \(error.localizedDescription)"`.

### M2 — El auto-clear del portapapeles a 60 s existe dos veces, con semánticas distintas

`FeedService.copyToClipboard` (`FeedService.swift:187-201`) usa un `Task` **cancelable** que se anula si llega otro feed. `HeadlessActions.copyWithAutoClear` (`HeadlessActions.swift:72-82`) usa `DispatchQueue.main.asyncAfter`, que **no se puede cancelar**. Dos copias seguidas por hotkey dejan dos temporizadores vivos; ambos comprueban `changeCount`, así que el resultado es correcto pero por accidente, no por diseño. El invariante de seguridad está escrito dos veces y solo una tiene freno.

**Fix** (bajo): mover el auto-clear a un tipo compartido (Kit no puede: es AppKit; que viva en un `ClipboardGuard` del target Pasture).

### M3 — Convención de claves de UserDefaults inconsistente

Nueve claves llevan el prefijo `com.sevecod.pasture.`; cuatro no: `pastureHideDockIcon`, `pastureGlobalHotkeysEnabled`, `pastureDefaultPresetID` (`IntegrationSettings`), `askQuestionHistory` (`QuestionHistory`), más `@AppStorage("mcpAllowProposals")` en `SettingsView.swift:469`. **No hay colisiones** (verificado: las 13 son únicas), pero la app no está sandboxed y comparte dominio con lo que el usuario instale bajo el mismo bundle ID. Un `askQuestionHistory` sin prefijo es exactamente el nombre que otra cosa podría querer.

**Fix** (trivial, con migración): unificar el prefijo leyendo la clave vieja como fallback una versión.

### M4 — `GlobalHotkeyManager.start()` registra un observador que nunca se retira y no es idempotente (`GlobalHotkeyManager.swift:45-55`)

Si `start()` se llamara dos veces habría dos observadores de `IntegrationSettings.didChangeNotification` y `apply()` correría dos veces por cambio. Hoy solo lo llama `AppDelegate.applicationDidFinishLaunching`, así que es teórico — pero el tipo es un singleton público del target y nada impide la segunda llamada. El `DispatchQueue.main.async` dentro de un bloque ya entregado en `queue: .main` es además redundante.

### M5 — `SettingsView` son cuatro pantallas sin nada en común en un fichero (654 líneas)

`GeneralSettingsTab` (129 líneas), `ExportSettingsTab` (146), `AISettingsTab` (166), `MCPSettingsTab` (196). Son cuatro `private struct` independientes; ninguna comparte tipo, estado ni helper con las otras — el único vínculo es el `TabView` de las primeras 23 líneas. No es un fichero «grande y acoplado», es un fichero **grande y trivialmente divisible**: cuatro ficheros de ~160 líneas y un `SettingsView.swift` de 23. El coste de no hacerlo es que cualquier toque en Ajustes abre un diff sobre las otras tres pestañas.

`ContentView` (569) es distinto: ahí sí hay estado compartido (28 `@State`, selección, modo detalle) y las extracciones obvias ya se hicieron (`SidebarView`, `FeedService`, `EditorStatusBar`, `FeedChrome`, `presetSheetsAndAlerts`). Lo que queda son ~8 acciones de presets/import/export que podrían irse a un `ContentView+Actions.swift`, pero no hay un corte limpio más profundo. `MCPTools` (558) tampoco pide división: son seis tools con la misma forma y helpers compartidos; partirlo por tool dispersaría `queueProposal` y `enumerateVaultFiles`.

### M6 — El comentario de `feed_context` sobre secretos no bloqueantes (SEC-M8) es correcto, pero `readFile` lee el fichero y **luego** aplica el tope exacto (`MCPTools.swift:317-330`)

Hay una precomprobación por tamaño en disco antes de leer, así que el caso patológico está cubierto; la segunda barrera sobre `content.utf8.count` solo materializa en RAM un fichero de hasta 25 MB que resulte pesar más en UTF-8 que en disco. Es correcto y deliberado (el comentario lo dice). Lo anoto solo para que no se lea como hueco en una auditoría futura.

---

## Concurrencia: veredicto por uso

| Uso | Ubicación | Veredicto | Razón |
|---|---|---|---|
| `nonisolated(unsafe)` × 5 (sources, workItems) | `DirectoryWatcher.swift:30-34` | **Justificado** | Todo acceso sale de métodos `@MainActor` (`watchRoot`, `watchInbox`, `updateSubdirectories`, `stop`, `schedule*`). La marca existe solo porque `deinit` es `nonisolated` y toca los mismos campos. El propietario (`MDFileManager`) es `@MainActor`, así que el `deinit` se ejecuta en main. Los handlers GCD capturan `[weak self]`, no hay retención cruzada. |
| `MainActor.assumeIsolated` × 4 | `DirectoryWatcher.swift:104,114,126,136` | **Justificado** | Siempre dentro de `DispatchQueue.main.async` / `asyncAfter`. Es el patrón canónico; la aserción no puede fallar. |
| `@unchecked Sendable` | `MCPDispatcher.swift:15` | **Justificado, con condición no verificada por el compilador** | El único estado mutable es `clientInfo`, escrito en `initialize` y leído en `tools/call`. La seguridad depende por completo de que `main.swift` sea un bucle secuencial (ADR-MCP-005). Lo es hoy (leído: read → dispatch → write, sin `Task`). **Si alguien paraleliza ese bucle, la carrera aparece sin que nada avise.** Cambiar `clientInfo` a un `NSLock` como el de `HTTPTaskBox` cuesta 6 líneas y quita la dependencia de una convención. |
| `@unchecked Sendable` | `AIClient.swift:314` (`HTTPTaskBox`) | **Justificado** | Cerrojo explícito `NSLock` en get y set, estado privado, un solo campo. Correcto por construcción, no por convención — es el contraejemplo del anterior. |
| `actor AIClient` | `AIClient.swift` | **Justificado** | El puente `AsyncThrowingStream` se consume en `AskViewModel` (`@MainActor`) con `streamTask` cancelable; la cancelación se comprueba en el bucle de reintentos y en el de SSE. |
| `Task.detached` × 3 | `FeedService.swift:114`, `SettingsView.swift:647`, `PackSyncRunner.swift:25` | **Justificado** | Los tres sacan trabajo pesado y puro del main actor (escáner de secretos, escaneo del vault, compilación de packs) y capturan solo valores `Sendable`. |
| `DispatchQueue.main.async` + `assumeIsolated` × 2 | `GlobalHotkeyManager.swift:50,133` | **Justificado** | El callback C de Carbon no captura contexto; el hop es obligatorio. El de la línea 50 es redundante (ya llega en `queue: .main`) pero inocuo. |
| `nonisolated(unsafe) lockFD` | `AppDelegate.swift:5` | **Justificado** | Escrito en `applicationDidFinishLaunching`, leído en `applicationWillTerminate`; ambos son callbacks del main thread de AppKit. |
| `DispatchQueue.main.asyncAfter(60)` | `HeadlessActions.swift:77` | **Sospechoso** | No es carrera (ver M2), pero es un temporizador no cancelable que duplica un invariante de seguridad ya implementado con `Task`. |

**¿Hay una carrera real? No.** Ningún camino permite escritura concurrente sobre estado compartido: `DirectoryWatcher` confina todo en main, `MCPDispatcher` corre single-thread, `AIClient` es actor y su única caja compartida lleva cerrojo. El riesgo que sí existe es **latente y de mantenimiento**: el `@unchecked Sendable` de `MCPDispatcher` es un contrato escrito en un comentario, no en el tipo.

**Sobre el gotcha del CI más estricto**: no encontré ningún tipo no-`Sendable` de un framework de Apple cruzando fronteras de actor. Los candidatos naturales (`NSPasteboard`, `NSSavePanel`, `SMAppService`, `UNUserNotificationCenter`, `NSAttributedString`) se usan siempre dentro de contexto `@MainActor` o detrás de un `MainActor.assumeIsolated`. `SystemNotifier` (`SystemNotifier.swift:18-26`) es el punto donde miré con más atención por el precedente de `UNNotificationSettings` en v1.10, y ahí ya se aplicó el arreglo. El build local está limpio, y eso —como dice el CLAUDE.md— no es prueba; pero no tengo un candidato concreto que señalar.

---

## Decisiones de diseño discutibles (sin severidad)

- **Namespaces estáticos sobre UserDefaults: ocho.** `ExportSettings`, `AISettings`, `FeedFormatSettings`, `IntegrationSettings`, `SelectionPresetStore`, `PackStore`, `CollectionExpansionStore`, `QuestionHistory`. Todos con el mismo patrón, todos con `defaults:` inyectable (lo que los hace testeables sin tocar el dominio real) y todos con `didChangeNotification` salvo los dos triviales. **No creo que sobren**: cada uno es una unidad de persistencia con su propio ciclo de vida y su propio consumidor. Lo que sí pediría es un protocolo común — hoy la firma `load/save` se reescribe ocho veces a mano, y `CollectionExpansionStore` ya se desvía (usa `key` en minúscula, los demás `defaultsKey`).
- **Notificaciones de `NotificationCenter` como bus interno.** `ContentView` escucha nueve publishers distintos. Funciona y desacopla, pero no hay ningún sitio donde estén declaradas todas: son `extension Notification.Name` repartidas. Un fichero `PastureNotifications.swift` no cambiaría el diseño y haría auditable la superficie.
- **`MDFile` lleva el contenido completo en memoria.** Es lo que hace posible que `matches` busque en el texto sin tocar disco, y a 673 notas de markdown el coste en RAM es trivial. Es una decisión correcta para el tamaño actual; solo dejo dicho que es lo que hace cara la relectura de A1.
- **La app define su propia `pastureDir` en vez de consumir la del Kit.** Lo listo como hallazgo (A4) porque es duplicación real, pero reconozco la lectura contraria: la app quiere una constante estática y el Kit expone una factory con inyección para tests. Unificar exige decidir cuál gana.

---

## Lo que está bien resuelto

- **La frontera de los tres targets se respeta de verdad.** `main.swift` del MCP son ~30 líneas de transporte y `MCPDispatcher.handle(line:)` es una frontera testeable sin lanzar proceso: eso es lo que permite 9 suites de tests MCP. No encontré lógica de negocio atrapada en la capa UI salvo el detalle de A4 y las acciones de presets de `ContentView`, que son cableado de UI legítimo.
- **La validación de rutas en dos capas** (`PathValidator` para `..`, `resolvingSymlinksInPath` para symlinks) está aplicada consistentemente en lectura, propuesta y promoción, y el inverso (`TargetValidator`, que impide compilar *hacia* el vault) cierra la simetría. Es la pieza mejor pensada del repo.
- **La separación entre error de tool (`isError`) y error de protocolo (objeto `error`)** está implementada con tipos distintos (`ToolCallResult` vs `MCPRequestError`) y no solo por convención: `resources/read` y `prompts/get` devuelven `Result` precisamente porque no pueden degradar. Esa distinción suele hacerse mal.
- **El manejo de errores es, salvo M1, honesto.** De 66 `try?`/`catch` en `Sources/`, los que descartan lo hacen sobre operaciones idempotentes (`createDirectory(withIntermediateDirectories: true)`) y varias veces con verificación posterior explícita — `MDFileManager.swift:94-98` comprueba el resultado del `try?` y fija `lastError` con un comentario que explica por qué. Los que importan propagan a `lastError` → toast, a `stderr` o a `SystemNotifier`.
- **Cero dependencias, verificado**: `Package.swift` no declara un solo `.package`. Los cuatro targets dependen entre sí y de Foundation/SwiftUI/AppKit.
- **La no-reentrada de `FeedService.guardSecrets`** (`FeedService.swift:103-131`) comprueba el invariante **dos veces**, antes y después del hop async. Ese segundo chequeo es exactamente lo que suele faltar.
- **`loadFiles()` cancela la tarea en vuelo** antes de lanzar la siguiente, lo que evita que una ráfaga del watcher apile N escaneos completos.

---

## Justificación del score

Parto de 100.

- **−14** por C1: una funcionalidad central de la ventana principal está muerta en producción, el comentario del código afirma lo contrario, y un test verde vigila una región de estado que nunca se alcanza. No es −25 porque el arreglo es de 15 minutos, el predicado subyacente está bien y hay una segunda búsqueda (menu bar) que sí funciona.
- **−8** por rendimiento (A1+A2+A3): ninguno bloquea de forma perceptible hoy, pero A2 es trabajo duplicado con peor calidad que la solución que ya existe a tres ficheros de distancia.
- **−4** por A4: dos procesos que deben coincidir en una ruta y ninguna constante compartida ni test que lo verifique.
- **−4** por los menores (M1 es un fallo silencioso genuino, M2 duplica un invariante de seguridad, M3/M4/M5 son higiene).
- **−2** por el `@unchecked Sendable` de `MCPDispatcher`, que es correcto hoy pero apoyado en una convención que el compilador no vigila.

**78/100.** La nota sería alta —la arquitectura, la disciplina de seguridad y la testabilidad están por encima de lo normal— si no fuera porque un defecto de cableado de 3 líneas dejó inerte la búsqueda. Es justo lo que este repo ya aprendió una vez: el diseño era correcto y el punto ciego estaba en el alcance de lo que se verificó.

---

## Dudas y asunciones

1. **C1 lo verifiqué en Combine aislado, no dentro de SwiftUI.** Ejecuté `Just("hola").debounce(for:.milliseconds(300), scheduler: RunLoop.main).sink{…}` bajo un `RunLoop.main.run` de 1,5 s y no llegó ningún valor, solo `completion: finished`. La cadena de operadores y el scheduler son idénticos a los de `ContentView:135`; `onReceive` no hace más que suscribirse. Asumo que el comportamiento es el mismo dentro de SwiftUI, pero **la confirmación definitiva es teclear en la barra de búsqueda de la app instalada y ver si el sidebar filtra** — treinta segundos de QA manual, y va antes que cualquier arreglo.
2. Asumo que el `PASTURE_ALLOW_PROPOSALS` de producción está activo (la memoria del proyecto dice que `propose_note` se validó en vivo), así que trato el camino de propuestas como código vivo y no como muerto.
3. Asumo 673 notas como tamaño de referencia (viene del enunciado de la auditoría, citando el CHANGELOG); no medí el vault real ni cronometré ninguna de las rutas de A1-A3. Las tres son hallazgos de **forma** (O(n) por render, relectura íntegra), no mediciones de latencia — no afirmo ningún número de milisegundos.
4. No evalué la cobertura ni la calidad de los 728 tests: quedaba fuera del alcance de arquitectura y concurrencia. Solo señalo, en C1, un caso donde un test verde no protege lo que dice proteger.
5. El build local terminó limpio (`Build complete!`), pero fue incremental sobre artefactos previos; no forcé un build limpio ni compilé el target de tests, así que no aporto eso como evidencia de nada más allá de que el árbol actual compila.
