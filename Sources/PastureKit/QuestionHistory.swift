import Foundation

/// Persists the last questions asked in Ask mode (UserDefaults, most recent first).
/// Same static-namespace pattern as `AISettings`/`ExportSettings`.
public enum QuestionHistory {
    public static let maxEntries = 10
    static let defaultsKey = "askQuestionHistory"

    public static func load(from defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    /// Records a question at the front of the history. Trims whitespace, ignores
    /// empty strings, deduplicates (an existing entry moves to the front), and
    /// caps the list at `maxEntries`.
    public static func record(_ question: String, in defaults: UserDefaults = .standard) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entries = load(from: defaults)
        entries.removeAll { $0 == trimmed }
        entries.insert(trimmed, at: 0)
        defaults.set(Array(entries.prefix(maxEntries)), forKey: defaultsKey)
    }

    public static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}
