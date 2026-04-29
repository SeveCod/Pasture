import Foundation

public enum FilenameSanitizer {
    public static func sanitize(_ name: String) -> String {
        name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }
}
