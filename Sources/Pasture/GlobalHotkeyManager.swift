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
            FileHandle.standardError.write(
                Data("[Pasture] RegisterEventHotKey failed (\(status)) for id \(id.rawValue)\n".utf8)
            )
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
