import SwiftUI
import PastureKit

struct SidebarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var fm: MDFileManager
    @Binding var selectedFiles: Set<MDFile>
    @Binding var activeFile: MDFile?
    @Binding var searchText: String
    @Binding var sortOrder: FileSortOrder
    @Binding var filesPendingDeletion: [MDFile]
    @Binding var showDeleteConfirmation: Bool
    var onDrop: ([NSItemProvider]) -> Bool
    var onOpenInEditor: (MDFile) -> Void
    @State private var collectionPendingDeletion: String?
    @State private var filePendingRename: MDFile?
    @State private var collectionPendingRename: String?
    @State private var showReviewQueue = false
    @State private var showInbox = false
    /// Colecciones desplegadas, por `CollectionNode.id`. Se siembra del store al
    /// aparecer y se reescribe en cada plegado (salvo durante una búsqueda).
    @State private var expandedCollections: Set<String> = CollectionExpansionStore.load()

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Color.pastureDivider(colorScheme).frame(height: 1)
            statusStrip
            fileList
            Color.pastureDivider(colorScheme).frame(height: 1)
            selectionSummary
        }
        .sheet(isPresented: $showReviewQueue) {
            ReviewQueueSheet(fm: fm)
        }
        .sheet(isPresented: $showInbox) {
            ReviewInboxSheet(fm: fm)
        }
        .background(Color.pastureSidebar(colorScheme))
        .alert("Delete collection?",
               isPresented: Binding(
                   get: { collectionPendingDeletion != nil },
                   set: { if !$0 { collectionPendingDeletion = nil } }
               ),
               presenting: collectionPendingDeletion) { name in
            Button("Delete", role: .destructive) { fm.deleteCollection(name) }
            Button("Cancel", role: .cancel) { collectionPendingDeletion = nil }
        } message: { name in
            Text("The empty collection '\(name)' will be moved to the Trash.")
        }
        .sheet(item: $filePendingRename) { file in
            NameInputSheet(title: "Rename '\(file.name)'", actionLabel: "Rename", initialName: file.name) { newName in
                renameFile(file, to: newName)
            }
        }
        .sheet(isPresented: Binding(
            get: { collectionPendingRename != nil },
            set: { if !$0 { collectionPendingRename = nil } }
        )) {
            if let name = collectionPendingRename {
                NameInputSheet(title: "Rename collection '\(name)'", actionLabel: "Rename", initialName: name) { newName in
                    fm.renameCollection(name, to: newName)
                }
            }
        }
    }

    /// Franja de avisos: propuestas pendientes (v1.8) y notas caducadas (v1.7).
    /// Una sola fila con hasta dos avisos, en vez de dos filas apiladas.
    @ViewBuilder
    private var statusStrip: some View {
        let proposals = fm.pendingProposals.count
        let stale = fm.staleFiles().count
        if proposals > 0 || stale > 0 {
            HStack(spacing: 12) {
                if proposals > 0 {
                    Button { showInbox = true } label: {
                        statusChip(
                            icon: "tray.and.arrow.down",
                            tint: Color.pastureAccent(colorScheme),
                            text: "Inbox (\(proposals))"
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Agent proposals waiting for your review")
                    .accessibilityLabel("Review inbox, \(proposals) proposals pending")
                }
                if stale > 0 {
                    Button { showReviewQueue = true } label: {
                        statusChip(
                            icon: "clock.badge.exclamationmark",
                            tint: Color.pastureWarning(colorScheme),
                            text: "\(stale) to review"
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Notes past their review date")
                    .accessibilityLabel("Review queue, \(stale) notes need review")
                }
                Spacer()
            }
            .padding(.horizontal, PastureLayout.searchBarHPadding)
            .padding(.vertical, 6)
            Color.pastureDivider(colorScheme).frame(height: 1)
        }
    }

    private func statusChip(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.pastureStatusBar)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
        }
        .contentShape(Rectangle())
    }

    private func renameFile(_ file: MDFile, to newName: String) {
        guard let renamed = fm.rename(file: file, to: newName) else { return }
        if activeFile == file { activeFile = renamed }
        if selectedFiles.contains(file) {
            selectedFiles.remove(file)
            selectedFiles.insert(renamed)
        }
    }

    // MARK: — Search

    private var searchBar: some View {
        HStack(spacing: PastureLayout.searchBarIconSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                .font(.system(size: 13))
            TextField("Search files...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.pastureSearch)
            if !searchText.isEmpty {
                Button { searchText = "" ; fm.searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityLabel("Clear search")
            }

            Menu {
                ForEach(FileSortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: sortOrder == .date ? "clock" : "textformat.abc")
                    .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(sortOrder == .date ? "Sorted by date" : "Sorted by name")
            .accessibilityLabel("Sort order")
            .accessibilityValue(sortOrder == .date ? "Date" : "Name")
        }
        .padding(.horizontal, PastureLayout.searchBarHPadding)
        .padding(.vertical, PastureLayout.searchBarVPadding)
        .animation(.easeInOut(duration: PastureEffects.animationQuick), value: searchText.isEmpty)
    }

    // MARK: — File List

    private var sortedFiles: [MDFile] {
        let base = fm.filteredFiles
        switch sortOrder {
        case .date:
            // fm.files is already kept sorted by date descending (loadFiles/save)
            return base
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var isSearching: Bool { !fm.searchQuery.isEmpty }

    /// Nodos que se pintan ahora. Con búsqueda activa se ocultan las colecciones
    /// sin coincidencias: un triángulo que no lleva a nada solo hace ruido.
    private var nodes: [CollectionNode] {
        SidebarTree.build(
            files: sortedFiles,
            collections: fm.collections,
            base: MDFileManager.pastureDir,
            hidingEmpty: isSearching
        )
    }

    /// El pliegue de un nodo. Durante una búsqueda se ve abierto y el `set` no
    /// escribe, así que al borrar la búsqueda vuelve el estado guardado.
    private func expansionBinding(for node: CollectionNode) -> Binding<Bool> {
        Binding(
            get: {
                CollectionExpansionStore.effectiveExpansion(
                    stored: expandedCollections, nodeID: node.id, isSearching: isSearching
                )
            },
            set: { newValue in
                let next = CollectionExpansionStore.applying(
                    newValue, to: expandedCollections, nodeID: node.id, isSearching: isSearching
                )
                guard next != expandedCollections else { return }
                expandedCollections = next
                CollectionExpansionStore.save(next)
            }
        )
    }

    var fileList: some View {
        List(selection: $selectedFiles) {
            ForEach(nodes) { node in
                DisclosureGroup(isExpanded: expansionBinding(for: node)) {
                    ForEach(node.files) { file in
                        fileRow(file: file)
                    }
                } label: {
                    collectionHeader(node)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            guard !selectedFiles.isEmpty else { return }
            // Se recorre `fm.files` para respetar el orden mostrado en la lista.
            filesPendingDeletion = fm.files.filter { selectedFiles.contains($0) }
            showDeleteConfirmation = true
        }
        .onChange(of: selectedFiles) { _, newVal in
            if newVal.count == 1 { activeFile = newVal.first }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            onDrop(providers)
        }
    }

    /// Cabecera del nodo: nombre, número de notas y tokens. Conserva el menú
    /// contextual de la colección (renombrar / borrar si está vacía).
    @ViewBuilder
    private func collectionHeader(_ node: CollectionNode) -> some View {
        HStack(spacing: 6) {
            Text(node.name ?? "Uncategorized")
                .font(.pastureSummary)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                .lineLimit(1)
            Spacer()
            Text("\(node.fileCount)")
                .font(.pastureSummary)
                .foregroundStyle(Color.pastureTextTertiary(colorScheme))
        }
        .contentShape(Rectangle())
        .help("\(node.fileCount) note\(node.fileCount == 1 ? "" : "s"), ~\(TokenEstimator.formatted(node.totalTokens)) tokens")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(node.name ?? "Uncategorized"), \(node.fileCount) notes, approximately \(TokenEstimator.formatted(node.totalTokens)) tokens")
        .contextMenu {
            if let name = node.name {
                collectionHeaderContextMenu(collectionName: name, isEmpty: node.files.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func fileRow(file: MDFile) -> some View {
        FileRow(file: file, colorScheme: colorScheme)
            .tag(file)
            .onTapGesture { activeFile = file }
            .draggable(FileTransfer(url: file.url))
            .contextMenu {
                fileContextMenu(for: file)
            }
    }

    @ViewBuilder
    private func fileContextMenu(for file: MDFile) -> some View {
        Button {
            onOpenInEditor(file)
        } label: {
            Label("Open in Editor", systemImage: "square.and.pencil")
        }

        Button {
            filePendingRename = file
        } label: {
            Label("Rename\u{2026}", systemImage: "pencil")
        }

        Menu("Move to...") {
            if file.collection != nil {
                Button("Uncategorized") {
                    fm.moveFile(file, toCollection: nil)
                }
            }
            ForEach(fm.collections.filter { $0 != file.collection }, id: \.self) { collectionName in
                Button(collectionName) {
                    fm.moveFile(file, toCollection: collectionName)
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            filesPendingDeletion = [file]
            showDeleteConfirmation = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func collectionHeaderContextMenu(collectionName: String, isEmpty: Bool) -> some View {
        Button {
            collectionPendingRename = collectionName
        } label: {
            Label("Rename Collection\u{2026}", systemImage: "pencil")
        }

        if isEmpty {
            Button(role: .destructive) {
                collectionPendingDeletion = collectionName
            } label: {
                Label("Delete Collection", systemImage: "trash")
            }
        } else {
            Text("Collection is not empty")
        }
    }

    // MARK: — Summary

    /// Modelo de AI configurado, o `nil` si no hay API key para el provider activo
    /// (sin denominador, sin regresión respecto a v1.3). La lectura del Keychain
    /// es lógica de UI.
    private var configuredModel: AIModel? {
        let provider = AISettings.loadProvider()
        guard AISettings.loadAPIKey(for: provider) != nil else { return nil }
        return AISettings.resolveModel()
    }

    private var selectionSummary: some View {
        HStack {
            let filtered = fm.filteredFiles
            let count = filtered.count
            let totalTokens = fm.totalTokens(
                for: selectedFiles.isEmpty ? filtered : Array(selectedFiles)
            )
            let label = selectedFiles.isEmpty ? "\(count) files" : "\(selectedFiles.count) selected"
            let model = configuredModel
            let limit = ContextLimit.state(totalTokens: totalTokens, contextWindow: model?.contextWindow)

            Text(label)
                .font(.pastureSummary)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            Spacer()
            HStack(spacing: 4) {
                if limit.exceeds {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.caption2, weight: .semibold))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "number")
                        .font(.system(.caption2, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(tokenSummaryText(totalTokens: totalTokens, contextWindow: limit.contextWindow))
                    .font(.pastureSummary)
            }
            .foregroundStyle(limit.exceeds
                ? Color.pastureError(colorScheme)
                : Color.pastureTokenBadgeText(colorScheme))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tokenSummaryAccessibilityLabel(
                totalTokens: totalTokens, contextWindow: limit.contextWindow, exceeds: limit.exceeds
            ))
            .help(summaryHelpText(model: model, exceeds: limit.exceeds))
        }
        .padding(.horizontal, PastureLayout.summaryBarHPadding)
        .padding(.vertical, PastureLayout.summaryBarVPadding)
    }

    private func tokenSummaryText(totalTokens: Int, contextWindow: Int?) -> String {
        if let window = contextWindow {
            return "~\(TokenEstimator.formatted(totalTokens)) / \(TokenEstimator.formatted(window)) tokens"
        }
        return "~\(TokenEstimator.formatted(totalTokens)) tokens"
    }

    private func tokenSummaryAccessibilityLabel(totalTokens: Int, contextWindow: Int?, exceeds: Bool) -> String {
        let base: String
        if let window = contextWindow {
            base = "Approximately \(TokenEstimator.formatted(totalTokens)) of \(TokenEstimator.formatted(window)) tokens"
        } else {
            base = "Approximately \(TokenEstimator.formatted(totalTokens)) tokens"
        }
        return exceeds ? base + ", exceeds context window" : base
    }

    /// Tooltip del resumen. Al exceder, lo señala; en estado normal con modelo
    /// configurado, nombra el modelo del denominador (m-5). Sin modelo, sin tooltip.
    private func summaryHelpText(model: AIModel?, exceeds: Bool) -> String {
        guard let model else { return "" }
        if exceeds {
            return "Selection exceeds the context window of \(model.displayName)"
        }
        return "Context window of \(model.displayName)"
    }
}
