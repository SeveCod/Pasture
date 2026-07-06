import Foundation

/// Catálogo y ejecución de las cuatro tools de solo lectura (D2: una sola
/// `feed_context`). Toda la lógica de dominio se reutiliza de PastureKit
/// (`FileLibrary`, `PathValidator`, `MDFile.matches`, `ContextBuilder`).
public enum MCPTools {

    // MARK: — Tipos del catálogo (tools/list)

    /// Esquema de entrada de una tool. `type` siempre `"object"` (gotcha 4).
    public struct InputSchema: Encodable {
        public let type = "object"
        public let properties: [String: PropertySchema]
        public let required: [String]

        private enum CodingKeys: String, CodingKey { case type, properties, required }
    }

    /// Esquema de una propiedad. `items` solo para arrays.
    public struct PropertySchema: Encodable {
        public let type: String
        public let items: ItemSchema?

        public init(type: String, items: ItemSchema? = nil) {
            self.type = type
            self.items = items
        }
    }

    public struct ItemSchema: Encodable {
        public let type: String
    }

    public struct ToolDefinition: Encodable {
        public let name: String
        public let description: String
        public let inputSchema: InputSchema
    }

    public struct ToolsListResult: Encodable {
        public let tools: [ToolDefinition]
    }

    // MARK: — Catálogo

    /// Catálogo para `tools/list`. Las cuatro tools de lectura, cada una con
    /// `inputSchema.type == "object"` (gotcha 4). Con `includingProposals` se
    /// añaden `propose_note`/`propose_append` (v1.8) — SIN el flag el catálogo es
    /// byte-idéntico a v1.7 (regresión de solo-lectura, SEC-M11).
    public static func catalog(includingProposals: Bool = false) -> ToolsListResult {
        var tools: [ToolDefinition] = [
            ToolDefinition(
                name: "list_files",
                description: "List all Markdown files and collections in the Pasture vault (~/.pasture/), read-only.",
                inputSchema: InputSchema(properties: [:], required: [])),
            ToolDefinition(
                name: "read_file",
                description: "Return the raw contents of a single file in the vault, by path relative to ~/.pasture/.",
                inputSchema: InputSchema(
                    properties: ["path": PropertySchema(type: "string")],
                    required: ["path"])),
            ToolDefinition(
                name: "search",
                description: "Find files in the vault whose name or content contains a literal, case-insensitive query.",
                inputSchema: InputSchema(
                    properties: ["query": PropertySchema(type: "string")],
                    required: ["query"])),
            ToolDefinition(
                name: "feed_context",
                description: "Assemble vault context using Pasture's Feed format from a collection or a list of files.",
                inputSchema: InputSchema(
                    properties: [
                        "collection": PropertySchema(type: "string"),
                        "files": PropertySchema(type: "array", items: ItemSchema(type: "string")),
                    ],
                    required: [])),
        ]
        if includingProposals {
            tools.append(ToolDefinition(
                name: "propose_note",
                description: "Propose a NEW note for the vault. Does NOT write it: it is queued in a review inbox and requires explicit human approval before it lands in ~/.pasture/.",
                inputSchema: InputSchema(
                    properties: [
                        "filename": PropertySchema(type: "string"),
                        "content": PropertySchema(type: "string"),
                        "collection": PropertySchema(type: "string"),
                    ],
                    required: ["filename", "content"])))
            tools.append(ToolDefinition(
                name: "propose_append",
                description: "Propose appending text to an EXISTING vault file. Does NOT write it: it is queued in a review inbox and requires explicit human approval.",
                inputSchema: InputSchema(
                    properties: [
                        "path": PropertySchema(type: "string"),
                        "content": PropertySchema(type: "string"),
                    ],
                    required: ["path", "content"])))
        }
        return ToolsListResult(tools: tools)
    }

    // MARK: — Ejecución (tools/call)

    /// Despacho de `tools/call`. Devuelve `ToolCallResult` (`isError` de tool,
    /// nunca lanza). Un nombre de tool inválido es error de TOOL, no de protocolo.
    /// `proposedBy` = nombre del cliente MCP (del `initialize`), o "unknown".
    public static func run(params: JSONValue?, config: MCPServerConfig,
                           proposedBy: String = "unknown") -> ToolCallResult {
        guard let name = params?.object?["name"]?.stringValue else {
            return .failure("falta el nombre de la tool")
        }
        let arguments = params?.object?["arguments"]

        switch name {
        case "list_files":
            return listFiles(config: config)
        case "read_file":
            return readFile(arguments: arguments, config: config)
        case "search":
            return search(arguments: arguments, config: config)
        case "feed_context":
            return feedContext(arguments: arguments, config: config)
        // Tools de escritura: solo si el flag está activo; si no, "desconocida".
        case "propose_note" where config.allowProposals:
            return proposeNote(arguments: arguments, config: config, proposedBy: proposedBy)
        case "propose_append" where config.allowProposals:
            return proposeAppend(arguments: arguments, config: config, proposedBy: proposedBy)
        default:
            return .failure("tool desconocida: \(name)")
        }
    }

    // MARK: — Tools de escritura (v1.8 Memory Inbox)

    /// Directorio staging oculto, fuera de `FileLibrary`/feed/tools de lectura.
    static func inboxRoot(_ config: MCPServerConfig) -> URL {
        config.vaultRoot.appendingPathComponent(".inbox", isDirectory: true)
    }

    /// `propose_note`: encola una nota nueva en el inbox. Orden: validar args →
    /// cap tamaño → sanitizar nombre → validar destino (doble capa) → cap pendientes
    /// → escanear secretos → dedupe → guardar. Cualquier fallo = `isError`.
    static func proposeNote(arguments: JSONValue?, config: MCPServerConfig,
                            proposedBy: String) -> ToolCallResult {
        guard let rawName = arguments?.object?["filename"]?.stringValue, !rawName.isEmpty else {
            return .failure("se requiere el argumento 'filename'")
        }
        guard let content = arguments?.object?["content"]?.stringValue else {
            return .failure("se requiere el argumento 'content'")
        }
        if content.utf8.count > MCPLimits.maxProposalBytes {
            return .failure("propuesta demasiado grande (máximo \(MCPLimits.maxProposalBytes) bytes)")
        }
        let filename = FilenameSanitizer.sanitize(rawName)
        guard !filename.isEmpty else { return .failure("nombre de fichero inválido") }
        let collection = arguments?.object?["collection"]?.stringValue

        // Validación de destino con la misma doble capa que la lectura (SEC-M1/M2).
        let relPath = collection.map { "\($0)/\(filename)" } ?? filename
        if case .failure = MCPPathResolver.resolve(relativePath: relPath, vaultRoot: config.vaultRoot) {
            return .failure("ruta fuera del vault")
        }

        let inbox = inboxRoot(config)
        if ProposalStore.pendingCount(inboxRoot: inbox) >= MCPLimits.maxPendingProposals {
            return .failure("bandeja de propuestas llena (máximo \(MCPLimits.maxPendingProposals))")
        }

        let summary = secretSummary(fileName: filename, content: content)
        let proposal = Proposal.note(filename: filename, collection: collection, content: content,
                                     proposedBy: proposedBy, secretSummary: summary)
        if ProposalStore.contains(payloadHash: proposal.payloadHash,
                                  destinationKey: proposal.destinationKey, inboxRoot: inbox) {
            return .failure("propuesta duplicada (mismo contenido y destino)")
        }

        do {
            try ProposalStore.save(proposal, payload: content, inboxRoot: inbox)
        } catch {
            return .failure("no se pudo guardar la propuesta")
        }
        return .ok("Proposal queued in review inbox (awaiting human approval): \(filename)",
                   warning: proposalSecretWarning(summary))
    }

    /// `propose_append`: encola un añadido a un fichero EXISTENTE. El destino debe
    /// existir y no ser un symlink; se graba el `targetHash` del contenido actual
    /// para detectar cambios en el momento de la aprobación.
    static func proposeAppend(arguments: JSONValue?, config: MCPServerConfig,
                              proposedBy: String) -> ToolCallResult {
        guard let path = arguments?.object?["path"]?.stringValue, !path.isEmpty else {
            return .failure("se requiere el argumento 'path'")
        }
        guard let content = arguments?.object?["content"]?.stringValue else {
            return .failure("se requiere el argumento 'content'")
        }
        if content.utf8.count > MCPLimits.maxProposalBytes {
            return .failure("propuesta demasiado grande (máximo \(MCPLimits.maxProposalBytes) bytes)")
        }

        // El destino no debe ser un symlink (defensa extra sobre la doble capa).
        let candidate = config.vaultRoot.appendingPathComponent(path)
        if (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            return .failure("el destino es un symlink")
        }
        let resolved: URL
        switch MCPPathResolver.resolve(relativePath: path, vaultRoot: config.vaultRoot) {
        case .failure: return .failure("ruta fuera del vault")
        case .success(let url): resolved = url
        }
        guard let current = try? String(contentsOf: resolved, encoding: .utf8) else {
            return .failure("el fichero destino no existe")
        }

        let inbox = inboxRoot(config)
        if ProposalStore.pendingCount(inboxRoot: inbox) >= MCPLimits.maxPendingProposals {
            return .failure("bandeja de propuestas llena (máximo \(MCPLimits.maxPendingProposals))")
        }

        let summary = secretSummary(fileName: resolved.lastPathComponent, content: content)
        let proposal = Proposal.append(relativePath: path, content: content,
                                       targetHash: SyncMarker.sha256(current),
                                       proposedBy: proposedBy, secretSummary: summary)
        if ProposalStore.contains(payloadHash: proposal.payloadHash,
                                  destinationKey: proposal.destinationKey, inboxRoot: inbox) {
            return .failure("propuesta duplicada (mismo contenido y destino)")
        }

        do {
            try ProposalStore.save(proposal, payload: content, inboxRoot: inbox)
        } catch {
            return .failure("no se pudo guardar la propuesta")
        }
        return .ok("Append proposal queued in review inbox (awaiting human approval): \(path)",
                   warning: proposalSecretWarning(summary))
    }

    /// Resumen enmascarado de secretos del payload (familia + fichero), o `nil`.
    static func secretSummary(fileName: String, content: String) -> String? {
        let result = SecretScanner.scan(fileName: fileName, content: content)
        return result.isEmpty ? nil : result.summaryLines().joined(separator: "; ")
    }

    /// Aviso no bloqueante para el `ToolCallResult` a partir del resumen (o `nil`).
    static func proposalSecretWarning(_ summary: String?) -> String? {
        summary.map { "possible secrets detected (proposal stored, needs human approval): \($0)" }
    }

    // MARK: — Implementación de tools (rellenadas por TDD en bloques 4-7)

    static func listFiles(config: MCPServerConfig) -> ToolCallResult {
        // Enumeración SOLO vía FileLibrary (SEC-M2): ya filtra ocultos y symlinks.
        // Síncrono: usamos mdFiles/realSubdirectories directamente, sin el puente
        // async de load(at:) (ADR-005, loop secuencial).
        let files = enumerateVaultFiles(vaultRoot: config.vaultRoot)

        guard !files.isEmpty else {
            return .ok("(vault is empty: no Markdown files found)")
        }

        let lines = files.map { entry -> String in
            if let collection = entry.collection {
                return "\(entry.relativePath)  [collection: \(collection)]"
            }
            return "\(entry.relativePath)  [root]"
        }
        return .ok(lines.joined(separator: "\n"))
    }

    /// Fichero del vault con su ruta relativa y colección. Vía FileLibrary,
    /// que filtra ocultos y symlinks (SEC-M2). Raíz + subdirectorios de 1 nivel.
    struct VaultFile {
        let url: URL
        let relativePath: String
        let collection: String?
    }

    static func enumerateVaultFiles(vaultRoot: URL) -> [VaultFile] {
        var entries: [VaultFile] = []
        let basePath = vaultRoot.standardizedFileURL.path

        func relative(_ url: URL) -> String {
            let full = url.standardizedFileURL.path
            if full.hasPrefix(basePath + "/") {
                return String(full.dropFirst(basePath.count + 1))
            }
            return url.lastPathComponent
        }

        for file in FileLibrary.mdFiles(in: vaultRoot) {
            entries.append(VaultFile(url: file.url, relativePath: relative(file.url), collection: nil))
        }
        for subdir in FileLibrary.realSubdirectories(in: vaultRoot) {
            let collectionName = subdir.lastPathComponent
            for file in FileLibrary.mdFiles(in: subdir) {
                entries.append(VaultFile(
                    url: file.url, relativePath: relative(file.url), collection: collectionName))
            }
        }
        return entries
    }

    static func readFile(arguments: JSONValue?, config: MCPServerConfig) -> ToolCallResult {
        guard let path = arguments?.object?["path"]?.stringValue, !path.isEmpty else {
            return .failure("se requiere el argumento 'path'")
        }

        // SEC-M1 + SEC-M2: validar ANTES de cualquier I/O, con resolución de symlinks.
        let resolved: URL
        switch MCPPathResolver.resolve(relativePath: path, vaultRoot: config.vaultRoot) {
        case .success(let url):
            resolved = url
        case .failure:
            return .failure("ruta fuera del vault")
        }

        // SEC-M5: rechazar por TAMAÑO EN DISCO antes de leer, para no materializar un
        // fichero gigante en RAM sólo para descartarlo después.
        if let onDisk = fileSizeOnDisk(resolved), onDisk > MCPLimits.maxResponseBytes {
            return .failure("fichero demasiado grande, no se puede entregar")
        }

        guard let content = try? String(contentsOf: resolved, encoding: .utf8) else {
            return .failure("fichero no encontrado")
        }

        // SEC-M5: segunda barrera exacta sobre los bytes UTF-8 ya cargados.
        if content.utf8.count > MCPLimits.maxResponseBytes {
            return .failure("fichero demasiado grande, no se puede entregar")
        }

        // SEC-M8 (D4): warning no bloqueante (secretos + staleness). Contenido íntegro.
        // La fecha de modificación es la referencia cuando no hay `last_reviewed`.
        let reference = (try? resolved.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let warning = joinWarnings([
            secretWarning(fileName: resolved.lastPathComponent, content: content),
            stalenessWarning(content: content, reference: reference),
        ])
        return .ok(content, warning: warning)
    }

    /// SEC-M8 (v1.7): anotación de frescura no bloqueante. Devuelve
    /// "stale: N days since last review" si la nota caducó (frontmatter
    /// `review_after`/`ttl`), o `nil`. Nunca altera el contenido (read-only).
    static func stalenessWarning(content: String, reference: Date, now: Date = Date()) -> String? {
        let frontmatter = FrontmatterParser.parse(content).frontmatter
        if case .expired(let days) = Freshness.state(frontmatter: frontmatter, reference: reference, now: now) {
            return "stale: \(days) days since last review"
        }
        return nil
    }

    /// Une avisos no nulos con el separador ' | ' (mismo estilo que combinedWarning).
    static func joinWarnings(_ parts: [String?]) -> String? {
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.joined(separator: " | ")
    }

    /// SEC-M5: tamaño en disco (bytes) de un fichero, o `nil` si no se puede leer.
    /// Permite rechazar ficheros gigantes ANTES de materializarlos en RAM.
    static func fileSizeOnDisk(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// SEC-M8 (D4): resumen enmascarado de secretos (familia + fichero), NUNCA el
    /// valor. Devuelve `nil` si el contenido está limpio. Reutiliza `SecretScanner`.
    static func secretWarning(fileName: String, content: String) -> String? {
        let result = SecretScanner.scan(fileName: fileName, content: content)
        guard !result.isEmpty else { return nil }
        let summary = result.summaryLines().joined(separator: "; ")
        return "possible secrets detected (content delivered unchanged): \(summary)"
    }

    static func search(arguments: JSONValue?, config: MCPServerConfig) -> ToolCallResult {
        guard let query = arguments?.object?["query"]?.stringValue else {
            return .failure("se requiere el argumento 'query'")
        }

        // SEC-M4: cap de longitud de query.
        if query.count > MCPLimits.maxQueryLength {
            return .failure("query demasiado larga (máximo \(MCPLimits.maxQueryLength) caracteres)")
        }

        // HU-10: query vacía NO vuelca el vault. Se intercepta ANTES de matches
        // (que devolvería true para todo). Resultado vacío con éxito.
        guard !query.isEmpty else {
            return .ok("(empty query: no results)")
        }

        let files = enumerateVaultFiles(vaultRoot: config.vaultRoot)
        var matched: [String] = []
        for entry in files {
            if matchesLiteral(query: query, fileURL: entry.url) {
                matched.append(entry.relativePath)
                // SEC-M4: cap de resultados.
                if matched.count >= MCPLimits.maxSearchResults { break }
            }
        }

        guard !matched.isEmpty else {
            return .ok("(no files match \"\(query)\")")
        }
        return .ok(matched.joined(separator: "\n"))
    }

    /// Misma semántica que `MDFile.matches` (literal, case-insensitive sobre
    /// nombre y contenido), pero leyendo el contenido ACOTADO (SEC-M4) en lugar de
    /// cargar ficheros enormes completos en RAM. El cap de 2 MB por fichero lo
    /// aplica `SecretScanner.cappedContent`, que vive en `SecretScanner.maxScanBytes`
    /// (no en `MCPLimits`): reusamos su truncado seguro de UTF-8 en vez de duplicarlo.
    static func matchesLiteral(query: String, fileURL: URL) -> Bool {
        let name = fileURL.deletingPathExtension().lastPathComponent
        if name.localizedCaseInsensitiveContains(query) { return true }
        guard let full = try? String(contentsOf: fileURL, encoding: .utf8) else { return false }
        let content = SecretScanner.cappedContent(full)   // SecretScanner.maxScanBytes (2 MB)
        return content.localizedCaseInsensitiveContains(query)
    }

    static func feedContext(arguments: JSONValue?, config: MCPServerConfig) -> ToolCallResult {
        let collection = arguments?.object?["collection"]?.stringValue
        let fileNames = arguments?.object?["files"]?.arrayValue?.compactMap { $0.stringValue }

        let hasFiles = !(fileNames?.isEmpty ?? true)
        let hasCollection = !(collection?.isEmpty ?? true)

        // HU-7: ni collection ni files → error de tool.
        guard hasFiles || hasCollection else {
            return .failure("se requiere 'collection' o 'files'")
        }

        // D2: si se pasan ambos, gana 'files' (más específica).
        let selection: FeedSelection
        if hasFiles {
            selection = resolveFileList(fileNames ?? [], config: config)
        } else {
            guard let resolved = resolveCollection(collection ?? "", config: config) else {
                return .failure("colección no encontrada: \(collection ?? "")")
            }
            selection = resolved
        }

        guard !selection.entries.isEmpty else {
            return .failure("no se encontró ningún fichero para ensamblar")
        }

        // SEC-M6: ensamblado EXCLUSIVAMENTE vía ContextBuilder (misma pieza que la app).
        // D3: contenido crudo — NO se llama a TemplateEngine.render.
        let payload = ContextBuilder.build(files: selection.entries, format: config.feedFormat)

        // SEC-M5: rechazar respuestas gigantes antes de serializar.
        if payload.utf8.count > MCPLimits.maxResponseBytes {
            return .failure("contexto demasiado grande, refina la selección")
        }

        // SEC-M8 (D4): warning combinado (secretos + ficheros ausentes), no bloqueante.
        let warning = combinedWarning(selection: selection)
        return .ok(payload, warning: warning)
    }

    /// Selección resuelta para feed_context: entries en orden + avisos de ausentes.
    struct FeedSelection {
        var entries: [ContextBuilder.FileEntry]
        /// Para SEC-M8: (fileName, content) de cada entry, para el escaneo de secretos.
        var scanned: [(name: String, content: String)]
        var missing: [String]
        /// v1.7: ficheros caducados, ya formateados "file.md (120d)".
        var stale: [String] = []
    }

    /// HU-7: lista de ficheros por nombre. Cada uno pasa el gate de ruta
    /// (SEC-M1/M2). Los ausentes/fuera se OMITEN y se listan como aviso (no falla
    /// en bloque). Orden preservado.
    static func resolveFileList(_ names: [String], config: MCPServerConfig) -> FeedSelection {
        var entries: [ContextBuilder.FileEntry] = []
        var scanned: [(name: String, content: String)] = []
        var missing: [String] = []
        var stale: [String] = []

        for name in names {
            switch MCPPathResolver.resolve(relativePath: name, vaultRoot: config.vaultRoot) {
            case .failure:
                missing.append(name)
            case .success(let url):
                // SEC-M5: omitir ficheros que por sí solos ya exceden el cap de respuesta,
                // sin cargarlos en RAM. El check final del payload ensamblado sigue en
                // feedContext; esto evita el pico de memoria por un único fichero gigante.
                if let onDisk = fileSizeOnDisk(url), onDisk > MCPLimits.maxResponseBytes {
                    missing.append(name)
                    continue
                }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                    missing.append(name)
                    continue
                }
                // FileEntry.name SIN extensión: ContextBuilder añade ".md".
                let entryName = url.deletingPathExtension().lastPathComponent
                entries.append(ContextBuilder.FileEntry(name: entryName, content: content))
                scanned.append((name: url.lastPathComponent, content: content))
                if let staleLabel = staleLabel(content: content, url: url) { stale.append(staleLabel) }
            }
        }
        return FeedSelection(entries: entries, scanned: scanned, missing: missing, stale: stale)
    }

    /// v1.7: etiqueta "file.md (Nd)" si la nota caducó, o `nil`. Referencia = fecha
    /// de modificación del fichero (fallback de `Freshness`).
    static func staleLabel(content: String, url: URL) -> String? {
        let reference = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        let frontmatter = FrontmatterParser.parse(content).frontmatter
        if case .expired(let days) = Freshness.state(frontmatter: frontmatter, reference: reference, now: Date()) {
            return "\(url.lastPathComponent) (\(days)d)"
        }
        return nil
    }

    /// HU-6: colección. Devuelve `nil` si no es un subdirectorio real. Symlinks
    /// ya filtrados por FileLibrary (SEC-M2).
    static func resolveCollection(_ name: String, config: MCPServerConfig) -> FeedSelection? {
        let subdirs = FileLibrary.realSubdirectories(in: config.vaultRoot)
        guard let dir = subdirs.first(where: { $0.lastPathComponent == name }) else {
            return nil
        }
        var entries: [ContextBuilder.FileEntry] = []
        var scanned: [(name: String, content: String)] = []
        var stale: [String] = []
        for file in FileLibrary.mdFiles(in: dir) {
            // FileEntry.name SIN extensión (MDFile.name ya viene sin ".md").
            entries.append(ContextBuilder.FileEntry(name: file.name, content: file.content))
            scanned.append((name: file.url.lastPathComponent, content: file.content))
            // MDFile ya trae frontmatter y modifiedDate: reusamos freshness().
            if case .expired(let days) = file.freshness(now: Date()) {
                stale.append("\(file.url.lastPathComponent) (\(days)d)")
            }
        }
        return FeedSelection(entries: entries, scanned: scanned, missing: [], stale: stale)
    }

    /// SEC-M8 + HU-7: combina el aviso de secretos (familia + fichero, sin valor)
    /// y el de ficheros ausentes. `nil` si no hay nada que avisar.
    static func combinedWarning(selection: FeedSelection) -> String? {
        var parts: [String] = []

        let scanResult = SecretScanner.scan(
            selection.scanned.map { SecretScanner.Input(fileName: $0.name, content: $0.content) })
        if !scanResult.isEmpty {
            parts.append("possible secrets detected (content delivered unchanged): "
                + scanResult.summaryLines().joined(separator: "; "))
        }
        if !selection.missing.isEmpty {
            parts.append("files not found (omitted): " + selection.missing.joined(separator: ", "))
        }
        if !selection.stale.isEmpty {
            parts.append("stale since last review: " + selection.stale.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }
}
