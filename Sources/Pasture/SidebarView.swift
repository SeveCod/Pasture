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

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Color.pastureDivider(colorScheme).frame(height: 1)
            fileList
            Color.pastureDivider(colorScheme).frame(height: 1)
            selectionSummary
        }
        .background(Color.pastureSidebar(colorScheme))
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
            return base.sorted { $0.modifiedDate > $1.modifiedDate }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var visibleCollections: [String] {
        if fm.searchQuery.isEmpty {
            return fm.collections
        }
        return fm.collections.filter { collection in
            fm.filteredFiles.contains { $0.collection == collection }
        }
    }

    var fileList: some View {
        let sorted = sortedFiles
        let uncategorized = sorted.filter { $0.collection == nil }
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

            ForEach(visibleCollections, id: \.self) { collectionName in
                let collectionFiles = sorted.filter { $0.collection == collectionName }
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
        .onChange(of: selectedFiles) { oldVal, newVal in
            if let previous = oldVal.first, oldVal.count == 1,
               let idx = fm.files.firstIndex(of: previous) {
                fm.save(file: fm.files[idx])
            }
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
        if isEmpty {
            Button(role: .destructive) {
                fm.deleteCollection(collectionName)
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
            let count = fm.filteredFiles.count
            let totalTokens = fm.totalTokens(
                for: selectedFiles.isEmpty ? fm.filteredFiles : Array(selectedFiles)
            )
            let label = selectedFiles.isEmpty ? "\(count) files" : "\(selectedFiles.count) selected"

            Text(label)
                .font(.pastureSummary)
                .foregroundStyle(Color.pastureTextSecondary(colorScheme))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.system(size: 9, weight: .semibold))
                Text("~\(TokenEstimator.formatted(totalTokens)) tokens")
                    .font(.pastureSummary)
            }
            .foregroundStyle(Color.pastureTokenBadge)
        }
        .padding(.horizontal, PastureLayout.summaryBarHPadding)
        .padding(.vertical, PastureLayout.summaryBarVPadding)
    }
}
