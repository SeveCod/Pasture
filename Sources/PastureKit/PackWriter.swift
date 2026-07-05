import Foundation

/// Context Compiler (v1.6) — capa de ESCRITURA de un destino compilado. Es el
/// primer write-path de Pasture hacia árboles git del usuario, así que el modelo
/// de amenaza es la DESTRUCCIÓN de trabajo ajeno, no la exfiltración:
///
/// - Sync unidireccional: vault → destino. Un conflicto (hash del cuerpo ≠ el
///   embebido en la cabecera, o fichero sin cabecera de Pasture) NUNCA se
///   sobrescribe sin `overwriteConflict` explícito (AC#2).
/// - Backup del contenido anterior ANTES de sobrescribir, fuera del repo del
///   usuario y del vault (en Application Support), con poda a 10 por destino (AC#3).
/// - Escritura atómica (`Data.write(options: .atomic)` = temp + rename) para no
///   dejar destinos truncados (AC#11).
/// - Un destino con secretos no se escribe sin `secretsAllowed` (AC#6).
public enum PackWriter {

    /// AC#3: máximo de backups retenidos por destino.
    public static let maxBackupsPerTarget = 10

    /// Raíz de backups por defecto: `~/Library/Application Support/Pasture/backups/`
    /// — fuera del repo del usuario y del vault (AC#3).
    public static func defaultBackupsRoot() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Pasture/backups", isDirectory: true)
    }

    public enum WriteOutcome: Equatable, Sendable {
        /// Creado (destino ausente) o sobrescrito (destino limpio / overwrite confirmado).
        case written(bodyHash: String)
        /// Omitido: el destino lo editó un humano y no se pidió sobrescribir (AC#2).
        case conflict
        /// Omitido: el contenido compilado contiene secretos y no se permitió (AC#6).
        case secretsBlocked
        /// Fallo de I/O (backup o escritura).
        case failed(String)
    }

    public struct WriteRequest: Sendable {
        public let packName: String
        public let body: String
        public let hasSecrets: Bool
        public let targetURL: URL
        /// Raíz de backups (típicamente `~/Library/Application Support/Pasture/backups/`).
        public let backupsRoot: URL
        public let overwriteConflict: Bool
        public let secretsAllowed: Bool

        public init(
            packName: String, body: String, hasSecrets: Bool, targetURL: URL,
            backupsRoot: URL, overwriteConflict: Bool = false, secretsAllowed: Bool = false
        ) {
            self.packName = packName
            self.body = body
            self.hasSecrets = hasSecrets
            self.targetURL = targetURL
            self.backupsRoot = backupsRoot
            self.overwriteConflict = overwriteConflict
            self.secretsAllowed = secretsAllowed
        }
    }

    public static func write(_ request: WriteRequest) -> WriteOutcome {
        let existing = try? String(contentsOf: request.targetURL, encoding: .utf8)
        let state = SyncMarker.state(existingFileContent: existing)

        // AC#2: conflicto sin confirmación explícita → no se toca el destino.
        if state == .conflict && !request.overwriteConflict {
            return .conflict
        }
        // AC#6: secretos sin permiso explícito → no se escribe.
        if request.hasSecrets && !request.secretsAllowed {
            return .secretsBlocked
        }

        // AC#3: backup del contenido anterior antes de sobrescribir.
        if let existing {
            do {
                try backup(content: existing, targetURL: request.targetURL, backupsRoot: request.backupsRoot)
            } catch {
                return .failed("backup falló: \(error.localizedDescription)")
            }
        }

        let composed = SyncMarker.compose(packName: request.packName, body: request.body)
        do {
            // AC#11: escritura atómica (temp + rename) — nunca un destino truncado.
            try Data(composed.utf8).write(to: request.targetURL, options: .atomic)
        } catch {
            return .failed("escritura falló: \(error.localizedDescription)")
        }
        return .written(bodyHash: SyncMarker.sha256(request.body))
    }

    // MARK: — Backups

    /// Subdirectorio de backups estable por destino (hash de su ruta absoluta) —
    /// nunca dentro del repo del usuario ni del vault (AC#3).
    static func backupSubdir(for targetURL: URL, backupsRoot: URL) -> URL {
        let key = String(SyncMarker.sha256(targetURL.standardizedFileURL.path).prefix(16))
        return backupsRoot.appendingPathComponent(key, isDirectory: true)
    }

    static func backup(content: String, targetURL: URL, backupsRoot: URL) throws {
        let subdir = backupSubdir(for: targetURL, backupsRoot: backupsRoot)
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        // Nombre ordenable por tiempo (epoch ms) + sufijo único para no colisionar.
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let name = "\(stamp)-\(UUID().uuidString.prefix(8)).bak"
        try Data(content.utf8).write(to: subdir.appendingPathComponent(name))
        prune(subdir: subdir)
    }

    /// Retiene los `maxBackupsPerTarget` más recientes (por nombre, que empieza por
    /// epoch ms → ordenable) y borra el resto.
    static func prune(subdir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil) else { return }
        let backups = files
            .filter { $0.pathExtension == "bak" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for extra in backups.dropFirst(maxBackupsPerTarget) {
            try? fm.removeItem(at: extra)
        }
    }

    // MARK: — Agregación de 'Sync all' (AC#8)

    public struct SyncSummary: Equatable, Sendable {
        public let synced: Int
        public let conflicts: Int
        public let blocked: Int
        public let failed: Int

        public var description: String {
            var parts = ["\(synced) synced"]
            if conflicts > 0 { parts.append("\(conflicts) conflict\(conflicts == 1 ? "" : "s")") }
            if blocked > 0 { parts.append("\(blocked) blocked") }
            if failed > 0 { parts.append("\(failed) failed") }
            return parts.joined(separator: ", ")
        }
    }

    public static func summarize(_ outcomes: [WriteOutcome]) -> SyncSummary {
        var synced = 0, conflicts = 0, blocked = 0, failed = 0
        for outcome in outcomes {
            switch outcome {
            case .written: synced += 1
            case .conflict: conflicts += 1
            case .secretsBlocked: blocked += 1
            case .failed: failed += 1
            }
        }
        return SyncSummary(synced: synced, conflicts: conflicts, blocked: blocked, failed: failed)
    }
}
