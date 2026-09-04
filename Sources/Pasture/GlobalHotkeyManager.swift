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

    /// Se emite tras cada intento de registro/desregistro para que Settings
    /// pueda releer `registrationError` (patrón notificación, no ObservableObject:
    /// el manager es un singleton MainActor sin dueño en la jerarquía de vistas).
    static let registrationDidChangeNotification = Notification.Name("PastureHotkeyRegistrationDidChange")

    /// Mensaje legible del último fallo de registro, o nil si los combos están
    /// vivos (o los hotkeys están desactivados). Sin esto el fallo solo iba a
    /// stderr y el toggle aparentaba estar activo con los atajos muertos (UX-9).
    private(set) var registrationError: String?

    private enum HotkeyID: UInt32 {
        case feed = 1
        case capture = 2

        /// Combo visible para el mensaje de error.
        var combo: String {
            switch self {
            case .feed: return "\u{2303}\u{2325}\u{2318}F"
            case .capture: return "\u{2303}\u{2325}\u{2318}N"
            }
        }
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
        var failed: [HotkeyID] = []
        if !registerKey(code: UInt32(kVK_ANSI_F), id: .feed, modifiers: modifiers) { failed.append(.feed) }
        if !registerKey(code: UInt32(kVK_ANSI_N), id: .capture, modifiers: modifiers) { failed.append(.capture) }
        setRegistrationError(message(forFailed: failed))
    }

    /// Mensaje que nombra el combo (o los dos) que no se pudo registrar.
    private func message(forFailed failed: [HotkeyID]) -> String? {
        switch failed.count {
        case 0: return nil
        case 1: return "\(failed[0].combo) is already in use by another app."
        default:
            let combos = failed.map(\.combo).joined(separator: " and ")
            return "\(combos) are already in use by another app."
        }
    }

    @discardableResult
    private func registerKey(code: UInt32, id: HotkeyID, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id.rawValue)
        let status = RegisterEventHotKey(code, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            return true
        }
        // stderr sigue siendo la única señal bajo `swift run` (sin Settings).
        FileHandle.standardError.write(
            Data("[Pasture] RegisterEventHotKey failed (\(status)) for id \(id.rawValue)\n".utf8)
        )
        return false
    }

    private func unregister() {
        for ref in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        setRegistrationError(nil)
    }

    private func setRegistrationError(_ message: String?) {
        registrationError = message
        NotificationCenter.default.post(name: Self.registrationDidChangeNotification, object: nil)
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
