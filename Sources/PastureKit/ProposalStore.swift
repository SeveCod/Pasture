import Foundation

/// v1.8 Memory Inbox — persistencia de propuestas en `~/.pasture/.inbox/`.
///
/// Cada propuesta es un par de ficheros con el mismo nombre base (el UUID):
/// `<uuid>.md` (el payload) + `<uuid>.json` (la metadata `Proposal`). El
/// directorio está oculto (empieza por `.`) → queda fuera de `FileLibrary`, del
/// feed y de las tools de lectura (SEC-M11 redefinido).
///
/// Namespace estático `nonisolated` (patrón `SelectionPresetStore`), pero con I/O
/// de disco en vez de UserDefaults. El directorio inbox se inyecta para tests
/// (patrón `PackWriter`); el reloj se inyecta para la expiración (patrón `Freshness`).
///
/// Robustez: pares huérfanos (`.md` sin `.json` o viceversa) y metadata corrupta
/// se ignoran y se loguean a stderr, nunca crashean.
public enum ProposalStore {

    public static let didChangeNotification = Notification.Name("PastureProposalInboxDidChange")

    // MARK: — Escritura

    /// Guarda el par `<uuid>.md` + `<uuid>.json` de forma atómica (temp + rename
    /// vía `Data.write(options: .atomic)`). Crea el directorio si no existe.
    public static func save(_ proposal: Proposal, payload: String, inboxRoot: URL) throws {
        try FileManager.default.createDirectory(at: inboxRoot, withIntermediateDirectories: true)
        let md = markdownURL(id: proposal.id, inboxRoot: inboxRoot)
        let json = metadataURL(id: proposal.id, inboxRoot: inboxRoot)
        let encoded = try JSONEncoder().encode(proposal)
        // Payload primero, metadata después: si algo falla entre medias, un `.md`
        // huérfano se ignora al listar (mejor que un `.json` apuntando a nada).
        try Data(payload.utf8).write(to: md, options: .atomic)
        try encoded.write(to: json, options: .atomic)
        post()
    }

    // MARK: — Lectura

    /// Propuestas pendientes válidas, más recientes primero. Efecto secundario: una
    /// propuesta más antigua que el TTL se retira de la bandeja (se borra su par).
    public static func loadPending(inboxRoot: URL, now: Date = Date()) -> [Proposal] {
        let cutoff = now.addingTimeInterval(-Double(MCPLimits.proposalTTLDays) * 86_400)
        var result: [Proposal] = []
        for proposal in loadRaw(inboxRoot: inboxRoot) {
            if proposal.createdAt < cutoff {
                delete(id: proposal.id, inboxRoot: inboxRoot, notify: false)   // expirada
            } else {
                result.append(proposal)
            }
        }
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    /// Todas las propuestas decodificables del inbox, SIN aplicar el TTL ni borrar.
    /// Base tanto de `loadPending` (que sí filtra) como del dedupe (que no debe
    /// depender del reloj ni tener efectos secundarios).
    private static func loadRaw(inboxRoot: URL) -> [Proposal] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: inboxRoot, includingPropertiesForKeys: nil) else { return [] }
        var result: [Proposal] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let proposal = try? JSONDecoder().decode(Proposal.self, from: data) else {
                logIgnored(url)   // metadata corrupta o ilegible
                continue
            }
            result.append(proposal)
        }
        return result
    }

    /// Payload (`<uuid>.md`) de una propuesta; `nil` si no existe.
    public static func payload(for id: UUID, inboxRoot: URL) -> String? {
        try? String(contentsOf: markdownURL(id: id, inboxRoot: inboxRoot), encoding: .utf8)
    }

    /// Número de propuestas pendientes (aplica el TTL, igual que `loadPending`).
    public static func pendingCount(inboxRoot: URL, now: Date = Date()) -> Int {
        loadPending(inboxRoot: inboxRoot, now: now).count
    }

    /// Dedupe: ¿ya hay una propuesta con el mismo payload y destino? Lectura cruda
    /// (sin TTL ni efectos secundarios) para ser determinista e idempotente.
    public static func contains(payloadHash: String, destinationKey: String, inboxRoot: URL) -> Bool {
        loadRaw(inboxRoot: inboxRoot).contains {
            $0.payloadHash == payloadHash && $0.destinationKey == destinationKey
        }
    }

    // MARK: — Borrado

    /// Elimina el par de una propuesta. Dispara `didChangeNotification`.
    public static func delete(id: UUID, inboxRoot: URL) {
        delete(id: id, inboxRoot: inboxRoot, notify: true)
    }

    private static func delete(id: UUID, inboxRoot: URL, notify: Bool) {
        // Borrar `.json` PRIMERO (simétrico a `save`, que lo escribe último): si el
        // proceso muere entre ambos removeItem, queda a lo sumo un `.md` huérfano
        // (invisible a `loadRaw`, que solo itera `.json`), nunca un `.json` sin
        // payload que reaparecería como propuesta fantasma irrecuperable.
        try? FileManager.default.removeItem(at: metadataURL(id: id, inboxRoot: inboxRoot))
        try? FileManager.default.removeItem(at: markdownURL(id: id, inboxRoot: inboxRoot))
        if notify { post() }
    }

    // MARK: — Helpers

    private static func markdownURL(id: UUID, inboxRoot: URL) -> URL {
        inboxRoot.appendingPathComponent("\(id.uuidString).md")
    }

    private static func metadataURL(id: UUID, inboxRoot: URL) -> URL {
        inboxRoot.appendingPathComponent("\(id.uuidString).json")
    }

    private static func post() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static func logIgnored(_ url: URL) {
        FileHandle.standardError.write(Data(
            "[pasture] ProposalStore: ignorando metadata inválida \(url.lastPathComponent)\n".utf8))
    }
}
