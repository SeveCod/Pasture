# UX / Accesibilidad — score 82/100

## Resumen

La base de accesibilidad que dejó la v1.10 sigue en pie y es buena: prácticamente todos los controles solo-icono llevan `accessibilityLabel`, los iconos decorativos están ocultos, Reduce Motion se respeta en los cuatro sitios donde hay animación, y los pares de color del sistema de diseño **miden AA de verdad** (los 44 pares que calculé están todos ≥4,5:1 en su uso real).

Lo que la v1.11 dejó suelto no es la retirada de New File —que es una decisión de producto escrita y razonada en el spec— sino dos cosas: su **objetivo declarado nº 2, los tooltips, quedó sin cerrar y con su arreglo revertido**, y el hueco que abre la retirada tiene un borde real (el botón Import no acepta `.md`, y el empty state no nombra ninguna de las vías que quedan).

En errores: hay tres sitios donde un fallo muere en silencio (guardar la API key en el Keychain, la continuación del feed en el popover, y el segundo alert de la bandeja). Los diálogos destructivos tienen el default seguro en todos los casos revisados menos uno (borrar un pack no confirma).

---

## Hallazgos altos

### A1 · El objetivo nº 2 de la v1.11 (tooltips) quedó sin cerrar, y su arreglo se revirtió

**Evidencia:**
- `docs/superpowers/plans/2026-09-18-sidebar-tree-simplification.md:27-139` — la Task 1 era diagnosticar por qué no se ve ningún `.help()` de la toolbar, con entregable obligatorio `docs/superpowers/specs/2026-09-18-tooltip-diagnosis.md`. **Ese fichero no existe** (`ls docs/superpowers/specs/` no lo lista).
- `docs/superpowers/specs/2026-09-18-sidebar-tree-simplification-design.md` — hipótesis 1: 11 elementos en un solo `ToolbarItemGroup` desbordan al chevron `»`, y un elemento desbordado no muestra tooltip. «Si la causa resulta ser la 1, la simplificación de la toolbar es a la vez el arreglo.»
- Commit `b9715a6` agrupó las cuatro acciones en un `+` (el arreglo). Commit `80a6379` (HEAD) **lo revierte**: «the toolbar now holds 10 items».
- `ContentView.swift:165-242` — hoy son, en efecto, 10 controles dentro de un único `ToolbarItemGroup(placement: .primaryAction)`.

**Por qué importa:** uno de los tres objetivos de la versión se cerró sin evidencia observada y con el cambio que lo implementaba deshecho. Si la causa era la 1, los tooltips siguen exactamente igual de invisibles que antes de la rama. Es el patrón «cifra autoestimada» aplicado a una corrección: no hay una sola observación registrada.

**Fix propuesto:** ejecutar la Task 1 tal cual está escrita (2 experimentos, 15 min) y, según el resultado, o bien mover los `.help()` al `Label` de cada botón (hipótesis 2, cambio mecánico de 10 líneas), o bien aceptar que con 10 iconos discretos el tooltip no se puede garantizar a ancho de ventana normal y documentarlo. **Esfuerzo: bajo (diagnóstico) + bajo (fix).** No tocar nada antes del diagnóstico.

---

### A2 · El botón «Import» no acepta `.md`, justo después de retirar la única vía de crear una nota

**Evidencia:** `ContentView.swift:427-433`
```swift
var types: [UTType] = [.pdf, .commaSeparatedText]
if let docxType = UTType(filenameExtension: "docx") { types.append(docxType) }
if let docType  = UTType(filenameExtension: "doc")  { types.append(docType) }
panel.allowedContentTypes = types
```
`MDFileManager+Import.swift` sí sabe copiar un `.md` tal cual, y el drag & drop sí lo permite (`ContentView.swift:473`). Es el panel el que lo excluye.

**Por qué importa:** con New File retirado, las vías de creación son Paste, Import, Scan Folder, Quick Capture y el editor externo. De esas, **Import es la única pensada para traer un fichero concreto, y no puede traer un Markdown suelto** — hay que arrastrarlo o escanear su carpeta entera. Antes de la v1.11 el hueco se tapaba solo; ahora se nota.

**Fix:** añadir `UTType(filenameExtension: "md")` (o `.plainText`) a `types` y actualizar el `panel.message`. **Esfuerzo: trivial.**

---

### A3 · Alerts encadenados en `ReviewInboxSheet`: el segundo se traga

**Evidencia:** `ReviewInboxSheet.swift:73-109` — tres `.alert` sobre el mismo `VStack`. El encadenamiento está en el código:
```swift
// :79-81  (dentro del alert de mismatch)
Button("Append anyway", role: .destructive) {
    apply(proposal, overrideChangedTarget: true)
}
```
y `apply` (`:235-251`) puede fijar `errorMessage` (`case .failure(let error)` → `.io`, `.targetMissing`, `.payloadMissing`, `.outsideVault`). Esa asignación ocurre **dentro de la acción del alert que se está descartando**: el `set:` del binding pone `mismatchProposal = nil` después. Durante ese instante hay dos condiciones de alert verdaderas en la misma vista.

**Veredicto completo en la sección dedicada más abajo.**

**Fix:** un único `@State private var activeAlert: InboxAlert?` (enum con los tres casos) y **un solo** `.alert(item:)`; o, mínimo, diferir la asignación del error al siguiente ciclo (`Task { @MainActor in errorMessage = … }`) para que no compita con el descarte. **Esfuerzo: medio (1 h).**

---

### A4 · El `FeedService` del popover muere con el popover, y se lleva el feed pendiente

**Evidencia:** `MenuBarView.swift:14` — `@StateObject private var feedService = FeedService()`; `MenuBarView.swift:39` — `.feedChrome(feedService, fm: fm)`, que instala el sheet de plantilla y el alert de secretos (`FeedChrome.swift:13-35`). La continuación del feed vive en `FeedService.pendingSecretProceed` (`FeedService.swift:24`), en memoria del objeto.

Un `MenuBarExtra(.window)` se cierra al perder el foco. Si al hacer Feed desde el popover salta el aviso de secretos o la sheet de plantilla, el popover pierde el foco, la vista se destruye y con ella el `@StateObject`: **la continuación se pierde y el feed nunca se entrega, sin ningún aviso**. El invariante de no-reentrada (`FeedService.swift:108-111`) tampoco ayuda: el objeto ya no existe.

**Por qué importa:** es el modo de fallo silencioso más caro que hay en esta app — el usuario cree que copió el contexto y el portapapeles tiene otra cosa. Es exactamente lo que el PR #6 dejó pendiente de QA.

**Fix:** mover el `FeedService` del popover a un objeto de ciclo de vida de app (propiedad de `PastureApp`, inyectado igual que `fm`), o bien, en el camino del popover, abrir la ventana principal antes de presentar cualquier sheet/alert. **Esfuerzo: medio.** Requiere QA visual para confirmar el síntoma, pero la estructura que lo produce es código verificado.

---

### A5 · Un fallo al guardar la API key en el Keychain no llega al usuario

**Evidencia:** `SettingsView.swift:339-347`
```swift
try AISettings.saveAPIKey(apiKeyInput, for: selectedProvider)
keySaved = true
hasKeychainKey = true
} catch {
    keySaved = false          // <- y nada más
}
```
`KeychainStore` lanza `KeychainError`; aquí se descarta. El único efecto visible es que **no** aparece el checkmark verde — una ausencia, no un mensaje. El usuario no puede distinguir «no se guardó» de «no pulsé bien».

**Por qué importa:** el síntoma se manifiesta mucho después, en el Ask, como «no API key configured», lejos de la causa.

**Fix:** un `@State errorText: String?` junto al campo, con `error.localizedDescription`. **Esfuerzo: trivial.** (Mismo patrón que ya usa el resto de la app con `lastError` → toast.)

---

### A6 · Renombrar y mover no tienen ninguna ruta de teclado

**Evidencia:** `SidebarView.swift:307-347` (menú contextual de fichero: Open in Editor, Rename…, Move to…, Delete) y `:350-366` (menú de colección: Rename Collection…, Delete Collection). Un `.contextMenu` solo se abre con clic derecho o Control-clic.

En la barra de menús (`PastureApp.swift:19-47`) hay Open in Editor (⌘E), Paste (⇧⌘V), Sync All Packs (⇧⌘P), Refresh Sources (⇧⌘R) y Toggle Ask (⇧⌘A). **Ninguna entrada de Rename, Move ni Delete.** Borrar sí tiene tecla (`.onDeleteCommand`, `SidebarView.swift:237`); renombrar y mover, nada.

**Por qué importa:** un usuario que navega solo con teclado (o con VoiceOver, donde invocar un menú contextual es posible pero laborioso) no puede renombrar una nota ni moverla de colección. Son dos de las tres operaciones de organización, que es la razón de ser declarada de la app.

**Fix:** llevar Rename (⏎ o ⌘R) y Move to… a un `CommandMenu` que opere sobre `activeFile`. **Esfuerzo: medio.**

---

## Hallazgos menores

### M1 · El `DisclosureGroup` no declara su estado en el código
`SidebarView.swift:226-233` + `:269-298`. La cabecera lleva `.accessibilityElement(children: .combine)` y un `accessibilityLabel` con nombre/recuento/tokens, pero **no hay `accessibilityValue`, ni `accessibilityAddTraits`, ni ninguna mención del estado plegado/desplegado**. SwiftUI suele aportarlo por su cuenta en el control de revelación, pero al combinar la etiqueta en un elemento propio deja de ser algo que se pueda afirmar leyendo este código. Añadir `.accessibilityValue(isExpanded ? "Expanded" : "Collapsed")` lo hace determinista y cuesta dos líneas (el binding ya existe: `expansionBinding(for:)`). **Confirmar el anuncio real requiere QA visual.**

### M2 · Borrar un pack no pide confirmación
`PacksSettingsTab.swift:108-115` — `PackStore.delete(id:)` directo, sin alert. Contrasta con borrar un preset (`ContentView.swift:552-567`, con alert y mensaje que explica que los ficheros no se tocan) y con borrar una colección (`SidebarView.swift:40-50`). Un pack lleva su preset, sus variables y hasta 20 destinos; rehacerlo a mano no es barato. Mismo alert que el de preset. **Esfuerzo: trivial.**

### M3 · El empty state no nombra ninguna vía de creación viva
`PastureEmptyState.swift:27` — «Select a file or paste content from the clipboard». Tras la v1.11 las vías son cinco y esta solo nombra una. Con la vault vacía y el portapapeles vacío, la pantalla no dice qué hacer (Import y Scan Folder están en la toolbar, sin texto). **Fix:** añadir una línea con las tres acciones y, si se quiere, botones. **Esfuerzo: bajo.**

### M4 · El botón «Ask» es el único botón mixto sin etiqueta combinada
`AskView.swift:391-409`. El `paperplane.fill` no está oculto y no hay `accessibilityElement(children: .combine)` ni `accessibilityLabel`, al revés que su gemelo `FeedButton` (`FeedAction.swift:101-122`) y que el botón Feed del `TemplateSheet` (`FeedAction.swift:187-202`, que sí oculta el icono). Inconsistencia con el patrón que la propia app fijó. **Esfuerzo: trivial.**

### M5 · Tres puntos decorativos sin ocultar en el empty state
`PastureEmptyState.swift:16-21` — `HStack` con tres `Circle()` puramente ornamentales. La hoja de encima sí lleva `.accessibilityHidden(true)` (`:14`); estos no. Probablemente inertes, pero rompen la regla que la v1.10 aplicó en todo lo demás.

### M6 · La tabla de atajos del README está incompleta y una fila es inexacta
`README.md:141-149` lista cuatro atajos. Faltan `⇧⌘P` (Sync All Packs) y `⇧⌘R` (Refresh Sources), ambos en `PastureApp.swift:32-40`, y los globales de la v1.9 `⌃⌥⌘F` / `⌃⌥⌘N`. La fila «Drag & drop — Import `.md` or `.pdf` files» se queda corta: `ContentView.swift:473` acepta `md, pdf, csv, docx, doc`. Bien: **⌘N ya no aparece** en el README ni en `CHANGELOG`, la retirada está correctamente documentada.

### M7 · Un `lastError` producido con la ventana principal cerrada no se ve
`ContentView.swift:124-129` es el **único** observador de `fm.lastError` en toda la app. `MenuBarView` usa el mismo `fm` (`applyPreset`, feed) y no lo observa. En modo solo-barra-de-menús (`IntegrationSettings.hideDockIcon`) un error de disco queda escrito en la propiedad y nadie lo pinta; al abrir después la ventana, `.onChange` tampoco dispara, porque el valor ya estaba puesto. Riesgo bajo (las rutas del popover apenas escriben), pero el observador debería estar en `feedChrome`, que ya comparten las dos vistas. **Esfuerzo: bajo.**

---

## Contraste: pares medidos

Ratios calculados con luminancia relativa sRGB, `(L1+0,05)/(L2+0,05)`, sobre los valores literales de `DesignTokens.swift:11-135`. Umbral AA texto normal 4,5:1; texto grande / UI 3:1.

| Token (texto) | Fondo | Hex | Ratio | AA |
|---|---|---|---:|---|
| `textPrimaryLight` | `sidebarLight` | `#1A1A18`/`#F6F5F2` | 15,99 | ✅ |
| `textPrimaryLight` | `editorLight` | `#1A1A18`/`#FDFCFA` | 17,00 | ✅ |
| `textSecondaryLight` | `sidebarLight` | `#6B6B65`/`#F6F5F2` | 4,92 | ✅ |
| `textSecondaryLight` | `statusBarLight` | `#6B6B65`/`#F2F1EE` | 4,75 | ✅ |
| `textTertiaryLight` | `sidebarLight` | `#666660`/`#F6F5F2` | 5,30 | ✅ |
| `textTertiaryLight` | `editorLight` | `#666660`/`#FDFCFA` | 5,64 | ✅ |
| `accentLight` | `sidebarLight` | `#3E7A3E`/`#F6F5F2` | 4,75 | ✅ |
| `accentLight` | `editorLight` | `#3E7A3E`/`#FDFCFA` | 5,05 | ✅ |
| `warningLight` (= `templateLight`) | `templateBgLight` | `#8F4F1A`/`#FDF3EB` | 5,81 | ✅ |
| `warningLight` | `sidebarLight` | `#8F4F1A`/`#F6F5F2` | 5,83 | ✅ |
| `errorLight` | `sidebarLight` | `#BF3838`/`#F6F5F2` | 5,02 | ✅ |
| `successLight` | `editorLight` | `#2F7A2F`/`#FDFCFA` | 5,19 | ✅ |
| `tokenBadgeTextLight` | `tokenBadgeBgLight` | `#3E6B3E`/`#EDF5ED` | 5,59 | ✅ |
| `textPrimaryDark` | `sidebarDark` | `#EDEDEB`/`#1E1E1C` | 14,24 | ✅ |
| `textSecondaryDark` | `editorDark` | `#9E9E98`/`#232321` | 5,85 | ✅ |
| `textTertiaryDark` | `sidebarDark` | `#A6A6A0`/`#1E1E1C` | 6,82 | ✅ |
| `accentDark` | `editorDark` | `#6B9F6B`/`#232321` | 5,10 | ✅ |
| `template` (dark) | `templateBgDark` | `#D4793B`/`#2E251B` | 4,72 | ✅ |
| `template` (dark) | `editorDark` | `#D4793B`/`#232321` | 4,95 | ✅ |
| `errorDark` | `editorDark` | `#E07A7A`/`#232321` | 5,42 | ✅ |
| `successDark` | `editorDark` | `#5A9F5A`/`#232321` | 4,90 | ✅ |
| `tokenBadgeTextDark` | `tokenBadgeBgDark` | `#8FBF8F`/`#2A3A2A` | 5,77 | ✅ |
| `textPrimaryLight` | gradiente Feed (extremo sage `#8BB88A`) | | 7,74 | ✅ |
| `textPrimaryLight` | gradiente Feed (extremo ámbar `#E8944A`) | | 7,28 | ✅ |

**Tarjeta de la bandeja** (`ReviewInboxSheet.swift:170`, `pastureDivider` al 35 %, compuesta): claro `#F4F4F2` → `successLight` **4,83** ✅, `textSecondaryLight` 4,87 ✅, `warningLight` 5,78 ✅. Oscuro sobre `editorDark` → `#272724`, `successDark` **4,67** ✅, `template` 4,71 ✅. Justos, pero pasan.

**Dos pares por debajo de 4,5, ninguno en uso real hoy:**

| Par | Ratio | Situación |
|---|---:|---|
| `textSecondaryDark` sobre `pastureSelectionDark` | **4,23** ❌ | `pastureSelection` solo se usa en `MenuBarFileRow.swift:38`, y allí el subtítulo es `textTertiary` (4,66 ✅) y el nombre `textPrimary`. **No hay texto secundario sobre selección en pantalla.** |
| `textSecondaryLight` sobre `pastureSelectionLight` | **4,45** ❌ | Mismo caso. |

No es una violación visible; es una **mina en el token**: el día que alguien ponga texto secundario sobre una fila seleccionada, falla AA sin que nada avise. Dos opciones: subir `textSecondary` o documentar en el token que sobre selección solo valen primary/tertiary.

**Decorativos, correctamente fuera del cómputo:** `pastureSageGreen` (2,20 sobre editor claro) y `pastureAmber` (2,34) solo aparecen como gradiente de fondo y como puntos ornamentales del empty state, nunca como texto.

---

## Veredicto sobre los alerts apilados de `ReviewInboxSheet`

**El riesgo es real, y el código lo demuestra a medias. Matizo lo que se puede afirmar y lo que no.**

Los tres `.alert` cuelgan del mismo `VStack` (`ReviewInboxSheet.swift:73`, `:86`, `:96`). Lo que **sí** se prueba leyendo el código:

1. **En el flujo normal son mutuamente excluyentes.** `apply` (`:239-251`) hace un `switch` y fija `mismatchProposal` **o** `errorMessage`, nunca los dos. `proposalPendingRejection` solo lo fija el botón Reject (`:159-162`), y mientras hay un alert en pantalla el botón no es alcanzable. Así que **el modo de fallo «Reject silencioso» que el PR #6 temía no se sostiene**: rechazar no compite con nada.

2. **El encadenamiento sí solapa dos condiciones.** La ruta es:
   ```
   Approve → apply(override: false) → .failure(.hashMismatch) → mismatchProposal = p   [alert 1]
   alert 1 → "Append anyway" → apply(override: true) → .failure(.io) → errorMessage = …  [alert 2]
   ```
   La acción del botón corre **antes** de que SwiftUI descarte el alert 1 (el `set:` del binding, `:76`, pone `mismatchProposal = nil` al descartarse). Durante ese solape hay dos condiciones verdaderas en el mismo nivel de la jerarquía. Presentar un alert mientras otro se descarta es el caso clásico en que SwiftUI se traga el segundo.

3. Lo que **no** puedo cerrar sin ejecutar la app: si el alert 2 se pierde del todo, si aparece con retraso, o si SwiftUI lo encola correctamente. Eso es comportamiento de runtime.

**Consecuencia si se traga:** el usuario pulsa «Append anyway», el escrito falla (`.io`, `.targetMissing`), **no ve nada**, y la propuesta sigue en la bandeja. Parecerá que la bandeja no responde. Es el mismo modo de fallo silencioso que el PR #6 buscaba, pero está en Approve→override, no en Reject.

**Recomendación:** no esperar a la QA. Unificar en un solo `.alert(item:)` con un enum elimina la clase entera de problema por construcción y es más corto que el código actual.

**Sobre el alert de secretos desde el popover:** no es un problema de apilamiento —`feedChrome` instala un `.sheet` y un `.alert` sobre vistas distintas, sin competencia— sino de **ciclo de vida del objeto que sostiene la continuación**. Detalle en A4.

---

## Requiere QA visual (no puntúa)

1. **Los tooltips de los 10 elementos de la toolbar.** Es la Task 1 nunca ejecutada. Con la ventana a ancho habitual, pasar el ratón 2 s por cada uno y anotar cuáles salen. Control: el `.help()` de `EditorStatusBar.swift:53`, fuera de la toolbar.
2. **Anuncio del `DisclosureGroup` con VoiceOver**: ¿dice «expandido/contraído»? ¿Se puede plegar con VO-Espacio? ¿Es alcanzable el triángulo o solo la etiqueta combinada?
3. **El encadenamiento del alert de la bandeja** (A3): forzar un `.io` tras «Append anyway» y ver si aparece «Could not apply proposal».
4. **Feed desde el popover con un secreto** (A4): ¿se queda el aviso en pantalla al cerrarse el popover? ¿Llega a copiarse algo?
5. **Dynamic Type al máximo**: quedan 28 `.font(.system(size:))` con punto fijo. Casi todos son símbolos SF decorativos (verificado uno a uno), pero `MenuBarFileRow.swift:15`, `SidebarView.swift:134/164` y `AskView.swift:384` afectan a controles; comprobar que nada se corta.
6. **Orden de foco por tabulador** en la ventana principal y en las sheets.
7. **Aumentar contraste (Increase Contrast)**: no hay ni un `colorSchemeContrast` en todo `Sources/Pasture/` (grep vacío). No es un fallo — la paleta ya va holgada de AA —, pero conviene mirar si el sistema la altera de forma indeseada.

---

## Justificación del score

**82/100.** Partiendo de 100:

- **−6 · A1** (tooltips): un objetivo declarado de la versión cerrado sin evidencia y con su arreglo revertido. No rompe nada, pero deja la versión sin cumplir lo que dice cumplir.
- **−5 · A4** (FeedService en el popover): pérdida silenciosa de un feed. Estructuralmente confirmado, síntoma pendiente de QA — por eso no pesa como crítico.
- **−4 · A3** (alerts encadenados): fallo de escritura invisible en la única puerta de escritura de un agente al vault.
- **−4 · A6** (sin teclado para renombrar/mover): dos de las tres operaciones de organización, inalcanzables sin ratón.
- **−3 · A2** (Import sin `.md`): hueco real abierto por la retirada de New File.
- **−2 · A5** (Keychain silencioso).
- **−4 · menores M1-M7** en conjunto.

**Lo que sostiene el 82:** los 44 pares de contraste medidos pasan AA en su uso real, con los dos únicos fallos en combinaciones que no se pintan; Reduce Motion está en los cuatro puntos con animación; las etiquetas de accesibilidad cubren prácticamente todos los controles solo-icono; los diálogos destructivos revisados (borrar ficheros, borrar colección, sobrescribir preset, borrar preset, limpiar conversación, rechazar propuesta, forzar sync de pack, aviso de secretos) tienen **todos** el default seguro en Cancel; y la tipografía es mayoritariamente relativa. Es una base sólida con remates pendientes, no una interfaz con problemas de fondo.

---

## Dudas y asunciones

1. **No ejecuté la app** (auditoría de código, read-only). Todo lo que depende de ver la pantalla está en «Requiere QA visual» y no puntúa.
2. **Asumo que retirar New File es una decisión de producto firme**, no un descuido: está escrita y argumentada en `docs/superpowers/specs/2026-09-18-…-design.md` («Consecuencia asumida: crear una nota vacía desde la interfaz deja de ser posible») y reflejada en el CHANGELOG. La audito por sus consecuencias, no por la decisión. Nótese que la v1.10 la había introducido un mes antes con el argumento contrario («antes no había vía de crear una nota»).
3. **Los ratios los calculé desde los literales `Color(red:green:blue:)`**, convertidos a sRGB de 8 bits. SwiftUI interpreta esos componentes en sRGB por defecto; si algún día se declararan en Display P3 los números cambiarían.
4. **Para los fondos compuestos** (la tarjeta de la bandeja, `divider.opacity(0.35)`) asumí como base `editorLight`/`editorDark` y blanco, porque el fondo real de la sheet lo pone el sistema y no está en el código.
5. **No audité `PastureKit`** salvo lo necesario para seguir una ruta de UI: el encargo es la capa de interfaz.
6. Asumo que el `ToolbarItemGroup` de 10 elementos es el estado final deseado (commit `80a6379` dice «the user prefers four discrete icons»), así que A1 propone diagnosticar y adaptar el arreglo, no volver a agrupar.
