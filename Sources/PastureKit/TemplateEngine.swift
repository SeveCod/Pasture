import Foundation

public struct TemplateVariable: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let name: String
    public let defaultValue: String
    public var value: String

    public init(name: String, defaultValue: String = "") {
        self.name = name
        self.defaultValue = defaultValue
        self.value = defaultValue
    }
}

public enum TemplateEngine {
    private static let pattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(
                pattern: #"\{\{([A-Za-z_][A-Za-z0-9_]*)(?:=([^}]*))?\}\}"#
            )
        } catch {
            fatalError("TemplateEngine regex failed to compile: \(error)")
        }
    }()

    public static func extractVariables(from text: String) -> [TemplateVariable] {
        let range = NSRange(text.startIndex..., in: text)
        let matches = pattern.matches(in: text, range: range)
        var seen = Set<String>()
        var vars: [TemplateVariable] = []
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: text) else { continue }
            let name = String(text[nameRange])
            // Deduplicate: first occurrence's default value wins
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            var defaultVal = ""
            if match.range(at: 2).location != NSNotFound,
               let defRange = Range(match.range(at: 2), in: text) {
                defaultVal = String(text[defRange])
            }
            vars.append(TemplateVariable(name: name, defaultValue: defaultVal))
        }
        return vars
    }

    public static func render(_ text: String, with variables: [TemplateVariable]) -> String {
        let lookup = Dictionary(variables.map { ($0.name, $0.value) }, uniquingKeysWith: { a, _ in a })
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = pattern.matches(in: text, range: range)
        var result = text
        // Iterate in reverse so replacements don't invalidate subsequent match ranges
        for match in matches.reversed() {
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let fullRange = Range(match.range, in: text) else { continue }
            let name = String(text[nameRange])
            if let replacement = lookup[name] {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }
        return result
    }

    public static func hasVariables(in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return pattern.firstMatch(in: text, range: range) != nil
    }
}
