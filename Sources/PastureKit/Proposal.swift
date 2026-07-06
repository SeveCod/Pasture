import Foundation

/// v1.8 Memory Inbox — clase de propuesta de escritura del agente MCP.
public enum ProposalKind: String, Codable, Sendable, CaseIterable {
    case note
    case append
}

/// v1.8 Memory Inbox — schema en disco (metadata `<uuid>.json`) de una propuesta
/// que un agente MCP deposita en `~/.pasture/.inbox/`. El humano la promociona
/// (o rechaza) desde la GUI; el servidor MCP nunca escribe en el vault visible.
///
/// Tipo de valor puro (sin I/O). `ProposalStore` (de)serializa, `MCPTools`
/// construye y `ProposalPromoter` lee destino/hashes. Los campos de destino son
/// planos y opcionales (calca la forma de `SelectionPreset`), NO valores asociados
/// del enum — así se conserva el Codable sintetizado (sin `CodingKeys`, camelCase).
///
/// SEC: nunca contiene el secreto en claro; `secretSummary` es el resumen
/// enmascarado de `SecretScanner`.
public struct Proposal: Codable, Sendable, Hashable, Identifiable {
    /// Versión del schema. Explícita desde v1 para permitir migraciones futuras.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let id: UUID
    public let kind: ProposalKind
    /// Destino `.note`: nombre del fichero a crear.
    public let filename: String?
    /// Destino `.note`: colección (subdirectorio); `nil` = raíz del vault.
    public let collection: String?
    /// Destino `.append`: path relativo del fichero existente al que anexar.
    public let relativePath: String?
    public let createdAt: Date
    /// Procedencia: nombre del cliente MCP (`clientInfo.name`), o "unknown".
    public let proposedBy: String
    /// Resumen enmascarado de secretos detectados en el payload (o `nil`).
    public let secretSummary: String?
    /// Destino `.append`: SHA-256 del contenido del destino en el momento de
    /// proponer, para detectar cambios antes de anexar.
    public let targetHash: String?
    /// Hash del contenido del payload, para deduplicar propuestas idénticas.
    public let payloadHash: String
    /// RESERVADO Fase 2 (auto-aprobación por colección). Ausente en v1.8 → `nil`.
    /// Opcional para forward/backward-compat sin migración de schema.
    public let autoApproved: Bool?

    public init(
        schemaVersion: Int = Proposal.currentSchemaVersion,
        id: UUID = UUID(),
        kind: ProposalKind,
        filename: String? = nil,
        collection: String? = nil,
        relativePath: String? = nil,
        createdAt: Date = Date(),
        proposedBy: String,
        secretSummary: String? = nil,
        targetHash: String? = nil,
        payloadHash: String,
        autoApproved: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.kind = kind
        self.filename = filename
        self.collection = collection
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.proposedBy = proposedBy
        self.secretSummary = secretSummary
        self.targetHash = targetHash
        self.payloadHash = payloadHash
        self.autoApproved = autoApproved
    }

    /// Hash canónico del payload. Reutiliza `SyncMarker.sha256` (CryptoKit) — una
    /// sola implementación de hash en todo el proyecto, regla de cero dependencias.
    public static func payloadHash(for content: String) -> String {
        SyncMarker.sha256(content)
    }

    /// Clave canónica del destino, para deduplicar (payload + destino). Distingue
    /// nota (colección/nombre) de append (path), así que dos propuestas al mismo
    /// contenido pero distinto destino no colisionan.
    public var destinationKey: String {
        switch kind {
        case .note:   return "note:\(collection ?? "")/\(filename ?? "")"
        case .append: return "append:\(relativePath ?? "")"
        }
    }

    // MARK: — Factories (garantizan el invariante kind ↔ campos de destino)

    /// Propuesta de nota nueva. `content` solo deriva el `payloadHash`; el payload
    /// en sí lo escribe `ProposalStore` en `<uuid>.md`, no vive en el struct.
    public static func note(
        id: UUID = UUID(),
        filename: String,
        collection: String? = nil,
        content: String,
        createdAt: Date = Date(),
        proposedBy: String,
        secretSummary: String? = nil
    ) -> Proposal {
        Proposal(
            id: id,
            kind: .note,
            filename: filename,
            collection: collection,
            createdAt: createdAt,
            proposedBy: proposedBy,
            secretSummary: secretSummary,
            payloadHash: payloadHash(for: content)
        )
    }

    /// Propuesta de añadido a un fichero existente. `targetHash` = SHA-256 del
    /// contenido del destino en el momento de proponer (lo aporta `MCPTools`).
    public static func append(
        id: UUID = UUID(),
        relativePath: String,
        content: String,
        targetHash: String,
        createdAt: Date = Date(),
        proposedBy: String,
        secretSummary: String? = nil
    ) -> Proposal {
        Proposal(
            id: id,
            kind: .append,
            relativePath: relativePath,
            createdAt: createdAt,
            proposedBy: proposedBy,
            secretSummary: secretSummary,
            targetHash: targetHash,
            payloadHash: payloadHash(for: content)
        )
    }
}
