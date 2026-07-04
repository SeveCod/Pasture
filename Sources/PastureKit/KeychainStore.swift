import Foundation
import Security

public enum KeychainStore {

    public static func save(key: String, value: String, service: String = "com.sevecod.pasture") throws {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let existing = SecItemCopyMatching(query as CFDictionary, nil)
        if existing == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.unhandled(status)
            }
        } else {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unhandled(status)
            }
        }
    }

    /// Devuelve el valor almacenado, o `nil` si no existe **o** si el llavero no es
    /// accesible (dispositivo bloqueado, acceso denegado). Colapsar ambos casos a `nil`
    /// es una decisión deliberada: para una app de escritorio personal, un llavero
    /// inaccesible se presenta como "sin clave configurada", un estado recuperable
    /// (el usuario vuelve a introducirla) en lugar de un error propagado.
    public static func load(key: String, service: String = "com.sevecod.pasture") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    /// Borra la entrada. Devuelve `true` si se borró o si no existía (ambos son el
    /// estado deseado: "ya no está"); `false` sólo ante un fallo real del llavero, para
    /// que el llamante pueda detectarlo en vez de creer que borró cuando no fue así.
    @discardableResult
    public static func delete(key: String, service: String = "com.sevecod.pasture") -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public enum KeychainError: Error, LocalizedError, Sendable {
        case unhandled(OSStatus)

        public var errorDescription: String? {
            "Keychain error: \(SecCopyErrorMessageString(osStatus, nil) as String? ?? "unknown")"
        }

        private var osStatus: OSStatus {
            switch self { case .unhandled(let s): return s }
        }
    }
}
