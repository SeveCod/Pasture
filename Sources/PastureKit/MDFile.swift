import Foundation

public struct MDFile: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public var name: String
    public var url: URL
    public var modifiedDate: Date
    public var content: String
    public var tokens: Int
    public var hasTemplateVars: Bool
    /// Metadatos de frescura/procedencia (v1.7). `nil` si la nota no lleva
    /// frontmatter válido — se trata como fresca (`Freshness`).
    public var frontmatter: Frontmatter?

    public init(name: String, url: URL, modifiedDate: Date, content: String, tokens: Int, hasTemplateVars: Bool, frontmatter: Frontmatter? = nil) {
        self.name = name
        self.url = url
        self.modifiedDate = modifiedDate
        self.content = content
        self.tokens = tokens
        self.hasTemplateVars = hasTemplateVars
        self.frontmatter = frontmatter
    }

    public init(url: URL) {
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        self.modifiedDate = attrs?[.modificationDate] as? Date ?? Date()
        self.content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        self.tokens = TokenEstimator.estimate(self.content)
        self.hasTemplateVars = TemplateEngine.hasVariables(in: self.content)
        self.frontmatter = FrontmatterParser.parse(self.content).frontmatter
    }

    /// Estado de frescura de la nota respecto a `now` (reloj inyectado). Usa la
    /// fecha de modificación como referencia cuando no hay `last_reviewed`.
    public func freshness(now: Date) -> Freshness.State {
        Freshness.state(frontmatter: frontmatter, reference: modifiedDate, now: now)
    }

    /// Single search predicate shared by the main window and the menu bar popover.
    /// Empty query matches everything. Case-insensitive over name and content.
    public func matches(query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return name.localizedCaseInsensitiveContains(query) ||
               content.localizedCaseInsensitiveContains(query)
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
        frontmatter = FrontmatterParser.parse(content).frontmatter
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    public static func == (lhs: MDFile, rhs: MDFile) -> Bool {
        lhs.url == rhs.url
    }
}
