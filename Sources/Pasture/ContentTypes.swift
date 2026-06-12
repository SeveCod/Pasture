import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

enum FileSortOrder: String, CaseIterable {
    case date = "Date"
    case name = "Name"
}

enum DetailMode: String, CaseIterable {
    case preview
    case ask
}

extension ExportFileFormat {
    /// Tipos para NSSavePanel: el UTType de la extensión elegida primero,
    /// para que el panel no coaccione el nombre hacia ".txt".
    var allowedContentTypes: [UTType] {
        switch self {
        case .markdown: return [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        case .plainText: return [.plainText]
        }
    }
}

struct FileTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .plainText) { transfer in
            SentTransferredFile(transfer.url, allowAccessingOriginalFile: true)
        } importing: { received in
            FileTransfer(url: received.file)
        }
    }
}
