import SwiftUI
import AppKit
import PastureKit

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var destinations: [ExportDestination] = ExportSettings.loadDestinations()
    @State private var defaultID: UUID? = ExportSettings.defaultDestinationID()

    var body: some View {
        Form {
            Section {
                if destinations.isEmpty {
                    Text("No export destinations configured.\nAdd one to enable Feed-to-file.")
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach($destinations) { $dest in
                        destinationRow(dest: $dest)
                    }
                }

                Button {
                    let new = ExportDestination(name: "Project", path: "")
                    destinations.append(new)
                    persist()
                    pickPath(for: new.id)
                } label: {
                    Label("Add Destination", systemImage: "plus")
                }
            } header: {
                Text("Export Destinations")
            } footer: {
                Text("Feed writes context directly to a file instead of clipboard. Star \u{2605} marks the default destination for one-click export.")
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 560, minHeight: 200)
    }

    @ViewBuilder
    private func destinationRow(dest: Binding<ExportDestination>) -> some View {
        HStack(spacing: 8) {
            Button {
                defaultID = defaultID == dest.wrappedValue.id ? nil : dest.wrappedValue.id
                ExportSettings.setDefaultDestinationID(defaultID)
                persist()
            } label: {
                Image(systemName: defaultID == dest.wrappedValue.id ? "star.fill" : "star")
                    .foregroundStyle(defaultID == dest.wrappedValue.id ? Color.pastureAmber : Color.pastureTextTertiary(colorScheme))
            }
            .buttonStyle(.plain)
            .help(defaultID == dest.wrappedValue.id ? "Default destination" : "Set as default")

            TextField("Name", text: dest.name)
                .frame(width: 120)
                .onChange(of: dest.wrappedValue.name) { _, _ in persist() }

            Text(dest.wrappedValue.path.isEmpty ? "No path selected" : dest.wrappedValue.path)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !dest.wrappedValue.path.isEmpty && !dest.wrappedValue.isWritable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.pastureError)
                    .help("Directory not writable")
            }

            Button("Choose\u{2026}") { pickPath(for: dest.wrappedValue.id) }
                .controlSize(.small)

            Button(role: .destructive) { remove(dest.wrappedValue) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.pastureError)
            }
            .buttonStyle(.plain)
        }
    }

    private func pickPath(for id: UUID) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CONTEXT.md"
        panel.allowedContentTypes = [.plainText]
        panel.message = "Choose where to export feed context"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let idx = destinations.firstIndex(where: { $0.id == id }) {
            destinations[idx].path = url.path
            persist()
        }
    }

    private func remove(_ dest: ExportDestination) {
        destinations.removeAll { $0.id == dest.id }
        if defaultID == dest.id {
            defaultID = nil
            ExportSettings.setDefaultDestinationID(nil)
        }
        persist()
    }

    private func persist() {
        ExportSettings.saveDestinations(destinations)
        NotificationCenter.default.post(name: ExportSettings.didChangeNotification, object: nil)
    }
}
