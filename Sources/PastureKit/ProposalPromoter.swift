import Foundation

/// v1.8 Memory Inbox — el ÚNICO write-path al vault visible. Se invoca solo desde
/// la GUI (nunca desde el servidor MCP: SEC-M11 redefinido). Promociona una
/// propuesta del `.inbox/` al vault (nota nueva o append) o la rechaza.
///
/// Antes de cualquier I/O valida el destino con la misma doble capa que la lectura
/// (`MCPPathResolver`: rechazo de absolutas + `..` + revalidación tras resolver
/// symlinks). Un `.note` lleva frontmatter de procedencia (`origin: agent`, quién y
/// cuándo). Un `.append` nunca reemplaza: añade al final con separador `\n\n`, y si
/// el destino cambió desde que se propuso (hash ≠ `targetHash`) devuelve
/// `.hashMismatch` para que la GUI recalcule el diff y pida confirmación.
public enum ProposalPromoter {

    public enum PromoteError: Error, Equatable {
        case outsideVault
        case payloadMissing
        case targetMissing
        case hashMismatch(currentContent: String)
        case io(String)
    }

    // MARK: — Nota nueva

    public static func promoteNote(_ proposal: Proposal, inboxRoot: URL, vaultRoot: URL,
                                   now: Date = Date()) -> Result<URL, PromoteError> {
        guard let payload = ProposalStore.payload(for: proposal.id, inboxRoot: inboxRoot) else {
            return .failure(.payloadMissing)
        }
        // Valida el directorio de la colección destino (doble capa) y lo crea.
        let relDir = proposal.collection ?? ""
        let dirURL: URL
        if relDir.isEmpty {
            dirURL = vaultRoot
        } else {
            switch MCPPathResolver.resolve(relativePath: relDir, vaultRoot: vaultRoot) {
            case .failure: return .failure(.outsideVault)
            case .success(let url): dirURL = url
            }
        }
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch { return .failure(.io("\(error)")) }

        let name = proposal.filename ?? "untitled.md"
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.isEmpty ? "md" : (name as NSString).pathExtension
        let destURL = FileLibrary.deduplicatedURL(baseName: base, ext: ext, in: dirURL)

        let content = provenanceFrontmatter(proposal: proposal, now: now, payload: payload)
        do {
            try Data(content.utf8).write(to: destURL, options: .atomic)
        } catch { return .failure(.io("\(error)")) }

        ProposalStore.delete(id: proposal.id, inboxRoot: inboxRoot)
        return .success(destURL)
    }

    // MARK: — Append a fichero existente

    /// `overrideChangedTarget`: la GUI lo pone a `true` SOLO tras mostrarle al
    /// humano el diff recalculado contra el contenido actual y recibir su
    /// confirmación explícita — entonces se anexa al contenido ACTUAL pese al
    /// cambio del destino (nunca lo hace el servidor MCP).
    public static func promoteAppend(_ proposal: Proposal, inboxRoot: URL, vaultRoot: URL,
                                     overrideChangedTarget: Bool = false) -> Result<URL, PromoteError> {
        guard let payload = ProposalStore.payload(for: proposal.id, inboxRoot: inboxRoot) else {
            return .failure(.payloadMissing)
        }
        let relPath = proposal.relativePath ?? ""
        let destURL: URL
        switch MCPPathResolver.resolve(relativePath: relPath, vaultRoot: vaultRoot) {
        case .failure: return .failure(.outsideVault)
        case .success(let url): destURL = url
        }
        guard let current = try? String(contentsOf: destURL, encoding: .utf8) else {
            return .failure(.targetMissing)
        }
        // El destino no debe haber cambiado desde que se propuso, salvo confirmación.
        if !overrideChangedTarget && SyncMarker.sha256(current) != proposal.targetHash {
            return .failure(.hashMismatch(currentContent: current))
        }
        do {
            try Data((current + "\n\n" + payload).utf8).write(to: destURL, options: .atomic)
        } catch { return .failure(.io("\(error)")) }

        ProposalStore.delete(id: proposal.id, inboxRoot: inboxRoot)
        return .success(destURL)
    }

    // MARK: — Rechazo

    /// Descarta la propuesta: borra su par de `.inbox/`, sin tocar el vault.
    public static func reject(_ proposal: Proposal, inboxRoot: URL) {
        ProposalStore.delete(id: proposal.id, inboxRoot: inboxRoot)
    }

    // MARK: — Procedencia

    /// Antepone/fusiona el frontmatter de procedencia al payload de una nota. La
    /// procedencia es permanente (mitigación de prompt-injection almacenada: se ve
    /// siempre que la nota fue propuesta por un agente).
    ///
    /// SEC (v1.8, H2): primero se despojan del payload las claves reservadas
    /// (frescura/`source`/`generated`) que solo Pasture/el humano deben controlar —
    /// si no, un agente podría plantar `review_after`/`ttl` lejanos (la nota evade
    /// la cola de revisión) o `source:` (dispara la re-importación de Fase B).
    private static func provenanceFrontmatter(proposal: Proposal, now: Date, payload: String) -> String {
        var content = FrontmatterWriter.removing(keys: FrontmatterParser.recognizedKeys, in: payload)
        content = FrontmatterWriter.setting(key: "origin", value: "agent", in: content)
        content = FrontmatterWriter.setting(key: "proposed_by", value: proposal.proposedBy, in: content)
        content = FrontmatterWriter.setting(
            key: "proposed_at", value: FrontmatterWriter.isoString(proposal.createdAt), in: content)
        content = FrontmatterWriter.setting(
            key: "approved_at", value: FrontmatterWriter.isoString(now), in: content)
        return content
    }
}
