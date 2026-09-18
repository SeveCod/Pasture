import Foundation

/// Un nodo plegable del sidebar: una colección con sus notas, o la raíz de la
/// vault (`name == nil`, *Uncategorized*).
public struct CollectionNode: Identifiable, Sendable, Hashable {
    /// Nombre de la colección; `nil` es la raíz de la vault.
    public let name: String?
    public let files: [MDFile]

    public init(name: String?, files: [MDFile]) {
        self.name = name
        self.files = files
    }

    /// Clave estable para la selección y para `CollectionExpansionStore`.
    /// Lleva prefijo para que una colección llamada "" no colisione con la raíz.
    public var id: String { name.map { "c:\($0)" } ?? "u:" }

    /// La identidad real del nodo es `id`; comparar por `(name, files)` haría
    /// que dos snapshots del mismo nodo con distinto contenido de fichero
    /// resultasen "distintos" cuando lo que importa aquí es qué colección es.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: CollectionNode, rhs: CollectionNode) -> Bool {
        lhs.id == rhs.id
    }

    public var isUncategorized: Bool { name == nil }

    public var fileCount: Int { files.count }

    public var totalTokens: Int { files.reduce(0) { $0 + $1.tokens } }
}

/// Agrupa la lista plana de notas en nodos de colección para el sidebar.
///
/// No ordena: preserva el orden de `files` (que llega ya ordenado por el criterio
/// activo) y el de `collections` (ya alfabético desde `MDFileManager`). Así el
/// criterio de orden vive en un solo sitio.
public enum SidebarTree {

    /// - Parameter hidingEmpty: descarta las colecciones sin ficheros. Se usa con
    ///   búsqueda activa, donde una colección sin coincidencias no aporta nada.
    public static func build(
        files: [MDFile],
        collections: [String],
        base: URL,
        hidingEmpty: Bool = false
    ) -> [CollectionNode] {
        var byCollection: [String: [MDFile]] = [:]
        var uncategorized: [MDFile] = []

        for file in files {
            if let name = file.collection(relativeTo: base) {
                byCollection[name, default: []].append(file)
            } else {
                uncategorized.append(file)
            }
        }

        var nodes: [CollectionNode] = []
        if !uncategorized.isEmpty {
            nodes.append(CollectionNode(name: nil, files: uncategorized))
        }
        for name in collections {
            let files = byCollection[name] ?? []
            if hidingEmpty && files.isEmpty { continue }
            nodes.append(CollectionNode(name: name, files: files))
        }
        return nodes
    }
}
