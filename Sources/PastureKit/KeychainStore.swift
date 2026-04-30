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

    public static func delete(key: String, service: String = "com.sevecod.pasture") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
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
