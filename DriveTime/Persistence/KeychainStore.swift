import Foundation
import Security

protocol KeychainStoring: AnyObject {
    func read(key: String) -> String?
    func write(_ value: String, key: String) throws
    func delete(key: String)
}

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case invalidData
}

/// Minimal generic-password Keychain store. Used only for the optional
/// DriveTime proxy access token; no AMap Web Service key is ever shipped in the
/// app or stored in UserDefaults.
final class KeychainStore: KeychainStoring {
    private let service: String

    init(service: String = "com.example.drivetime.proxy") {
        self.service = service
    }

    func read(key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                AppLog.settings.error("Keychain read failed: \(status, privacy: .public)")
            }
            return nil
        }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    func write(_ value: String, key: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(key: key)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            for (key, value) in attributes {
                addQuery[key] = value
            }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(key: String) {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            AppLog.settings.error("Keychain delete failed: \(status, privacy: .public)")
        }
    }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
