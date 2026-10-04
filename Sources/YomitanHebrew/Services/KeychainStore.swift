import Foundation
import Security

enum KeychainStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.yomitanforhebrew.app"

    static func value(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        guard !value.isEmpty else {
            SecItemDelete(identity as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let updates = [kSecValueData as String: data]
        if SecItemUpdate(identity as CFDictionary, updates as CFDictionary) == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
