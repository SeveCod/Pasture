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
    ///
    /// `reusing` permite una carga INCREMENTAL: cada nota cuyo fichero no haya
    /// cambiado se reaprovecha del resultado anterior en vez de releerse. Sin
    /// esto, cada ráfaga del watcher —incluidas las que provoca la propia app al
    /// guardar— releía el vault entero: contenido, estimación de tokens, escaneo
    /// de plantillas y parseo de frontmatter de cada nota (audit 360, A3).
    /// Pasar `reusing: []` conserva el comportamiento de relectura completa.
    public static func load(at root: URL, reusing previous: [MDFile] = []) async -> LoadResult {
        let index = Dictionary(previous.map { (cacheKey(for: $0.url), $0) },
                               uniquingKeysWith: { first, _ in first })
        let subdirs = realSubdirectories(in: root)
        var all = mdFiles(in: root, reusing: index)
        for subdir in subdirs {
            all.append(contentsOf: mdFiles(in: subdir, reusing: index))
        }
        return LoadResult(
            files: all.sorted { $0.modifiedDate > $1.modifiedDate },
            subdirectories: subdirs
        )
    }

    /// Non-hidden, non-symlink `.md` files directly inside `directory`.
    public static func mdFiles(in directory: URL) -> [MDFile] {
        mdFiles(in: directory, reusing: [:])
    }

    /// Variante con caché. Una entrada sólo se reutiliza si coinciden **fecha de
    /// modificación y tamaño en bytes**; con uno solo de los dos, un editor que
    /// preserve la fecha o una edición que no cambie el tamaño devolverían
    /// contenido obsoleto, que de ahí viajaría a un feed o a un pack.
    static func mdFiles(in directory: URL, reusing index: [String: MDFile]) -> [MDFile] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isSymbolicLinkKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        ) else { return [] }
        return urls
            .filter { url in
                guard url.pathExtension.lowercased() == "md" else { return false }
                let rv = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
                return rv?.isSymbolicLink != true
            }
            .map { url in
                if let cached = index[cacheKey(for: url)], isUnchanged(cached, at: url) { return cached }
                return MDFile(url: url)
            }
    }

    /// Clave normalizada de la caché.
    ///
    /// Comparar `URL` directamente NO vale: `contentsOfDirectory` devuelve rutas
    /// ya resueltas (`/private/var/…`) mientras una URL construida con
    /// `appendingPathComponent` conserva el symlink (`/var/…`), y las dos son
    /// distintas como `URL` aunque apunten al mismo fichero. Un fallo de clave
    /// sólo degrada a relectura completa (nunca sirve contenido obsoleto), pero
    /// dejaría la carga incremental sin efecto sin que nada lo indicase.
    static func cacheKey(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// ¿El fichero en disco sigue siendo el que produjo `cached`?
    ///
    /// Se compara el tamaño contra los bytes UTF-8 del contenido cacheado. Un
    /// fichero que no sea UTF-8 válido guarda `content` vacío, así que nunca
    /// coincidirá y se releerá: conservador por diseño.
    static func isUnchanged(_ cached: MDFile, at url: URL) -> Bool {
        guard let rv = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = rv.contentModificationDate,
              let size = rv.fileSize
        else { return false }
        return modified == cached.modifiedDate && size == cached.content.utf8.count
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
