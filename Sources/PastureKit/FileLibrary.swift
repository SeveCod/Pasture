import Foundation

/// Pure filesystem queries for the Pasture library. Extracted from `MDFileManager`
/// so they are unit-testable and can run off the main actor (`load(at:)` is async
/// and nonisolated, so it executes on the global concurrent executor).
public enum FileLibrary {

    /// Result of a full library scan: files sorted by date descending, plus subdirectories.
    public struct LoadResult: Sendable {
        public let files: [MDFile]
        public let subdirectories: [URL]

        public init(files: [MDFile], subdirectories: [URL]) {
            self.files = files
            self.subdirectories = subdirectories
        }
    }

    /// Scans the library root and its first-level subdirectories for `.md` files.
    /// Runs on the global executor — safe to call from the main actor without blocking it.
    public static func load(at root: URL) async -> LoadResult {
        let subdirs = realSubdirectories(in: root)
        var all = mdFiles(in: root)
        for subdir in subdirs {
            all.append(contentsOf: mdFiles(in: subdir))
        }
        return LoadResult(
            files: all.sorted { $0.modifiedDate > $1.modifiedDate },
            subdirectories: subdirs
        )
    }

    /// Non-hidden, non-symlink `.md` files directly inside `directory`.
    public static func mdFiles(in directory: URL) -> [MDFile] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return urls
            .filter { url in
                guard url.pathExtension.lowercased() == "md" else { return false }
                let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                return rv?.isSymbolicLink != true
            }
            .map { MDFile(url: $0) }
    }

    /// Non-hidden, non-symlink subdirectories directly inside `directory`.
    public static func realSubdirectories(in directory: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return urls.filter { url in
            let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return rv?.isDirectory == true && rv?.isSymbolicLink != true
        }
    }

    /// Visible (non-hidden) entries inside `directory`. A collection containing only
    /// `.DS_Store` counts as empty — Finder creates those files in any visited folder.
    /// Throws if the directory cannot be read.
    public static func visibleContents(of directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
    }

    /// First non-existing URL for `baseName.ext` in `directory`, appending `-2`, `-3`, …
    public static func deduplicatedURL(baseName: String, ext: String, in directory: URL) -> URL {
        let filename = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        var url = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let numbered = ext.isEmpty ? "\(baseName)-\(counter)" : "\(baseName)-\(counter).\(ext)"
            url = directory.appendingPathComponent(numbered)
            counter += 1
        }
        return url
    }
}
