import Foundation

/// Context Compiler (v1.6) — un *pack* de compilación: qué contenido del vault
/// se emite, con qué variables, y a qué destinos en repos del usuario.
///
/// El pack persiste SOLO referencias (UUID de preset, rutas destino, variables) —
/// JAMÁS contenido de fichero, credenciales ni claves (mismo ADR-QW-003 que
/// `SelectionPreset`). Las variables se guardan en claro en UserDefaults: la UI
/// debe advertir de no poner secretos ahí, y el `SecretScanner` post-render
/// (PackCompiler) actúa de red de seguridad antes de cada escritura.

/// Formato de destino de una compilación. Enum con casos futuros (`.cursorRules`,
/// `.githubInstructions`) detrás de la misma frontera.
public enum TargetKind: String, Codable, Sendable, CaseIterable, Hashable {
    case claudeMd
    case agentsMd

    /// Nombre de fichero canónico sugerido para el destino.
    public var defaultFileName: String {
        switch self {
        case .claudeMd: return "CLAUDE.md"
        case .agentsMd: return "AGENTS.md"
        }
    }
}

/// Un destino concreto de un pack: dónde escribir y el estado del último sync.
public struct CompileTarget: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var kind: TargetKind
    /// Ruta ABSOLUTA en un repo del usuario. Validada (fuera de `~/.pasture/`) por
    /// `TargetValidator` antes de guardar o compilar.
    public var absolutePath: String
    /// SHA-256 del cuerpo escrito en el último sync exitoso (para el panel de
    /// estado: al día / desfasado). La detección de conflicto no depende de este
    /// campo — usa el hash embebido en la cabecera del propio fichero (SyncMarker).
    public var lastSyncHash: String?
    public var lastSyncAt: Date?

    public init(
        id: UUID = UUID(),
        kind: TargetKind,
        absolutePath: String,
        lastSyncHash: String? = nil,
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.absolutePath = absolutePath
        self.lastSyncHash = lastSyncHash
        self.lastSyncAt = lastSyncAt
    }
}

/// Un pack de compilación completo.
public struct CompilePack: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    /// Referencia al `SelectionPreset` (por UUID) que decide QUÉ ficheros entran.
    /// Un preset borrado deja el pack en estado 'preset ausente' (no rompe el decode).
    public var presetID: UUID
    /// Variables por proyecto persistidas (`{{PROJECT}}` → "foo"). Nunca secretos.
    public var variables: [String: String]
    public var targets: [CompileTarget]
    /// Opt-in: recompilar al detectar cambios en los ficheros fuente (off por defecto).
    public var autoResync: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        presetID: UUID,
        variables: [String: String] = [:],
        targets: [CompileTarget] = [],
        autoResync: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.presetID = presetID
        self.variables = variables
        self.targets = targets
        self.autoResync = autoResync
        self.createdAt = createdAt
    }

    /// Máximo de caracteres del nombre de pack (reutiliza el límite de preset).
    public static let maxNameLength = SelectionPreset.maxNameLength

    /// Normaliza el nombre igual que `SelectionPreset` (control chars fuera, trim,
    /// límite de longitud). Cadena vacía ⇒ el llamante lo rechaza.
    public static func sanitizedName(_ raw: String) -> String {
        SelectionPreset.sanitizedName(raw)
    }
}
