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
