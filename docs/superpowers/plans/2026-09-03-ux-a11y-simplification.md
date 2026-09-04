# Pasture v1.10 — UX, accesibilidad y simplificación · Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cerrar los 28 hallazgos verificados de la revisión 2026-09-03 (12 usabilidad, 12 accesibilidad, 5 simplificación) sin cambiar la arquitectura.

**Architecture:** Cambios quirúrgicos sobre el árbol existente. Orden: primero simplificación (reduce la superficie que después se toca), luego tokens/contraste, luego comportamiento (VoiceOver, Reduce Motion, flujos). La lógica nueva reutilizable va a PastureKit con test; lo que es puro pegamento SwiftUI se queda en el target Pasture y se verifica con build + QA manual (ese target no tiene tests).

**Tech Stack:** Swift 6 strict concurrency, SwiftUI, SPM, Swift Testing (`@Test`/`#expect`). Cero dependencias externas.

**Spec:** `docs/superpowers/specs/2026-09-03-ux-a11y-simplification-findings.md` — cada tarea cita sus IDs (UX-n / A11Y-n / SIMP-n). Leerlo antes de empezar.

## Global Constraints

- **Cero dependencias externas** (regla identitaria del proyecto). Nada de `.package` en `Package.swift`.
- **Los 710 tests existentes siguen verdes** tras cada tarea. ⚠️ En esta máquina `swift test` falla con el toolchain de CLT (no trae el módulo Testing): usar `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test`. `swift build` sí vale con el default.
- **Invariantes SEC-\* intocables** (CLAUDE.md del repo). En particular SEC-6: el diálogo de secretos mantiene Cancel como default, y el servidor MCP sigue sin write-path al vault visible.
- **Prosa y comentarios en español; identifiers y commits en inglés** (estilo ya presente en el repo).
- El target `Pasture` (UI) no tiene tests: su verificación es `swift build` + QA manual descrita en cada tarea. Para QA de notificaciones/hotkeys hace falta bundle real: `./scripts/bundle.sh` (UNUserNotificationCenter aborta bajo `swift run`).
- No tocar `streamdeck-whisper/` (untracked, ajeno a este trabajo).
- Commit por tarea. Mensajes `type(scope): summary` en inglés terminados en `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 0: Rama de trabajo

**Files:** ninguno.

- [ ] **Step 1:** Verificar árbol limpio (`git status --porcelain --untracked-files=no` → vacío) y crear rama:

```bash
git checkout -b feat/v1.10-ux-a11y-simplify
```

---

### Task 1: Poda de código muerto (SIMP-1, SIMP-4, SIMP-5)

**Files:**
- Modify: `Sources/Pasture/DesignTokens.swift`
- Modify: `Sources/Pasture/PastureEmptyState.swift:18`
- Modify: `Sources/PastureKit/MCP/MCPMessage.swift:92`
- Modify: `Sources/PastureKit/MCP/MCPTools.swift:421`
- Modify: `Sources/Pasture/ContentView.swift:368-371`

**Interfaces:** ninguna nueva. Solo eliminaciones; el compilador es la guardia.

- [ ] **Step 1: Re-verificar que cada símbolo sigue muerto** (obligatorio antes de borrar — un call-site no visto no existe hasta comprobarlo):

```bash
for t in pastureMidGradient pastureAccentDeep pastureEditorProse pastureSidebarGradient shadowHover shadowModal animationSlow springResponse springDamping searchBarHeight summaryBarHeight statusBarHeight editorTopPadding; do echo -n "$t: "; grep -rn "$t" Sources Tests scripts | grep -v "DesignTokens.swift" | wc -l; done
```

Esperado: 0 en los 13. Si alguno da >0, NO borrarlo y anotarlo en Dudas.

- [ ] **Step 2:** Borrar en `DesignTokens.swift` las 13 declaraciones muertas (token + su doc comment). ⚠️ NO tocar `pastureSageGreen` ni `pastureAmber` (los usa `LinearGradient.pastureBrand` en el propio fichero) ni `ShadowSpec`/`shadowFloat` (uso real en FeedbackToast).

- [ ] **Step 3:** Eliminar el alias `static let pastureGrassOrange = pastureTemplate` (`DesignTokens.swift:113`) y en `PastureEmptyState.swift:18` sustituir `pastureGrassOrange` por `pastureTemplate`.

- [ ] **Step 4:** Eliminar `JSONValue.arrayValue` (`MCPMessage.swift:92`) y en `MCPTools.swift:421` usar pattern-matching directo sobre `.array` (misma forma que ya use el código vecino para `.string`/`.object`).

- [ ] **Step 5:** En `ContentView.swift:368-371` sustituir:

```swift
if let existing = SelectionPresetStore.preset(named: name) {
    // HU-4: confirmar sobrescritura de un nombre duplicado.
    _ = existing
    presetOverwritePending = (name: name, paths: paths)
    return
}
```

por:

```swift
if SelectionPresetStore.preset(named: name) != nil {
    // HU-4: confirmar sobrescritura de un nombre duplicado.
    presetOverwritePending = (name: name, paths: paths)
    return
}
```

- [ ] **Step 6:** `swift build && ~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test` → build OK, 710 tests PASS.

- [ ] **Step 7:** Commit: `refactor: prune dead design tokens and redundant aliases`

---

### Task 2: `secretAlertMessage` a una sola fuente en PastureKit (SIMP-2 parcial, TDD)

**Files:**
- Modify: `Sources/PastureKit/SecretScanner.swift` (extensión de `SecretScanResult`)
- Create: test en `Tests/PastureKitTests/SecretScannerTests.swift` (o el fichero de suite existente de SecretScanner)
- Modify: `Sources/Pasture/ContentView.swift:401-411` (borrar función privada)
- Modify: `Sources/Pasture/MenuBarView.swift:76-86` (borrar función privada)

**Interfaces:**
- Produces: `public extension SecretScanResult { var alertMessage: String }` — el texto EXACTO que hoy generan las dos copias privadas. Task 4 lo consume.

- [ ] **Step 1: Test que falla.** ⚠️ GitHub Push Protection bloquea fixtures de tokens realistas: construir el token concatenando literales (gotcha ya documentado del repo).

```swift
@Test func alertMessageCarriesSummaryAndCaveat() {
    let token = "sk-ant-" + "api03-" + String(repeating: "a", count: 24)
    let result = SecretScanner.scan(files: [("note.md", "key: \(token)")])
    let message = result.alertMessage
    #expect(message.contains("Pasture found patterns that look like known credentials"))
    #expect(message.contains("best-effort check"))
    for line in result.summaryLines() { #expect(message.contains(line)) }
    #expect(!message.contains(token))  // SEC-4: nunca el valor completo
}
```

(Ajustar la llamada a `SecretScanner.scan` a su firma real — mirar cómo la invocan los tests existentes de SecretScanner.)

- [ ] **Step 2:** Correr el test → FAIL (símbolo `alertMessage` inexistente).

- [ ] **Step 3: Implementación** — mover el cuerpo idéntico de las dos copias privadas:

```swift
public extension SecretScanResult {
    /// Mensaje del aviso de secretos. SEC-4 (sin valores) + SEC-5 (best-effort).
    var alertMessage: String {
        let detections = summaryLines().joined(separator: "\n")
        return """
        Pasture found patterns that look like known credentials:

        \(detections)

        This is a best-effort check for known secret types — it is not a guarantee. Review before sending.
        """
    }
}
```

- [ ] **Step 4:** Sustituir en `ContentView.swift:138` y `MenuBarView.swift:72` `secretAlertMessage(for: result)` por `result.alertMessage` y borrar las dos funciones privadas.

- [ ] **Step 5:** Build + suite completa → PASS. Commit: `refactor: single source for secret alert message in PastureKit`

---

### Task 3: Helper de cola compartido en propose_note/propose_append (SIMP-3)

**Files:**
- Modify: `Sources/PastureKit/MCP/MCPTools.swift:164-183` y `:215-235`

**Interfaces:**
- Produces: helper privado `static func queueProposal(_ proposal: Proposal, content: String, inbox: URL) -> ToolCallResult` (nombre y firma ajustables al código real) que encapsula: cap de pendientes (SEC-M15) → escaneo de secretos → dedupe (payload hash + destinationKey) → save → mensaje de éxito. Las validaciones de destino se QUEDAN en cada tool (difieren a propósito: note valida ruta proyectada; append exige existencia + no-symlink + targetHash).

- [ ] **Step 1:** Leer los dos bloques y extraer la secuencia común al helper. No cambiar ningún string de mensaje ni el orden de las comprobaciones — los tests actuales fijan ambos.

- [ ] **Step 2:** Correr las suites que lo cubren:

```bash
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test --filter MCPProposalToolsTests
~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test --filter MCPProposalDispatchTests
```

Esperado: PASS sin tocar un solo test (si un test exige cambios, el refactor cambió comportamiento — revertir y revisar).

- [ ] **Step 3:** Suite completa → PASS. Commit: `refactor(mcp): shared queueing helper for proposal tools`

---

### Task 4: Chrome de feed compartido ContentView↔MenuBarView (SIMP-2)

**Files:**
- Create: `Sources/Pasture/FeedChrome.swift`
- Modify: `Sources/Pasture/ContentView.swift` (bloques 102-141, 179-184)
- Modify: `Sources/Pasture/MenuBarView.swift` (bloques 43-74, 267-272)

**Interfaces:**
- Consumes: `FeedService` (`showTemplateSheet`, `templateVariables`, `pendingSecretResult`, `pendingFeedTargets`, `cancelTemplateFeed`, `confirmTemplateFeed(fm:)`, `cancelSecretDialog`, `proceedDespiteSecrets`, `feedbackMessage`, `feedbackIsError`), `SecretScanResult.alertMessage` (Task 2), `TemplateSheet`, `FeedbackToast`.
- Produces: `struct FeedChrome: ViewModifier` + `extension View { func feedChrome(_ feedService: FeedService, fm: MDFileManager) -> some View }`.

- [ ] **Step 1: Implementar el modifier** (mismo patrón que el `PresetSheetsAndAlerts` que ContentView ya usa para aliviar el type-checker):

```swift
/// Aparato común del flujo de feed: sheet de plantilla, alert de secretos
/// (SEC-6: Cancel por defecto) y toast de feedback. Compartido por la ventana
/// principal y el popover del menu bar.
struct FeedChrome: ViewModifier {
    @ObservedObject var feedService: FeedService
    let fm: MDFileManager

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $feedService.showTemplateSheet) {
                TemplateSheet(
                    variables: $feedService.templateVariables,
                    totalTokens: fm.totalTokens(for: feedService.pendingFeedTargets),
                    onCancel: { feedService.cancelTemplateFeed() },
                    onConfirm: { feedService.confirmTemplateFeed(fm: fm) }
                )
            }
            .alert(
                "Possible secret detected",
                isPresented: Binding(
                    get: { feedService.pendingSecretResult != nil },
                    set: { if !$0 { feedService.cancelSecretDialog() } }
                ),
                presenting: feedService.pendingSecretResult
            ) { _ in
                // Default seguro = Cancelar (Enter/Escape). SEC-6.
                Button("Cancel", role: .cancel) { feedService.cancelSecretDialog() }
                Button("Continue anyway", role: .destructive) { feedService.proceedDespiteSecrets() }
            } message: { result in
                Text(result.alertMessage)
            }
            .overlay(alignment: .bottom) {
                if let msg = feedService.feedbackMessage {
                    FeedbackToast(message: msg, isError: feedService.feedbackIsError)
                }
            }
    }
}

extension View {
    func feedChrome(_ feedService: FeedService, fm: MDFileManager) -> some View {
        modifier(FeedChrome(feedService: feedService, fm: fm))
    }
}
```

Nota deliberada: el `totalTokens` del sheet pasa a calcularse SIEMPRE sobre `feedService.pendingFeedTargets` (lo que se va a alimentar de verdad). MenuBarView hoy pasa los tokens de su selección — en el momento en que el sheet se muestra ambos coinciden, pero verificarlo en QA.

- [ ] **Step 2:** En ContentView: sustituir sus bloques `.sheet` de TemplateSheet, `.alert` de secretos y `feedbackOverlay` por `.feedChrome(feedService, fm: fm)`. ⚠️ Conservar en ContentView la `.animation(..., value: feedService.feedbackMessage)` de la línea 141 (o moverla al modifier — decidir una, no duplicar). En MenuBarView: ídem con sus bloques equivalentes.

- [ ] **Step 3:** `swift build` OK; suite completa PASS (no cubre estas vistas, pero valida PastureKit).

- [ ] **Step 4: QA manual en ambas superficies** (`swift run` basta aquí):
  1. Ventana principal: feed de fichero con `{{VAR}}` → sale TemplateSheet; feed de fichero con `sk-ant-…` de prueba → alert con Cancel por defecto (Enter cancela); feed limpio → toast.
  2. Menu bar: repetir los tres casos.

- [ ] **Step 5:** Commit: `refactor: extract shared FeedChrome modifier for main window and menu bar`

---

### Task 5: Contraste AA — template adaptativo y ámbar significativo (A11Y-1, A11Y-2)

**Files:**
- Modify: `Sources/Pasture/DesignTokens.swift`
- Modify: `Sources/Pasture/TemplateBadge.swift:16`, `Sources/Pasture/FeedAction.swift:127-129`, `Sources/Pasture/FileRow.swift:22`, `Sources/Pasture/SidebarView.swift:104`, `Sources/Pasture/ReviewInboxSheet.swift:111-114`, `Sources/Pasture/SettingsView.swift:202`

**Interfaces:**
- Produces: `static func pastureTemplate(_ scheme: ColorScheme) -> Color` (nuevo helper, mismo patrón que `pastureWarning(_:)` en `DesignTokens.swift:209-211`).

- [ ] **Step 1:** En `DesignTokens.swift`, junto al actual `pastureTemplate` (línea 89), añadir la variante clara y el helper:

```swift
/// Template indicator — variante clara. Mismo ámbar profundo que warning:
/// #D4793B mide 2,91:1 sobre el fondo del badge claro (falla AA); #8F4F1A
/// mide ≥4,5:1 sobre todos los fondos claros de la app. #8F4F1A
static let pastureTemplateLight = pastureWarningLight
```

y en la sección de helpers adaptativos:

```swift
/// Template indicator — adapts to color scheme (AA en ambos esquemas).
static func pastureTemplate(_ scheme: ColorScheme) -> Color {
    scheme == .dark ? .pastureTemplate : .pastureTemplateLight
}
```

- [ ] **Step 2:** Sustituir usos como TEXTO/ICONO con significado:
  - `TemplateBadge.swift:16` y `FeedAction.swift:127-129`: `Color.pastureTemplate` → `Color.pastureTemplate(colorScheme)` (las vistas ya tienen `@Environment(\.colorScheme)`; si alguna no, añadirlo).
  - `FileRow.swift:22`, `SidebarView.swift:104`, `ReviewInboxSheet.swift:111` y `:114`, `SettingsView.swift:202`: `Color.pastureAmber` → `Color.pastureWarning(colorScheme)`.
  - ⚠️ NO tocar `pastureAmber` dentro de `LinearGradient.pastureBrand` ni `pastureWarningDark` (que es alias de `pastureTemplate` — correcto en dark, 4,95:1).

- [ ] **Step 3: Verificar los ratios por cálculo, no a ojo** (guardia contra regresión del claim del CLAUDE.md):

```bash
python3 - <<'EOF'
def lum(c): return c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
def L(r,g,b): return 0.2126*lum(r)+0.7152*lum(g)+0.0722*lum(b)
def ratio(f,b):
    l1,l2 = sorted([L(*f),L(*b)], reverse=True)
    return round((l1+0.05)/(l2+0.05), 2)
warn_light = (0.561,0.310,0.102)     # #8F4F1A
print("warning sobre sidebar claro:", ratio(warn_light,(0.965,0.961,0.949)))   # esperado >= 4.5
print("warning sobre badge template claro:", ratio(warn_light,(0.992,0.953,0.922)))  # esperado >= 4.5
print("template dark sobre bg dark:", ratio((0.831,0.475,0.231),(0.227,0.180,0.133)))  # esperado >= 4.5
EOF
```

Los tres deben salir ≥4,5. Si alguno no llega, oscurecer la variante clara hasta que llegue y documentar el hex final.

- [ ] **Step 4:** Build + QA visual: abrir la app en light y dark; comprobar badge Template, badge stale, banner de revisión, aviso de secretos del Inbox y estrella de Settings — legibles en ambos esquemas.

- [ ] **Step 5:** Actualizar el comentario del claim AA en `CLAUDE.md` del repo solo si el hex final difiere del documentado. Commit: `fix(a11y): WCAG AA contrast for template and semantic amber in light mode`

---

### Task 6: Anuncios VoiceOver para toasts y fin de streaming (A11Y-3)

**Files:**
- Modify: `Sources/Pasture/FeedService.swift:203-212`
- Modify: `Sources/Pasture/AskViewModel.swift` (donde el stream termina con éxito)

**Interfaces:** ninguna nueva.

- [ ] **Step 1:** En `FeedService.showFeedback`, anunciar el mensaje (SwiftUI, macOS 14+):

```swift
func showFeedback(_ message: String, isError: Bool = false) {
    feedbackDismissTask?.cancel()
    feedbackIsError = isError
    withAnimation { feedbackMessage = message }
    // El toast desaparece solo a los 2,5 s: sin anuncio, VoiceOver nunca lo ve.
    AccessibilityNotification.Announcement(message).post()
    feedbackDismissTask = Task { /* … sin cambios … */ }
}
```

- [ ] **Step 2:** En `AskViewModel`, al completarse el stream con éxito (localizar el punto donde `isStreaming` pasa a `false` sin error), añadir:

```swift
AccessibilityNotification.Announcement("Response complete").post()
```

- [ ] **Step 3:** Build + suite PASS. QA manual con VoiceOver (⌘F5): hacer un feed → VoiceOver lee el mensaje del toast; pregunta en Ask → al terminar anuncia "Response complete".

- [ ] **Step 4:** Commit: `fix(a11y): announce toasts and Ask completion to VoiceOver`

---

### Task 7: Respetar Reduce Motion (A11Y-4)

**Files:**
- Modify: `Sources/Pasture/AskView.swift:140-144` y `:441-452`
- Modify: `Sources/Pasture/PastureEmptyState.swift:57` (transición del toast)
- Modify: `Sources/Pasture/FeedAction.swift:101-102` (scaleEffect hover)

**Interfaces:** ninguna nueva.

- [ ] **Step 1:** `PulseModifier` estático bajo Reduce Motion:

```swift
private struct PulseModifier: ViewModifier {
    let speed: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.7)
        } else {
            content
                .scaleEffect(pulse ? 1.3 : 1.0)
                .opacity(pulse ? 1.0 : 0.4)
                .animation(.easeInOut(duration: speed).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
        }
    }
}
```

- [ ] **Step 2:** En la transición del toast (`PastureEmptyState.swift:57` y la `.animation` asociada en `ContentView.swift:141` / FeedChrome tras Task 4): con `@Environment(\.accessibilityReduceMotion)` activo usar `.transition(.opacity)` sin desplazamiento. En el autoscroll del stream (`AskView.swift:140-144`): scroll sin animación (`proxy.scrollTo(...)` fuera de `withAnimation`) cuando reduceMotion. En el hover del Feed button (`FeedAction.swift:101-102`): omitir el `scaleEffect` animado.

- [ ] **Step 3:** Build. QA: Ajustes del Sistema → Accesibilidad → Pantalla → Reducir movimiento ON; verificar que el indicador de streaming queda estático, el toast aparece por fundido y el botón Feed no escala.

- [ ] **Step 4:** Commit: `fix(a11y): honor Reduce Motion in pulse, toasts, scroll and hover effects`

---

### Task 8: Accesibilidad media — sheets y diff del Inbox (A11Y-5, A11Y-6, A11Y-7, A11Y-8, A11Y-9)

**Files:**
- Modify: `Sources/Pasture/FeedAction.swift:133-141` (TemplateSheet)
- Modify: `Sources/Pasture/ReviewQueueSheet.swift:18-19`, `Sources/Pasture/ReviewInboxSheet.swift:30-31` y `:144-163`
- Modify: `Sources/Pasture/FileRow.swift:8-43`
- Modify: `Sources/Pasture/AskView.swift:69-73`

**Interfaces:** ninguna nueva.

- [ ] **Step 1 (A11Y-5):** En cada TextField del TemplateSheet: `.accessibilityLabel("Value for \(variable.name)")`. Añadir `@FocusState` que enfoque el primer campo en `.onAppear` (copiar el patrón exacto de `NameInputSheet.swift:26/38`).

- [ ] **Step 2 (A11Y-6):** En ReviewQueueSheet y ReviewInboxSheet, el botón "Done" pasa a `.keyboardShortcut(.cancelAction)` (es un sheet de solo-cierre: Escape debe salir). Verificar que ningún otro control del sheet reclama `.cancelAction`.

- [ ] **Step 3 (A11Y-7):** En `contentPreview` de ReviewInboxSheet (rama `.append`), anteponer encabezados textuales para no depender solo del color:

```swift
Text("Current content").font(.caption).foregroundStyle(Color.pastureTextTertiary(colorScheme))
Text(truncated(current))
    .foregroundStyle(Color.pastureTextSecondary(colorScheme))
Text("Proposed addition").font(.caption).foregroundStyle(Color.pastureTextTertiary(colorScheme))
Text(payload)
    .foregroundStyle(Color.pastureSuccess(colorScheme))
    .accessibilityLabel("Proposed addition: \(payload)")
```

- [ ] **Step 4 (A11Y-8):** En el HStack raíz de `FileRow`: `.accessibilityElement(children: .combine)` (referencia: `MenuBarFileRow.swift:42-44` ya lo hace bien).

- [ ] **Step 5 (A11Y-9):** En el label de uso de contexto de Ask (`AskView.swift:73`), añadir el estado en texto: cuando el ratio supere el umbral ámbar/rojo, sufijo `" — above 50 % of the context window"` / `" — above 80 % of the context window"` (mismo patrón que `SidebarView.swift:366-374`).

- [ ] **Step 6:** Build + QA con VoiceOver: recorrer TemplateSheet (cada campo anuncia su variable), cerrar sheets con Escape, navegar una fila de fichero (un solo elemento combinado), oír el diff del Inbox con los dos encabezados.

- [ ] **Step 7:** Commit: `fix(a11y): labeled template fields, Escape on sheets, non-color diff cues, combined file rows`

---

### Task 9: Accesibilidad baja — fuentes escalables, hint y decorativos (A11Y-10, A11Y-11, A11Y-12)

**Files:**
- Modify: `Sources/Pasture/DesignTokens.swift:288`, `Sources/Pasture/MenuBarFileRow.swift:25,44`, `Sources/Pasture/SidebarView.swift:81,110`, `Sources/Pasture/ReviewInboxSheet.swift:158`, `Sources/Pasture/PastureEmptyState.swift:9`, `Sources/Pasture/AskView.swift:238`

- [ ] **Step 1:** Fuentes fijas → relativas: `pastureEditor` (13 pt) pasa a `.system(.body, design: …)` conservando diseño/peso actuales; los `size: 9` de chevrons y MenuBarFileRow a `.caption2`; el `size: 12` monospaced del diff a `.system(.caption, design: .monospaced)`. Comparar visualmente antes/después — si algún cambio rompe el layout compacto del menu bar, documentarlo y dejar ese caso.

- [ ] **Step 2:** `MenuBarFileRow.swift:44`: eliminar el hint "Double-tap to toggle selection" (el `.accessibilityValue` Selected/Not selected ya hace el trabajo; el gesto citado es de iOS).

- [ ] **Step 3:** `PastureEmptyState.swift:9` y `AskView.swift:238`: `.accessibilityHidden(true)` en los iconos decorativos.

- [ ] **Step 4:** Build + QA visual rápida en ambas superficies. Commit: `fix(a11y): scalable fonts, macOS-correct hints, hidden decorative icons`

---

### Task 10: Borrar mueve a la Papelera (UX-1)

**Files:**
- Modify: `Sources/Pasture/MDFileManager.swift:295` y `:385`
- Modify: `Sources/Pasture/ContentView.swift:123` (copy del alert)

- [ ] **Step 1:** Sustituir en ambos puntos:

```swift
try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
```

(ídem para `collectionURL` en la línea 385).

- [ ] **Step 2:** Copy del alert: `"'\(file.name).md' will be moved to the Trash."`. Buscar cualquier otro copy que diga "permanently deleted" para colecciones y alinearlo:

```bash
grep -rn "permanently" Sources/Pasture/
```

- [ ] **Step 3:** Build + QA: borrar una nota de prueba → aparece en la Papelera de macOS y se puede restaurar; borrar una colección → ídem.

- [ ] **Step 4:** Commit: `fix: move deleted files and collections to Trash instead of permanent removal`

---

### Task 11: Crear nota nueva vacía — Cmd+N y toolbar (UX-2)

**Files:**
- Modify: `Sources/Pasture/PastureApp.swift:16` (CommandGroup)
- Modify: `Sources/Pasture/ContentView.swift` (toolbar + sheet + onReceive)

**Interfaces:**
- Consumes: `NameInputSheet(title:actionLabel:onSubmit:)` (patrón existente de New Collection, `ContentView.swift:102-108`) y el método de creación de `MDFileManager` (verificar firma exacta: hay un `create` usado por QuickCapture/paste — localizarlo con `grep -n "func create" Sources/Pasture/MDFileManager.swift` y usar ese, con contenido `""`).
- Produces: `Notification.Name.newFile` (mismo patrón que `.openInEditor`/`.pasteFromClipboard` que PastureApp ya postea).

- [ ] **Step 1:** En PastureApp, reemplazar el CommandGroup vacío:

```swift
CommandGroup(replacing: .newItem) {
    Button("New File") {
        NotificationCenter.default.post(name: .newFile, object: nil)
    }
    .keyboardShortcut("n")
}
```

y declarar `Notification.Name.newFile` donde viven las otras (buscar `static let openInEditor`).

- [ ] **Step 2:** En ContentView: `@State private var showNewFileSheet = false`; `.onReceive` de `.newFile` → `showNewFileSheet = true`; botón en la toolbar (primero del grupo):

```swift
Button { showNewFileSheet = true } label: {
    Label("New File", systemImage: "square.and.pencil")
}
.help("Create a new empty note")
.accessibilityLabel("New file")
```

y el sheet:

```swift
.sheet(isPresented: $showNewFileSheet) {
    NameInputSheet(title: "New file", actionLabel: "Create") { name in
        if let file = fm.create(name: name, content: "") {
            selectFile(file)
            feedService.showFeedback("Created '\(name).md'")
        }
    }
}
```

(Adaptar al retorno real de `create` — si devuelve `Bool` o `URL`, ajustar la selección posterior.)

- [ ] **Step 3:** Build + QA: Cmd+N abre el sheet, crea la nota, queda seleccionada y visible; también desde la toolbar.

- [ ] **Step 4:** Commit: `feat: create empty note via Cmd+N and toolbar button`

---

### Task 12: Feedback headless robusto sin permiso de notificaciones (UX-3)

**Files:**
- Modify: `Sources/Pasture/SystemNotifier.swift`
- Modify: `Sources/Pasture/SettingsView.swift` (pestaña General, junto al toggle de hotkeys)

- [ ] **Step 1:** Fallback audible + stderr cuando no hay permiso:

```swift
static func notify(title: String, body: String) {
    guard isBundled else {
        FileHandle.standardError.write(Data("[Pasture] \(title): \(body)\n".utf8))
        return
    }
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
        guard granted else {
            // Sin permiso, el aviso moriría en silencio: al menos un beep y stderr,
            // que para "feed cancelled by secret" es la diferencia entre saberlo y no.
            DispatchQueue.main.async { NSSound.beep() }
            FileHandle.standardError.write(Data("[Pasture] (notifications denied) \(title): \(body)\n".utf8))
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
```

(`import AppKit` para `NSSound`.)

- [ ] **Step 2:** En Settings → General, bajo el toggle de hotkeys: al activarlo, disparar `SystemNotifier`-style `requestAuthorization` (o un método nuevo `SystemNotifier.ensurePermission`) y, si `getNotificationSettings` reporta `.denied`, mostrar caption persistente con el patrón visual de `loginItemError` (`SettingsView.swift:49-53`):

```swift
Text("Notifications are disabled for Pasture — hotkey feedback will be silent. Enable them in System Settings → Notifications.")
```

- [ ] **Step 3:** Build + bundle (`./scripts/bundle.sh`, instalar el .app) + QA: con notificaciones denegadas, ⌃⌥⌘F sin preset por defecto → suena beep (antes: nada); con permiso → notificación normal. El caption aparece en Settings cuando el permiso está denegado.

- [ ] **Step 4:** Commit: `fix: audible fallback and settings warning when notifications are denied`

---

### Task 13: Memory Inbox visible y seguro (UX-4, UX-5)

**Files:**
- Modify: `Sources/Pasture/MenuBarView.swift:88-115` (header)
- Modify: `Sources/Pasture/ReviewInboxSheet.swift:120-132` y `:183-192`

**Interfaces:**
- Consumes: `fm.pendingProposals` (`@Published`), `fm.reject(_:)`, `fm.promote(_:overrideChangedTarget:)` (verificar si el `.success` lleva URL asociada: `grep -n "func promote" Sources/Pasture/MDFileManager.swift` y la firma de `ProposalPromoter`).

- [ ] **Step 1 (UX-4): badge en el header del menu bar**, tras el menú de presets:

```swift
if !fm.pendingProposals.isEmpty {
    Button {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    } label: {
        Label("\(fm.pendingProposals.count)", systemImage: "tray.and.arrow.down")
            .font(.system(size: 11))
            .foregroundStyle(Color.pastureWarning(colorScheme))
    }
    .buttonStyle(.plain)
    .help("Proposals pending review")
    .accessibilityLabel("Review inbox, \(fm.pendingProposals.count) proposals pending")
}
```

(El popover ya tiene `@Environment(\.openWindow)`, línea 8.)

- [ ] **Step 2 (UX-5a): confirmación en Reject.** En ReviewInboxSheet: `@State private var proposalPendingRejection: Proposal?`; el botón Reject pasa a `proposalPendingRejection = proposal`; alert:

```swift
.alert("Reject proposal?", isPresented: Binding(
    get: { proposalPendingRejection != nil },
    set: { if !$0 { proposalPendingRejection = nil } }
), presenting: proposalPendingRejection) { proposal in
    Button("Reject", role: .destructive) { fm.reject(proposal); proposalPendingRejection = nil }
    Button("Cancel", role: .cancel) { proposalPendingRejection = nil }
} message: { proposal in
    Text("The proposal for '\(destinationLabel(proposal))' will be discarded permanently.")
}
```

- [ ] **Step 3 (UX-5b): feedback de éxito en Approve.** En `apply(_:overrideChangedTarget:)`, sustituir `case .success: break` por un mensaje con la ruta resultante. Si `promote` devuelve `Result<URL, _>`:

```swift
case .success(let url):
    successMessage = "Promoted to \(fm.relativeDisplayPath(for: url))"
```

con `@State private var successMessage: String?` mostrado sobre la lista con el estilo del `errorMessage` existente (y color `pastureSuccess(colorScheme)`). Si `promote` no devuelve URL, construir el texto desde `destinationLabel(proposal)`.

- [ ] **Step 4:** Build + QA: generar una propuesta de prueba vía MCP (`PASTURE_ALLOW_PROPOSALS=1`, tool `propose_note`) o usar la pendiente real del inbox si sigue ahí (`Mercados/mercado-portugues.md` — NO rechazarla: usarla solo para ver el badge y el diff; cualquier prueba destructiva, con una propuesta sintética). Verificar: badge visible en el menu bar → clic abre la ventana; Reject pide confirmación; Approve muestra la ruta creada.

- [ ] **Step 5:** Commit: `feat: inbox badge in menu bar, reject confirmation and approve feedback`

---

### Task 14: Error de registro de hotkeys visible en Settings (UX-9)

**Files:**
- Modify: `Sources/Pasture/GlobalHotkeyManager.swift:59-65`
- Modify: `Sources/Pasture/SettingsView.swift:65-68`

**Interfaces:**
- Produces: `GlobalHotkeyManager` expone el resultado del registro (p. ej. `@Published private(set) var registrationError: String?` si ya es ObservableObject; si es un tipo plano, un `var lastError: String?` consultado tras activar — adaptar a su forma real, que hay que leer primero).

- [ ] **Step 1:** En el punto donde `RegisterEventHotKey` falla (hoy solo stderr), guardar además un mensaje legible: `"⌃⌥⌘F is already in use by another app"` (o el combo que falló).

- [ ] **Step 2:** En SettingsView, bajo el toggle de hotkeys, caption condicional con el patrón de `loginItemError` (`SettingsView.swift:49-53`) mostrando ese mensaje.

- [ ] **Step 3:** Build + QA: registrar ⌃⌥⌘F en otra app (p. ej. un atajo de Atajos.app) → activar el toggle en Pasture → aparece el caption. Sin conflicto → no aparece.

- [ ] **Step 4:** Commit: `fix: surface global hotkey registration failures in Settings`

---

### Task 15: Fricciones de la ventana principal — presets, Feed y Clear (UX-6, UX-7, UX-8)

**Files:**
- Modify: `Sources/Pasture/ContentView.swift:302-314` (presetMenu)
- Modify: `Sources/Pasture/FeedAction.swift` (tooltip del FeedButton)
- Modify: `Sources/Pasture/AskView.swift:380-389` + `Sources/Pasture/AskViewModel.swift`

- [ ] **Step 1 (UX-6):** clic en el nombre del preset aplica; la gestión queda en el hold — igual que el propio FeedButton:

```swift
ForEach(presets) { preset in
    Menu(preset.name) {
        Button("Rename\u{2026}") { presetPendingRename = preset }
        Divider()
        Button("Delete\u{2026}", role: .destructive) { presetPendingDeletion = preset }
    } primaryAction: {
        applyPreset(preset)
    }
}
```

- [ ] **Step 2 (UX-7):** el `.help` del FeedButton nombra el destino del clic. En `FeedAction.swift`, donde hoy hay el tooltip genérico, con el destino por defecto disponible (la propiedad que decide la acción primaria en las líneas 36-47):

```swift
.help(defaultDestination.map { "Feed → \($0.name) (hold for more options)" }
      ?? "Feed → clipboard (hold for more options)")
```

(Ajustar al nombre real de la propiedad; si el default sin estrella es clipboard, reflejarlo tal cual hace la lógica del clic.)

- [ ] **Step 3 (UX-8):** icono coherente + confirmación solo si hay conversación que perder:

```swift
Button {
    if viewModel.conversation.messages.count >= 2 {
        showClearConfirmation = true
    } else {
        viewModel.clear()
    }
} label: {
    Image(systemName: "trash")
}
.help("Clear conversation")
```

más `@State private var showClearConfirmation = false` y un `.alert("Clear conversation?", …)` con "Clear" destructivo y "Cancel" por defecto.

- [ ] **Step 4:** Build + QA: clic en nombre de preset aplica; hold muestra Rename/Delete; tooltip del Feed nombra destino con y sin estrella configurada; Clear con 1 mensaje no pregunta, con 2+ pide confirmación.

- [ ] **Step 5:** Commit: `fix(ux): one-click presets, feed destination tooltip, safe clear conversation`

---

### Task 16: Sidebar — borrado múltiple, Open in Editor y Scan Folder limpio (UX-10, UX-11, UX-12)

**Files:**
- Modify: `Sources/Pasture/SidebarView.swift:232-237` y `:257-286`
- Modify: `Sources/Pasture/ContentView.swift:117-124` y `:338-342` (alert y deleteFile)
- Modify: `Sources/Pasture/MDFileManager+Import.swift:66-91`

- [ ] **Step 1 (UX-10):** generalizar el borrado a N ficheros. Cambiar el estado compartido `filePendingDeletion: MDFile?` por `filesPendingDeletion: [MDFile]` (ContentView + los bindings que recibe SidebarView), y:

```swift
.onDeleteCommand {
    guard !selectedFiles.isEmpty else { return }
    filesPendingDeletion = fm.files.filter { selectedFiles.contains($0) }
    showDeleteConfirmation = true
}
```

Alert con texto singular/plural (tras Task 10, ya en clave Papelera):

```swift
Text(files.count == 1
    ? "'\(files[0].name).md' will be moved to the Trash."
    : "\(files.count) files will be moved to the Trash.")
```

y `deleteFile` pasa a `deleteFiles(_ files: [MDFile])` limpiando `activeFile`/`selectedFiles` y llamando a `fm.delete(files:)` (que ya acepta array). El menú contextual del fichero individual sigue funcionando: llena el array con un elemento.

- [ ] **Step 2 (UX-11):** "Open in Editor" en el menú contextual. SidebarView recibe un callback `let onOpenInEditor: (MDFile) -> Void` (mismo patrón que `onDrop`), y en `fileContextMenu`, antes de Rename:

```swift
Button {
    onOpenInEditor(file)
} label: {
    Label("Open in Editor", systemImage: "square.and.pencil")
}
```

ContentView lo cablea a su `openInExternalEditor` existente.

- [ ] **Step 3 (UX-12):** en `scanFolder` (`MDFileManager+Import.swift`), si al terminar `count == 0`, eliminar la colección recién creada antes de fijar `lastError` (es un directorio vacío que acabamos de crear; usar la misma vía que `deleteCollection` o `FileManager` directo sobre esa URL). Alternativa equivalente: diferir la creación hasta el primer `.md` encontrado — elegir la que menos reordene el código actual.

- [ ] **Step 4:** Build + QA: seleccionar 3 ficheros + ⌫ → alert plural → los 3 a la Papelera; clic derecho → Open in Editor abre el editor externo; Scan Folder sobre carpeta sin .md → error visible y CERO colección residual en el sidebar.

- [ ] **Step 5:** Commit: `fix(ux): multi-file delete, Open in Editor context action, no residual collection on empty scan`

---

### Task 17: Verificación integral y cierre

**Files:**
- Modify: `CHANGELOG.md` (entrada v1.10.0, formato Keep a Changelog: Added / Changed / Fixed)
- Modify: `scripts/bundle.sh` (VERSION → 1.10.0) — solo si se decide release; si no, dejar versión y anotarlo

- [ ] **Step 1:** Suite completa con el toolchain correcto → los 710+ tests PASS (los nuevos de Task 2 incluidos). `swift build -c release` OK.

- [ ] **Step 2:** `./scripts/bundle.sh` y QA transversal con el .app instalado: recorrido de humo por los 12 fixes de UX y los 12 de a11y (checklist = pasos de QA de cada tarea), en light y dark, ventana principal y menu bar, con VoiceOver y Reduce Motion activados al menos una pasada.

- [ ] **Step 3:** Revisar que ningún cambio tocó invariantes SEC-\*: `grep -rn "Continue anyway" Sources/Pasture/` (sigue con rol destructivo y Cancel default), y la suite MCP entera verde.

- [ ] **Step 4:** CHANGELOG + commit final: `docs: changelog for v1.10 ux/a11y/simplification pass`. Push de la rama y PR contra `main` (CI macos-15 debe quedar verde antes de mergear).

---

## Decisiones pendientes del propietario (NO ejecutar sin OK)

1. **`Proposal.autoApproved`** (SIMP, señalado): reserva de la Fase 2 del Memory Inbox. Retirarlo si la Fase 2 no está en el horizonte — reintroducible sin migración.
2. **Unificar el auto-clear de clipboard** (FeedService vs HeadlessActions): invariante de seguridad duplicado con feedback distinto; beneficio marginal.
3. **Orden del Merge** (concatena por fecha aunque el sidebar ordene por nombre): indicar el orden en el sheet o respetar el orden visible.
4. **`AIClient.buildRequest` single-turn** público solo-tests: candidato a retirar reescribiendo sus 8 tests.
5. **IntegrationSettings postea `didChangeNotification` en sus setters y los otros tres namespaces no**: unificar cambia semántica con UserDefaults inyectados en tests — solo si se toca esa zona por otro motivo.

## Dudas y asunciones

- Asumo v1.10.0 como etiqueta de la iteración; el bump real de `scripts/bundle.sh` es decisión de release (Task 17 lo condiciona).
- Las firmas exactas de `fm.create`, `fm.promote`/`ProposalPromoter` y la forma de `GlobalHotkeyManager` no se leyeron completas en la revisión: las Tasks 11, 13 y 14 incluyen el paso de verificación correspondiente antes de escribir código.
- Los cambios de fuente de Task 9 pueden alterar el layout compacto del menu bar: el paso de QA manda — ante duda, conservar el caso conflictivo y anotarlo.
- La propuesta real pendiente en el inbox (`Mercados/mercado-portugues.md`) no se toca de forma destructiva en QA (Task 13).
