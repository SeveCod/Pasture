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
            MCPSettingsTab()
                .tabItem { Label("MCP", systemImage: "powerplug") }
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
                            .foregroundStyle(Color.pastureSuccess(colorScheme))
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
                            .foregroundStyle(Color.pastureSuccess(colorScheme))
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
                        .foregroundStyle(result.hasPrefix("\u{2714}") ? Color.pastureSuccess(colorScheme) : Color.pastureError(colorScheme))
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

// MARK: - MCP Tab (HU-1, HU-2, HU-3, SEC-M9)

private struct MCPSettingsTab: View {
    /// Número máximo de líneas de secretos visibles antes de resumir (m-3).
    private static let maxVisibleSecretLines = 5

    @Environment(\.colorScheme) private var colorScheme
    @State private var feedback: String?
    @State private var secretStats: MCPVaultStats.SecretStats?
    @State private var isScanning = false

    /// Ruta real del binario embebido. NUNCA hardcodeada: se deriva de la
    /// ubicación del .app en ejecución, así mover el .app mueve la ruta (HU-2).
    private var binaryPath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/pasture-mcp")
            .path
    }

    /// M-4: ¿existe el binario embebido? Sin él, registrar no tiene sentido.
    private var binaryExists: Bool {
        FileManager.default.fileExists(atPath: binaryPath)
    }

    /// Formato del feed actual del usuario, inyectado en el snippet (ADR-007).
    private var feedFormat: FeedFormat { FeedFormatSettings.feedFormat() }

    var body: some View {
        Form {
            // 1. Descripción de la capacidad (HU-1).
            descriptionSection

            // 2. Comprobación de secretos ANTES de registrar (SEC-M9): el
            //    consentimiento informado se basa en escanear antes (orden por Alfred).
            secretCheckSection

            // 3. Registro del server (HU-2/3).
            registerSection
        }
        .formStyle(.grouped)
    }

    // MARK: — Secciones

    private var descriptionSection: some View {
        Section {
            Text("Pasture can act as a Model Context Protocol server, exposing ~/.pasture/ as read-only to MCP clients like Claude Code and Claude Desktop. Register it once with the configuration below; the client then reads your curated context without copy-paste.")
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text("Model Context Protocol")
        }
    }

    private var secretCheckSection: some View {
        Section {
            Button {
                scanForSecrets()
            } label: {
                HStack {
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isScanning ? "Scanning\u{2026}" : "Scan vault for secrets")
                }
            }
            .disabled(isScanning)

            if let stats = secretStats {
                secretStatsView(stats)
            }
        } header: {
            Text("Vault secret check")
        } footer: {
            Text("Before registering, check whether your vault contains credential patterns. The MCP channel delivers file contents unchanged — ~/.pasture/ is meant for shareable context, not secrets.")
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
        }
    }

    @ViewBuilder
    private func secretStatsView(_ stats: MCPVaultStats.SecretStats) -> some View {
        if stats.fileCount == 0 {
            Label("No secret patterns detected in the vault.", systemImage: "checkmark.shield")
                .foregroundStyle(Color.pastureSuccess(colorScheme))
        } else {
            Label("\(stats.fileCount) file(s) contain possible secrets:", systemImage: "exclamationmark.shield")
                .foregroundStyle(Color.pastureError(colorScheme))
            // m-3: limita a 5 líneas visibles + resumen del resto.
            ForEach(stats.summaryLines.prefix(Self.maxVisibleSecretLines), id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            }
            if stats.summaryLines.count > Self.maxVisibleSecretLines {
                Text("\u{2026}and \(stats.summaryLines.count - Self.maxVisibleSecretLines) more files")
                    .font(.caption)
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
            }
        }
    }

    private var registerSection: some View {
        Section {
            // M-3: Feed format activo (solo lectura).
            LabeledContent("Active Feed format", value: feedFormat.displayName)

            // Claude Code.
            Button {
                copy(MCPConfigGenerator.claudeCodeCommand(binaryPath: binaryPath, feedFormat: feedFormat))
            } label: {
                Label("Copy configuration (Claude Code)", systemImage: "terminal")
            }
            .disabled(!binaryExists)
            .accessibilityHint("Copies a 'claude mcp add' command for your terminal")   // m-1
            Text("Paste in your terminal and press Enter.")                              // M-1
                .font(.caption)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))

            // Claude Desktop.
            Button {
                copy(MCPConfigGenerator.claudeDesktopJSON(binaryPath: binaryPath, feedFormat: feedFormat))
            } label: {
                Label("Copy configuration (Claude Desktop)", systemImage: "doc.on.clipboard")
            }
            .disabled(!binaryExists)
            .accessibilityHint("Copies a JSON block for claude_desktop_config.json")    // m-1
            Text("Paste inside the mcpServers key in claude_desktop_config.json.")       // M-1
                .font(.caption)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))

            // M-4: binario ausente.
            if !binaryExists {
                Label("Server binary not found. Install Pasture.app to enable MCP registration.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Color.pastureError(colorScheme))
            }

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(Color.pastureSuccess(colorScheme))
                    .transition(.opacity)
            }
        } header: {
            Text("Register the server")
        } footer: {
            // m-4: consentimiento en presente.
            Text("This server gives your MCP client read-only access to ~/.pasture/. File contents may be sent to the client's AI provider.")
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
        }
    }

    // MARK: — Acciones

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation { feedback = "Copied to clipboard." }
        // M-5: auto-limpia el feedback tras ~2.5 s con animación.
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation { feedback = nil }
            }
        }
    }

    /// SEC-M9: escaneo bajo demanda (no en cada keystroke). Off the main actor.
    private func scanForSecrets() {
        isScanning = true
        let vault = MDFileManager.pastureDir
        Task {
            let stats = await Task.detached { MCPVaultStats.secretStats(vaultRoot: vault) }.value
            await MainActor.run {
                secretStats = stats
                isScanning = false
            }
        }
    }
}
