import Foundation

/// Primitiva MCP `resources`: cada `.md` del vault se expone como resource
/// nativo, adjuntable/@-mencionable en clientes que lo soporten.
///
/// Solo lectura (SEC-M11): `list` enumera vía `MCPTools.enumerateVaultFiles`
/// (FileLibrary ya filtra ocultos y symlinks) y `read` valida la uri con las dos
/// capas de `MCPPathResolver` (SEC-M1 `..`, SEC-M2 symlink) ANTES de cualquier
/// I/O. Cero código nuevo de enumeración de disco (ADR reusa la fuente única).
///
/// A diferencia de las tools, `resources/read` no tiene canal `isError`: un fallo
/// es un error JSON-RPC de protocolo (`MCPRequestError`, -32602), que el
/// dispatcher traduce a una línea de error sin tumbar la conexión (SEC-M12).
public enum MCPResources {

    /// Esquema uri del vault. `pasture:///<ruta-relativa>` (tres barras = scheme
    /// + authority vacía + path). Es el ÚNICO esquema aceptado por `read`.
    static let uriScheme = "pasture://"

    // MARK: — Tipos de resultado

    public struct ResourcesListResult: Encodable {
        public struct ResourceDescriptor: Encodable {
            public let uri: String
            public let name: String
            public let mimeType: String
        }
        public let resources: [ResourceDescriptor]
    }

    public struct ResourceReadResult: Encodable {
        public struct ResourceContents: Encodable {
            public let uri: String
            public let mimeType: String
            public let text: String
        }
        public let contents: [ResourceContents]
    }

    // MARK: — uri ⇄ ruta relativa

    /// uri canónica de un resource a partir de su ruta relativa al vault.
    static func uri(forRelativePath relativePath: String) -> String {
        uriScheme + "/" + relativePath
    }

    /// Extrae la ruta relativa de una uri `pasture:///…`. Devuelve `nil` si el
    /// esquema no es `pasture://` (rechaza `file://`, absolutas ajenas, etc.).
    /// No valida traversal aquí: eso lo hace `MCPPathResolver` sobre el resultado.
    static func relativePath(fromURI uri: String) -> String? {
        guard uri.hasPrefix(uriScheme) else { return nil }
        var rest = String(uri.dropFirst(uriScheme.count))
        // `pasture:///notas.md` → "/notas.md"; quitar una sola barra de authority.
        // `pasture:////etc` → "//etc" → "/etc", que MCPPathResolver rechaza por
        // absoluta (defensa en profundidad).
        if rest.hasPrefix("/") { rest.removeFirst() }
        return rest
    }

    // MARK: — resources/list

    /// Enumera todos los `.md` del vault como resources. Orden = el de
    /// `enumerateVaultFiles` (raíz + subdirectorios de 1 nivel).
    public static func list(config: MCPServerConfig) -> ResourcesListResult {
        let files = MCPTools.enumerateVaultFiles(vaultRoot: config.vaultRoot)
        let resources = files.map { entry in
            ResourcesListResult.ResourceDescriptor(
                uri: uri(forRelativePath: entry.relativePath),
                name: entry.relativePath,
                mimeType: "text/markdown")
        }
        return ResourcesListResult(resources: resources)
    }

    // MARK: — resources/read

    /// Lee un resource por su uri. Valida esquema + traversal + symlink + tamaño
    /// ANTES de materializar contenido en RAM (SEC-M1/M2/M5). Todo fallo es
    /// `MCPRequestError` de protocolo.
    public static func read(params: JSONValue?, config: MCPServerConfig) -> Result<ResourceReadResult, MCPRequestError> {
        guard let uriString = params?.object?["uri"]?.stringValue, !uriString.isEmpty else {
            return .failure(.invalidParams("se requiere el argumento 'uri'"))
        }

        guard let relative = relativePath(fromURI: uriString) else {
            return .failure(.invalidParams("esquema de uri no soportado (se espera pasture://)"))
        }

        // SEC-M1 + SEC-M2: validar ANTES de cualquier I/O, con resolución de symlinks.
        let resolved: URL
        switch MCPPathResolver.resolve(relativePath: relative, vaultRoot: config.vaultRoot) {
        case .success(let url):
            resolved = url
        case .failure:
            return .failure(.invalidParams("ruta fuera del vault"))
        }

        // SEC-M5: rechazar por TAMAÑO EN DISCO antes de leer (patrón de read_file).
        if let onDisk = MCPTools.fileSizeOnDisk(resolved), onDisk > MCPLimits.maxResponseBytes {
            return .failure(.invalidParams("recurso demasiado grande, no se puede entregar"))
        }

        guard let content = try? String(contentsOf: resolved, encoding: .utf8) else {
            return .failure(.invalidParams("recurso no encontrado"))
        }

        // SEC-M5: segunda barrera exacta sobre los bytes UTF-8 ya cargados.
        if content.utf8.count > MCPLimits.maxResponseBytes {
            return .failure(.invalidParams("recurso demasiado grande, no se puede entregar"))
        }

        let result = ResourceReadResult(contents: [
            ResourceReadResult.ResourceContents(
                uri: uriString, mimeType: "text/markdown", text: content),
        ])
        return .success(result)
    }
}
