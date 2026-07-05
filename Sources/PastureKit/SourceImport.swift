import Foundation

/// Memoria viva (v1.7, Fase B) — validación y decisiones puras de la
/// re-importación de fuentes locales. El I/O (leer la carpeta, escribir en el
/// vault) vive en la GUI/MDFileManager; el servidor MCP no participa (read-only).
///
/// Recorte deliberado v1: solo carpetas LOCALES como fuente — sin URLs, sin
/// ejecución de comandos, sin red (superficie de ataque casi nula).

/// Valida el `source:` de una nota: debe ser una carpeta local existente FUERA
/// del vault (evita ciclos de re-importación). Rechaza symlinks que resuelvan
/// dentro del vault (misma defensa que MCPPathResolver, en sentido inverso).
public enum SourceValidator {

    public enum SourceError: Error, Equatable, Sendable {
        case empty
        case notFound
        case notADirectory
        case insideVault
    }

    public static func validate(sourcePath: String, vaultRoot: URL) -> Result<URL, SourceError> {
        let trimmed = sourcePath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let expanded = (trimmed as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return .failure(.notFound) }
        guard isDir.boolValue else { return .failure(.notADirectory) }

        // Anti-ciclo: la fuente no puede estar dentro del vault (directa o symlink).
        if PathValidator.isInside(target: url, base: vaultRoot) { return .failure(.insideVault) }
        let resolved = url.resolvingSymlinksInPath()
        if PathValidator.isInside(target: resolved, base: vaultRoot.resolvingSymlinksInPath()) {
            return .failure(.insideVault)
        }
        return .success(resolved)
    }
}

/// Decisión por fichero destino al re-importar (AC#11): una nota generada que el
/// usuario editó pero MANTUVO `generated: true` se sobrescribe; si RETIRÓ la
/// marca (desvinculación) o el nombre lo ocupa una nota escrita a mano, NO se
/// toca. Determinista sobre el contenido actual del destino.
public enum SourceImportDecision: Equatable, Sendable {
    /// El destino no existe → crear la nota generada.
    case create
    /// El destino existe y sigue marcado `generated: true` → re-importar.
    case overwrite
    /// El destino existe pero no está marcado como generado → proteger (no tocar).
    case skipUnlinked

    public static func decide(existingContent: String?) -> SourceImportDecision {
        guard let existing = existingContent else { return .create }
        let frontmatter = FrontmatterParser.parse(existing).frontmatter
        return frontmatter?.generated == true ? .overwrite : .skipUnlinked
    }
}
