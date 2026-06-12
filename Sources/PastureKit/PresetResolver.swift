import Foundation

/// F2 — Resolución pura de rutas relativas de un preset a URLs absolutas.
///
/// SEC-9: cada ruta se valida con `PathValidator.isInside` contra la base
/// `~/.pasture/`. Una ruta que escape (`../`) se descarta y se cuenta como
/// rechazada — nunca se selecciona un fichero fuera del directorio lógico.
public enum PresetResolver {

    public struct Resolution: Sendable, Equatable {
        /// URLs válidas (dentro de la base). No garantiza que el fichero exista
        /// en disco: el llamante cruza esto con su lista de ficheros reales.
        public let urls: [URL]
        /// Rutas descartadas por path traversal (fuera de la base).
        public let rejectedCount: Int
    }

    /// Convierte rutas relativas en URLs absolutas, validando contención (SEC-9).
    public static func resolve(relativePaths: [String], base: URL) -> Resolution {
        var urls: [URL] = []
        var rejected = 0
        for path in relativePaths {
            let candidate = base.appendingPathComponent(path)
            if PathValidator.isInside(target: candidate, base: base) {
                urls.append(candidate.standardizedFileURL)
            } else {
                rejected += 1
            }
        }
        return Resolution(urls: urls, rejectedCount: rejected)
    }

    /// Rutas relativas del preset que NO están disponibles: o bien fueron
    /// descartadas por path traversal (SEC-9), o bien su URL resuelta no figura
    /// en `existing` (el fichero ya no está en disco). Preserva el path original
    /// para mostrarlo en un toast accionable (M-3).
    public static func missingPaths(relativePaths: [String], base: URL, existing: Set<URL>) -> [String] {
        let normalizedExisting = Set(existing.map { $0.standardizedFileURL })
        var missing: [String] = []
        for path in relativePaths {
            let candidate = base.appendingPathComponent(path)
            guard PathValidator.isInside(target: candidate, base: base) else {
                missing.append(path)   // descartado por SEC-9
                continue
            }
            if !normalizedExisting.contains(candidate.standardizedFileURL) {
                missing.append(path)   // ruta válida pero el fichero no existe
            }
        }
        return missing
    }

    /// Path relativo de una URL respecto a la base, o `nil` si está fuera.
    /// Usado al construir un preset desde una selección actual (ADR-003).
    public static func relativePath(for url: URL, base: URL) -> String? {
        guard PathValidator.isInside(target: url, base: base) else { return nil }
        let basePath = base.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        guard targetPath.hasPrefix(basePath + "/") else { return nil }
        return String(targetPath.dropFirst(basePath.count + 1))
    }
}
