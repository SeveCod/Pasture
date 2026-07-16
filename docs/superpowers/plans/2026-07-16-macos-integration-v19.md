# macOS System Integration (v1.9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dar a Pasture puntos de entrada desde el sistema: hotkeys globales con acciones headless (feed al portapapeles / captura rápida), URL scheme `pasture://`, menú Servicios, arranque al login, modo "solo menu bar" y firma ad-hoc del bundle.

**Architecture:** Toda la lógica nueva con decisiones (parser de URL, propuesta de captura, ensamblado del feed headless, persistencia de preferencias) vive en PastureKit como tipos puros/testables (TDD). El pegamento AppKit (Carbon hotkeys, NSPasteboard, UNUserNotificationCenter, SMAppService, servicesProvider) vive en el target Pasture como capas finas sin tests unitarios (QA manual al final). El bundle.sh gana las claves de Info.plist (CFBundleURLTypes, NSServices) y codesign ad-hoc.

**Tech Stack:** Swift 6 strict, SwiftUI/AppKit, Carbon.HIToolbox (RegisterEventHotKey), ServiceManagement (SMAppService), UserNotifications. **Cero dependencias externas** (todo frameworks de Apple).

## Global Constraints

- macOS 14+ (`Package.swift` ya lo fija). Swift 6 strict concurrency.
- **Cero dependencias externas** — regla identitaria del proyecto.
- Prosa y comentarios en español; identifiers y commits en inglés.
- Tests con Swift Testing (`import Testing`, `@Test`, `#expect`). Ejecutar con el toolchain: `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test` (el CLT no trae el módulo Testing).
- El servidor MCP NO participa (SEC-M11): nada de esto toca `Sources/pasture-mcp/` ni `Sources/PastureKit/MCP/`.
- Patrón de settings: namespace estático sobre UserDefaults con `defaults` inyectable + `didChangeNotification` (como `ExportSettings`).
- Invariante de portapapeles: auto-clear a los 60 s post-feed (se replica en el feed headless).
- Los hotkeys globales son **opt-in** (default off) — no sorprender con capturas de teclado globales.
- Rama de trabajo: `feat/macos-integration-v1.9` desde `main`.

---

### Task 0: Rama de trabajo

- [ ] **Step 1:** `git checkout -b feat/macos-integration-v1.9` (desde main limpio).

---

### Task 1: IntegrationSettings (PastureKit)

**Files:**
- Create: `Sources/PastureKit/IntegrationSettings.swift`
- Test: `Tests/PastureKitTests/IntegrationSettingsTests.swift`

**Interfaces:**
- Produces: `IntegrationSettings.hideDockIcon(from:) -> Bool`, `setHideDockIcon(_:in:)`, `globalHotkeysEnabled(from:) -> Bool`, `setGlobalHotkeysEnabled(_:in:)`, `defaultPresetID(from:) -> UUID?`, `setDefaultPresetID(_:in:)`, `didChangeNotification`. Defaults seguros: false/false/nil.

- [ ] **Step 1: Test que falla**

```swift
import Foundation
import Testing
@testable import PastureKit

@Suite("IntegrationSettings")
struct IntegrationSettingsTests {

    private func makeDefaults() -> UserDefaults {
        let name = "IntegrationSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsAreSafe() {
        let defaults = makeDefaults()
        #expect(IntegrationSettings.hideDockIcon(from: defaults) == false)
        #expect(IntegrationSettings.globalHotkeysEnabled(from: defaults) == false)
        #expect(IntegrationSettings.defaultPresetID(from: defaults) == nil)
    }

    @Test func roundTripAllSettings() {
        let defaults = makeDefaults()
        let id = UUID()
        IntegrationSettings.setHideDockIcon(true, in: defaults)
        IntegrationSettings.setGlobalHotkeysEnabled(true, in: defaults)
        IntegrationSettings.setDefaultPresetID(id, in: defaults)
        #expect(IntegrationSettings.hideDockIcon(from: defaults) == true)
        #expect(IntegrationSettings.globalHotkeysEnabled(from: defaults) == true)
        #expect(IntegrationSettings.defaultPresetID(from: defaults) == id)
    }

    @Test func clearingDefaultPresetID() {
        let defaults = makeDefaults()
        IntegrationSettings.setDefaultPresetID(UUID(), in: defaults)
        IntegrationSettings.setDefaultPresetID(nil, in: defaults)
        #expect(IntegrationSettings.defaultPresetID(from: defaults) == nil)
    }

    @Test func corruptPresetIDDegradesToNil() {
        let defaults = makeDefaults()
        defaults.set("not-a-uuid", forKey: "pastureDefaultPresetID")
        #expect(IntegrationSettings.defaultPresetID(from: defaults) == nil)
    }
}
```

- [ ] **Step 2:** Run `~/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swift test --filter IntegrationSettingsTests` → FAIL (tipo no existe).
- [ ] **Step 3: Implementación mínima**

```swift
import Foundation

/// v1.9 — Preferencias de integración con el sistema (hotkeys globales,
/// icono del Dock, preset por defecto para el feed headless).
/// Mismo patrón que ExportSettings/AISettings: namespace estático sobre
/// UserDefaults con defaults inyectables para tests.
public enum IntegrationSettings {

    static let hideDockIconKey = "pastureHideDockIcon"
    static let globalHotkeysEnabledKey = "pastureGlobalHotkeysEnabled"
    static let defaultPresetIDKey = "pastureDefaultPresetID"

    public static let didChangeNotification = Notification.Name("PastureIntegrationSettingsDidChange")

    public static func hideDockIcon(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: hideDockIconKey)
    }

    public static func setHideDockIcon(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: hideDockIconKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    /// Default false: los hotkeys globales son opt-in — nunca sorprender
    /// con capturas de teclado a nivel de sistema.
    public static func globalHotkeysEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: globalHotkeysEnabledKey)
    }

    public static func setGlobalHotkeysEnabled(_ value: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: globalHotkeysEnabledKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func defaultPresetID(from defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: defaultPresetIDKey).flatMap(UUID.init(uuidString:))
    }

    public static func setDefaultPresetID(_ id: UUID?, in defaults: UserDefaults = .standard) {
        if let id {
            defaults.set(id.uuidString, forKey: defaultPresetIDKey)
        } else {
            defaults.removeObject(forKey: defaultPresetIDKey)
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
```

- [ ] **Step 4:** Run filtro de nuevo → PASS. Run suite completa → PASS (690+4).
- [ ] **Step 5:** `git add -A && git commit -m "feat(kit): IntegrationSettings for system-integration preferences"`

---

### Task 2: PastureURLCommand (PastureKit)

**Files:**
- Create: `Sources/PastureKit/PastureURLCommand.swift`
- Test: `Tests/PastureKitTests/PastureURLCommandTests.swift`

**Interfaces:**
- Produces: `PastureURLCommand.parse(_ url: URL) -> PastureURLCommand?` con casos `.feed(presetName: String?)`, `.new(title: String?, text: String?)`, `.search(query: String)`.

- [ ] **Step 1: Test que falla**

```swift
import Foundation
import Testing
@testable import PastureKit

@Suite("PastureURLCommand")
struct PastureURLCommandTests {

    @Test func feedWithoutPreset() {
        let cmd = PastureURLCommand.parse(URL(string: "pasture://feed")!)
        #expect(cmd == .feed(presetName: nil))
    }

    @Test func feedWithPercentEncodedPreset() {
        let cmd = PastureURLCommand.parse(URL(string: "pasture://feed?preset=Mi%20Preset")!)
        #expect(cmd == .feed(presetName: "Mi Preset"))
    }

    @Test func newWithTitleAndText() {
        let cmd = PastureURLCommand.parse(URL(string: "pasture://new?title=Idea&text=hola%20mundo")!)
        #expect(cmd == .new(title: "Idea", text: "hola mundo"))
    }

    @Test func newWithNoParams() {
        let cmd = PastureURLCommand.parse(URL(string: "pasture://new")!)
        #expect(cmd == .new(title: nil, text: nil))
    }

    @Test func searchRequiresQuery() {
        #expect(PastureURLCommand.parse(URL(string: "pasture://search?q=mcp")!) == .search(query: "mcp"))
        #expect(PastureURLCommand.parse(URL(string: "pasture://search")!) == nil)
        #expect(PastureURLCommand.parse(URL(string: "pasture://search?q=%20")!) == nil)
    }

    @Test func foreignSchemeAndUnknownHostRejected() {
        #expect(PastureURLCommand.parse(URL(string: "https://feed?preset=x")!) == nil)
        #expect(PastureURLCommand.parse(URL(string: "pasture://selfdestruct")!) == nil)
    }

    @Test func hostIsCaseInsensitive() {
        #expect(PastureURLCommand.parse(URL(string: "pasture://FEED")!) == .feed(presetName: nil))
    }
}
```

- [ ] **Step 2:** Run filtro → FAIL.
- [ ] **Step 3: Implementación**

```swift
import Foundation

/// v1.9 — Comandos del URL scheme `pasture://`. Parser puro y testable;
/// el dispatch (AppKit) vive en AppDelegate. Un URL no reconocido devuelve
/// nil y se ignora en silencio — nunca crashea ni ejecuta nada.
public enum PastureURLCommand: Equatable, Sendable {
    /// pasture://feed[?preset=Nombre] — feed headless al portapapeles.
    case feed(presetName: String?)
    /// pasture://new[?title=T][&text=B] — captura una nota nueva.
    case new(title: String?, text: String?)
    /// pasture://search?q=término — abre la ventana con la búsqueda aplicada.
    case search(query: String)

    public static func parse(_ url: URL) -> PastureURLCommand? {
        guard url.scheme?.lowercased() == "pasture",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            guard let raw = items.first(where: { $0.name == name })?.value else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        switch components.host?.lowercased() {
        case "feed":
            return .feed(presetName: value("preset"))
        case "new":
            return .new(title: value("title"), text: value("text"))
        case "search":
            guard let query = value("q") else { return nil }
            return .search(query: query)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4:** Run filtro → PASS. Suite completa → PASS.
- [ ] **Step 5:** `git commit -m "feat(kit): pasture:// URL command parser"`

---

### Task 3: QuickCapture (PastureKit)

**Files:**
- Create: `Sources/PastureKit/QuickCapture.swift`
- Test: `Tests/PastureKitTests/QuickCaptureTests.swift`

**Interfaces:**
- Consumes: `FilenameSanitizer.sanitize(_:)`.
- Produces: `QuickCapture.proposal(text:title:now:) -> Proposal?` con `Proposal(baseName: String, content: String)`; `QuickCapture.collectionName == "Captures"`; `maxBaseNameLength == 40`.
- Nota de diseño: la colección visible se llama **`Captures/`** (NO "Inbox") para no confundir con el `.inbox/` oculto del Memory Inbox v1.8.

- [ ] **Step 1: Test que falla**

```swift
import Foundation
import Testing
@testable import PastureKit

@Suite("QuickCapture")
struct QuickCaptureTests {

    @Test func emptyOrWhitespaceReturnsNil() {
        #expect(QuickCapture.proposal(text: "") == nil)
        #expect(QuickCapture.proposal(text: "  \n\t ") == nil)
    }

    @Test func baseNameFromFirstNonEmptyLine() {
        let proposal = QuickCapture.proposal(text: "\n\nMi idea brillante\nsegunda línea")
        #expect(proposal?.baseName == "Mi idea brillante")
        #expect(proposal?.content == "Mi idea brillante\nsegunda línea\n")
    }

    @Test func explicitTitleWinsOverFirstLine() {
        let proposal = QuickCapture.proposal(text: "cuerpo de la nota", title: "Titulo Explicito")
        #expect(proposal?.baseName == "Titulo Explicito")
    }

    @Test func baseNameTruncatedTo40() {
        let long = String(repeating: "a", count: 100)
        let proposal = QuickCapture.proposal(text: long)
        #expect(proposal?.baseName.count == QuickCapture.maxBaseNameLength)
    }

    @Test func baseNameIsSanitized() {
        let proposal = QuickCapture.proposal(text: "re: plan/notas \\ finales")
        let base = try! #require(proposal?.baseName)
        #expect(!base.contains("/"))
        #expect(!base.contains(":"))
        #expect(!base.contains("\\"))
    }

    @Test func timestampFallbackIsDeterministic() {
        // Título compuesto solo de caracteres que el sanitizer elimina/recorta.
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        let a = QuickCapture.proposal(text: "cuerpo", title: "...", now: fixed)
        let b = QuickCapture.proposal(text: "cuerpo", title: "...", now: fixed)
        #expect(a?.baseName == b?.baseName)
        #expect(a?.baseName.hasPrefix("capture-") == true)
    }
}
```

- [ ] **Step 2:** Run filtro → FAIL.
- [ ] **Step 3: Implementación**

```swift
import Foundation

/// v1.9 — Propuesta pura de nota para la captura rápida (hotkey global,
/// menú Servicios y pasture://new). Decide nombre base y contenido; el I/O
/// (dedupe + escritura en disco) vive en la app (HeadlessActions).
///
/// La colección destino es `Captures/` — visible, distinta del `.inbox/`
/// oculto del Memory Inbox (propuestas MCP, v1.8).
public enum QuickCapture {

    public static let collectionName = "Captures"
    public static let maxBaseNameLength = 40

    public struct Proposal: Equatable, Sendable {
        public let baseName: String   // sin extensión .md
        public let content: String
    }

    /// `nil` si el texto está vacío o es solo whitespace. El nombre sale del
    /// título explícito o de la primera línea no vacía; si tras sanear no
    /// queda nada, timestamp determinista (clock inyectado, patrón Freshness).
    public static func proposal(text: String, title: String? = nil, now: Date = Date()) -> Proposal? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = (trimmedTitle?.isEmpty == false ? trimmedTitle! : nil)
            ?? body.components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces)
            ?? ""

        var base = FilenameSanitizer.sanitize(String(candidate.prefix(maxBaseNameLength)))
        if base.isEmpty {
            base = "capture-" + timestamp(now)
        }
        return Proposal(baseName: base, content: body + "\n")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
```

Gotcha del test de truncado: `sanitize` recorta `". "` en extremos — con 100 aes no afecta. Si el test de 40 falla por recorte, ajustar el `#expect` a `<= maxBaseNameLength` y `> 0` (documentando el porqué).

- [ ] **Step 4:** Run filtro → PASS. Suite completa → PASS.
- [ ] **Step 5:** `git commit -m "feat(kit): QuickCapture note proposal for headless capture"`

---

### Task 4: HeadlessFeed (PastureKit)

**Files:**
- Create: `Sources/PastureKit/HeadlessFeed.swift`
- Test: `Tests/PastureKitTests/HeadlessFeedTests.swift`

**Interfaces:**
- Consumes: `PresetResolver.resolve(relativePaths:base:) -> Resolution{urls,rejectedCount}`, `PresetResolver.missingPaths(relativePaths:base:existing:)`, `ContextBuilder.build(files:format:)`, `SecretScanner.scan(_: [Input])` → `SecretScanResult{isEmpty, summaryLines()}`, `TokenEstimator.estimate(_:)`, `SelectionPreset`.
- Produces: `HeadlessFeed.build(preset:base:format:) -> Outcome` con `.success(Success{context,fileCount,tokens,missingPaths})`, `.noFiles(missingPaths:)`, `.secretsDetected(summaryLines:)`.
- Política: secretos **bloquean** (equivalente al default Cancel del diálogo GUI); ficheros ausentes no bloquean si queda ≥1.

- [ ] **Step 1: Test que falla**

```swift
import Foundation
import Testing
@testable import PastureKit

@Suite("HeadlessFeed")
struct HeadlessFeedTests {

    private func makeVault() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HeadlessFeedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makePreset(paths: [String]) -> SelectionPreset {
        SelectionPreset(id: UUID(), name: "test", relativePaths: paths, createdAt: Date())
    }

    @Test func successWithPartialMissing() throws {
        let vault = try makeVault()
        try "# uno".write(to: vault.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "# dos".write(to: vault.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        let preset = makePreset(paths: ["a.md", "b.md", "gone.md"])

        let outcome = HeadlessFeed.build(preset: preset, base: vault, format: .xml)
        guard case .success(let result) = outcome else {
            Issue.record("Expected .success, got \(outcome)")
            return
        }
        #expect(result.fileCount == 2)
        #expect(result.missingPaths == ["gone.md"])
        #expect(result.context.contains("a.md"))
        #expect(result.tokens > 0)
    }

    @Test func allMissingReturnsNoFiles() throws {
        let vault = try makeVault()
        let preset = makePreset(paths: ["x.md", "../escape.md"])
        let outcome = HeadlessFeed.build(preset: preset, base: vault, format: .xml)
        guard case .noFiles(let missing) = outcome else {
            Issue.record("Expected .noFiles, got \(outcome)")
            return
        }
        #expect(missing.count == 2)
    }

    @Test func secretsBlockTheFeed() throws {
        let vault = try makeVault()
        // Literal concatenado: GitHub Push Protection bloquea fixtures realistas.
        let fakeKey = "sk-ant-" + String(repeating: "a", count: 24)
        try "clave: \(fakeKey)".write(to: vault.appendingPathComponent("leak.md"), atomically: true, encoding: .utf8)
        let preset = makePreset(paths: ["leak.md"])

        let outcome = HeadlessFeed.build(preset: preset, base: vault, format: .xml)
        guard case .secretsDetected(let lines) = outcome else {
            Issue.record("Expected .secretsDetected, got \(outcome)")
            return
        }
        #expect(!lines.isEmpty)
        #expect(!lines.joined().contains(fakeKey))  // SEC-4: nunca el valor
    }
}
```

- [ ] **Step 2:** Run filtro → FAIL.
- [ ] **Step 3: Implementación**

```swift
import Foundation

/// v1.9 — Ensamblado puro del feed headless (hotkey global / pasture://feed).
/// Resuelve el preset, lee los ficheros, escanea secretos y construye el
/// contexto. Sin UI: el llamante decide portapapeles/notificación.
///
/// Política de secretos: BLOQUEA. En la GUI el diálogo tiene Cancel como
/// default; sin diálogo posible, el equivalente conservador es no entregar.
public enum HeadlessFeed {

    public struct Success: Equatable, Sendable {
        public let context: String
        public let fileCount: Int
        public let tokens: Int
        public let missingPaths: [String]
    }

    public enum Outcome: Equatable, Sendable {
        case success(Success)
        case noFiles(missingPaths: [String])
        case secretsDetected(summaryLines: [String])
    }

    public static func build(preset: SelectionPreset, base: URL, format: FeedFormat) -> Outcome {
        let resolution = PresetResolver.resolve(relativePaths: preset.relativePaths, base: base)

        var entries: [ContextBuilder.FileEntry] = []
        var existing: Set<URL> = []
        for url in resolution.urls {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            existing.insert(url)
            entries.append(.init(name: url.lastPathComponent, content: content))
        }
        let missing = PresetResolver.missingPaths(
            relativePaths: preset.relativePaths, base: base, existing: existing
        )

        guard !entries.isEmpty else { return .noFiles(missingPaths: missing) }

        let scan = SecretScanner.scan(entries.map { .init(fileName: $0.name, content: $0.content) })
        guard scan.isEmpty else { return .secretsDetected(summaryLines: scan.summaryLines()) }

        let context = ContextBuilder.build(files: entries, format: format)
        let tokens = entries.reduce(0) { $0 + TokenEstimator.estimate($1.content) }
        return .success(.init(context: context, fileCount: entries.count, tokens: tokens, missingPaths: missing))
    }
}
```

Nota: si `SelectionPreset` no tiene init memberwise público con esas etiquetas exactas, mirar `Sources/PastureKit/SelectionPreset.swift` y usar el init real en el test (no cambiar el tipo).

- [ ] **Step 4:** Run filtro → PASS. Suite completa → PASS.
- [ ] **Step 5:** `git commit -m "feat(kit): HeadlessFeed — preset feed assembly with secret gate"`

---

### Task 5: SystemNotifier + HeadlessActions (app, pegamento)

**Files:**
- Create: `Sources/Pasture/SystemNotifier.swift`
- Create: `Sources/Pasture/HeadlessActions.swift`

**Interfaces:**
- Consumes: `HeadlessFeed.build`, `QuickCapture.proposal`, `IntegrationSettings.defaultPresetID()`, `SelectionPresetStore.load()/preset(named:)`, `FeedFormatSettings.feedFormat()`, `FileLibrary.deduplicatedURL(baseName:ext:in:)`, `MDFileManager.pastureDir`, `TokenEstimator.formatted(_:)`.
- Produces: `HeadlessActions.feedDefaultPreset()`, `HeadlessActions.feed(named:)`, `HeadlessActions.capture(text:title:)`, `HeadlessActions.captureClipboard()` — todos `@MainActor`. `SystemNotifier.notify(title:body:)`.

- [ ] **Step 1: SystemNotifier.swift**

```swift
import Foundation
import UserNotifications

/// v1.9 — Feedback de acciones headless vía Centro de Notificaciones.
/// Gotcha: UNUserNotificationCenter exige un bundle real (.app). Bajo
/// `swift run` (ejecutable suelto) el bundle proxy es nil y el framework
/// aborta: en ese caso degradamos a stderr y seguimos.
@MainActor
enum SystemNotifier {

    private static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static func notify(title: String, body: String) {
        guard isBundled else {
            FileHandle.standardError.write(Data("[Pasture] \(title): \(body)\n".utf8))
            return
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
```

- [ ] **Step 2: HeadlessActions.swift**

```swift
import AppKit
import PastureKit

/// v1.9 — Acciones sin ventana: feed del preset por defecto al portapapeles
/// y captura rápida (hotkey global, menú Servicios, pasture://). La lógica
/// con decisiones vive en PastureKit (HeadlessFeed/QuickCapture); aquí solo
/// el pegamento AppKit: pasteboard, disco, notificación.
@MainActor
enum HeadlessActions {

    // MARK: - Feed

    /// Feed del preset por defecto. Sin default configurado: si existe
    /// exactamente un preset se usa ese; si no, se pide configuración.
    static func feedDefaultPreset() {
        let presets = SelectionPresetStore.load()
        let preset: SelectionPreset?
        if let id = IntegrationSettings.defaultPresetID() {
            preset = presets.first(where: { $0.id == id })
        } else if presets.count == 1 {
            preset = presets.first
        } else {
            preset = nil
        }
        guard let preset else {
            SystemNotifier.notify(
                title: "Pasture",
                body: "No default preset configured. Pick one in Settings → General."
            )
            return
        }
        feed(preset: preset)
    }

    static func feed(named name: String) {
        guard let preset = SelectionPresetStore.preset(named: name) else {
            SystemNotifier.notify(title: "Pasture", body: "Preset '\(name)' not found.")
            return
        }
        feed(preset: preset)
    }

    private static func feed(preset: SelectionPreset) {
        let outcome = HeadlessFeed.build(
            preset: preset,
            base: MDFileManager.pastureDir,
            format: FeedFormatSettings.feedFormat()
        )
        switch outcome {
        case .success(let result):
            copyWithAutoClear(result.context)
            var body = "'\(preset.name)': \(result.fileCount) files, \(TokenEstimator.formatted(result.tokens)) tokens copied."
            if !result.missingPaths.isEmpty {
                body += " Missing: \(result.missingPaths.joined(separator: ", "))."
            }
            SystemNotifier.notify(title: "Context copied", body: body)
        case .noFiles:
            SystemNotifier.notify(
                title: "Feed cancelled",
                body: "No files from '\(preset.name)' exist on disk."
            )
        case .secretsDetected(let lines):
            SystemNotifier.notify(
                title: "Possible secret detected — feed cancelled",
                body: lines.joined(separator: "\n") + "\nReview and feed from the app."
            )
        }
    }

    /// Copia preservando el invariante de seguridad del feed GUI:
    /// auto-clear a los 60 s si el usuario no ha copiado otra cosa.
    private static func copyWithAutoClear(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            if NSPasteboard.general.changeCount == changeCount {
                NSPasteboard.general.clearContents()
            }
        }
    }

    // MARK: - Capture

    /// Captura texto a una nota nueva en `Captures/`. El DirectoryWatcher
    /// del manager recoge el fichero nuevo solo (0,5 s de debounce).
    @discardableResult
    static func capture(text: String, title: String? = nil) -> String? {
        guard let proposal = QuickCapture.proposal(text: text, title: title) else {
            SystemNotifier.notify(title: "Nothing to capture", body: "No text available.")
            return nil
        }
        let dir = MDFileManager.pastureDir
            .appendingPathComponent(QuickCapture.collectionName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = FileLibrary.deduplicatedURL(baseName: proposal.baseName, ext: "md", in: dir)
            try proposal.content.write(to: url, atomically: true, encoding: .utf8)
            SystemNotifier.notify(
                title: "Captured",
                body: "\(url.lastPathComponent) → \(QuickCapture.collectionName)/"
            )
            return url.lastPathComponent
        } catch {
            SystemNotifier.notify(title: "Capture failed", body: error.localizedDescription)
            return nil
        }
    }

    static func captureClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        capture(text: text)
    }
}
```

- [ ] **Step 3:** `swift build` → OK (sin tests: pegamento AppKit; la lógica ya está testeada en Kit). Suite completa sigue en verde.
- [ ] **Step 4:** `git commit -m "feat(app): headless feed & capture actions with notification feedback"`

---

### Task 6: GlobalHotkeyManager (Carbon) + arranque

**Files:**
- Create: `Sources/Pasture/GlobalHotkeyManager.swift`
- Modify: `Sources/Pasture/AppDelegate.swift` (arranque de hotkeys + política de activación)

**Interfaces:**
- Consumes: `HeadlessActions.feedDefaultPreset()/captureClipboard()`, `IntegrationSettings.globalHotkeysEnabled()/hideDockIcon()/didChangeNotification`.
- Produces: `GlobalHotkeyManager.shared.start()` (idempotente; observa didChange y (des)registra). Combos fijos v1: ⌃⌥⌘F feed, ⌃⌥⌘N captura.

- [ ] **Step 1: GlobalHotkeyManager.swift**

```swift
import AppKit
import Carbon.HIToolbox
import PastureKit

/// v1.9 — Hotkeys globales vía Carbon RegisterEventHotKey (framework de
/// Apple; a diferencia de los monitors de NSEvent NO requiere permiso de
/// Accesibilidad). Combos fijos en v1 (grabador de atajos = trabajo futuro):
///   ⌃⌥⌘F → feed del preset por defecto al portapapeles
///   ⌃⌥⌘N → captura rápida del portapapeles
/// Opt-in desde Settings → General; el callback C no puede capturar contexto,
/// por eso el hop a MainActor va vía DispatchQueue.main (patrón DirectoryWatcher).
@MainActor
final class GlobalHotkeyManager {

    static let shared = GlobalHotkeyManager()

    private enum HotkeyID: UInt32 {
        case feed = 1
        case capture = 2
    }

    private var refs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x50535452  // 'PSTR'

    private init() {}

    func start() {
        NotificationCenter.default.addObserver(
            forName: IntegrationSettings.didChangeNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotkeyManager.shared.apply() }
            }
        }
        apply()
    }

    private func apply() {
        if IntegrationSettings.globalHotkeysEnabled() {
            register()
        } else {
            unregister()
        }
    }

    private func register() {
        guard refs.isEmpty else { return }
        installHandlerIfNeeded()
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        registerKey(code: UInt32(kVK_ANSI_F), id: .feed, modifiers: modifiers)
        registerKey(code: UInt32(kVK_ANSI_N), id: .capture, modifiers: modifiers)
    }

    private func registerKey(code: UInt32, id: HotkeyID, modifiers: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        let status = RegisterEventHotKey(code, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
        } else {
            FileHandle.standardError.write(Data("[Pasture] RegisterEventHotKey failed (\(status)) for id \(id.rawValue)\n".utf8))
        }
    }

    private func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // Cierre @convention(c): prohibido capturar. Referenciar statics es legal.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated { GlobalHotkeyManager.shared.dispatch(id: id) }
            }
            return noErr
        }, 1, &eventType, nil, &handlerRef)
    }

    private func dispatch(id: UInt32) {
        switch HotkeyID(rawValue: id) {
        case .feed: HeadlessActions.feedDefaultPreset()
        case .capture: HeadlessActions.captureClipboard()
        case nil: break
        }
    }
}
```

- [ ] **Step 2: AppDelegate — arranque.** En `applicationDidFinishLaunching`, tras el bloque del lock, añadir:

```swift
        // v1.9 — integración de sistema: política de Dock + hotkeys globales.
        MainActor.assumeIsolated {
            if IntegrationSettings.hideDockIcon() {
                NSApp.setActivationPolicy(.accessory)
            }
            GlobalHotkeyManager.shared.start()
        }
```

(más `import PastureKit` arriba). Si el compilador ya considera el método MainActor-aislado, quitar el wrapper `MainActor.assumeIsolated` y dejar las llamadas directas.

- [ ] **Step 3:** `swift build` → OK. Suite → verde.
- [ ] **Step 4:** `git commit -m "feat(app): Carbon global hotkeys (feed/capture) behind opt-in setting"`

---

### Task 7: URL scheme + menú Servicios (AppDelegate + ServicesProvider)

**Files:**
- Create: `Sources/Pasture/ServicesProvider.swift`
- Modify: `Sources/Pasture/AppDelegate.swift` (open urls, showMainWindow, servicesProvider)
- Modify: `Sources/Pasture/PastureApp.swift` (notificación `.performSearch`)
- Modify: `Sources/Pasture/ContentView.swift` (onReceive de `.performSearch`)

**Interfaces:**
- Consumes: `PastureURLCommand.parse`, `HeadlessActions.*`.
- Produces: `Notification.Name.performSearch` (object = query String); `AppDelegate.showMainWindow()`.

- [ ] **Step 1: ServicesProvider.swift**

```swift
import AppKit

/// v1.9 — Proveedor del menú Servicios: "New Pasture Capture" sobre texto
/// seleccionado en cualquier app. El nombre del método DEBE coincidir con
/// NSMessage en Info.plist (capturePasture). Los servicios llegan por el
/// main run loop → assumeIsolated es seguro.
final class ServicesProvider: NSObject {

    @objc func capturePasture(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text in selection" as NSString
            return
        }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { HeadlessActions.capture(text: text) }
        }
    }
}
```

- [ ] **Step 2: AppDelegate.** Añadir propiedad + registro + URL handler + refactor de reopen:

```swift
    private let servicesProvider = ServicesProvider()
```

En `applicationDidFinishLaunching` (dentro del mismo bloque v1.9 del Task 6):

```swift
            NSApp.servicesProvider = servicesProvider
            NSUpdateDynamicServices()
```

Nuevos métodos:

```swift
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            for url in urls {
                guard let command = PastureURLCommand.parse(url) else { continue }
                switch command {
                case .feed(let presetName):
                    if let presetName {
                        HeadlessActions.feed(named: presetName)
                    } else {
                        HeadlessActions.feedDefaultPreset()
                    }
                case .new(let title, let text):
                    HeadlessActions.capture(text: text ?? "", title: title)
                case .search(let query):
                    showMainWindow()
                    NotificationCenter.default.post(name: .performSearch, object: query)
                }
            }
        }
    }

    func showMainWindow() {
        for window in NSApplication.shared.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(self)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
```

Y `applicationShouldHandleReopen` pasa a delegar:

```swift
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }
```

(ajustar aislamiento igual que en Task 6 si el compilador protesta: los delegate callbacks de AppKit llegan en main).

- [ ] **Step 3: PastureApp.swift** — añadir a la extensión de `Notification.Name`:

```swift
    static let performSearch = Notification.Name("performSearch")
```

- [ ] **Step 4: ContentView.swift** — junto a los `.onReceive` existentes:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .performSearch)) { note in
            if let query = note.object as? String {
                fm.searchQuery = query
            }
        }
```

(si el binding de búsqueda del sidebar usa un `@State` local además de `fm.searchQuery`, sincronizarlo igual que hace el botón de limpiar en `SidebarView.swift:143`).

- [ ] **Step 5:** `swift build` → OK. Suite → verde.
- [ ] **Step 6:** `git commit -m "feat(app): pasture:// URL scheme dispatch and Services provider"`

---

### Task 8: Settings → pestaña General (login item, Dock, hotkeys, preset por defecto)

**Files:**
- Modify: `Sources/Pasture/SettingsView.swift` (nueva primera pestaña + `import ServiceManagement`)

**Interfaces:**
- Consumes: `SMAppService.mainApp`, `IntegrationSettings.*`, `SelectionPresetStore.load()`.

- [ ] **Step 1:** En el `TabView` de `SettingsView`, insertar ANTES de Export:

```swift
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
```

- [ ] **Step 2:** Nueva vista al final del fichero (seguir el estilo de las tabs existentes — si usan `Form`/spacing propio, imitarlo):

```swift
// MARK: - General (v1.9)

private struct GeneralSettingsTab: View {
    @State private var launchAtLogin = false
    @State private var hideDockIcon = IntegrationSettings.hideDockIcon()
    @State private var hotkeysEnabled = IntegrationSettings.globalHotkeysEnabled()
    @State private var presets: [SelectionPreset] = SelectionPresetStore.load()
    @State private var defaultPresetID: UUID? = IntegrationSettings.defaultPresetID()
    @State private var loginItemError: String?

    /// SMAppService exige app empaquetada (falla bajo `swift run`).
    private var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Pasture at login", isOn: $launchAtLogin)
                    .disabled(!isBundled)
                    .onChange(of: launchAtLogin) { _, newValue in updateLoginItem(newValue) }
                if !isBundled {
                    Text("Available when running the bundled app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Toggle("Hide Dock icon (menu bar only)", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, newValue in
                        IntegrationSettings.setHideDockIcon(newValue)
                        NSApp.setActivationPolicy(newValue ? .accessory : .regular)
                        if !newValue { NSApp.activate(ignoringOtherApps: true) }
                    }
            }
            Section("Global hotkeys") {
                Toggle("Enable global hotkeys", isOn: $hotkeysEnabled)
                    .onChange(of: hotkeysEnabled) { _, newValue in
                        IntegrationSettings.setGlobalHotkeysEnabled(newValue)
                    }
                LabeledContent("Feed default preset", value: "⌃⌥⌘F")
                LabeledContent("Capture clipboard", value: "⌃⌥⌘N")
            }
            Section("Headless feed") {
                Picker("Default preset", selection: $defaultPresetID) {
                    Text("None").tag(UUID?.none)
                    ForEach(presets) { preset in
                        Text(preset.name).tag(UUID?.some(preset.id))
                    }
                }
                .onChange(of: defaultPresetID) { _, newValue in
                    IntegrationSettings.setDefaultPresetID(newValue)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if isBundled { launchAtLogin = SMAppService.mainApp.status == .enabled }
            presets = SelectionPresetStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: SelectionPresetStore.didChangeNotification)) { _ in
            presets = SelectionPresetStore.load()
        }
    }

    private func updateLoginItem(_ enable: Bool) {
        guard isBundled else { return }
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Could not update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
```

- [ ] **Step 3:** `swift build` → OK. Suite → verde.
- [ ] **Step 4:** `git commit -m "feat(app): General settings tab — login item, dock policy, hotkeys, default preset"`

---

### Task 9: bundle.sh (Info.plist + codesign + 1.9.0), CHANGELOG, docs

**Files:**
- Modify: `scripts/bundle.sh`
- Modify: `CHANGELOG.md`
- Modify: `CLAUDE.md` (secciones Key files / Security / versión 1.9.0)

- [ ] **Step 1: bundle.sh** — `VERSION="1.9.0"`. En el heredoc del plist, antes de `</dict>`:

```xml
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>com.sevecod.pasture</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>pasture</string>
            </array>
        </dict>
    </array>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>New Pasture Capture</string>
            </dict>
            <key>NSMessage</key>
            <string>capturePasture</string>
            <key>NSPortName</key>
            <string>Pasture</string>
            <key>NSSendTypes</key>
            <array>
                <string>NSStringPboardType</string>
            </array>
        </dict>
    </array>
```

Tras generar el plist y antes del zip:

```bash
echo "Signing (ad-hoc)..."
codesign --force -s - "$APP_BUNDLE/Contents/MacOS/pasture-mcp"
codesign --force -s - "$APP_BUNDLE"
codesign --verify --deep "$APP_BUNDLE" && echo "Signature OK."
```

- [ ] **Step 2:** `./scripts/bundle.sh` → termina sin error, "Signature OK.".
- [ ] **Step 3:** CHANGELOG.md — entrada `## [1.9.0]` (Added: global hotkeys, pasture:// URL scheme, Services menu, launch at login, menu-bar-only mode, Captures quick-capture collection, ad-hoc codesign). CLAUDE.md — versión 1.9.0 + párrafos breves de los ficheros nuevos en Key files y la política de secretos del feed headless en Security invariants.
- [ ] **Step 4:** `git commit -m "feat(bundle): v1.9.0 — URL scheme, Services, ad-hoc codesign; changelog & docs"`

---

### Task 10: QA manual (bundle instalado) — checklist para verificación en vivo

No automatizable; ejecutar con la app de `dist/` copiada a `/Applications` (LaunchServices necesita el bundle instalado para URL scheme y Servicios; `pbs -update` o relogin si el servicio no aparece):

- [ ] `open "pasture://search?q=mcp"` → la ventana se abre con la búsqueda aplicada.
- [ ] `open "pasture://new?title=Prueba&text=hola"` → nota `Prueba.md` en `Captures/` + notificación.
- [ ] Settings → General: activar hotkeys; ⌃⌥⌘N con texto en el portapapeles → captura; ⌃⌥⌘F con preset default → notificación "Context copied" y contexto en portapapeles (y auto-clear a los 60 s).
- [ ] Feed headless de un preset que incluya una nota con un secreto de prueba → notificación de cancelación, portapapeles intacto.
- [ ] Servicios: seleccionar texto en otra app → menú de la app → Services → "New Pasture Capture".
- [ ] Toggle "Hide Dock icon" → el icono desaparece/reaparece sin relanzar.
- [ ] Toggle "Launch at login" → aparece en Ajustes del Sistema → General → Ítems de inicio.
- [ ] `codesign --verify --deep /Applications/Pasture.app` → OK.

## Dudas y asunciones (registradas al planificar)

- Combos fijos ⌃⌥⌘F / ⌃⌥⌘N en v1 (sin grabador de atajos — sería UI considerable; futuro).
- Hotkeys opt-in (default off) por cautela; el usuario los activa en Settings → General.
- Colección de capturas: `Captures/` (no "Inbox") para no colisionar mentalmente con `.inbox/` del Memory Inbox v1.8.
- Secretos en feed headless: bloquean (no hay diálogo posible; equivale al default Cancel de la GUI).
- Firma ad-hoc (sin cuenta Developer ID confirmada); la notarización queda como pendiente conocido.
