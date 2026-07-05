import Foundation

/// Pure transforms over an Ask transcript. The transcript stored in the view
/// model is *clean*: questions and answers only, never the XML file context.
/// The context is embedded at send time (`wire`) and stripped conceptually from
/// what the user sees or saves (`distill`).
public enum ConversationComposer {

    /// Builds the wire transcript for a request: the file context is embedded
    /// into the first `.user` message and nowhere else (AC#1–3). An empty
    /// context returns the transcript unchanged. The first message's identity
    /// and role are preserved — only its content grows.
    public static func wire(transcript: [ChatMessage], context: String) -> [ChatMessage] {
        guard !context.isEmpty, var first = transcript.first else { return transcript }
        first.content = "\(context)\n\n\(first.content)"
        var result = transcript
        result[0] = first
        return result
    }

    /// Renders a clean transcript to Markdown for saving into the vault as a new
    /// context note. Incomplete answers (Stop, or a stream cut short) are flagged.
    public static func distill(_ transcript: [ChatMessage]) -> String {
        transcript.map { message in
            switch message.role {
            case .user:
                return "## Question\n\n\(message.content)"
            case .assistant:
                let suffix = message.isComplete ? "" : "\n\n_(incomplete answer)_"
                return "## Answer\n\n\(message.content)\(suffix)"
            }
        }
        .joined(separator: "\n\n")
    }
}
