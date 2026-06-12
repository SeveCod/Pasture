import SwiftUI
import AppKit
import PastureKit

struct SettingsView: View {
    var body: some View {
        TabView {
            ExportSettingsTab()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "brain") }
        }
        .frame(minWidth: 560, minHeight: 280)
    }
}

// MARK: - Export Tab

private struct ExportSettingsTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var destinations: [ExportDestination] = ExportSettings.loadDestinations()
    @State private var defaultID: UUID? = ExportSettings.defaultDestinationID()
    @State private var fileFormat: ExportFileFormat = ExportSettings.fileFormat()
    @State private var feedFormat: FeedFormat = FeedFormatSettings.feedFormat()

    var body: some View {
        Form {
            Section {
                Picker("Feed format", selection: $feedFormat) {
                    ForEach(FeedFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .onChange(of: feedFormat) { _, newValue in
                    FeedFormatSettings.setFeedFormat(newValue)
                    NotificationCenter.default.post(name: FeedFormatSettings.didChangeNotification, object: nil)
                }
            } header: {
                Text("Feed Output Format")
            } footer: {
                Text("Payload format for clipboard, export, and Ask context. XML is robust for model parsing; Markdown and Plain text suit chats and READMEs. Plain text is best-effort for automatic parsing.")
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }

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

            Section {
                Picker("File format", selection: $fileFormat) {
                    ForEach(ExportFileFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .onChange(of: fileFormat) { _, newValue in
                    ExportSettings.setFileFormat(newValue)
                }
            } footer: {
                Text("Extension suggested when exporting feed context to disk.")
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }
        }
        .formStyle(.grouped)
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
            .accessibilityLabel(defaultID == dest.wrappedValue.id ? "Remove as default destination" : "Set as default destination")
            .accessibilityValue(defaultID == dest.wrappedValue.id ? "Default" : "Not default")

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
                    .foregroundStyle(Color.pastureError(colorScheme))
                    .help("Directory not writable")
                    .accessibilityLabel("Warning: Directory not writable")
            }

            Button("Choose\u{2026}") { pickPath(for: dest.wrappedValue.id) }
                .controlSize(.small)

            Button(role: .destructive) { remove(dest.wrappedValue) } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.pastureError(colorScheme))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete destination")
            .accessibilityHint("Removes this export destination")
        }
    }

    private func pickPath(for id: UUID) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "CONTEXT.\(fileFormat.fileExtension)"
        panel.allowedContentTypes = fileFormat.allowedContentTypes
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

// MARK: - AI Tab

private struct AISettingsTab: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedProvider: AIProviderKind = AISettings.loadProvider()
    @State private var selectedModelID: String = AISettings.loadModelID()
    @State private var apiKeyInput = ""
    @State private var keySaved = false
    @State private var hasKeychainKey: Bool = AISettings.loadAPIKey(for: AISettings.loadProvider()) != nil
    @State private var testResult: String?
    @State private var isTesting = false

    private var availableModels: [AIModel] {
        AIModel.models(for: selectedProvider)
    }

    var body: some View {
        Form {
            Section {
                Picker("Provider", selection: $selectedProvider) {
                    Text("Anthropic").tag(AIProviderKind.anthropic)
                    Text("OpenRouter").tag(AIProviderKind.openRouter)
                }
                .onChange(of: selectedProvider) { _, newValue in
                    AISettings.saveProvider(newValue, to: .standard)
                    let models = AIModel.models(for: newValue)
                    if !models.contains(where: { $0.id == selectedModelID }) {
                        selectedModelID = models.first?.id ?? AIModel.defaultModelID
                        AISettings.saveModelID(selectedModelID, to: .standard)
                    }
                    apiKeyInput = ""
                    keySaved = false
                    hasKeychainKey = AISettings.loadAPIKey(for: newValue) != nil
                    postChange()
                }

                HStack {
                    SecureField("API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    if keySaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.pastureSuccess)
                            .accessibilityLabel("API key saved successfully")
                    }

                    Button("Save") {
                        guard !apiKeyInput.isEmpty else { return }
                        do {
                            try AISettings.saveAPIKey(apiKeyInput, for: selectedProvider)
                            keySaved = true
                            hasKeychainKey = true
                        } catch {
                            keySaved = false
                        }
                        postChange()
                    }
                    .disabled(apiKeyInput.isEmpty)
                }

                if hasKeychainKey && apiKeyInput.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.pastureSuccess)
                            .accessibilityHidden(true)
                        Text("Key saved in Keychain")
                            .font(.caption)
                            .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                        Spacer()
                        Button("Remove", role: .destructive) {
                            AISettings.deleteAPIKey(for: selectedProvider)
                            keySaved = false
                            hasKeychainKey = false
                            postChange()
                        }
                        .font(.caption)
                    }
                }
            } header: {
                Text("API Configuration")
            }

            Section {
                Picker("Model", selection: $selectedModelID) {
                    ForEach(availableModels) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                .onChange(of: selectedModelID) { _, newValue in
                    AISettings.saveModelID(newValue, to: .standard)
                    postChange()
                }

                if let model = AIModel.model(byID: selectedModelID) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Context: \(TokenEstimator.formatted(model.contextWindow)) tokens")
                                .font(.caption)
                            Text("Input: $\(String(format: "%.2f", model.inputCostPer1M))/1M tokens")
                                .font(.caption)
                            Text("Output: $\(String(format: "%.2f", model.outputCostPer1M))/1M tokens")
                                .font(.caption)
                        }
                        .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                        Spacer()
                    }
                }
            } header: {
                Text("Model")
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isTesting ? "Testing\u{2026}" : "Test Connection")
                    }
                }
                .disabled(!hasKeychainKey || isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("\u{2714}") ? Color.pastureSuccess : Color.pastureError(colorScheme))
                }
            }
        }
        .formStyle(.grouped)
    }

    private func testConnection() {
        guard let apiKey = AISettings.loadAPIKey(for: selectedProvider) else { return }
        isTesting = true
        testResult = nil

        let model = AIModel.model(byID: selectedModelID) ?? AIModel.defaultModels[0]
        // Shared client: the connection test exercises the same session config as real asks
        let client = AIClient.shared

        Task {
            var gotResponse = false
            do {
                let stream = await client.ask(question: "Reply with: OK", context: "", model: model, apiKey: apiKey)
                for try await _ in stream {
                    gotResponse = true
                    break
                }
                testResult = gotResponse ? "\u{2714} Connection successful" : "\u{2714} Connected (empty response)"
            } catch {
                testResult = "\u{2718} \(error.localizedDescription)"
            }
            isTesting = false
        }
    }

    private func postChange() {
        NotificationCenter.default.post(name: AISettings.didChangeNotification, object: nil)
    }
}
