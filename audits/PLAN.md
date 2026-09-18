# Audit 360 — Pasture v1.11.0

Fecha: 2026-09-18
Rama: feat/v1.11-sidebar-tree-simplify · HEAD 80a6379
Árbol: limpio

## Pre-flight
- preflight.sh: 5 PASS / 2 WARN / 0 FAIL. Los 2 WARN (CLOUDFLARE_API_TOKEN, ANTHROPIC_API_KEY) NO aplican:
  Pasture es una app macOS local, sin despliegue a VPS ni CDN. No cuentan contra el score.
- Blocked on user: ninguno de momento.

## Dimensiones y pesos
| # | Dimensión | Peso | Estado |
|---|-----------|------|--------|
| 1 | Seguridad (invariantes SEC-*, MCP, Keychain, path traversal) | 25% | pendiente |
| 2 | QA / tests (cobertura real, guardias, tests vacuos) | 20% | pendiente |
| 3 | Arquitectura / concurrencia Swift 6 | 20% | pendiente |
| 4 | UX / accesibilidad (SwiftUI, WCAG, VoiceOver) | 15% | pendiente |
| 5 | Docs / drift (CLAUDE.md vs código real, CHANGELOG, README) | 10% | pendiente |
| 6 | Simplificación / deuda técnica | 10% | pendiente |

Justificación de pesos: Pasture escribe en el sistema de ficheros del usuario, expone un
servidor MCP a agentes externos y guarda claves de API — seguridad manda. No hay backend,
ni base de datos, ni PII de terceros, ni SEO: esas dimensiones no aplican.

## Fases
- [x] Fase 0 — pre-flight
- [x] Fase 1 — análisis read-only (6 subagentes, 6 informes en audits/)
- [ ] Fase 2 — informe + score, ESPERAR aprobación
- [ ] Fase 3 — fixes (solo tras "dale")

## Hallazgos ya VERIFICADOS por el auditor principal (no sólo reportados)

### C1 — La búsqueda de la ventana principal no filtra nada (CRÍTICO, confirmado)
- `ContentView.swift:136` — `Just(searchText).debounce(for:.milliseconds(300), scheduler:.main)`
- Combine descarta el valor pendiente del debounce cuando el upstream completa. `Just` completa
  de inmediato → el sink NUNCA se invoca.
- Verificación empírica propia (programa aislado, toolchain real):
    Just(...).debounce      -> recibidos = []
    PassthroughSubject.deb. -> recibidos = ["mundo"]
- Cadena completa confirmada: `:131` sólo asigna `fm.searchQuery` si el texto está VACÍO →
  la única vía para texto no vacío es el debounce roto → `MDFileManager:46 updateFilteredFiles`
  nunca ve la consulta → `SidebarView:180 sortedFiles` lee `fm.filteredFiles` sin filtrar.
- Efectos en cascada: `isSearching` (`SidebarView:190`) siempre false → `hidingEmpty` y el
  invariante "buscar no persiste el plegado" nunca se ejercen en producción; `pasture://search?q=`
  es inerte.
- Por qué escapó a la QA: el menu bar tiene OTRA implementación de búsqueda y ésa sí funciona.

### Drift de CLAUDE.md (verificado uno a uno por el auditor principal)
- Settings tiene 5 pestañas (`SettingsView.swift:9-17`), el doc dice 3.
- La GUI del Context Compiler SÍ existe (PacksSettingsTab / PackEditorView / PackSyncRunner),
  el doc dice "GUI wiring is a follow-up".
- Cmd+Shift+P "Sync All Packs" existe (`PastureApp.swift:32-35`), sin documentar.
- LICENSE MIT SÍ existe en la raíz → el pendiente que lo da por ausente es drift.

## Fase 3 — ejecución (aprobada por el usuario: "dale")

- [x] C1 búsqueda rota → `.task(id:)` + `Task.sleep`. Guardia de fuente + test de premisa
      de Combine. **Mutación verificada** (mutante en Sources → la guardia lo caza).
- [x] A1 SecretScanner: familias `openRouterKey`, `googleAPIKey`, `stripeKey` (solo `live`).
      Guardia de barrido sobre `AIProviderKind.allCases`. **Mutación verificada**
      (retirar el patrón tumba el test específico Y la guardia de barrido).
- [x] A2 PackWriter: lectura en crudo, "ilegible" ≠ "ausente", backup por bytes.
      Rejilla de 3 casos (Latin-1 / binario / UTF-8 truncado). **Mutación verificada**
      (comportamiento viejo → .written, destino destruido, sin backup).
- Checkpoint: **735 tests en 78 suites, verdes** (desde 728).
- [x] 4 tests vacuos: SidebarTree (fuente única `CollectionNode.id(forCollection:)` + prefijos
      fijados, mutación verificada), Keychain (aserción real: no toca a las vecinas),
      MCPServerVersion (cotejado contra bundle.sh; serverVersion 1.8.0 → 1.11.0).
      MCPLimits NO se toca: discrepo, un cap de seguridad contra su literal sí detecta cambios.
- [x] Hotfix del portapapeles: decisión extraída a `ClipboardPaste` (PastureKit) + 3 tests.
- [x] A3 carga incremental de la biblioteca. ⚠️ Mi primera implementación tenía un defecto
      (clave de caché sin normalizar: /var vs /private/var) que sólo cazó mi propio test.
      Mutación verificada.
- [x] A4 popover: filtrado cacheado en estado.
- [x] A5 `FeedService` del popover pasa a ser propiedad de `PastureApp`.
- [x] Drift: CLAUDE.md (5 tabs, Context Compiler conectado, Ask multi-turno), docstring de
      MCPTools, README (v1.11.0, 743 tests, 6 secciones nuevas), CHANGELOG.
      `streamdeck-whisper/` y `.superpowers/` destrackeados + gitignorados (siguen en disco).
- [x] A6 tooltips: NO se toca la toolbar. Creado el diagnóstico que faltaba con la parte
      verificable por código; los pasos de observación requieren la app y quedan pendientes.
- [x] Memoria del proyecto actualizada.

## Verificación final
- **743 tests en 80 suites, verdes.** Build debug y release limpios (el release importa: el
  compilador del CI es más estricto que el toolchain local).
- **NADA COMMITEADO.** 20 ficheros modificados + 5 nuevos.
