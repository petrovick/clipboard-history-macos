import Foundation
import Security

/// A store that loads and creates the history encryption key in the macOS Keychain.
protocol HistoryKeychainStoring {
    /// Loads the existing encryption key or creates and stores a new one.
    func loadOrCreateEncryptionKey() throws -> Data
}

/// Stores the history encryption key in the macOS Keychain.
final class KeychainStore: HistoryKeychainStoring {
    /// Errors thrown by keychain access.
    private enum Error: Swift.Error {
        case unexpectedItemData
        case unexpectedStatus(OSStatus)
    }

    private let service: String
    private let account: String
    private let keyByteCount: Int

    /// Creates a keychain store for the clipboard history encryption key.
    init(
        service: String = "OptionVClipboard",
        account: String = "history-encryption-key",
        keyByteCount: Int = 32
    ) {
        self.service = service
        self.account = account
        self.keyByteCount = keyByteCount
    }

    /// Loads the key from the Keychain or creates a new 32-byte key on first launch.
    func loadOrCreateEncryptionKey() throws -> Data {
        if let existingKey = try loadEncryptionKey() {
            return existingKey
        }

        let newKey = try makeEncryptionKey()
        try storeEncryptionKey(newKey)
        return newKey
    }

    private func loadEncryptionKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw Error.unexpectedItemData
            }

            guard data.count == keyByteCount else {
                throw Error.unexpectedItemData
            }

            return data
        case errSecItemNotFound:
            return nil
        default:
            throw Error.unexpectedStatus(status)
        }
    }

    private func storeEncryptionKey(_ key: Data) throws {
        let itemQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let addAttributes: [String: Any] = [
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let addStatus = SecItemAdd((itemQuery.merging(addAttributes, uniquingKeysWith: { _, new in new })) as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }

        if addStatus == errSecDuplicateItem {
            let updateAttributes: [String: Any] = [
                kSecValueData as String: key
            ]

            let updateStatus = SecItemUpdate(itemQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw Error.unexpectedStatus(updateStatus)
            }

            return
        }

        throw Error.unexpectedStatus(addStatus)
    }

    private func makeEncryptionKey() throws -> Data {
        var key = Data(count: keyByteCount)
        let status = key.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return errSecAllocate
            }

            return SecRandomCopyBytes(kSecRandomDefault, keyByteCount, baseAddress)
        }

        guard status == errSecSuccess else {
            throw Error.unexpectedStatus(status)
        }

        return key
    }
}
