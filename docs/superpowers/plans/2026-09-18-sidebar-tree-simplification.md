# Sidebar Tree & Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el sidebar de Pasture abra plegado por colección en vez de pintar 673 filas, que los tooltips se vean, y retirar `New File`.

**Architecture:** La lógica nueva es **pura y vive en PastureKit** (`SidebarTree`, `CollectionExpansionStore`), siguiendo el patrón ya establecido por `ContextLimit` y `SelectionPresetStore`: sin I/O propio, `UserDefaults` inyectable, probable en aislamiento. `SidebarView` cambia sus `Section` por `DisclosureGroup` pero conserva intacto el `List(selection:)` de selección múltiple plana, del que dependen Feed, Presets, Merge y el Context Compiler. Nada toca `FileLibrary`, el servidor MCP, los presets ni los packs.

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`), Swift Package Manager. Cero dependencias externas — regla identitaria del repo.

**Spec:** `docs/superpowers/specs/2026-09-18-sidebar-tree-simplification-design.md`

## Global Constraints

- **Cero dependencias externas.** Solo frameworks de Apple. No se añade ningún `.package` a `Package.swift`.
- **Prosa y comentarios en español; identifiers y mensajes de commit en inglés.**
- **Tests locales:** `swift test` con las Command Line Tools falla por falta del módulo `Testing`. Usar siempre:
  `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test`
- **El veredicto es el de CI, no el build local.** El compilador del runner `macos-15` es más estricto que el toolchain local (lección de v1.10 con `UNNotificationSettings`). Un build local limpio no cierra nada.
- **Suite de partida: 711 tests.** Ninguna tarea puede dejarla en rojo.
- **Toda lógica nueva va en `Sources/PastureKit/`**, no en `Sources/Pasture/`. El target `Pasture` es la UI y no tiene tests.
- **Los stores toman `UserDefaults` por parámetro con valor por defecto `.standard`** (patrón de `SelectionPresetStore`), para que los tests no contaminen el dominio real.
- **Colores:** nunca literales. Usar los tokens `Color.pastureX(colorScheme)` de `DesignTokens.swift`. Todo par texto/fondo cumple WCAG AA (≥4,5:1) en claro y oscuro.

---

### Task 1: Diagnosticar por qué no se ven los tooltips

**Esta tarea va primero y su resultado puede cambiar la Task 6.** No se escribe ni un `.help()` nuevo hasta tener una causa **observada**. Es una investigación, no TDD: el entregable es un hallazgo escrito, no código.

**Files:**
- Modify: ninguno todavía (salvo el experimento 2, que se revierte)
- Create: `docs/superpowers/specs/2026-09-18-tooltip-diagnosis.md`

**Interfaces:**
- Consumes: nada.
- Produces: el fichero de diagnóstico con la causa observada. La Task 6 lo lee antes de decidir su arreglo.

**Contexto.** `Sources/Pasture/ContentView.swift:180-262` mete **11 elementos** en un único `ToolbarItemGroup(placement: .primaryAction)`, y los 11 ya llevan `.help()`. En toda la app hay 30 `.help()` escritos. El usuario confirma que al pasar el ratón **no aparece ninguno** en la toolbar.

- [ ] **Step 1: Compilar y lanzar la app**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift build 2>&1 | tail -5
swift run
```

Esperado: la ventana de Pasture abre con la vault real (673 notas).

- [ ] **Step 2: Prueba de control — ¿funciona algún tooltip fuera de la toolbar?**

Seleccionar una nota cualquiera para que aparezca el panel de previsualización. En la barra de estado inferior, pasar el ratón **2 segundos completos** sobre el botón "Open in Editor" (`Sources/Pasture/EditorStatusBar.swift:53`, que lleva `.help("Open in default editor (Cmd+E)")`).

Anotar: ¿aparece el tooltip, sí o no?

- **Si aparece:** el problema es específico de la toolbar → seguir al Step 3.
- **Si NO aparece:** el problema es global y las dos hipótesis del spec quedan invalidadas. **Parar, anotarlo en el fichero de diagnóstico y avisar al usuario antes de seguir.**

- [ ] **Step 3: Experimento 1 — hipótesis del desbordamiento**

Con la ventana en su ancho habitual, contar cuántos botones se ven en la toolbar y si aparece el chevron `»` de desbordamiento a la derecha. Anotar el número.

Ensanchar la ventana a pantalla completa hasta que **los 11 elementos sean visibles** y desaparezca el chevron. Volver a pasar el ratón 2 segundos sobre "Refresh" (el último del grupo).

Anotar: ¿aparece el tooltip ahora que no está desbordado?

- **Si aparece:** hipótesis 1 **confirmada**. El arreglo es reducir el número de elementos, que es exactamente la Task 6.
- **Si no aparece:** hipótesis 1 descartada → Step 4.

- [ ] **Step 4: Experimento 2 — hipótesis de `.help()` sobre `Button` en `ToolbarItemGroup`**

Mover el modificador al `Label` en **un solo** botón, para comparar con sus vecinos sin tocar nada más. En `Sources/Pasture/ContentView.swift`, el botón Refresh:

```swift
            Button {
                // Async reload; selection is reconciled by onChange(of: fm.files)
                fm.loadFiles()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .help("Reload file list from ~/.pasture/")
            }
            .accessibilityLabel("Refresh file list")
```

Recompilar, lanzar y pasar el ratón sobre Refresh y sobre su vecino Feed.

Anotar: ¿sale el de Refresh y no el de Feed?

- **Si sale solo el de Refresh:** hipótesis 2 confirmada. El arreglo es mover los 11 `.help()` al `Label`.
- **Si no sale ninguno:** las dos hipótesis fallan. **Parar y avisar al usuario** con lo observado en los 4 pasos.

- [ ] **Step 5: Revertir el experimento**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git checkout -- Sources/Pasture/ContentView.swift
git status --short
```

Esperado: sin cambios pendientes en `ContentView.swift`. El experimento es desechable; el arreglo de verdad lo aplica la Task 6.

- [ ] **Step 6: Escribir el diagnóstico**

Crear `docs/superpowers/specs/2026-09-18-tooltip-diagnosis.md` con exactamente esta estructura, rellenando lo **observado** (nunca lo supuesto):

```markdown
# Diagnóstico: los tooltips no aparecen

Fecha: 2026-09-18
Entorno: macOS <versión>, toolchain <versión de `swift --version`>

## Prueba de control (EditorStatusBar, fuera de la toolbar)
Resultado: <aparece / no aparece>

## Experimento 1 — desbordamiento de la toolbar
Elementos visibles al ancho habitual: <N de 11>
Chevron de desbordamiento: <sí / no>
Tooltip con los 11 visibles: <aparece / no aparece>
Veredicto: <confirmada / descartada>

## Experimento 2 — .help() en Button vs. en Label
Tooltip de Refresh (modificador en el Label): <aparece / no aparece>
Tooltip de Feed (modificador en el Button): <aparece / no aparece>
Veredicto: <confirmada / descartada>

## Causa observada
<una frase>

## Arreglo que se deriva
<una frase, la que aplicará la Task 6>
```

- [ ] **Step 7: Commit**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git add docs/superpowers/specs/2026-09-18-tooltip-diagnosis.md
git commit -m "docs: observed cause for missing toolbar tooltips"
```

---

### Task 2: `SidebarTree` — agrupar ficheros en nodos de colección

**Files:**
- Create: `Sources/PastureKit/SidebarTree.swift`
- Test: `Tests/PastureKitTests/SidebarTreeTests.swift`

**Interfaces:**
- Consumes: `MDFile` (`Sources/PastureKit/MDFile.swift`), en concreto `collection(relativeTo base: URL) -> String?` y `tokens: Int`.
- Produces:
  - `public struct CollectionNode: Identifiable, Sendable, Hashable` con `name: String?`, `files: [MDFile]`, `id: String`, `fileCount: Int`, `totalTokens: Int`, `isUncategorized: Bool`
  - `public static func SidebarTree.build(files: [MDFile], collections: [String], base: URL, hidingEmpty: Bool = false) -> [CollectionNode]`

**Contexto de diseño.** `name == nil` significa *Uncategorized* (la raíz de la vault). El `id` lleva prefijo (`"u:"` / `"c:<nombre>"`) para que una colección llamada literalmente `""` no colisione con Uncategorized; ese `id` es además la clave que usa el store de la Task 3. `build` **no ordena**: recibe los ficheros ya ordenados por quien llama (`SidebarView.sortedFiles`) y preserva su orden relativo dentro de cada nodo, y recibe `collections` ya ordenado alfabéticamente por `MDFileManager.refreshCollections`.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `Tests/PastureKitTests/SidebarTreeTests.swift`:

```swift
import Foundation
import Testing
@testable import PastureKit

/// Agrupación del sidebar en nodos plegables. Lógica pura: `build` no ordena,
/// preserva el orden que le entregan y solo agrupa.
@Suite("SidebarTree")
struct SidebarTreeTests {

    private let base = URL(fileURLWithPath: "/tmp/pasture-test", isDirectory: true)

    /// Fichero de prueba en la raíz (colección nil) o dentro de `collection`.
    private func file(_ name: String, in collection: String? = nil, tokens: Int = 10) -> MDFile {
        var url = base
        if let collection { url.appendPathComponent(collection, isDirectory: true) }
        url.appendPathComponent("\(name).md")
        return MDFile(
            name: name, url: url, modifiedDate: Date(),
            content: "", tokens: tokens, hasTemplateVars: false
        )
    }

    @Test("Uncategorized va el primero")
    func uncategorizedFirst() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Zeta"), file("b")],
            collections: ["Zeta"], base: base
        )
        #expect(nodes.first?.isUncategorized == true)
        #expect(nodes.first?.name == nil)
    }

    @Test("Uncategorized no aparece si no hay ficheros sueltos")
    func uncategorizedOmittedWhenEmpty() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Zeta")],
            collections: ["Zeta"], base: base
        )
        #expect(nodes.count == 1)
        #expect(nodes.first?.name == "Zeta")
    }

    @Test("Cada fichero cae en su colección")
    func groupsByCollection() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Alpha"), file("b", in: "Beta"), file("c", in: "Alpha")],
            collections: ["Alpha", "Beta"], base: base
        )
        #expect(nodes.count == 2)
        #expect(nodes[0].files.map(\.name) == ["a", "c"])
        #expect(nodes[1].files.map(\.name) == ["b"])
    }

    @Test("Respeta el orden de `collections` que recibe")
    func preservesCollectionOrder() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Zeta"), file("b", in: "Alpha")],
            collections: ["Alpha", "Zeta"], base: base
        )
        #expect(nodes.map(\.name) == ["Alpha", "Zeta"])
    }

    @Test("Preserva el orden de los ficheros dentro del nodo (no reordena)")
    func preservesFileOrder() {
        let nodes = SidebarTree.build(
            files: [file("zzz", in: "Alpha"), file("aaa", in: "Alpha")],
            collections: ["Alpha"], base: base
        )
        #expect(nodes[0].files.map(\.name) == ["zzz", "aaa"])
    }

    @Test("Una colección vacía sigue apareciendo (es la única vía de borrarla)")
    func emptyCollectionStillShows() {
        let nodes = SidebarTree.build(files: [], collections: ["Vacia"], base: base)
        #expect(nodes.count == 1)
        #expect(nodes[0].fileCount == 0)
    }

    @Test("hidingEmpty descarta las colecciones sin ficheros (modo búsqueda)")
    func hidingEmptyDropsEmpties() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Alpha")],
            collections: ["Alpha", "Vacia"], base: base, hidingEmpty: true
        )
        #expect(nodes.map(\.name) == ["Alpha"])
    }

    @Test("fileCount y totalTokens se calculan por nodo")
    func countsAndTokens() {
        let nodes = SidebarTree.build(
            files: [file("a", in: "Alpha", tokens: 100), file("b", in: "Alpha", tokens: 25)],
            collections: ["Alpha"], base: base
        )
        #expect(nodes[0].fileCount == 2)
        #expect(nodes[0].totalTokens == 125)
    }

    @Test("El id distingue Uncategorized de una colección de nombre vacío")
    func idDisambiguates() {
        let nodes = SidebarTree.build(
            files: [file("a")],
            collections: [""], base: base
        )
        #expect(Set(nodes.map(\.id)).count == nodes.count)
        #expect(nodes.first(where: { $0.isUncategorized })?.id == "u:")
    }
}
```

- [ ] **Step 2: Ejecutar los tests para verificar que fallan**

```bash
cd /Users/eula/Desktop/Claude/Pasture
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test --filter SidebarTreeTests 2>&1 | tail -20
```

Esperado: FALLO de compilación, `cannot find 'SidebarTree' in scope`.

- [ ] **Step 3: Escribir la implementación mínima**

Crear `Sources/PastureKit/SidebarTree.swift`:

```swift
import Foundation

/// Un nodo plegable del sidebar: una colección con sus notas, o la raíz de la
/// vault (`name == nil`, *Uncategorized*).
public struct CollectionNode: Identifiable, Sendable, Hashable {
    /// Nombre de la colección; `nil` es la raíz de la vault.
    public let name: String?
    public let files: [MDFile]

    public init(name: String?, files: [MDFile]) {
        self.name = name
        self.files = files
    }

    /// Clave estable para la selección y para `CollectionExpansionStore`.
    /// Lleva prefijo para que una colección llamada "" no colisione con la raíz.
    public var id: String { name.map { "c:\($0)" } ?? "u:" }

    public var isUncategorized: Bool { name == nil }

    public var fileCount: Int { files.count }

    public var totalTokens: Int { files.reduce(0) { $0 + $1.tokens } }
}

/// Agrupa la lista plana de notas en nodos de colección para el sidebar.
///
/// No ordena: preserva el orden de `files` (que llega ya ordenado por el criterio
/// activo) y el de `collections` (ya alfabético desde `MDFileManager`). Así el
/// criterio de orden vive en un solo sitio.
public enum SidebarTree {

    /// - Parameter hidingEmpty: descarta las colecciones sin ficheros. Se usa con
    ///   búsqueda activa, donde una colección sin coincidencias no aporta nada.
    public static func build(
        files: [MDFile],
        collections: [String],
        base: URL,
        hidingEmpty: Bool = false
    ) -> [CollectionNode] {
        var byCollection: [String: [MDFile]] = [:]
        var uncategorized: [MDFile] = []

        for file in files {
            if let name = file.collection(relativeTo: base) {
                byCollection[name, default: []].append(file)
            } else {
                uncategorized.append(file)
            }
        }

        var nodes: [CollectionNode] = []
        if !uncategorized.isEmpty {
            nodes.append(CollectionNode(name: nil, files: uncategorized))
        }
        for name in collections {
            let files = byCollection[name] ?? []
            if hidingEmpty && files.isEmpty { continue }
            nodes.append(CollectionNode(name: name, files: files))
        }
        return nodes
    }
}
```

- [ ] **Step 4: Ejecutar los tests para verificar que pasan**

```bash
cd /Users/eula/Desktop/Claude/Pasture
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test --filter SidebarTreeTests 2>&1 | tail -10
```

Esperado: los 9 tests en verde.

- [ ] **Step 5: Commit**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git add Sources/PastureKit/SidebarTree.swift Tests/PastureKitTests/SidebarTreeTests.swift
git commit -m "feat: add SidebarTree to group files into collapsible collection nodes"
```

---

### Task 3: `CollectionExpansionStore` — pliegue persistente y anulación por búsqueda

**Files:**
- Create: `Sources/PastureKit/CollectionExpansionStore.swift`
- Test: `Tests/PastureKitTests/CollectionExpansionStoreTests.swift`

**Interfaces:**
- Consumes: el `id: String` de `CollectionNode` (Task 2) como clave.
- Produces:
  - `public static func CollectionExpansionStore.load(from: UserDefaults = .standard) -> Set<String>`
  - `public static func CollectionExpansionStore.save(_ expanded: Set<String>, to: UserDefaults = .standard)`
  - `public static func CollectionExpansionStore.effectiveExpansion(stored: Set<String>, nodeID: String, isSearching: Bool) -> Bool`
  - `public static func CollectionExpansionStore.applying(_ expanded: Bool, to stored: Set<String>, nodeID: String, isSearching: Bool) -> Set<String>`

**Contexto de diseño.** `effectiveExpansion` y `applying` son **funciones puras** precisamente para que el invariante central del spec —la búsqueda abre todo pero **no escribe** el estado guardado— tenga test propio y no viva enterrado en un `Binding` de SwiftUI.

- [ ] **Step 1: Escribir los tests que fallan**

Crear `Tests/PastureKitTests/CollectionExpansionStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import PastureKit

/// Pliegue de las colecciones del sidebar. El invariante que más importa:
/// con búsqueda activa todo se ve abierto, pero el estado guardado NO se toca.
@Suite("CollectionExpansionStore")
struct CollectionExpansionStoreTests {

    /// Dominio propio por test para no contaminar `.standard`.
    private func freshDefaults() -> UserDefaults {
        let suite = "pasture.tests.expansion.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    @Test("Sin nada guardado, todo está plegado")
    func defaultsToCollapsed() {
        #expect(CollectionExpansionStore.load(from: freshDefaults()).isEmpty)
    }

    @Test("Lo guardado sobrevive a una relectura")
    func roundTrip() {
        let defaults = freshDefaults()
        CollectionExpansionStore.save(["c:Alpha", "u:"], to: defaults)
        #expect(CollectionExpansionStore.load(from: defaults) == ["c:Alpha", "u:"])
    }

    @Test("Sin búsqueda, manda el estado guardado")
    func storedWins() {
        #expect(CollectionExpansionStore.effectiveExpansion(
            stored: ["c:Alpha"], nodeID: "c:Alpha", isSearching: false) == true)
        #expect(CollectionExpansionStore.effectiveExpansion(
            stored: ["c:Alpha"], nodeID: "c:Beta", isSearching: false) == false)
    }

    @Test("Con búsqueda, todo se ve abierto aunque esté plegado")
    func searchForcesExpanded() {
        #expect(CollectionExpansionStore.effectiveExpansion(
            stored: [], nodeID: "c:Beta", isSearching: true) == true)
    }

    @Test("Con búsqueda, plegar o desplegar NO altera el estado guardado")
    func searchDoesNotWriteState() {
        let stored: Set<String> = ["c:Alpha"]
        #expect(CollectionExpansionStore.applying(
            false, to: stored, nodeID: "c:Alpha", isSearching: true) == stored)
        #expect(CollectionExpansionStore.applying(
            true, to: stored, nodeID: "c:Beta", isSearching: true) == stored)
    }

    @Test("Sin búsqueda, desplegar añade y plegar quita")
    func togglesWhenNotSearching() {
        #expect(CollectionExpansionStore.applying(
            true, to: [], nodeID: "c:Alpha", isSearching: false) == ["c:Alpha"])
        #expect(CollectionExpansionStore.applying(
            false, to: ["c:Alpha"], nodeID: "c:Alpha", isSearching: false) == [])
    }

    @Test("Una colección borrada del disco deja una entrada huérfana inofensiva")
    func orphanEntryIsHarmless() {
        let stored: Set<String> = ["c:Borrada"]
        #expect(CollectionExpansionStore.effectiveExpansion(
            stored: stored, nodeID: "c:Viva", isSearching: false) == false)
    }
}
```

- [ ] **Step 2: Ejecutar los tests para verificar que fallan**

```bash
cd /Users/eula/Desktop/Claude/Pasture
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test --filter CollectionExpansionStoreTests 2>&1 | tail -20
```

Esperado: FALLO de compilación, `cannot find 'CollectionExpansionStore' in scope`.

- [ ] **Step 3: Escribir la implementación mínima**

Crear `Sources/PastureKit/CollectionExpansionStore.swift`:

```swift
import Foundation

/// Qué colecciones del sidebar están desplegadas. Mismo patrón que
/// `SelectionPresetStore`: namespace estático, `UserDefaults` inyectable.
///
/// La clave es el `id` de `CollectionNode`, no el nombre: así la raíz
/// (*Uncategorized*) tiene entrada propia.
public enum CollectionExpansionStore {
    private static let key = "com.sevecod.pasture.expandedCollections"

    public static func load(from defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    public static func save(_ expanded: Set<String>, to defaults: UserDefaults = .standard) {
        defaults.set(Array(expanded), forKey: key)
    }

    /// Si una colección se ve abierta ahora mismo. Con búsqueda activa se abre
    /// todo, para que ninguna coincidencia quede escondida tras un triángulo.
    public static func effectiveExpansion(
        stored: Set<String>, nodeID: String, isSearching: Bool
    ) -> Bool {
        isSearching || stored.contains(nodeID)
    }

    /// Nuevo estado tras plegar o desplegar. Durante una búsqueda **no se escribe
    /// nada**: al borrar la búsqueda, el sidebar vuelve al pliegue que tenía.
    public static func applying(
        _ expanded: Bool, to stored: Set<String>, nodeID: String, isSearching: Bool
    ) -> Set<String> {
        guard !isSearching else { return stored }
        var next = stored
        if expanded { next.insert(nodeID) } else { next.remove(nodeID) }
        return next
    }
}
```

- [ ] **Step 4: Ejecutar los tests para verificar que pasan**

```bash
cd /Users/eula/Desktop/Claude/Pasture
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test --filter CollectionExpansionStoreTests 2>&1 | tail -10
```

Esperado: los 7 tests en verde.

- [ ] **Step 5: Validar por mutación que la guardia de búsqueda no es decorativa**

Un arreglo sin test de guardia se revierte en silencio. Comprobar que el test lo caza:

En `Sources/PastureKit/CollectionExpansionStore.swift`, borrar temporalmente la línea `guard !isSearching else { return stored }` de `applying`, y ejecutar:

```bash
cd /Users/eula/Desktop/Claude/Pasture
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test --filter CollectionExpansionStoreTests 2>&1 | tail -10
```

Esperado: **falla** `searchDoesNotWriteState`. Si pasa en verde, el test no vale y hay que rehacerlo antes de seguir.

Restaurar la línea:

```bash
cd /Users/eula/Desktop/Claude/Pasture
git diff Sources/PastureKit/CollectionExpansionStore.swift
```

Volver a ejecutar los tests y confirmar verde antes de commitear.

- [ ] **Step 6: Commit**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git add Sources/PastureKit/CollectionExpansionStore.swift Tests/PastureKitTests/CollectionExpansionStoreTests.swift
git commit -m "feat: persist sidebar collection expansion with search override"
```

---

### Task 4: Cablear el árbol plegable en `SidebarView`

**Files:**
- Modify: `Sources/Pasture/SidebarView.swift:178-233` (`sortedFiles` y `fileList`)
- Test: cubierto por las Tasks 2 y 3; esta tarea es UI y se verifica a mano (Step 5) y en la QA visual de la Task 8.

**Interfaces:**
- Consumes: `SidebarTree.build(files:collections:base:hidingEmpty:)` y `CollectionNode` (Task 2); `CollectionExpansionStore.load/save/effectiveExpansion/applying` (Task 3); `MDFileManager.pastureDir` (estático, ya existe), `fm.collections`, `fm.filteredFiles`, `fm.searchQuery`.
- Produces: nada que consuman otras tareas.

**Qué NO cambia, y es lo importante:** sigue siendo un solo `List(selection: $selectedFiles)` con la misma selección múltiple plana. Los `DisclosureGroup` van **dentro** de ese `List`. Feed, Presets, Merge y Ask siguen pudiendo seleccionar notas de varias colecciones a la vez.

- [ ] **Step 1: Añadir el estado de pliegue**

En `Sources/Pasture/SidebarView.swift`, junto a los demás `@State` (tras la línea 19, `@State private var showInbox = false`):

```swift
    /// Colecciones desplegadas, por `CollectionNode.id`. Se siembra del store al
    /// aparecer y se reescribe en cada plegado (salvo durante una búsqueda).
    @State private var expandedCollections: Set<String> = CollectionExpansionStore.load()
```

- [ ] **Step 2: Sustituir `fileList` por la versión con `DisclosureGroup`**

Reemplazar el cuerpo completo de `var fileList: some View` (líneas 190-233) por:

```swift
    private var isSearching: Bool { !fm.searchQuery.isEmpty }

    /// Nodos que se pintan ahora. Con búsqueda activa se ocultan las colecciones
    /// sin coincidencias: un triángulo que no lleva a nada solo hace ruido.
    private var nodes: [CollectionNode] {
        SidebarTree.build(
            files: sortedFiles,
            collections: fm.collections,
            base: MDFileManager.pastureDir,
            hidingEmpty: isSearching
        )
    }

    /// El pliegue de un nodo. Durante una búsqueda se ve abierto y el `set` no
    /// escribe, así que al borrar la búsqueda vuelve el estado guardado.
    private func expansionBinding(for node: CollectionNode) -> Binding<Bool> {
        Binding(
            get: {
                CollectionExpansionStore.effectiveExpansion(
                    stored: expandedCollections, nodeID: node.id, isSearching: isSearching
                )
            },
            set: { newValue in
                let next = CollectionExpansionStore.applying(
                    newValue, to: expandedCollections, nodeID: node.id, isSearching: isSearching
                )
                guard next != expandedCollections else { return }
                expandedCollections = next
                CollectionExpansionStore.save(next)
            }
        )
    }

    var fileList: some View {
        List(selection: $selectedFiles) {
            ForEach(nodes) { node in
                DisclosureGroup(isExpanded: expansionBinding(for: node)) {
                    ForEach(node.files) { file in
                        fileRow(file: file)
                    }
                } label: {
                    collectionHeader(node)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            guard !selectedFiles.isEmpty else { return }
            // Se recorre `fm.files` para respetar el orden mostrado en la lista.
            filesPendingDeletion = fm.files.filter { selectedFiles.contains($0) }
            showDeleteConfirmation = true
        }
        .onChange(of: selectedFiles) { _, newVal in
            if newVal.count == 1 { activeFile = newVal.first }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            onDrop(providers)
        }
    }

    /// Cabecera del nodo: nombre, número de notas y tokens. Conserva el menú
    /// contextual de la colección (renombrar / borrar si está vacía).
    @ViewBuilder
    private func collectionHeader(_ node: CollectionNode) -> some View {
        HStack(spacing: 6) {
            Text(node.name ?? "Uncategorized")
                .font(.pastureSummary)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                .lineLimit(1)
            Spacer()
            Text("\(node.fileCount)")
                .font(.pastureSummary)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
        }
        .contentShape(Rectangle())
        .help("\(node.fileCount) note\(node.fileCount == 1 ? "" : "s"), ~\(TokenEstimator.formatted(node.totalTokens)) tokens")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.name ?? "Uncategorized"), \(node.fileCount) notes, approximately \(TokenEstimator.formatted(node.totalTokens)) tokens")
        .contextMenu {
            if let name = node.name {
                collectionHeaderContextMenu(collectionName: name, isEmpty: node.files.isEmpty)
            }
        }
    }
```

- [ ] **Step 3: Compilar**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift build 2>&1 | tail -20
```

Esperado: compila sin errores. Si el type-checker se atraganta en `fileList`, extraer el `ForEach` a un `@ViewBuilder` aparte — es un problema conocido de este fichero (`ContentView` ya usa ese truco con `presetSheetsAndAlerts`).

- [ ] **Step 4: Ejecutar la suite completa**

```bash
cd /Users/eula/Desktop/Claude/Pasture
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test 2>&1 | tail -10
```

Esperado: todo verde, ≥711 tests más los 16 nuevos.

- [ ] **Step 5: Comprobar a mano las cuatro conductas**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift run
```

1. El sidebar abre **plegado**: se ven ~23 cabeceras, no 673 filas.
2. Desplegar `Mercados`, cerrar la app (Cmd+Q), volver a `swift run`: sigue desplegada.
3. Escribir algo en el buscador: las colecciones con coincidencias se ven abiertas. Borrar la búsqueda: vuelve el pliegue anterior, con `Mercados` abierta y el resto cerrado.
4. Con dos colecciones abiertas, seleccionar con Cmd una nota de cada una: las dos quedan seleccionadas y el resumen inferior dice "2 selected".

Si el punto 3 falla, el problema está en el `Binding`, no en el store: los tests de la Task 3 ya cubren la lógica.

- [ ] **Step 6: Commit**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git add Sources/Pasture/SidebarView.swift
git commit -m "feat: collapsible collection tree in the sidebar"
```

---

### Task 5: Retirar `New File`

**Files:**
- Modify: `Sources/Pasture/PastureApp.swift:16-20` y `:66`
- Modify: `Sources/Pasture/ContentView.swift:12`, `:53-55`, `:92-102`, `:183-187`

**Interfaces:**
- Consumes: nada.
- Produces: nada. `MDFileManager.create(name:content:collection:)` **no se toca** — lo usan Paste, el Quick Capture de v1.9 y `ProposalPromoter`.

- [ ] **Step 1: Vaciar el comando de menú, sin borrar el grupo**

En `Sources/Pasture/PastureApp.swift`, sustituir las líneas 16-20 por:

```swift
            // Grupo vacío a propósito: suprime el comando "New" por defecto de
            // SwiftUI. Borrar el CommandGroup entero lo repondría.
            CommandGroup(replacing: .newItem) { }
```

- [ ] **Step 2: Borrar la notificación `.newFile`**

En el mismo fichero, borrar de la extensión `Notification.Name` la línea:

```swift
    static let newFile = Notification.Name("newFile")
```

- [ ] **Step 3: Borrar el estado, el `onReceive`, la sheet y el botón**

En `Sources/Pasture/ContentView.swift`, borrar estos cuatro bloques:

Línea 12:
```swift
    @State private var showNewFileSheet = false
```

Líneas 53-55:
```swift
        .onReceive(NotificationCenter.default.publisher(for: .newFile)) { _ in
            showNewFileSheet = true
        }
```

Líneas 92-102, la sheet entera:
```swift
        .sheet(isPresented: $showNewFileSheet) {
            NameInputSheet(title: "New file", actionLabel: "Create") { name in
                // Nace en la colección activa, igual que una nota pegada.
                // Los fallos de `create` llegan al usuario por `fm.lastError`.
                if let created = fm.create(name: name, content: "", collection: activeFile?.collection) {
                    selectFile(created)
                    // `created.name` y no `name`: la deduplicación puede haberlo cambiado.
                    feedService.showFeedback("Created '\(created.name).md'")
                }
            }
        }
```

Líneas 183-187, el botón de la toolbar:
```swift
            Button { showNewFileSheet = true } label: {
                Label("New File", systemImage: "doc.badge.plus")
            }
            .help("Create a new empty note")
            .accessibilityLabel("New file")
```

- [ ] **Step 4: Verificar que no queda ni un rastro**

```bash
cd /Users/eula/Desktop/Claude/Pasture
grep -rn "showNewFileSheet\|\.newFile\b\|New File" Sources/ || echo "LIMPIO"
```

Esperado: `LIMPIO`. Cualquier coincidencia es una referencia huérfana que hay que borrar. (Ojo: `MDFileManager.swift:251` y `MDFileManager+Import.swift:42` tienen variables locales llamadas `newFile` — esas **se quedan**, no son lo mismo; el `grep` usa `\.newFile\b` para no cazarlas.)

- [ ] **Step 5: Compilar y ejecutar la suite**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift build 2>&1 | tail -10
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test 2>&1 | tail -10
```

Esperado: compila y todo verde.

- [ ] **Step 6: Comprobar el menú a mano**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift run
```

Abrir el menú **File** de la barra de menús: no aparece "New File". Pulsar **Cmd+N**: no ocurre nada (ni se abre una sheet ni una ventana nueva). Este segundo punto es el que demuestra que el `CommandGroup` vacío hace su trabajo.

- [ ] **Step 7: Commit**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git add Sources/Pasture/PastureApp.swift Sources/Pasture/ContentView.swift
git commit -m "feat: remove New File command, button and sheet"
```

---

### Task 6: Toolbar de 10 elementos a 7, y arreglo de los tooltips

**Files:**
- Modify: `Sources/Pasture/ContentView.swift`, `toolbarContent` (a partir de la línea ~176, ya sin el botón de la Task 5)

**Interfaces:**
- Consumes: el diagnóstico de la Task 1 (`docs/superpowers/specs/2026-09-18-tooltip-diagnosis.md`); los métodos ya existentes `startPasteFlow()`, `importFromDisk()`, `scanFolderFromDisk()`, `exportFeedToDisk()`, y el estado `showNewCollectionSheet`.
- Produces: nada.

**Antes de empezar: leer el diagnóstico de la Task 1.** Si concluyó la hipótesis 2 (`.help()` no se propaga desde el `Button`), además de agrupar hay que **mover cada `.help()` al `Label`** en los 7 elementos que queden. Si concluyó la hipótesis 1 (desbordamiento), la agrupación **es** el arreglo y los `.help()` se quedan donde están.

- [ ] **Step 1: Sustituir los cuatro botones por un menú `+`**

En `Sources/Pasture/ContentView.swift`, reemplazar los bloques de **New Collection, Paste, Import y Scan Folder** por este único menú, que va el primero del grupo:

```swift
            Menu {
                Button { showNewCollectionSheet = true } label: {
                    Label("New Collection\u{2026}", systemImage: "folder.badge.plus")
                }

                Divider()

                Button { startPasteFlow() } label: {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
                Button { importFromDisk() } label: {
                    Label("Import Files\u{2026}", systemImage: "square.and.arrow.down")
                }
                Button { scanFolderFromDisk() } label: {
                    Label("Scan Folder\u{2026}", systemImage: "folder.badge.questionmark")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .help("Add: new collection, paste, import files or scan a folder")
            .accessibilityLabel("Add content")
```

El grupo queda, en orden: `+`, Export, Merge (condicional), Ask, Presets, Feed, Refresh. **Siete elementos.**

- [ ] **Step 2: Aplicar el arreglo de tooltips que dicte el diagnóstico**

**Solo si la Task 1 confirmó la hipótesis 2.** Mover el modificador dentro del `label:` en los 7 elementos. Patrón, con Export como ejemplo:

```swift
            Button { exportFeedToDisk() } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .help("Export context as .md to any location")
            }
            .disabled(targets.isEmpty)
            .accessibilityLabel("Export context")
```

Si la Task 1 confirmó la hipótesis 1, **saltar este paso**: los `.help()` se quedan tal cual.

- [ ] **Step 3: Compilar y ejecutar la suite**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift build 2>&1 | tail -10
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test 2>&1 | tail -10
```

Esperado: compila y todo verde.

- [ ] **Step 4: Verificar los tooltips uno a uno, que es el objetivo de la petición**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift run
```

Con la ventana a su **ancho habitual** (no maximizada — así se prueba de verdad que ya no desborda), pasar el ratón 2 segundos sobre cada uno de los 7 elementos y anotar cuáles muestran tooltip:

| Elemento | ¿Tooltip? |
|---|---|
| `+` (Add) | |
| Export | |
| Ask | |
| Presets | |
| Feed | |
| Refresh | |
| Merge (con 2 notas seleccionadas) | |

Esperado: **los 7**. Si alguno falla, el diagnóstico de la Task 1 era incompleto: volver a él antes de commitear.

Comprobar además que los cuatro comandos del menú `+` siguen funcionando: New Collection abre su sheet, Paste crea una nota desde el portapapeles, Import abre el panel de ficheros y Scan Folder el de carpetas.

- [ ] **Step 5: Commit**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git add Sources/Pasture/ContentView.swift
git commit -m "feat: group add actions into one toolbar menu and fix tooltips"
```

---

### Task 7: Fundir los dos banners del sidebar en una sola franja

**Files:**
- Modify: `Sources/Pasture/SidebarView.swift`, `inboxBanner` (líneas ~66-92) y `reviewBanner` (líneas ~94-119), más su uso en `body` (líneas ~24-25)

**Interfaces:**
- Consumes: `fm.pendingProposals.count`, `fm.staleFiles()`, y los estados ya existentes `showInbox` / `showReviewQueue`.
- Produces: nada.

**Contexto.** Hoy son dos filas independientes que pueden apilarse encima de la lista, cada una con su divisor. Pasan a ser **una sola franja** con hasta dos avisos. Cada aviso conserva su acción y su etiqueta de accesibilidad; no se pierde información, solo altura.

- [ ] **Step 1: Sustituir los dos banners por una franja única**

En `Sources/Pasture/SidebarView.swift`, reemplazar `inboxBanner` y `reviewBanner` enteros por:

```swift
    /// Franja de avisos: propuestas pendientes (v1.8) y notas caducadas (v1.7).
    /// Una sola fila con hasta dos avisos, en vez de dos filas apiladas.
    @ViewBuilder
    private var statusStrip: some View {
        let proposals = fm.pendingProposals.count
        let stale = fm.staleFiles().count
        if proposals > 0 || stale > 0 {
            HStack(spacing: 12) {
                if proposals > 0 {
                    Button { showInbox = true } label: {
                        statusChip(
                            icon: "tray.and.arrow.down",
                            tint: Color.pastureAccent(colorScheme),
                            text: "Inbox (\(proposals))"
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Agent proposals waiting for your review")
                    .accessibilityLabel("Review inbox, \(proposals) proposals pending")
                }
                if stale > 0 {
                    Button { showReviewQueue = true } label: {
                        statusChip(
                            icon: "clock.badge.exclamationmark",
                            tint: Color.pastureWarning(colorScheme),
                            text: "\(stale) to review"
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Notes past their review date")
                    .accessibilityLabel("Review queue, \(stale) notes need review")
                }
                Spacer()
            }
            .padding(.horizontal, PastureLayout.searchBarHPadding)
            .padding(.vertical, 6)
            Color.pastureDivider(colorScheme).frame(height: 1)
        }
    }

    private func statusChip(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.pastureStatusBar)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
        }
        .contentShape(Rectangle())
    }
```

- [ ] **Step 2: Cambiar el `body` para usar la franja**

En el `VStack` del `body` (líneas ~22-29), sustituir las dos líneas:

```swift
            inboxBanner
            reviewBanner
```

por una sola:

```swift
            statusStrip
```

- [ ] **Step 3: Compilar y ejecutar la suite**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift build 2>&1 | tail -10
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test 2>&1 | tail -10
```

Esperado: compila y todo verde.

- [ ] **Step 4: Verificar a mano los dos avisos**

```bash
cd /Users/eula/Desktop/Claude/Pasture
swift run
```

La vault tiene una propuesta pendiente en el inbox (`Mercados/mercado-portugues.md`), así que el aviso de Inbox debe verse. **No rechazarla: sirve de material de prueba.** Pulsarla debe abrir `ReviewInboxSheet`.

Si hay notas caducadas, el segundo aviso aparece **en la misma fila**, no debajo. Pulsarlo abre `ReviewQueueSheet`.

Sin propuestas ni notas caducadas, la franja **no ocupa altura** y el buscador queda pegado a la lista.

- [ ] **Step 5: Commit**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git add Sources/Pasture/SidebarView.swift
git commit -m "feat: merge inbox and review banners into one status strip"
```

---

### Task 8: Versión, changelog y QA visual de cierre

**Files:**
- Modify: `scripts/bundle.sh` (variable `VERSION`)
- Modify: `CHANGELOG.md`
- Modify: `CLAUDE.md` (secciones "PastureKit models" y "Bundle ID & versioning")

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: la release 1.11.0 lista para PR.

- [ ] **Step 1: Subir la versión**

```bash
cd /Users/eula/Desktop/Claude/Pasture
grep -n "^VERSION=" scripts/bundle.sh
```

Cambiar el valor a `1.11.0`.

- [ ] **Step 2: Escribir la entrada del changelog**

Añadir al principio de `CHANGELOG.md`, bajo la cabecera, en formato Keep a Changelog:

```markdown
## [1.11.0] - 2026-09-18

### Added
- El sidebar agrupa las notas en colecciones plegables, plegadas por defecto: con 673 notas ahora abre con ~23 filas en vez de 673. El pliegue se recuerda entre sesiones.
- Cada cabecera de colección muestra su número de notas y su total de tokens.

### Changed
- Las acciones de añadir contenido (New Collection, Paste, Import, Scan Folder) se agrupan en un único menú `+` de la toolbar, que pasa de 11 elementos a 7.
- Los avisos de Inbox y de cola de revisión se funden en una sola franja.

### Removed
- **New File**: fuera el botón de la toolbar, el atajo Cmd+N y su diálogo. Las notas se crean con Paste, Import, Scan Folder, el Quick Capture global o el editor externo.

### Fixed
- Los tooltips de la toolbar vuelven a aparecer al pasar el ratón.
```

- [ ] **Step 3: Actualizar CLAUDE.md**

En la sección **PastureKit models**, añadir dos entradas junto a las de `ContextLimit` y `SelectionPresetStore`:

```markdown
- **`SidebarTree`** — Pure `nonisolated` enum. `build(files:collections:base:hidingEmpty:)` groups a flat `[MDFile]` into `[CollectionNode]` (`name: String?` — `nil` is *Uncategorized*, which sorts first and is omitted when empty). Does not sort: it preserves the order of both inputs, so the sort criterion lives in one place (`SidebarView.sortedFiles`). `hidingEmpty` drops collections with no matches while a search is active. `CollectionNode.id` is prefixed (`"u:"` / `"c:<name>"`) so a collection literally named `""` cannot collide with the vault root.
- **`CollectionExpansionStore`** — Static namespace persisting the set of expanded collections in UserDefaults, keyed by `CollectionNode.id` (same pattern as `SelectionPresetStore`). `effectiveExpansion(stored:nodeID:isSearching:)` and `applying(_:to:nodeID:isSearching:)` are pure: **while a search is active every collection reads as expanded and the stored state is never written**, so clearing the search restores the previous collapse state. That invariant is guarded by `searchDoesNotWriteState` and validated by mutation.
```

En **Bundle ID & versioning**, cambiar `Current version: **1.10.0**` por `**1.11.0**`.

- [ ] **Step 4: QA visual completa, con la app instalada**

Nada de lo automatizado prueba que un `DisclosureGroup` se pliegue ni que un tooltip salga. Construir el bundle y ejercitar la checklist del spec:

```bash
cd /Users/eula/Desktop/Claude/Pasture
./scripts/bundle.sh
open dist/
```

Lanzar `dist/Pasture.app` (no `swift run`: el bundle es lo que usa el usuario, y `SystemNotifier` degrada a stderr sin bundle) y recorrer los seis puntos:

1. El sidebar arranca plegado, ~23 filas.
2. Plegar y desplegar varias colecciones, cerrar y reabrir la app: el estado sobrevive.
3. Buscar: las colecciones con coincidencias se abren. Borrar la búsqueda: vuelve el pliegue previo.
4. Seleccionar notas de dos colecciones distintas y hacer Feed: el portapapeles lleva las dos.
5. Los **7** elementos de la toolbar muestran tooltip al ancho habitual de ventana.
6. Menú File sin rastro de New File, y Cmd+N no hace nada.

Anotar el resultado de cada punto. **Un punto en rojo bloquea el cierre**; no se da por terminado con "debería funcionar".

- [ ] **Step 5: Commit y push**

```bash
cd /Users/eula/Desktop/Claude/Pasture
git add scripts/bundle.sh CHANGELOG.md CLAUDE.md
git commit -m "chore: release 1.11.0"
git push -u origin feat/v1.11-sidebar-tree-simplify
```

- [ ] **Step 6: Abrir el PR con la checklist de QA en el cuerpo**

```bash
cd /Users/eula/Desktop/Claude/Pasture
gh pr create --title "v1.11.0: collapsible sidebar tree, toolbar slimming, New File removal" --body "$(cat <<'EOF'
Implementa `docs/superpowers/specs/2026-09-18-sidebar-tree-simplification-design.md`.

## Qué cambia
- Sidebar: colecciones plegables, plegadas por defecto. Con 673 notas abre con ~23 filas.
- Toolbar: de 11 elementos a 7; las acciones de añadir se agrupan en un menú `+`.
- `New File` retirado por completo (botón, Cmd+N y sheet).
- Tooltips de la toolbar arreglados — causa observada en `docs/superpowers/specs/2026-09-18-tooltip-diagnosis.md`.
- Los avisos de Inbox y revisión se funden en una franja.

## Qué NO cambia
`FileLibrary`, el servidor MCP, los presets y los packs siguen viendo la misma lista plana. La selección múltiple entre colecciones se conserva.

## Checklist de QA visual
- [ ] El sidebar arranca plegado, ~23 filas
- [ ] El pliegue sobrevive a cerrar y reabrir la app
- [ ] Buscar abre las colecciones con coincidencias; borrar la búsqueda restaura el pliegue previo
- [ ] Feed con notas de dos colecciones distintas
- [ ] Los 7 elementos de la toolbar muestran tooltip
- [ ] Menú File sin New File; Cmd+N no hace nada

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Notas para quien ejecute

- **La Task 1 va primero y puede cambiar la Task 6.** No adelantes el arreglo de tooltips sin el diagnóstico.
- **La Task 2 y la Task 3 son independientes entre sí** y pueden ir en paralelo; la Task 4 depende de las dos.
- Las Tasks 5, 6 y 7 tocan ficheros distintos de la Task 4, pero **la Task 6 asume que la Task 5 ya quitó el botón New File** de la toolbar (por eso habla de 10 elementos de partida, no 11).
- Si algo de este plan choca con el código real —números de línea que se han movido, un `ViewBuilder` que el type-checker no traga—, **para y dilo** en vez de improvisar: los números de línea son del estado en `7f2d67d`.
