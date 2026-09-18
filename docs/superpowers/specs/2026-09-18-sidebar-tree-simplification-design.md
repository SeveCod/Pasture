# Simplificación de Pasture: árbol por colección, tooltips y retirada de New File

Fecha: 2026-09-18
Estado: aprobado (diseño). Pendiente de plan de implementación.

## Problema

La ventana principal de Pasture no escala a la vault real del usuario y sus
tooltips no llegan a verse.

Medido sobre `~/.pasture/` el 2026-09-18:

| Dato | Valor |
|---|---|
| Notas `.md` totales | 673 |
| Notas sueltas en la raíz (*Uncategorized*) | 96 |
| Colecciones de primer nivel | 22 |
| Notas en la colección mayor (`Desktop/`) | 500 |
| Subdirectorios anidados (nivel 2 o más) | 0 |

`SidebarView.fileList` construye un `List` con una `Section` por colección y
**todas las secciones están siempre desplegadas**: al abrir la app se pintan las
673 filas. No hay forma de plegar nada.

En paralelo, los 30 `.help()` que ya existen en la app **no se muestran al pasar
el ratón** (confirmado por el usuario sobre los botones de la toolbar). El texto
está escrito; lo que falla es que aparezca.

Y `New File` —añadido en v1.10— sobra: el usuario quiere que Pasture organice y
alimente contexto, no que sea un editor.

## Objetivos

1. Que el sidebar abra legible: colecciones plegables, plegadas por defecto.
2. Que los tooltips se vean al pasar el ratón.
3. Retirar `New File` por completo.
4. Adelgazar la toolbar y la cabecera del sidebar.

## No objetivos

- **Anidación real de subcolecciones.** Hoy no existe ni una en disco. Soportarla
  obligaría a tocar `FileLibrary`, `MDFile.collection`, los presets, el Context
  Compiler y el MCP. Queda fuera; si algún día hace falta, spec aparte.
- **Partir o reorganizar `Desktop/` (500 notas).** Plegada deja de estorbar; una
  vez abierta sigue siendo un muro. Se documenta, no se resuelve aquí.
- Cualquier cambio en el servidor MCP, en los packs o en los presets.

## Fase 0 — Diagnóstico de los tooltips

**Esta fase va primero y puede cambiar el resto del diseño.** No se escribe ni un
`.help()` nuevo hasta saber por qué no se ven los que ya hay.

Hipótesis, por orden de probabilidad:

1. **Desbordamiento de la toolbar.** `ContentView.toolbarContent` mete 11
   elementos en un único `ToolbarItemGroup(placement: .primaryAction)`. Cuando no
   hay ancho, macOS los empuja al chevron `»`, y un elemento desbordado no
   muestra tooltip. Comprobación: ensanchar la ventana hasta que quepan los 11 y
   volver a pasar el ratón.
2. **`.help()` sobre un `Button` dentro de `ToolbarItemGroup` no se propaga en
   macOS 26.** Comprobación: mover el modificador al `Label` en un solo botón y
   comparar con sus vecinos.

Prueba de control ya presente en el código: `EditorStatusBar.swift:53` lleva un
`.help()` en un botón normal, fuera de la toolbar. Si ese sí aparece y los de la
toolbar no, la causa está en la toolbar; si tampoco aparece, el problema es más
de fondo y hay que replantear esta fase.

Criterio de salida: una causa **observada**, no supuesta, y el arreglo derivado
de ella. Si la causa resulta ser la 1, la simplificación de la toolbar (más
abajo) es a la vez el arreglo.

## Árbol plegable del sidebar

### Tipos nuevos en PastureKit

Ambos puros y probables en aislamiento, siguiendo el patrón ya establecido por
`ContextLimit` y `PresetResolver` (sin I/O propio, `nonisolated`).

**`SidebarTree`** — transforma `[MDFile]` en `[CollectionNode]`.

- `CollectionNode`: `name: String?` (`nil` = *Uncategorized*), `files: [MDFile]`,
  `fileCount: Int`, `totalTokens: Int`.
- El nodo *Uncategorized* va siempre el primero, y **solo aparece si tiene
  ficheros**.
- El resto respeta el orden alfabético que `MDFileManager.refreshCollections`
  ya garantiza (`localizedCaseInsensitiveCompare`).
- Dentro de cada nodo, los ficheros conservan el criterio de orden activo
  (`FileSortOrder.date` o `.name`), que hoy aplica `SidebarView.sortedFiles`.
- Una colección **vacía** sigue apareciendo (es la única vía para borrarla desde
  su menú contextual, comportamiento actual que no se toca).

**`CollectionExpansionStore`** — persistencia en UserDefaults del conjunto de
colecciones abiertas, por nombre. Mismo patrón de namespace estático que
`ExportSettings` / `SelectionPresetStore`. Una colección que desaparece del disco
deja una entrada huérfana inofensiva; no se purga.

### Cambios en SidebarView

Cada `Section` pasa a `DisclosureGroup`. La cabecera muestra nombre, número de
notas y tokens totales, y conserva íntegro su menú contextual actual (renombrar,
borrar si está vacía).

**Todo plegado por defecto.** El sidebar abre con ~23 filas en vez de 673.

**Regla de la búsqueda, el invariante central de esta fase:** mientras
`fm.searchQuery` no esté vacía, el estado de pliegue se **ignora** —las
colecciones con coincidencias se muestran abiertas— y el estado guardado **no se
escribe**. Al borrar la búsqueda, el sidebar vuelve exactamente al pliegue previo.

Lo que **no** cambia: `List(selection: $selectedFiles)` sigue siendo la misma
selección múltiple plana. Feed, Presets, Merge, Ask y el Context Compiler
dependen de que se puedan seleccionar ficheros de varias colecciones a la vez, y
eso se conserva tal cual.

## Retirada de New File

Se elimina:

- El botón de la toolbar (`ContentView.swift:183-187`).
- El estado `showNewFileSheet` y su `.sheet`.
- La notificación `.newFile` y su `onReceive`.
- El `Button("New File")` con `.keyboardShortcut("n")` de `PastureApp`.

**`CommandGroup(replacing: .newItem)` se deja vacío, no se borra.** Hoy ese grupo
sustituye el comando "New" por defecto de SwiftUI; al borrarlo entero, SwiftUI lo
repone, que es justo lo contrario de lo pedido.

`MDFileManager.create(name:content:collection:)` **se queda**: lo usan el flujo de
Paste, el Quick Capture de v1.9 y la promoción de propuestas del Memory Inbox.

Consecuencia asumida: crear una nota vacía desde la interfaz deja de ser posible.
Quedan Paste (⌘⇧V), Import, Scan Folder, el Quick Capture global y el editor
externo.

## Simplificación

### Toolbar: de 11 elementos a 7

Un único botón `+` con menú agrupa **New Collection, Paste, Import y Scan
Folder**. En la barra quedan, en este orden: `+`, Export, Merge (condicional a
selección múltiple, como hoy), Ask, Presets, Feed, Refresh.

Además de ser el adelgazamiento pedido, es la comprobación directa de la
hipótesis 1 de la Fase 0.

### Sidebar

Los banners de Inbox (`inboxBanner`) y de cola de revisión (`reviewBanner`) se
funden en **una sola franja** de estado: hoy pueden apilarse como dos filas
separadas antes de la lista. Cada aviso conserva su acción (abrir
`ReviewInboxSheet` y `ReviewQueueSheet` respectivamente) y su etiqueta de
accesibilidad.

Se quedan como están: el buscador, el menú de orden y el resumen de selección con
el presupuesto de tokens. Ese resumen es la única señal que impide pasarse de la
ventana de contexto del modelo; retirarlo sería perder información, no simplificar.

## Pruebas y verificación

**Automatizado (PastureKit, Swift Testing, TDD):**

- `SidebarTree`: agrupación correcta, *Uncategorized* primero y solo si tiene
  ficheros, recuentos y tokens por nodo, orden alfabético de colecciones, ambos
  criterios de orden dentro del nodo, colección vacía presente.
- `CollectionExpansionStore`: alta, baja, persistencia, nombre inexistente.
- **Anulación por búsqueda**: con búsqueda activa el pliegue se ignora y el estado
  guardado no se modifica. Este test se escribe **antes** de la implementación y
  se valida por mutación: al quitar la anulación, debe caer.

**Manual, obligatorio antes de dar nada por hecho:**

Nada de lo anterior prueba que un `DisclosureGroup` se pliegue ni que un tooltip
salga. El cierre es QA visual en la app instalada:

1. Abrir con la vault real: el sidebar arranca plegado, ~23 filas.
2. Plegar/desplegar varias colecciones, cerrar y reabrir la app: el estado
   sobrevive.
3. Buscar: las colecciones con coincidencias se abren. Borrar la búsqueda: vuelve
   el pliegue previo.
4. Seleccionar ficheros de dos colecciones distintas y hacer Feed.
5. Pasar el ratón por los 7 elementos de la toolbar: **los 7 muestran tooltip**.
6. Menú File: no queda rastro de New File, y ⌘N no hace nada.

## Riesgos

- **El pliegue por defecto cambia lo primero que se ve al abrir la app.** Es el
  objetivo, pero es un cambio de hábito notable.
- **La Fase 0 puede invalidar el arreglo de tooltips previsto.** Por eso va
  primero y su criterio de salida es una causa observada.
- **El CI compila más estricto que el toolchain local** (lección de v1.10): el
  veredicto es el de GitHub Actions, no el build local.
- Localmente, `swift test` con las Command Line Tools falla por falta del módulo
  `Testing`; hay que usar
  `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test`.

## Dudas y asunciones

- Se asume que "no aparece ningún tooltip" se refiere a los botones de la toolbar,
  que es lo que se preguntó. Si tampoco salen fuera de ella, la Fase 0 lo
  detectará con la prueba de control de `EditorStatusBar`.
- Se asume que las colecciones vacías deben seguir mostrándose, porque es el
  comportamiento actual y la única vía de borrarlas desde la interfaz.
- Se asume que `Refresh` sigue haciendo falta pese al `DirectoryWatcher`; no se
  retira porque no se ha pedido.
