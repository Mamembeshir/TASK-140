import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.forgeflow.app"

    static func save(data: Data, forKey key: String) throws {
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess { return }

        // Fallback: simulator may lack keychain entitlement (-34018)
        #if DEBUG
        UserDefaults.standard.set(data, forKey: "kc_fallback_\(key)")
        #else
        throw KeychainError.saveFailed(status: status)
        #endif
    }

    static func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return data
        }

        // Fallback: check UserDefaults (debug simulator)
        #if DEBUG
        return UserDefaults.standard.data(forKey: "kc_fallback_\(key)")
        #else
        return nil
        #endif
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        #if DEBUG
        UserDefaults.standard.removeObject(forKey: "kc_fallback_\(key)")
        #endif
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        }
    }
}
