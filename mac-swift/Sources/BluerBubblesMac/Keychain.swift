import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case read(OSStatus)
    case write(OSStatus)
    case invalidValue

    var errorDescription: String? {
        switch self {
        case .read(let status): "keychain read failed: \(status)"
        case .write(let status): "keychain write failed: \(status)"
        case .invalidValue: "keychain value is not valid UTF-8"
        }
    }
}

struct Keychain: Sendable {
    private static let service = "bluer-bubbles"
    private static let account = "mac-api-key"

    static func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.read(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.invalidValue
        }

        guard let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidValue
        }

        return value
    }

    static func store(_ value: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(
            (query.merging(attributes) { _, new in new }) as CFDictionary,
            nil
        )

        if status == errSecDuplicateItem {
            let updateStatus = SecItemUpdate(
                query as CFDictionary,
                attributes as CFDictionary
            )

            guard updateStatus == errSecSuccess else {
                throw KeychainError.write(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.write(status)
        }
    }
}
