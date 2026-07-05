import Foundation
import PastureKit

/// Memoria viva (v1.7, Fase B) — re-importación de fuentes locales. Una nota con
/// `source: <carpeta>` en su frontmatter trae los `.md` de esa carpeta a su
/// colección, marcados `generated: true`. No destructivo: una nota generada que
/// el usuario editó y desvinculó (retiró `generated`) NUNCA se sobrescribe (AC#11).
///
/// Solo en la GUI (el servidor MCP sigue read-only, SEC-M11). v1: solo carpetas
/// locales, solo `.md`, sin red ni ejecución de comandos.
extension MDFileManager {

    struct SourceRefreshSummary: Equatable {
        var imported = 0
        var updated = 0
        var skipped = 0
        var sourcesFailed = 0

        var message: String {
            if imported == 0 && updated == 0 && skipped == 0 && sourcesFailed == 0 {
                return "No sources to refresh."
            }
            var parts: [String] = []
            if imported > 0 { parts.append("\(imported) imported") }
            if updated > 0 { parts.append("\(updated) updated") }
            if skipped > 0 { parts.append("\(skipped) unlinked skipped") }
            if sourcesFailed > 0 { parts.append("\(sourcesFailed) source(s) failed") }
            return "Sources — " + (parts.isEmpty ? "nothing to do" : parts.joined(separator: ", "))
        }
    }

    /// Máximo de ficheros re-importados por refresco (paridad con `scanFolder`).
    private static var maxSourceFiles: Int { 500 }

    /// Re-importa todas las fuentes declaradas en el vault. Devuelve un resumen.
    @discardableResult
    func refreshSources() -> SourceRefreshSummary {
        var summary = SourceRefreshSummary()
        var processed = 0

        for note in files where note.frontmatter?.source != nil {
            guard let sourcePath = note.frontmatter?.source else { continue }

            let resolved: URL
            switch SourceValidator.validate(sourcePath: sourcePath, vaultRoot: Self.pastureDir) {
            case .failure(let error):
                summary.sourcesFailed += 1
                lastError = "Source for '\(note.name)' rejected: \(sourceErrorText(error))"
                continue
            case .success(let url):
                resolved = url
            }

            guard let targetDir = resolveTargetDirectory(collection: note.collection) else {
                summary.sourcesFailed += 1
                continue
            }

            for sourceFile in FileLibrary.mdFiles(in: resolved) {
                if processed >= Self.maxSourceFiles { break }
                processed += 1
                importOneSourceFile(sourceFile, into: targetDir, summary: &summary)
            }
        }

        // AC#13: una sola recarga (loadFiles cancela in-flight; el watcher coalesce
        // con su debounce de 0,5 s las N escrituras). La selección del usuario vive
        // en las vistas, no se pierde con el reload.
        if summary.imported > 0 || summary.updated > 0 {
            loadFiles()
        }
        return summary
    }

    private func importOneSourceFile(
        _ source: MDFile, into targetDir: URL, summary: inout SourceRefreshSummary
    ) {
        let clean = FilenameSanitizer.sanitize(source.url.deletingPathExtension().lastPathComponent)
        guard !clean.isEmpty else { return }
        let dest = targetDir.appendingPathComponent(clean + ".md")
        guard Self.isInsidePasture(dest) else { return }

        let existing = try? String(contentsOf: dest, encoding: .utf8)
        switch SourceImportDecision.decide(existingContent: existing) {
        case .skipUnlinked:
            summary.skipped += 1
        case .create, .overwrite:
            let content = FrontmatterWriter.markingGenerated(in: source.content)
            do {
                try content.write(to: dest, atomically: true, encoding: .utf8)
                if existing == nil { summary.imported += 1 } else { summary.updated += 1 }
            } catch {
                summary.sourcesFailed += 1
            }
        }
    }

    private func sourceErrorText(_ error: SourceValidator.SourceError) -> String {
        switch error {
        case .empty: return "empty path"
        case .notFound: return "folder not found"
        case .notADirectory: return "not a directory"
        case .insideVault: return "inside ~/.pasture/ (would loop)"
        }
    }
}
