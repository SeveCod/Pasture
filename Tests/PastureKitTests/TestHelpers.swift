import Foundation

/// Shared fixtures for PastureKit test suites.

/// Creates a unique temporary directory. Callers remove it with
/// `defer { try? FileManager.default.removeItem(at: dir) }`.
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pasture-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Creates an isolated UserDefaults suite, cleared defensively so tests never
/// see residue from a previous run.
func makeIsolatedUserDefaults() -> UserDefaults {
    let suiteName = "pasture-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
