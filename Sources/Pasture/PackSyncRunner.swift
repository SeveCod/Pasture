import Foundation
import PastureKit

/// Context Compiler (v1.6) — punto único para sincronizar packs desde la barra de
/// menús, el comando de menú y el auto-resync del watcher. Reutiliza el motor
/// probado (`PackSyncEngine`) con **defaults seguros**: nunca sobrescribe un
/// destino editado a mano ni escribe secretos salvo `force` explícito.
enum PackSyncRunner {

    /// Sincroniza packs y devuelve un resumen legible para un toast.
    /// - `force`: escala a sobrescribir conflictos e incluir secretos (solo desde
    ///   una confirmación explícita del usuario).
    /// - `autoResyncOnly`: limita a los packs con `autoResync` activado (watcher).
    ///   Devuelve "" si no hay ninguno, para no molestar con un toast vacío.
    @MainActor
    static func syncAll(force: Bool = false, autoResyncOnly: Bool = false) async -> String {
        let all = PackStore.load()
        let selected = autoResyncOnly ? all.filter(\.autoResync) : all
        guard !selected.isEmpty else { return autoResyncOnly ? "" : "No packs to sync." }

        let presets = SelectionPresetStore.load()
        let vault = MDFileManager.pastureDir
        let backups = PackWriter.defaultBackupsRoot()

        let summaryText = await Task.detached { () -> String in
            var outcomes: [PackWriter.WriteOutcome] = []
            var skipped = 0
            for pack in selected {
                let preset = presets.first { $0.id == pack.presetID }
                let context = PackSyncEngine.Context(
                    vaultRoot: vault, backupsRoot: backups,
                    overwriteConflicts: force, secretsAllowed: force)
                switch PackSyncEngine.sync(pack: pack, preset: preset, context: context) {
                case .success(let results):
                    outcomes.append(contentsOf: results.map(\.outcome))
                case .failure:
                    skipped += 1
                }
            }
            let summary = PackWriter.summarize(outcomes)
            var message = summary.description
            if skipped > 0 { message += ", \(skipped) skipped" }
            return message
        }.value

        return "Packs — \(summaryText)"
    }
}
