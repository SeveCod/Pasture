import SwiftUI
import PastureKit

struct SidebarView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var fm: MDFileManager
    @Binding var selectedFiles: Set<MDFile>
    @Binding var activeFile: MDFile?
    @Binding var searchText: String
    @Binding var sortOrder: FileSortOrder
    @Binding var filePendingDeletion: MDFile?
    @Binding var showDeleteConfirmation: Bool
    var onDrop: ([NSItemProvider]) -> Bool
    @State private var collectionPendingDeletion: String?
    @State private var filePendingRename: MDFile?
    @State private var collectionPendingRename: String?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Color.pastureDivider(colorScheme).frame(height: 1)
            fileList
            Color.pastureDivider(colorScheme).frame(height: 1)
            selectionSummary
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
            Text("The empty collection '\(name)' will be deleted.")
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

    var fileList: some View {
        let sorted = sortedFiles
        let grouped = Dictionary(grouping: sorted, by: \.collection)
        let uncategorized = grouped[nil] ?? []
        let visibleCollns = fm.searchQuery.isEmpty
            ? fm.collections
            : fm.collections.filter { grouped[$0] != nil }
        return List(selection: $selectedFiles) {
            if !uncategorized.isEmpty {
                Section {
                    ForEach(uncategorized) { file in
                        fileRow(file: file)
                    }
                } header: {
                    Text("Uncategorized")
                        .font(.pastureSummary)
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                }
            }

            ForEach(visibleCollns, id: \.self) { collectionName in
                let collectionFiles = grouped[collectionName] ?? []
                Section {
                    ForEach(collectionFiles) { file in
                        fileRow(file: file)
                    }
                } header: {
                    Text(collectionName)
                        .font(.pastureSummary)
                        .foregroundStyle(Color.pastureTextTertiary(colorScheme))
                        .contextMenu {
                            collectionHeaderContextMenu(collectionName: collectionName, isEmpty: collectionFiles.isEmpty)
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onDeleteCommand {
            if selectedFiles.count == 1, let file = selectedFiles.first {
                filePendingDeletion = file
                showDeleteConfirmation = true
            }
        }
        .onChange(of: selectedFiles) { _, newVal in
            if newVal.count == 1 { activeFile = newVal.first }
        }
        .onDrop(of: ["public.file-url"], isTargeted: nil) { providers in
            onDrop(providers)
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
            filePendingDeletion = file
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

    private var selectionSummary: some View {
        HStack {
            let filtered = fm.filteredFiles
            let count = filtered.count
            let totalTokens = fm.totalTokens(
                for: selectedFiles.isEmpty ? filtered : Array(selectedFiles)
            )
            let label = selectedFiles.isEmpty ? "\(count) files" : "\(selectedFiles.count) selected"

            Text(label)
                .font(.pastureSummary)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text("~\(TokenEstimator.formatted(totalTokens)) tokens")
                    .font(.pastureSummary)
            }
            .foregroundStyle(Color.pastureTokenBadgeText(colorScheme))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Approximately \(TokenEstimator.formatted(totalTokens)) tokens")
        }
        .padding(.horizontal, PastureLayout.summaryBarHPadding)
        .padding(.vertical, PastureLayout.summaryBarVPadding)
    }
}
