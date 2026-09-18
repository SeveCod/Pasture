# Audit 360 — Pasture v1.11.0 · Score global 78,9/100

Fecha: 2026-09-18 · Rama `feat/v1.11-sidebar-tree-simplify` · HEAD `80a6379` · árbol limpio
6 agentes en paralelo, read-only. Informes por dimensión en `audits/*.md`.

## Score

| Dimensión | Score | Peso | Aporta | Hallazgo principal |
|---|---|---|---|---|
| Seguridad | 84 | 25% | 21,00 | El detector de secretos no ve las claves de OpenRouter, el segundo proveedor de la propia app |
| QA / Tests | 72 | 20% | 14,40 | 16 de 17 commits de v1.10–v1.11 tocaron sólo la GUI y ninguno añadió test |
| Arquitectura | 78 | 20% | 15,60 | La búsqueda de la ventana principal no filtra nada |
| UX / a11y | 82 | 15% | 12,30 | El objetivo «tooltips» de la v1.11 se cerró sin diagnóstico y con su arreglo revertido |
| Docs / drift | 68 | 10% | 6,80 | CLAUDE.md describe una app de hace 3 versiones en varias secciones |
| Simplificación | 88 | 10% | 8,80 | Código inusualmente limpio; sobran ~36 líneas y 2 directorios ajenos |
| **GLOBAL** | **78,9** | 100% | | |

Pesos: la app escribe en el sistema de ficheros del usuario, expone un servidor MCP a agentes
externos y guarda claves de API → seguridad manda. No hay backend, BD, PII de terceros ni SEO.

## Cifras medidas (ninguna estimada)

| Métrica | Valor | Comando |
|---|---|---|
| Tests | 728 en 77 suites, verdes, exit 0 | `swift test` (toolchain swift-latest) |
| Dependencias externas | 0 | `grep -c 'package(' Package.swift` |
| TODO/FIXME/HACK | 0 | `grep -rn 'TODO\|FIXME\|HACK\|XXX' Sources` |
| `catch {}` vacíos | 0 | `grep -rn 'catch {}' Sources` |
| `nonisolated(unsafe)` / `@unchecked Sendable` | 7 / 3 | grep |
| Líneas Sources / Tests | 11.713 / 7.655 | `wc -l` |
| Versión | 1.11.0 coherente (bundle.sh:7 ↔ CHANGELOG) | grep |

## CRÍTICO — 1

### C1 · La búsqueda de la ventana principal no filtra nada
`Sources/Pasture/ContentView.swift:136`

```swift
.onReceive(Just(searchText).debounce(for: .milliseconds(300), scheduler: RunLoop.main)) { value in
    if !value.isEmpty { fm.searchQuery = value }
}
```

`debounce` de Combine descarta el valor pendiente cuando el upstream completa, y `Just` completa
de inmediato → el sink **nunca** se invoca.

**Verificado empíricamente** (programa aislado, toolchain real, no lectura de código):
```
Just(...).debounce       -> recibidos = []
PassthroughSubject.deb.  -> recibidos = ["mundo"]   (control)
```

Cadena completa confirmada: `:131` sólo asigna `fm.searchQuery` cuando el texto está **vacío**,
así que la única vía para una consulta real es el debounce roto → `MDFileManager:46
updateFilteredFiles()` nunca la ve → `SidebarView:180 sortedFiles` lee `fm.filteredFiles` sin filtrar.

Daños colaterales: `isSearching` (`SidebarView:190`) es siempre `false`, de modo que `hidingEmpty`
y el invariante «buscar no persiste el plegado» —el que vigila el test `searchDoesNotWriteState`—
**nunca se ejercen en producción**; y `pasture://search?q=` es inerte.

Por qué escapó a la QA: la barra de menús tiene otra implementación (`MenuBarView:18-21`) que sí
funciona. Fix: sustituir por `.task(id: searchText)` con `Task.sleep`, o mover el debounce a un
`PassthroughSubject` del modelo. **Esfuerzo: 30 min + test de guardia.**

## ALTOS — 6

### A1 · `SecretScanner` no detecta claves de OpenRouter
`Sources/PastureKit/SecretScanner.swift:137-160`. `sk-proj-` no casa, y el genérico
`sk-[A-Za-z0-9]{20,}` se corta en el guion de `sk-or-v1-…` (la clase exige alfanuméricos
inmediatamente tras `sk-`).

**Verificado empíricamente** contra los patrones reales:
```
OpenRouter           detectada = false
OpenAI (control)     detectada = true
```

No es cosmético: es un **gate que bloquea**. `HeadlessFeed:43` (`guard scan.isEmpty`) y
`PackWriter:74-76` dejarían pasar esa clave, y `PackWriter` la escribiría en el `CLAUDE.md` de un
repo del usuario, camino del commit. La app integra OpenRouter y guarda esa clave en el llavero
(`AISettings`), así que es el escenario exacto para el que existe el escáner. Faltan también
Google (`AIza…`) y Stripe (`sk_live_…`, con guion bajo). **Fix: 3 líneas + un test por familia, 30 min.**

### A2 · `PackWriter` destruye un destino no-UTF-8 sin conflicto y sin backup
`Sources/PastureKit/PackWriter.swift:66-90`. `try? String(contentsOf:encoding:.utf8)` → `nil` para
un fichero en Latin-1 o binario → `SyncMarker.state(nil)` = `.targetMissing` (`SyncMarker.swift:92`)
→ el gate de conflicto de `:70` no dispara **y** el `if let existing` de `:79` no hace backup →
`:90` sobrescribe. Las tres defensas del módulo fallan a la vez y contradicen su propio docstring.
Un `CLAUDE.md` en Latin-1 con acentos —nada teórico escribiendo en español— se pierde sin red.
Mismo patrón en `MDFileManager+Sources.swift:83-90`. **Fix: 4 líneas (distinguir «no existe» de
«no legible»), 1 h.**

### A3 · Relectura íntegra del vault en cada evento del watcher
`FileLibrary.load` reconstruye los 673 `MDFile` (leer contenido + estimar tokens + escanear
plantillas + parsear frontmatter) en cada ráfaga, incluidas las que provoca la propia app al
guardar. Corre fuera del main actor, así que no congela; el coste es I/O y CPU repetidos. El
`mtime` ya está disponible para saltarse lo no modificado. **Esfuerzo: 2 h.**

### A4 · El popover filtra 673 notas en el main actor, sin caché
`Sources/Pasture/MenuBarView.swift:18-21` — propiedad computada de la vista que hace
`matches(query:)` sobre el contenido completo en cada evaluación de `body`. La ventana principal
resolvió esto con `fm.filteredFiles`; el popover se quedó fuera. **Esfuerzo: 30 min.**

### A5 · El `FeedService` del popover muere con el popover
`MenuBarView.swift:14` (`@StateObject`) + `:39` (`.feedChrome`). Si un feed desde la barra de menús
dispara el aviso de secretos o la sheet de plantilla, el popover pierde el foco, la vista se
destruye y `pendingSecretProceed` se va con ella: el feed nunca se entrega y nadie avisa. Es el
fallo silencioso más caro de la app. **Esfuerzo: 1-2 h** (elevar el `FeedService` a la app).

### A6 · El objetivo «tooltips» de la v1.11 se cerró sin diagnóstico y con su arreglo revertido
El plan (`docs/superpowers/plans/2026-09-18-…:27-139`) exigía un diagnóstico observado en
`docs/superpowers/specs/2026-09-18-tooltip-diagnosis.md`: **ese fichero no existe** (verificado).
El arreglo previsto —agrupar la toolbar, commit `b9715a6`— lo **revierte** `80a6379` (HEAD), y
`ContentView.swift:165-242` vuelve a meter 10 controles en un único `ToolbarItemGroup`, que era
justo la hipótesis de desbordamiento. Los ~30 `.help()` pueden seguir igual de invisibles que
antes de la rama. **Es el patrón «cifra autoestimada» aplicado a una corrección.**
**Fix: ejecutar el diagnóstico (15 min) antes de tocar nada.**

## MENORES — selección

- **`Import` no acepta `.md`** (`ContentView.swift:427-431`: sólo pdf/csv/docx/doc) justo después de
  retirar New File. El drag & drop sí lo permite; el panel no. Trivial.
- **El empty state no nombra las vías que quedan** (`PastureEmptyState.swift:27`, sólo el portapapeles).
  Con vault vacía y portapapeles vacío, la pantalla no dice qué hacer. Trivial.
- **Alerts encadenados en `ReviewInboxSheet`**: el bug que temía el PR #6 (Reject silencioso) **NO es
  real**; pero «Append anyway» (`:79`) puede fijar `errorMessage` mientras el alert de mismatch se
  descarta y el `set:` de `:76` lo anula después. Solapan en el código; que se trague es runtime.
- **`pasture://new` escribe en el vault sin confirmación ni marca de procedencia**
  (`PastureURLCommand.swift:29` → `HeadlessActions.swift:97-99`). A diferencia de las propuestas MCP,
  la nota no lleva `origin:`. Vector de prompt injection almacenada.
- **Borrar un pack no pide confirmación** (único diálogo destructivo sin default seguro).
- **`serverVersion` congelada en `"1.8.0"`** (`MCPProtocol.swift:7`) con la app en 1.11.0 —
  y `MCPServerVersionTests` **defiende el desfase** en vez de detectarlo.
- **Dos pares de contraste por debajo de AA** (`textSecondaryDark`/`selectionDark` 4,23; gemelo claro
  4,45) — hoy **no se pintan** en ninguna pantalla. Mina latente en el token, no violación.
- **`streamdeck-whisper/` (278 líneas) y `.superpowers/sdd-cifix-report.md` (42)**: trackeados en git,
  ajenos al proyecto, entraron por el commit `137986d auto-sync` (`git add -A`). Verificado con
  `git ls-files`. Mismo patrón que ya coló artefactos en prompt-lab/rentabano/moneySeve.
- **~36 líneas de código muerto confirmado**: `Proposal.autoApproved` (su comentario promete una
  compatibilidad que el `Codable` sintetizado ya da gratis), `AIClient.buildRequest(question:context:)`
  (y su docstring miente sobre quién lo usa), 7 tokens de `DesignTokens`, `SecretScanResult.kinds`,
  `CollectionNode.isUncategorized`.

## Tests vacuos (verificados por mutación)

1. **`SidebarTreeTests.idDisambiguates:98`** — mutando `"c:"` → `"X:"` en `SidebarTree.swift:17`,
   la suite da **728/728 en verde**. El test sólo exige que los ids difieran entre sí, nunca el
   prefijo. Importa porque `SidebarView.swift:260` **reconstruye ese id a mano** y porque es la clave
   persistida en UserDefaults: cambiarlo rompe el auto-despliegue y huerfaniza el plegado del usuario.
2. `KeychainStoreTests.deleteNonexistent:44` — **sin ninguna aserción** (verificado).
3. `MCPServerVersionTests` — fija la versión desfasada, ver arriba.
4. `MCPLimitsTests` (3) — constantes contra su propio literal; redundantes, no peligrosos.

**En la otra dirección, para no inflar:** mutar las dos defensas de ruta (`PathValidator:8` sin el
`+ "/"`, `MCPPathResolver:33` limitado al primer componente) **tumbó 3 tests en ambas rondas**.
Los guardas de seguridad no son decorativos.

## Drift de documentación (todo verificado a mano)

| Dice CLAUDE.md | Realidad |
|---|---|
| Settings tiene «three tabs» (:88) | **Cinco** (`SettingsView.swift:9-17`) |
| Context Compiler: «GUI wiring is a follow-up» (:141) | **Ya está conectado por 4 vías** (`SettingsView:15`, `ContentView:65`, `MenuBarView:228`, `MDFileManager:184`) |
| Ask: `responseText`, `copyResponse()`, `ask(question:context:…)` | `conversation: AskConversation`, `copyConversation()`, `saveAsContext(…)`, `ask(messages:…)`. Los 4 tipos del Ask multi-turno no se nombran ni una vez |
| `MCPTools.swift:3`: «las cuatro tools de solo lectura» | La línea 78 del **mismo fichero** añade `propose_note`/`propose_append` |
| Pendiente: «LICENSE ausente» | **LICENSE MIT existe** en la raíz desde el 24-jun |
| README | Fosilizado en v1.5.1 («501 tests»), 6 releases por detrás |
| — | Cmd+Shift+P «Sync All Packs» (`PastureApp.swift:32-35`) sin documentar en ningún sitio |

## Lo que está bien (verificado, no asumido)

- **Los invariantes de seguridad se cumplen en su forma estructural**: los 8 puntos de I/O del MCP
  pasan por `MCPPathResolver` (dos capas), el `.inbox/` es inalcanzable por las tools de lectura
  (dos mecanismos independientes), la inyección vía `clientInfo.name` está cerrada en ingest **y** en
  escritura, y las claves reservadas del frontmatter se despojan antes de la procedencia.
- **Cero dependencias externas** (regla identitaria intacta), cero secretos hardcodeados, y el único
  `standardOutput` del árbol está en `main.swift:22` (SEC-M7 a salvo).
- **Ninguna carrera de concurrencia real**: los 7 `nonisolated(unsafe)`, 3 `@unchecked Sendable`,
  4 `MainActor.assumeIsolated` y 3 `Task.detached` están justificados y confinados. Riesgo latente
  único: el `@unchecked Sendable` de `MCPDispatcher:15` es seguro **sólo** porque `main.swift` es un
  bucle secuencial — un contrato en un comentario, no en el tipo.
- **44 pares de contraste medidos, todos AA en su uso real.**
- **Cero TODO/FIXME/HACK en 19.368 líneas**, cero código comentado, ninguna función sobre 69 líneas,
  ninguna abstracción de un solo uso.
- Los 8 namespaces de UserDefaults se midieron (360 líneas, ahorro máximo de abstraerlos ~40):
  **se recomienda NO abstraer**, la capa costaría más comprensión de la que ahorra.

## Falsos positivos descartados

- «El Context Compiler es funcionalidad fantasma» — **falso**, y era una premisa mía en el encargo.
  Las 1.031 líneas están conectadas por 4 vías verificadas. Lo muerto es la frase del doc.
- «Los 3 alerts apilados del ReviewInboxSheet provocan un Reject silencioso» (temor del PR #6) —
  **no es real**: Reject no compite con ningún otro alert.
- `ContextLimit`, el enmascarado de `SecretScanner` y `TargetValidator` parecían tests vacuos y
  **no lo son**: los tres cubren su frontera real.

## Dudas y asunciones

1. **C1 lo medí con Combine aislado, no dentro de SwiftUI.** La conclusión es sólida (el sink nunca
   se invoca), pero antes de tocar código conviene teclear en la barra de búsqueda de la app
   instalada y confirmar el síntoma. Es 1 minuto y cierra la última duda.
2. Los dos WARN del pre-flight (CLOUDFLARE_API_TOKEN, ANTHROPIC_API_KEY) **no aplican**: Pasture es
   una app local sin despliegue a VPS ni CDN. No cuentan contra el score.
3. Asumo que la rama `feat/v1.11-sidebar-tree-simplify` (13 commits por delante de `main`, sin
   mergear) es la línea de trabajo actual y que el PR #6 sigue abierto.
4. Ninguna dimensión cubre **QA visual en pantalla**: nada aquí sustituye al checklist pendiente del
   PR #6, y varios hallazgos (tooltips, alerts encadenados) sólo se cierran mirando la app.
5. No he ejecutado la app ni instalado nada. Todo es análisis de código + tests + mutación en copias
   fuera del repo.
