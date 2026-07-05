import Foundation

/// One turn in an Ask conversation. The transcript is an ordered `[ChatMessage]`:
/// the first `.user` message carries the file context (embedded by the caller),
/// every later message is a plain question or answer.
///
/// `isComplete == false` marks an assistant answer that was cut short (the user
/// pressed Stop, or the stream ended before the provider's end event). Such a
/// partial answer still travels back to the model as history — it is simply
/// flagged so the UI can show it as unfinished.
public struct ChatMessage: Sendable, Hashable, Codable, Identifiable {
    public enum Role: String, Sendable, Codable {
        case user
        case assistant
    }

    public let id: UUID
    public var role: Role
    public var content: String
    public var isComplete: Bool

    public init(id: UUID = UUID(), role: Role, content: String, isComplete: Bool = true) {
        self.id = id
        self.role = role
        self.content = content
        self.isComplete = isComplete
    }
}
