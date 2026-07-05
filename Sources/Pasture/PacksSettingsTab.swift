import SwiftUI
import AppKit
import PastureKit

/// Context Compiler (v1.6) — pestaña de gestión de packs de compilación.
///
/// Un pack compila una selección del vault (preset) + variables a uno o más
/// `CLAUDE.md`/`AGENTS.md` en repos del usuario. La escritura es NO destructiva:
/// por defecto nunca sobrescribe un destino editado a mano ni escribe secretos;
/// escalar a "Force sync" exige confirmación explícita (default Cancel).
struct PacksSettingsTab: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var packs: [CompilePack] = PackStore.load()
    @State private var presets: [SelectionPreset] = SelectionPresetStore.load()
    @State private var editingPack: CompilePack?
    /// Resultado del último sync por pack id (para mostrar el resumen en su fila).
    @State private var lastResults: [UUID: SyncOutcome] = [:]
    /// Escalada pendiente de confirmación (force sync).
    @State private var forcePack: CompilePack?

    private var vaultRoot: URL { MDFileManager.pastureDir }

    var body: some View {
        Form {
            descriptionSection
            packsSection
        }
        .formStyle(.grouped)
        .sheet(item: $editingPack) { pack in
            PackEditorView(pack: pack, presets: presets) { saved in
                PackStore.upsert(saved)
            }
        }
        .alert("Force sync?", isPresented: forceAlertBinding, presenting: forcePack) { pack in
            Button("Cancel", role: .cancel) {}
            Button("Overwrite / include secrets", role: .destructive) {
                sync(pack, force: true)
            }
        } message: { _ in
            Text("This overwrites targets edited outside Pasture (a backup is kept) and writes files even if they contain possible secrets. This cannot be undone except from the backups.")
        }
        .onReceive(NotificationCenter.default.publisher(for: PackStore.didChangeNotification)) { _ in
            packs = PackStore.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: SelectionPresetStore.didChangeNotification)) { _ in
            presets = SelectionPresetStore.load()
        }
    }

    // MARK: — Secciones

    private var descriptionSection: some View {
        Section {
            Text("Compile a vault selection into your repos' CLAUDE.md / AGENTS.md. Fix a rule once in the vault and sync it everywhere. Pasture never overwrites a file you edited by hand without confirmation, and always keeps a backup.")
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Context Compiler")
        }
    }

    private var packsSection: some View {
        Section {
            if packs.isEmpty {
                Text(presets.isEmpty
                     ? "Create a selection preset first, then define a pack that compiles it to your repos."
                     : "No packs yet. Add one to compile a preset to your repos.")
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(packs) { pack in
                    packRow(pack)
                }
            }

            Button {
                addPack()
            } label: {
                Label("Add Pack", systemImage: "plus")
            }
            .disabled(presets.isEmpty)
        } header: {
            Text("Compile Packs")
        } footer: {
            Text("Targets must live outside ~/.pasture/. Variables are stored in plain text — never put secrets in them.")
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
        }
    }

    @ViewBuilder
    private func packRow(_ pack: CompilePack) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name).fontWeight(.medium)
                    Text("\(presetName(pack.presetID)) · \(pack.targets.count) target(s)\(pack.autoResync ? " · auto" : "")")
                        .font(.caption)
                        .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                }
                Spacer()
                Button("Sync") { sync(pack, force: false) }
                    .controlSize(.small)
                    .disabled(pack.targets.isEmpty)
                Button("Edit") { editingPack = pack }
                    .controlSize(.small)
                Button(role: .destructive) {
                    PackStore.delete(id: pack.id)
                    lastResults[pack.id] = nil
                } label: {
                    Image(systemName: "trash").foregroundStyle(Color.pastureError(colorScheme))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete pack")
            }

            if let result = lastResults[pack.id] {
                resultRow(pack, result)
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ pack: CompilePack, _ result: SyncOutcome) -> some View {
        HStack(spacing: 6) {
            Image(systemName: result.isClean ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundStyle(result.isClean ? Color.pastureSuccess(colorScheme) : Color.pastureAmber)
            Text(result.message)
                .font(.caption)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            Spacer()
            if result.canForce {
                Button("Force sync\u{2026}") { forcePack = pack }
                    .controlSize(.small)
            }
        }
    }

    // MARK: — Acciones

    private func addPack() {
        guard let firstPreset = presets.first else { return }
        let pack = CompilePack(name: "New Pack", presetID: firstPreset.id)
        editingPack = pack
    }

    private func presetName(_ id: UUID) -> String {
        presets.first { $0.id == id }?.name ?? "(preset missing)"
    }

    private func sync(_ pack: CompilePack, force: Bool) {
        let preset = presets.first { $0.id == pack.presetID }
        let context = PackSyncEngine.Context(
            vaultRoot: vaultRoot,
            backupsRoot: PackWriter.defaultBackupsRoot(),
            overwriteConflicts: force,
            secretsAllowed: force)
        let packID = pack.id

        Task {
            let outcome = await Task.detached { () -> SyncOutcome in
                switch PackSyncEngine.sync(pack: pack, preset: preset, context: context) {
                case .failure(.presetMissing):
                    return SyncOutcome(message: "Preset missing — edit the pack.", isClean: false, canForce: false)
                case .failure(.missingSourceFiles(let missing)):
                    let msg = SelectionPreset.missingFilesMessage(missingPaths: missing) ?? "source files missing"
                    return SyncOutcome(message: "Not compiled: \(msg).", isClean: false, canForce: false)
                case .success(let results):
                    let summary = PackWriter.summarize(results.map(\.outcome))
                    let needsForce = summary.conflicts > 0 || results.contains {
                        if case .secretsBlocked = $0.outcome { return true } else { return false }
                    }
                    return SyncOutcome(message: summary.description, isClean: !needsForce && summary.failed == 0, canForce: needsForce)
                }
            }.value
            await MainActor.run {
                lastResults[packID] = outcome
                packs = PackStore.load()
            }
        }
    }

    private var forceAlertBinding: Binding<Bool> {
        Binding(get: { forcePack != nil }, set: { if !$0 { forcePack = nil } })
    }
}

/// Resultado de un sync mostrado en la fila del pack.
private struct SyncOutcome {
    let message: String
    let isClean: Bool
    let canForce: Bool
}
