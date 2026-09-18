import Testing
import Foundation
@testable import PastureKit

/// Guardia del hotfix `3fb633e` (audit 360: se desplegó sin ninguna).
///
/// Con la privacidad de portapapeles de macOS 15.4+ una lectura programática
/// puede devolver `nil` sin error; el código anterior hacía `?? ""` y creaba una
/// nota en blanco en silencio.
@Suite("ClipboardPaste — nunca una nota en blanco")
struct ClipboardPasteTests {

    /// El invariante se afirma en absoluto ("nunca"), así que se barre la región
    /// entera de entradas sin contenido en vez de elegir un vector.
    @Test("Ninguna entrada sin texto llega a crear una nota",
          arguments: [nil, ""] as [String?])
    func neverProceedsWithoutText(entrada: String?) {
        for denegado in [true, false] {
            let outcome = ClipboardPaste.outcome(clipboardText: entrada, accessDenied: denegado)
            guard case .refuse = outcome else {
                Issue.record("entrada \(String(describing: entrada)) (denegado=\(denegado)) produjo \(outcome), que crearía una nota en blanco")
                return
            }
        }
    }

    @Test("Con texto real, se procede con el contenido intacto")
    func proceedsWithText() {
        let texto = "# Nota\n\ncontenido real"
        #expect(ClipboardPaste.outcome(clipboardText: texto, accessDenied: false)
                == .proceed(text: texto))
        // Un texto que sí existe se pega aunque el sistema declare acceso
        // restringido: si llegó contenido, denegarlo sería perder trabajo.
        #expect(ClipboardPaste.outcome(clipboardText: texto, accessDenied: true)
                == .proceed(text: texto))
    }

    @Test("El bloqueo del sistema da el mensaje accionable, no el genérico")
    func blockedGivesActionableMessage() {
        #expect(ClipboardPaste.outcome(clipboardText: nil, accessDenied: true)
                == .refuse(message: ClipboardPaste.blockedMessage))
        #expect(ClipboardPaste.outcome(clipboardText: nil, accessDenied: false)
                == .refuse(message: ClipboardPaste.noTextMessage))
        // El mensaje de bloqueo sólo sirve si dice dónde ir a arreglarlo.
        #expect(ClipboardPaste.blockedMessage.contains("System Settings"))
    }
}
