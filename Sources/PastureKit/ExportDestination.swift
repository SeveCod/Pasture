import Foundation

public struct ExportDestination: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var path: String

    public init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public var isWritable: Bool {
        let parent = url.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parent)
    }
}
