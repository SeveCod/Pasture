import Foundation

public struct MDFile: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public var name: String
    public var url: URL
    public var modifiedDate: Date
    public var content: String
    public var tokens: Int
    public var hasTemplateVars: Bool

    public init(name: String, url: URL, modifiedDate: Date, content: String, tokens: Int, hasTemplateVars: Bool) {
        self.name = name
        self.url = url
        self.modifiedDate = modifiedDate
        self.content = content
        self.tokens = tokens
        self.hasTemplateVars = hasTemplateVars
    }

    public init(url: URL) {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.modifiedDate = attrs?[.modificationDate] as? Date ?? Date()
        self.content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        self.tokens = TokenEstimator.estimate(self.content)
        self.hasTemplateVars = TemplateEngine.hasVariables(in: self.content)
    }

    public func collection(relativeTo base: URL) -> String? {
        let parentDir = url.deletingLastPathComponent()
        let basePath = base.standardizedFileURL.path
        let parentPath = parentDir.standardizedFileURL.path
        guard parentPath != basePath else { return nil }
        guard parentPath.hasPrefix(basePath + "/") else { return nil }
        return parentDir.lastPathComponent
    }

    public mutating func updateDerivedProperties() {
        tokens = TokenEstimator.estimate(content)
        hasTemplateVars = TemplateEngine.hasVariables(in: content)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    public static func == (lhs: MDFile, rhs: MDFile) -> Bool {
        lhs.url == rhs.url
    }
}
