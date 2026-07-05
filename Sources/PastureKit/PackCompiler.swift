import Foundation

/// Context Compiler (v1.6) — emisor del cuerpo de un destino a partir de los
/// ficheros fuente. En v1 ambos targets (CLAUDE.md, AGENTS.md) emiten Markdown
/// limpio vía `ContextBuilder`; el `kind` deja la puerta abierta a divergir el
/// formato por destino sin tocar el resto del pipeline.
public enum PackEmitter {
    public static func assemble(files: [ContextBuilder.FileEntry], kind: TargetKind) -> String {
        switch kind {
        case .claudeMd, .agentsMd:
            return ContextBuilder.build(files: files, format: .markdown)
        }
    }
}

/// Compilación PURA de un pack: assemble → render (single-pass) → cap → scan.
/// Sin I/O: recibe los ficheros fuente ya leídos (la capa de escritura resuelve
/// el preset y lee de disco). Determinista y sin timestamps ⇒ idempotente (AC#12).
public enum PackCompiler {

    /// AC#11: tamaño máximo del cuerpo compilado por destino.
    public static let maxBodyBytes = 2_000_000   // 2 MB

    public struct CompileResult: Sendable {
        /// Cuerpo compilado (sin la cabecera de SyncMarker — esa la añade el writer).
        public let body: String
        /// Escaneo de secretos sobre el cuerpo YA renderizado (ADR-QW-002).
        public let secretScan: SecretScanResult
    }

    public enum CompileError: Error, Equatable, Sendable {
        case tooLarge(bytes: Int)
    }

    /// - Parameters:
    ///   - variables: variables por proyecto del pack (`{{PROJECT}}` → valor).
    ///   - sourceFiles: contenido ya leído de los ficheros del preset, en orden.
    public static func compile(
        packName: String,
        variables: [String: String],
        kind: TargetKind,
        sourceFiles: [ContextBuilder.FileEntry]
    ) -> Result<CompileResult, CompileError> {
        let assembled = PackEmitter.assemble(files: sourceFiles, kind: kind)

        // Render single-pass: un valor de variable jamás se re-parsea como sintaxis
        // de template (invariante del motor). Value = defaultValue en el init.
        let templateVars = variables.map { TemplateVariable(name: $0.key, defaultValue: $0.value) }
        let rendered = TemplateEngine.render(assembled, with: templateVars)

        if rendered.utf8.count > maxBodyBytes {
            return .failure(.tooLarge(bytes: rendered.utf8.count))
        }

        // Red de seguridad: los destinos se commitean en repos potencialmente
        // públicos. Escaneo post-render (captura secretos inyectados por variable).
        let scan = SecretScanner.scan(fileName: packName, content: rendered)
        return .success(CompileResult(body: rendered, secretScan: scan))
    }
}
