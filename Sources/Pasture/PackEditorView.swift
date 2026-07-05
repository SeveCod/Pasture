import SwiftUI
import AppKit
import PastureKit

/// Context Compiler (v1.6) — editor modal de un pack: nombre, preset, variables,
/// destinos (validados fuera del vault) y auto-resync. No escribe nada: solo edita
/// la configuración del pack, que se persiste al pulsar Save.
struct PackEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CompilePack
    /// Variables como filas ordenadas (el dict del modelo no preserva orden).
    @State private var variableRows: [VariableRow]
    @State private var targetError: String?
    private let presets: [SelectionPreset]
    private let onSave: (CompilePack) -> Void

    private var vaultRoot: URL { MDFileManager.pastureDir }

    init(pack: CompilePack, presets: [SelectionPreset], onSave: @escaping (CompilePack) -> Void) {
        _draft = State(initialValue: pack)
        _variableRows = State(initialValue: pack.variables.map { VariableRow(key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key })
        self.presets = presets
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Pack") {
                    TextField("Name", text: $draft.name)
                    Picker("Preset", selection: $draft.presetID) {
                        ForEach(presets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    Toggle("Auto-resync when source files change", isOn: $draft.autoResync)
                }

                Section {
                    ForEach($variableRows) { $row in
                        HStack(spacing: 8) {
                            TextField("NAME", text: $row.key)
                                .frame(width: 140)
                                .font(.system(.body, design: .monospaced))
                            TextField("value", text: $row.value)
                                .frame(maxWidth: .infinity)
                            Button(role: .destructive) {
                                variableRows.removeAll { $0.id == row.id }
                            } label: { Image(systemName: "minus.circle").foregroundStyle(Color.pastureError(colorScheme)) }
                                .buttonStyle(.plain)
                        }
                    }
                    Button { variableRows.append(VariableRow(key: "", value: "")) } label: {
                        Label("Add Variable", systemImage: "plus")
                    }
                } header: {
                    Text("Variables")
                } footer: {
                    Text("{{NAME}} tokens in the selected files are replaced by these values. Never store secrets here.")
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                }

                Section {
                    if draft.targets.isEmpty {
                        Text("No targets. Add a CLAUDE.md or AGENTS.md in one of your repos.")
                            .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 6)
                    } else {
                        ForEach($draft.targets) { $target in
                            targetRow($target)
                        }
                    }
                    Button { addTarget() } label: { Label("Add Target", systemImage: "plus") }
                    if let targetError {
                        Label(targetError, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Color.pastureError(colorScheme))
                    }
                } header: {
                    Text("Targets")
                } footer: {
                    Text("Each target is a file path in one of your repos, outside ~/.pasture/.")
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(CompilePack.sanitizedName(draft.name).isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private func targetRow(_ target: Binding<CompileTarget>) -> some View {
        HStack(spacing: 8) {
            Picker("", selection: target.kind) {
                ForEach(TargetKind.allCases, id: \.self) { kind in
                    Text(kind.defaultFileName).tag(kind)
                }
            }
            .labelsHidden()
            .frame(width: 120)

            Text(target.wrappedValue.absolutePath.isEmpty ? "No path" : target.wrappedValue.absolutePath)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Choose\u{2026}") { pickPath(for: target.wrappedValue.id) }
                .controlSize(.small)
            Button(role: .destructive) {
                draft.targets.removeAll { $0.id == target.wrappedValue.id }
            } label: { Image(systemName: "trash").foregroundStyle(Color.pastureError(colorScheme)) }
                .buttonStyle(.plain)
        }
    }

    // MARK: — Acciones

    private func addTarget() {
        draft.targets.append(CompileTarget(kind: .claudeMd, absolutePath: ""))
    }

    private func pickPath(for id: UUID) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CLAUDE.md"
        panel.message = "Choose where to write the compiled context (outside ~/.pasture/)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Validación inmediata: el destino no puede caer dentro del vault.
        switch TargetValidator.validate(targetPath: url.path, vaultRoot: vaultRoot) {
        case .failure:
            targetError = "That path is inside ~/.pasture/ — the vault can't be a target."
        case .success:
            targetError = nil
            if let idx = draft.targets.firstIndex(where: { $0.id == id }) {
                draft.targets[idx].absolutePath = url.path
            }
        }
    }

    private func save() {
        draft.name = CompilePack.sanitizedName(draft.name)
        // Reconstruir el dict de variables desde las filas (descarta claves vacías).
        var vars: [String: String] = [:]
        for row in variableRows {
            let key = row.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            vars[key] = row.value
        }
        draft.variables = vars
        // Descartar targets sin ruta.
        draft.targets.removeAll { $0.absolutePath.isEmpty }
        onSave(draft)
        dismiss()
    }
}

/// Fila editable de variable (identificable para el ForEach).
private struct VariableRow: Identifiable {
    let id = UUID()
    var key: String
    var value: String
}
