import Foundation

/// Límites numéricos de seguridad del servidor MCP (threat model §5).
///
/// El threat model es explícito: lo innegociable es que EXISTA un límite en cada
/// eje; el valor es un default defendible. Centralizados aquí para que cada uno
/// sea visible, testeable y ajustable en un solo sitio.
public enum MCPLimits {
    /// SEC-M3: tamaño máximo de una línea/mensaje de entrada por stdin.
    /// Un `tools/call` legítimo es de KB; 10 MB es holgura de ~1000×.
    public static let maxInputLineBytes = 10_000_000   // 10 MB

    // SEC-M4 — cap de bytes leídos por fichero en `search`: NO vive aquí. El
    // truncado seguro de UTF-8 lo aplica `SecretScanner.cappedContent`
    // (`SecretScanner.maxScanBytes`, 2 MB), reutilizado en `MCPTools.matchesLiteral`
    // para no duplicar la lógica de truncado. Ver `MCPTools.matchesLiteral`.

    /// SEC-M4: número máximo de ficheros devueltos por `search`.
    public static let maxSearchResults = 100

    /// SEC-M4: longitud máxima de la query de `search`.
    public static let maxQueryLength = 1_000

    /// SEC-M5: tamaño máximo de la respuesta ensamblada de `read_file`/`feed_context`.
    /// Por encima → `isError`, sin serializar el gigante.
    public static let maxResponseBytes = 25_000_000   // 25 MB
}
