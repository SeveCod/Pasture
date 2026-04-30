import Foundation

public enum ContextBuilder {

    public struct FileEntry: Sendable {
        public let name: String
        public let content: String

        public init(name: String, content: String) {
            self.name = name
            self.content = content
        }
    }

    public static func build(files: [FileEntry]) -> String {
        guard !files.isEmpty else { return "" }

        if files.count == 1, let f = files.first {
            return contextTag(name: f.name, content: f.content)
        }
        let inner = files.map { contextTag(name: $0.name, content: $0.content) }.joined(separator: "\n")
        return "<documents>\n\(inner)\n</documents>"
    }

    static func contextTag(name: String, content: String) -> String {
        let body = content.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
        let safeName = "\(name).md".xmlEscapedAttribute
        return "<context name=\"\(safeName)\">\n<![CDATA[\(body)]]>\n</context>"
    }
}
