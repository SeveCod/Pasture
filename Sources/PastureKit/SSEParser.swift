import Foundation

public struct SSEEvent: Sendable {
    public let event: String?
    public let data: String

    public init(event: String?, data: String) {
        self.event = event
        self.data = data
    }
}

public struct SSELineBuffer: Sendable {
    public var eventType: String?
    public var dataLines: [String]

    public init() {
        eventType = nil
        dataLines = []
    }
}

public enum SSEParser {

    public static func parse(line: String, buffer: inout SSELineBuffer) -> SSEEvent? {
        if line.isEmpty {
            guard !buffer.dataLines.isEmpty else {
                buffer = SSELineBuffer()
                return nil
            }
            let event = SSEEvent(event: buffer.eventType, data: buffer.dataLines.joined(separator: "\n"))
            buffer = SSELineBuffer()
            return event
        }

        if line.hasPrefix(":") {
            return nil
        }

        if line.hasPrefix("event:") {
            buffer.eventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            buffer.dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .init(charactersIn: " ")))
        } else if line.hasPrefix("id:") || line.hasPrefix("retry:") {
            // ignored for now
        }
        return nil
    }
}
