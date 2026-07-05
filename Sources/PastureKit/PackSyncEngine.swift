import Foundation

/// Context Compiler (v1.6) — orquestador que une las piezas para sincronizar un
/// pack: resolver preset (SEC-9) → abortar si faltan fuentes (AC#5) → leer → por
/// cada destino validar (TargetValidator) → compilar (PackCompiler, con el kind
/// del destino) → escribir (PackWriter). Vive SOLO en PastureKit/GUI; el servidor
/// MCP sigue estrictamente read-only (SEC-M11) — no se añade ningún tool nuevo.
public enum PackSyncEngine {

    public struct Context: Sendable {
        public let vaultRoot: URL
        public let backupsRoot: URL
        public let overwriteConflicts: Bool
        public let secretsAllowed: Bool

        public init(vaultRoot: URL, backupsRoot: URL, overwriteConflicts: Bool = false, secretsAllowed: Bool = false) {
            self.vaultRoot = vaultRoot
            self.backupsRoot = backupsRoot
            self.overwriteConflicts = overwriteConflicts
            self.secretsAllowed = secretsAllowed
        }
    }

    public enum PackSyncError: Error, Equatable, Sendable {
        /// El preset referenciado por el pack ya no existe.
        case presetMissing
        /// El preset referencia ficheros que no están en disco (o rutas rechazadas
        /// por path-traversal). La compilación aborta ANTES de emitir nada (AC#5).
        case missingSourceFiles([String])
    }

    public struct TargetResult: Sendable, Equatable {
        public let targetID: UUID
        public let outcome: PackWriter.WriteOutcome
    }

    /// Sincroniza un pack contra todos sus destinos.
    public static func sync(
        pack: CompilePack, preset: SelectionPreset?, context: Context
    ) -> Result<[TargetResult], PackSyncError> {
        guard let preset else { return .failure(.presetMissing) }

        // Resolución + validación de contención (SEC-9). Los ficheros que existen
        // en disco forman el conjunto 'existing'; los ausentes o rechazados abortan.
        let resolution = PresetResolver.resolve(relativePaths: preset.relativePaths, base: context.vaultRoot)
        let existing = Set(resolution.urls.filter { FileManager.default.fileExists(atPath: $0.path) })
        let missing = PresetResolver.missingPaths(
            relativePaths: preset.relativePaths, base: context.vaultRoot, existing: existing)
        guard missing.isEmpty else {
            return .failure(.missingSourceFiles(missing))   // AC#5
        }

        // Leer en el orden del preset. FileEntry.name sin extensión (ContextBuilder añade .md).
        let files = resolution.urls.map { url in
            ContextBuilder.FileEntry(
                name: url.deletingPathExtension().lastPathComponent,
                content: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
        }

        var results: [TargetResult] = []
        for target in pack.targets {
            let outcome = syncTarget(target, pack: pack, files: files, context: context)
            results.append(TargetResult(targetID: target.id, outcome: outcome))
        }
        return .success(results)
    }

    private static func syncTarget(
        _ target: CompileTarget, pack: CompilePack,
        files: [ContextBuilder.FileEntry], context: Context
    ) -> PackWriter.WriteOutcome {
        // AC#4: el destino nunca puede caer dentro del vault.
        guard case .success(let url) = TargetValidator.validate(
            targetPath: target.absolutePath, vaultRoot: context.vaultRoot) else {
            return .failed("destino inválido (dentro del vault o ruta no absoluta)")
        }

        switch PackCompiler.compile(
            packName: pack.name, variables: pack.variables, kind: target.kind, sourceFiles: files) {
        case .failure:
            return .failed("cuerpo compilado demasiado grande")
        case .success(let compiled):
            let request = PackWriter.WriteRequest(
                packName: pack.name, body: compiled.body,
                hasSecrets: !compiled.secretScan.isEmpty, targetURL: url,
                backupsRoot: context.backupsRoot,
                overwriteConflict: context.overwriteConflicts,
                secretsAllowed: context.secretsAllowed)
            return PackWriter.write(request)
        }
    }
}
