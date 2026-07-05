import Foundation

/// Context Compiler (v1.6) — valida que un destino de compilación NO cae dentro
/// del vault. Es la validación INVERSA a la de las tools MCP: los destinos son
/// explícitamente externos a `~/.pasture/` (como las export destinations), pero
/// el vault jamás debe ser destino de escritura — un pack que apunte al vault
/// (directo, con `..` o vía symlink) corrompería la fuente de verdad.
///
/// Doble capa al estilo SEC-M2: contención directa (que resuelve `..`) + destino
/// real tras `resolvingSymlinksInPath()`.
public enum TargetValidator {

    public enum ValidationError: Error, Equatable, Sendable {
        case notAbsolute
        case insideVault
    }

    /// Valida un path de destino contra el vault. Devuelve la URL absoluta lista
    /// para escribir, o el motivo del rechazo.
    public static func validate(targetPath: String, vaultRoot: URL) -> Result<URL, ValidationError> {
        guard targetPath.hasPrefix("/") else {
            return .failure(.notAbsolute)
        }
        let url = URL(fileURLWithPath: targetPath)

        let resolvedVault = vaultRoot.resolvingSymlinksInPath()

        // Capa 1: contención directa (standardizedFileURL resuelve `..`).
        if PathValidator.isInside(target: url, base: vaultRoot) {
            return .failure(.insideVault)
        }
        // Capa 2: destino real tras resolver symlinks (SEC-M2 inverso).
        if PathValidator.isInside(target: url.resolvingSymlinksInPath(), base: resolvedVault) {
            return .failure(.insideVault)
        }
        // Capa 3: symlink COLGANTE. Si el destino aún no existe,
        // `resolvingSymlinksInPath` lo deja sin resolver, pero escribir a través
        // del enlace crearía el fichero dentro del vault. Resolvemos el destino
        // inmediato explícitamente y revalidamos.
        if let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) {
            let destURL = dest.hasPrefix("/")
                ? URL(fileURLWithPath: dest)
                : url.deletingLastPathComponent().appendingPathComponent(dest)
            if PathValidator.isInside(target: destURL, base: vaultRoot)
                || PathValidator.isInside(target: destURL.resolvingSymlinksInPath(), base: resolvedVault) {
                return .failure(.insideVault)
            }
        }
        return .success(url)
    }
}
