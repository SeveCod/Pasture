import Foundation

/// Resuelve y valida rutas de tool dentro del vault (SEC-M1 + SEC-M2).
///
/// `PathValidator.isInside` usa `standardizedFileURL`, que resuelve `..` pero NO
/// sigue symlinks. Un symlink dentro del vault apuntando fuera pasaría esa
/// comprobación. Aquí se valida TRAS `resolvingSymlinksInPath()`, de modo que el
/// destino REAL del enlace debe seguir dentro del vault. No se modifica
/// `PathValidator` (lo usa la app con su semántica actual).
public enum MCPPathResolver {

    public enum ResolveError: Error, Equatable {
        case absolutePathRejected
        case outsideVault
    }

    /// Resuelve `relativePath` contra `vaultRoot` y valida que el destino real
    /// (tras resolver symlinks) sigue dentro del vault.
    ///
    /// - Rechaza rutas absolutas en el argumento.
    /// - Valida `..` (vía PathValidator) y symlinks (vía resolvingSymlinksInPath).
    /// - Devuelve la URL resuelta lista para I/O.
    public static func resolve(relativePath: String, vaultRoot: URL) -> Result<URL, ResolveError> {
        // Una ruta absoluta en el argumento se rechaza de plano (SEC-M1).
        if relativePath.hasPrefix("/") {
            return .failure(.absolutePathRejected)
        }

        let candidate = vaultRoot.appendingPathComponent(relativePath)

        // Capa 1 (SEC-M1): contención por `..` con la semántica de PathValidator.
        guard PathValidator.isInside(target: candidate, base: vaultRoot) else {
            return .failure(.outsideVault)
        }

        // Capa 2 (SEC-M2): resolver symlinks y revalidar el destino REAL.
        let resolvedTarget = candidate.resolvingSymlinksInPath()
        let resolvedBase = vaultRoot.resolvingSymlinksInPath()
        guard PathValidator.isInside(target: resolvedTarget, base: resolvedBase) else {
            return .failure(.outsideVault)
        }

        return .success(resolvedTarget)
    }
}
