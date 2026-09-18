# QA / Tests — score 72/100

## Resumen

La suite de PastureKit es genuinamente buena: 728 tests, cobertura por fichero prácticamente completa, aislamiento disciplinado de `UserDefaults` y reloj, y los dos guardas de seguridad más importantes (`PathValidator`, `MCPPathResolver`) **verificados por mutación real**: los mato y la suite se pone roja. No es una suite decorativa.

El problema está fuera de PastureKit. **De los 17 commits de `feat`/`fix` de v1.10 y v1.11, dieciséis tocaron solo `Sources/Pasture/` y ninguno añadió un test.** Toda la corrección de la pasada de UX/a11y es reversible en silencio, incluido el hotfix de producción del portapapeles de macOS 26.

Y hay una vacuidad confirmada por mutación: el contrato del `id` de `CollectionNode` — del que depende la GUI con una copia literal del prefijo — se puede cambiar sin que falle un solo test.

## Métricas medidas

| Métrica | Valor | Comando |
|---|---|---|
| Tests | **728** | `grep -c '@Test' Tests/PastureKitTests/*.swift \| awk -F: '{s+=$2} END{print s}'` |
| Suites | **77** | salida de `swift test` |
| Tests parametrizados (`arguments:`) | **0** | `grep -n '@Test.*arguments' Tests/PastureKitTests/*.swift` → vacío |
| Baseline | 728/728 verde, exit 0 | `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test` |
| Ficheros de PastureKit (62) sin suite asociada por nombre | 8, **todos cubiertos** por una suite de otro nombre (`ConversationTests`, `PackStoreTests`, `MCPProtocolTests`, `MCPVaultSecretStatTests`) | bucle sobre `Sources/PastureKit/**/*.swift` |
| Ficheros de `Sources/Pasture/` (34, **5.931 líneas**) con test | **0** | el test target solo depende de `PastureKit` (`Package.swift:24-28`) |
| Tests sin ninguna aserción | 1 (`KeychainStoreTests.swift:44`) | barrido AWK sobre bloques `@Test` |
| Tests que tocan la red | 0 (`AIClientTests` solo valida `buildRequest`) | `grep -l 'URLSession' Tests/` |
| Ficheros de test que dejan basura en `/tmp` | **10 de 19** que crean directorios temporales | `grep -L removeItem` sobre los que usan `temporaryDirectory` |

Nota: el recuento de 728 del CHANGELOG es **honesto** — no hay tests parametrizados que inflen el número frente a `@Test`.

---

## Hallazgos

### CRÍTICO 1 — Toda la pasada v1.10/v1.11 se puede revertir en silencio

Evidencia (`git show --stat` sobre cada commit del rango):

| Commit | Qué arregló | Ficheros | ¿Test? |
|---|---|---|---|
| `3fb633e` | portapapeles leído en el gesto del usuario (macOS 15.4+) | `ContentView.swift` | **no** |
| `78527cb` | borrar → Papelera en vez de destrucción permanente | `MDFileManager.swift`, 2 vistas | **no** |
| `bf463c6` | escaneo de carpeta vacía no deja colección residual | `MDFileManager+Import.swift`, 2 vistas | **no** |
| `341121e` + `8d3c2ce` | contraste WCAG AA (2,91 → ≥4,5; badge 4,15 → 4,73) | `DesignTokens.swift` + 7 vistas | **no** |
| `b261776`, `7527e56`, `8a4dd8c`, `5a8354a`, `2a958f3`, `c77e9ea`, `63d23d0`, `b91d8fe`, `209e29e`, `80a6379`, `8e9fc68` | resto de la pasada UX/a11y/simplificación | solo `Sources/Pasture/` | **no** |
| `c6b545d` | revisión final de la rama sidebar-tree | `SidebarTree.swift` + **8 líneas de test** | **sí** (único) |

**Por qué importa.** Es exactamente el modo de fallo que este repo ya documentó («un arreglo sin test de guardia se revierte en silencio», incidente de multimin del 27-jul). Los tres peores casos:

1. **`3fb633e` — el hotfix del portapapeles** (`ContentView.swift:105-109`). Bajo la privacidad de portapapeles de macOS 15.4+, leer `NSPasteboard.general.string(forType:)` fuera del gesto del usuario **devuelve `nil` en silencio**, y el `?? ""` anterior creaba un fichero en blanco sin error. El arreglo mueve la lectura a `startPasteFlow()`. Nada impide que un refactor futuro devuelva la lectura al botón de la hoja: el síntoma sería un fichero vacío, sin excepción ni log. Es el fix de mayor riesgo del repo sin guarda.
2. **`bf463c6` — `scanFolder`** (`MDFileManager+Import.swift:69,89-95`). La lógica es pura de decisión: `didCreateCollection` distingue «la creé yo en esta llamada» de «ya existía», y solo retira la colección en el primer caso. Es perfectamente testeable y no tiene test.
3. **`78527cb` — `trashItem`** (`MDFileManager.swift:295` y `:385`). Un `removeItem` accidental en lugar de `trashItem` destruye datos del usuario sin que nada avise.

**Fix propuesto.** Extraer a PastureKit las tres decisiones y testearlas ahí (ver hallazgo ALTO 3). Esfuerzo: 3-4 h para las tres.

---

### CRÍTICO 2 — Test vacuo confirmado por mutación: el contrato del `id` de `CollectionNode`

`Sources/PastureKit/SidebarTree.swift:17`

```swift
public var id: String { name.map { "c:\($0)" } ?? "u:" }
```

`Sources/Pasture/SidebarView.swift:258-266` **reconstruye ese mismo id a mano**:

```swift
private func expandCollection(of file: MDFile?) {
    guard let file, !isSearching else { return }
    let id = file.collection.map { "c:\($0)" } ?? "u:"   // ← copia literal del prefijo
    ...
}
```

**Mutación real ejecutada** (`git archive HEAD | tar -x` a un directorio del scratchpad, mutación solo en la copia): cambié el prefijo `"c:"` por `"X:"` en `SidebarTree.swift:17` y corrí la suite completa:

```
Test run with 728 tests in 77 suites passed after 0.643 seconds.
```

**728/728 en verde.** `idDisambiguates` (`SidebarTreeTests.swift:98`) no lo caza porque solo comprueba que los ids sean *distintos entre sí* y que el de la raíz sea `"u:"` — nunca afirma cuál es el prefijo de una colección. `CollectionExpansionStoreTests` usa literales `"c:Alpha"` pero recibe el nodeID como parámetro, así que es independiente del productor.

**Doble consecuencia de que nadie vigile ese prefijo:**
- La GUI y el Kit se desincronizan: el auto-despliegue de la colección del fichero activo deja de funcionar, y el síntoma es «creo una nota y queda seleccionada pero invisible» — justo lo que ese código existe para evitar (`SidebarView.swift:255-257`).
- El id es además **la clave persistida en `UserDefaults`** (`CollectionExpansionStore.swift:8`). Cambiarlo huerfaniza todo el estado de pliegue guardado de los usuarios, sin aviso.

**Fix propuesto.** Mover la construcción del id a PastureKit como única fuente (`CollectionNode.id(forCollection: String?) -> String`), hacer que `SidebarView` la llame, y añadir dos tests: uno que fije el formato exacto (`#expect(CollectionNode(name: "Alpha", files: []).id == "c:Alpha")`) y otro que exija `CollectionNode(name: n, files: []).id == CollectionNode.id(forCollection: n)`. Esfuerzo: 30 min.

---

### ALTO 1 — El invariante WCAG AA está declarado y no lo vigila nada

`CLAUDE.md` afirma: *«All text/background token pairs meet WCAG AA contrast (≥4.5:1) in both schemes — keep that invariant when adding or changing tokens.»* Y v1.10 corrigió medidas concretas: ámbar 2,91 → ≥4,5, tinte oscuro del badge 4,15 → 4,73 (`DesignTokens.swift`, commits `341121e` y `8d3c2ce`).

```
$ grep -rn 'contrast\|WCAG\|luminance\|4\.5' Tests/ Sources/PastureKit/
(sin resultados)
```

**Por qué importa.** El ratio de contraste es **aritmética pura** sobre dos valores RGB: es de lo más testeable que hay en esta app. Que un invariante numérico, declarado por escrito y ya violado una vez, viva solo en literales hexadecimales de un fichero SwiftUI es la definición de arreglo sin guarda. Cualquiera que retoque una paleta puede volver a bajar de 4,5 sin que nada lo diga.

**Fix propuesto.** Llevar los pares (texto, fondo) a PastureKit como una tabla de tripletas RGB + una función `contrastRatio(_:_:)` (fórmula WCAG de luminancia relativa, ~15 líneas), y un test que recorra la tabla entera en ambos esquemas exigiendo ≥4,5. Que sea la **tabla** la que se recorra, no dos pares elegidos a mano — esa es la lección del repo sobre vectores. Esfuerzo: 2-3 h.

---

### ALTO 2 — El bucle real de `AIClient.ask()` no se ejecuta en ningún test

`Sources/PastureKit/AIClient.swift:70-180`. Los 48 tests de `AIClientTests` cubren muy bien las **piezas puras**: `buildRequest` (URL, cabeceras, cuerpo, multi-turno), `extractDelta`, `isStreamEnd`, `mapStatusCode`, `isRetryable`, `retryDelay` (con tope, backoff exponencial, `Retry-After` cero y negativo). Todo eso está bien.

Lo que no cubre nadie es la **orquestación**: el `for attempt in 0...Self.maxRetries` (línea 92), la decisión de reintentar en línea 117, la propagación de cancelación por `Task.isCancelled`, y el bucle de lectura SSE. Es decir: las piezas están probadas, el ensamblaje no. Un reintento que no reintenta, o una cancelación que no corta el stream, pasan la suite entera.

**Fix propuesto.** Inyectar `URLSessionConfiguration` en el `actor` y usar un `URLProtocol` de prueba que devuelva 429 → 200 con un cuerpo SSE guionizado. Con eso se cubren reintento, agotamiento de reintentos y cancelación. Esfuerzo: 4-6 h.

---

### ALTO 3 — `MDFileManager` (444 líneas de lógica de rutas y ficheros) es intestable por construcción

`Package.swift:24-28` hace que `PastureKitTests` dependa solo de `PastureKit`. `MDFileManager` vive en el ejecutable, así que **no es alcanzable desde la suite**. Y no es una vista: es lógica de decisión con efectos destructivos.

Funciones con decisiones reales y cero cobertura (`Sources/Pasture/MDFileManager.swift`):

| Línea | Función | Decisión que toma |
|---|---|---|
| `:56` | `resolveTargetDirectory(collection:)` | ⚠️ **el `collection` no pasa por `FilenameSanitizer`**; solo lo frena `isInsidePasture`. Un nombre con `/` crearía un subdirectorio anidado que ni `FileLibrary` ni `SidebarTree` contemplan (modelo de un solo nivel) |
| `:230` | `create` | saneado, deduplicación y contención de ruta encadenados |
| `:263` | `rename` | «mismo nombre → devuelve el original» vs deduplicar vs fallar |
| `:290` | `delete` | Papelera + reconstrucción de `files` por `deletedURLs` |
| `:304` / `:344` / `:366` | `createCollection` / `renameCollection` / `deleteCollection` | colisión de nombres, «solo si está vacía» vía `visibleContents` (el arreglo del `.DS_Store`) |
| `:324` | `moveFile` | destino igual al origen, contención |
| `:421` | `resolve(_ preset:)` | composición de `PresetResolver.resolve` + `missingPaths` |

`PathValidator`, `FileLibrary`, `FilenameSanitizer` y `PresetResolver` están **muy bien testeados por separado**; lo que nunca se ha probado es su **composición**, que es donde vive el riesgo (el orden en que se sanea, se deduplica y se valida).

**Fix propuesto.** Extraer las decisiones puras a PastureKit como funciones que devuelvan una intención en vez de ejecutarla — p. ej. `VaultMutation.plan(create:in:existing:) -> Result<URL, Error>` — y dejar en `MDFileManager` solo la llamada a `FileManager`. Empezar por `create`, `rename` y el `didCreateCollection` de `scanFolder`. Esfuerzo: 1-2 días para el conjunto; 3-4 h para las tres primeras.

---

### ALTO 4 — CI: no prueba en release, no construye el bundle, no ejecuta el binario MCP

`.github/workflows/ci.yml` hace `swift build`, `swift build -c release` y `swift test`. Tres huecos:

1. **`swift test` solo corre en debug.** La release compila pero sus tests nunca se ejecutan. Las optimizaciones cambian comportamiento en aritmética de límites (`MCPLimits`, el corte UTF-8 de `SecretScanner`) y en carreras de concurrencia. Coste: una línea, `swift test -c release`.
2. **`scripts/bundle.sh` no se ejecuta nunca en CI.** Es donde viven `CFBundleURLTypes`, `NSServices` y la firma ad-hoc de v1.9, además del `VERSION="1.11.0"` (`scripts/bundle.sh:7`). Un Info.plist roto o una firma fallida solo se descubren al empaquetar a mano. Coste: un step más.
3. **`Sources/pasture-mcp/main.swift` no se ejecuta en ninguna prueba.** `MCPEndToEndTests` entra por `MCPDispatcher.handle(line:)`, que es la frontera correcta por ADR-MCP-004, pero el cableado transporte↔dispatcher (stdout sagrado, descarte de líneas sobredimensionadas, salida limpia en EOF) no se ejercita nunca. Un `print()` accidental a stdout en ese camino rompe el framing y CI no se entera.

Añadidos que faltan y son baratos: coherencia `VERSION` de `bundle.sh` ↔ último encabezado del `CHANGELOG.md` (hoy es manual y ya se desalineó antes), y un `swift build` con warnings como error para cazar la asimetría conocida entre el compilador del runner y el toolchain local.

---

### MENOR 1 — `MCPProtocol.serverVersion` congelado en 1.8.0 y el test lo consagra

`Sources/PastureKit/MCP/MCPProtocol.swift:7` sigue en `"1.8.0"` con la app en 1.11.0, y `MCPServerVersionTests.swift` (suite literalmente titulada *«MCPProtocol — server version 1.8.0»*) **fija ese valor con dos aserciones**. Funciona como detector de cambios, pero el efecto práctico es que el test *defiende* el desfase: subir la versión del servidor obliga a tocar el test, así que la vía de menor resistencia es no subirla nunca. Si es deliberado (la versión del servidor MCP no sigue a la de la app), debería decirlo el comentario de la suite; si no lo es, hay que subirla.

### MENOR 2 — Tests de constante que no vigilan nada

`MCPLimitsTests.swift` (3 tests) afirma que tres constantes valen su propio literal:

```swift
#expect(MCPLimits.maxProposalBytes == 1_000_000)
#expect(MCPLimits.maxPendingProposals == 50)
#expect(MCPLimits.proposalTTLDays == 14)
```

No prueban que el límite se **aplique**. Atenuante importante y verificado: la aplicación **sí** está cubierta en otro sitio — `MCPTools.swift:151,184,220` y `ProposalStore.swift:41`, con tests en `MCPProposalToolsTests` («rejects content over the size cap», «refuses new proposals when the inbox is full») y `ProposalStoreTests` («drops proposals older than the TTL»). Así que son redundantes, no peligrosos. Lo mismo, en menor grado, con `MCPServerConfigTests`.

### MENOR 3 — Un test sin aserción

`KeychainStoreTests.swift:44` — `deleteNonexistent()` llama a `KeychainStore.delete` y no comprueba nada. Solo prueba que no revienta. Al lado tiene `deleteReturnsSuccess` (línea 50), que sí afirma el valor de retorno en ambos casos: el primero es un duplicado degradado.

### MENOR 4 — Fragilidades de entorno

- **Llavero real.** `KeychainStoreTests` escribe en el llavero de inicio de sesión real (con `service` único por test, así que no colisiona, pero si un test falla a mitad deja residuo en el llavero del usuario o del runner).
- **Basura en `/tmp`.** 10 de los 19 ficheros que crean directorios temporales no los borran: `HeadlessFeedTests`, `MCPEndToEndTests`, `MCPDispatcherTests`, `MCPPromptsTests`, `MCPStalenessTests`, `MCPResourcesTests`, `MCPVaultSecretStatTests`, `PackSyncEngineTests`, `SourceImportTests`, `TargetValidatorTests`. `TestHelpers.swift:9` documenta el contrato (`defer { try? FileManager.default.removeItem(at: dir) }`) y la mitad de los llamantes no lo cumple. No causa falsos verdes — cada directorio lleva un UUID — pero acumula.
- **Sin dependencia de reloj real ni de orden de ejecución**: `Freshness`, `ProposalStore` y `QuickCapture` inyectan el reloj; `UserDefaults` va siempre a una suite con UUID. Esto está bien resuelto.

---

## Tests vacuos detectados

Lista explícita, con el motivo por el que no vigilan lo que anuncian:

1. **`SidebarTreeTests.idDisambiguates` (`:98`)** — *vacuo respecto al contrato que la GUI consume*. Afirma que los ids son distintos entre sí y que el de la raíz es `"u:"`, pero nunca el prefijo de una colección. **Confirmado por mutación: cambiar `"c:"` → `"X:"` deja 728/728 en verde.** Es el único caso donde la vacuidad tiene consecuencia real (desincroniza `SidebarView.swift:260` y huerfaniza el estado persistido).
2. **`MCPLimitsTests` (3 tests)** — aserciones de constante contra su propio literal. Detector de cambios, no guarda. La aplicación del límite sí está cubierta en otro sitio (ver MENOR 2), así que son redundantes, no falsos.
3. **`KeychainStoreTests.deleteNonexistent` (`:44`)** — sin ninguna aserción. Solo prueba que la llamada no lanza.
4. **`MCPServerVersionTests` (2 tests)** — fijan una versión desfasada respecto a la app y encarecen corregirla.

**Tres candidatos que revisé y NO son vacuos** (lo digo porque parecían serlo por el nombre):

- `ContextLimitTests.atLimit` / `justBelow` / `overLimit` — cubren los tres puntos de la frontera binaria, incluido el exacto. Correcto.
- `SecretScannerTests.maskedSnippetHidesSecret` («never contains the full secret») — el vector es lo bastante largo y comprueba tres cosas distintas (no contiene el secreto, contiene la marca `…`, no contiene el centro sensible). Una mutación de `head = 7` a un valor grande lo rompe.
- `TargetValidatorTests.rejectsSymlinkPointingIntoVault` — el symlink que crea apunta a un fichero que **no existe**, así que en realidad está ejercitando la capa 3 (symlink colgante, `TargetValidator.swift:39-49`), que es la más sutil de las tres. Funciona, pero el nombre no lo dice: convendría renombrarlo a `rejectsDanglingSymlinkPointingIntoVault` y añadir el caso del symlink **no colgante** para cubrir la capa 2 por separado.

---

## Lo que está bien cubierto

Esto no es relleno: hay áreas donde la suite es mejor que la media del sector.

- **Los guardas de ruta, verificados por mutación.** Maté las dos defensas centrales en una copia aislada y ambas cayeron:
  - `PathValidator.swift:8`, quitando el `+ "/"` del `hasPrefix` → **2 fallos** (`similarPrefixNotMatched`, `prefixWithExtraSuffixNotMatched`). El truco del prefijo (`.pasture-evil/`, `.pasturefiles/`) está realmente vigilado.
  - `MCPPathResolver.swift:33`, limitando la comprobación de componentes ocultos al primero → **1 fallo** (`rejects a hidden component in any position`, con el vector `sub/.hidden.md`). El cierre de `.inbox/` no es decorativo.
- **Camino de escritura del Memory Inbox.** `ProposalPromoter` (10 tests) cubre procedencia, deduplicación de nombre, `hashMismatch` con y sin override, destino ausente, destino fuera del vault y limpieza del par del inbox. `ProposalStore` (8) cubre TTL, huérfanos, metadatos corruptos y dedupe por *hash + destino*.
- **Endurecimiento antiinyección.** `FrontmatterWriterSecurityTests` prueba lo correcto: no que la función «sanee», sino que un `clientInfo.name` con `\n` **no genere claves de frontmatter reconocidas** (comprueba el resultado reparseado, no la cadena).
- **Casos límite adversariales de verdad.** `SecretScannerEdgeCaseTests` cubre el corte del tope de 2 MB en frontera de carácter multibyte sin producir `U+FFFD`, el falso negativo *conocido y documentado* del token partido en dos líneas, y hay tests de tiempo acotado contra ReDoS.
- **Determinismo y aislamiento.** Reloj inyectado donde importa, `UserDefaults` en suites con UUID en los 9 stores, cero red.
- **Trazabilidad.** Casi cada suite cita su ADR o su identificador SEC-M en el docstring. Eso es lo que me ha permitido comprobar si el test hace lo que su invariante dice.
- **Compilador (`Context Compiler`).** Idempotencia byte a byte probada en dos capas (`PackCompilerTests.compileIsByteIdenticalAcrossRuns`, `PackWriterTests.rewritingSameBodyIsByteIdentical`), poda de backups a 10, conflicto no sobrescrito sin confirmación, y que el valor de una variable **no se reparsea** como plantilla.

---

## Justificación del score

| Dimensión | Peso | Nota | Razón |
|---|---|---|---|
| Cobertura de PastureKit | 25 % | 92 | 62 ficheros, todos con suite; composición de casos límite real |
| Calidad de las guardas (¿vigilan algo?) | 25 % | 80 | 2 de 2 mutaciones de seguridad cazadas; 1 vacuidad confirmada + 4 redundantes de 728 |
| Cobertura de la capa GUI | 20 % | 15 | 5.931 líneas, 0 tests, y `MDFileManager` no es «vista»: son 444 líneas de lógica de rutas y ficheros |
| Guardas de los fixes recientes | 15 % | 20 | 16 de 17 commits de v1.10/v1.11 sin un solo test |
| CI | 10 % | 55 | build debug + release + test debug; sin test en release, sin bundle, sin binario MCP, sin comprobación de versión |
| Higiene y determinismo | 5 % | 78 | aislamiento excelente; 10/19 ficheros dejan basura, un test sin aserción, llavero real |

Ponderado: **72,15 → 72/100**.

La nota no es más alta porque el punto ciego es estructural, no de esfuerzo: la suite es excelente exactamente donde es fácil serlo (lógica pura en una librería) y no existe donde está el riesgo de pérdida de datos y el 100 % de los arreglos recientes. No es más baja porque lo que hay está **medido y probado por mutación**, no asumido: cuando digo que un guarda de seguridad funciona es porque lo he matado y la suite se ha puesto roja.

Los tres arreglos que más suben la nota, por relación valor/esfuerzo:
1. Fijar el contrato del `id` de `CollectionNode` y hacer que la GUI lo consuma (30 min) → cierra la única vacuidad con consecuencia real.
2. `swift test -c release` en CI (1 línea).
3. Extraer y testear las tres decisiones de `MDFileManager` que arreglaron v1.10 (Papelera, escaneo vacío, saneo en `create`) (3-4 h) → convierte el peor bloque en el primer bloque cubierto.

---

## Dudas y asunciones

1. **No he corrido mutaciones sobre el árbol de trabajo.** Las dos rondas se hicieron sobre copias de `git archive HEAD` en el directorio de scratchpad de la sesión, y no he tocado `Sources/` ni `Tests/`. Las copias mutadas siguen ahí por si se quieren reproducir; el árbol real está intacto.
2. **Asumo que la capa GUI se dejó sin test deliberadamente** (SwiftUI, sin target de UI tests). Mi crítica no es «faltan tests de SwiftUI»: es que hay lógica de decisión no visual **dentro** de esa capa, y esa parte sí debería vivir en PastureKit. No propongo montar un target de UI tests.
3. **`MCPProtocol.serverVersion == "1.8.0"` con la app en 1.11.0**: asumo que es desfase, no política. Si el versionado del servidor MCP es independiente a propósito, el hallazgo MENOR 1 se cae y basta con documentarlo en el docstring de la suite.
4. **No he medido cobertura de líneas** (`--enable-code-coverage`). Todas las cifras de este informe son conteos y mutaciones verificadas, no estimaciones de cobertura. Donde digo «sin cobertura» quiero decir «no hay ningún test que ejecute ese símbolo», comprobado por `grep` del identificador en `Tests/`.
5. **`3fb633e` (portapapeles) es difícil de testear sin abstraer `NSPasteboard`.** Lo he clasificado como crítico por su riesgo, no porque el arreglo sea trivial de cubrir: exige una fachada inyectable, que es una decisión de diseño que no me corresponde tomar aquí.
6. **No he ejecutado CI ni `scripts/bundle.sh`** — el análisis de CI es de lectura del YAML, no de una ejecución observada.
