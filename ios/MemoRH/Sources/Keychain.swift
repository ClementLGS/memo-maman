import Foundation
import Security

/// Jeton GitHub de la sauvegarde : rangé dans le trousseau iOS, jamais relu par la page (elle ne peut que l'écrire ou l'effacer).
enum Keychain {
    private static let service = "com.clement.memorh.github"
    private static let account = "token"

    private static var base: [String: Any] {
        return [kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account]
    }

    static func set(_ value: String) -> Bool {
        delete()
        var q = base
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func get() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    @discardableResult
    static func delete() -> Bool {
        let s = SecItemDelete(base as CFDictionary)
        return s == errSecSuccess || s == errSecItemNotFound
    }
}
