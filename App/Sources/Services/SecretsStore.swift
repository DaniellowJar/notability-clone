import CryptoKit
import Foundation
import Security

/// Secret storage abstraction. Keys live in the Keychain only (Build prompt §9):
/// never UserDefaults, never source, never logs.
protocol SecretsStore {
    func setSecret(_ value: String, for service: String) throws
    func secret(for service: String) -> String?
    func deleteSecret(for service: String) throws
}

enum SecretsService {
    static let deepInfra = "deepinfra"
    static let ownCloudURL = "owncloud-url"
    static let ownCloudUser = "owncloud-user"
    static let ownCloudPassword = "owncloud-password"
}

/// Keychain-backed primary store. Works under LiveContainer (the container is
/// allocated a keychain access group; no entitlements required for SecItem).
final class KeychainSecretsStore: SecretsStore {
    enum KeychainError: Error {
        case status(OSStatus)
    }

    func setSecret(_ value: String, for service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func secret(for service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(for service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}

/// Encrypted-file store used as a unit-testable stand-in and as a documented
/// fallback if the Keychain is ever unavailable. The symmetric key is injected
/// (in production it would be a Keychain-stored key — not UserDefaults).
final class FileSecretsStore: SecretsStore {
    private let fileURL: URL
    private let key: SymmetricKey

    init(directory: URL, key: SymmetricKey) {
        self.fileURL = directory.appendingPathComponent("secrets.bin")
        self.key = key
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func setSecret(_ value: String, for service: String) throws {
        var entries = load()
        entries[service] = value
        let box = try ChaChaPoly.seal(try JSONEncoder().encode(entries), using: key)
        try box.combined.write(to: fileURL, options: .atomic)
    }

    func secret(for service: String) -> String? {
        load()[service]
    }

    func deleteSecret(for service: String) throws {
        var entries = load()
        entries.removeValue(forKey: service)
        let box = try ChaChaPoly.seal(try JSONEncoder().encode(entries), using: key)
        try box.combined.write(to: fileURL, options: .atomic)
    }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let box = try? ChaChaPoly.SealedBox(combined: data),
              let plain = try? ChaChaPoly.open(box, using: key),
              let entries = try? JSONDecoder().decode([String: String].self, from: plain)
        else { return [:] }
        return entries
    }
}

/// Facade the app talks to.
final class AppSecrets {
    static let shared = AppSecrets()
    private let store: SecretsStore

    init(store: SecretsStore = KeychainSecretsStore()) {
        self.store = store
    }

    var deepInfraKey: String? { store.secret(for: SecretsService.deepInfra) }
    var isConfigured: Bool { !(deepInfraKey?.isEmpty ?? true) }

    func saveDeepInfraKey(_ key: String) throws {
        try store.setSecret(key, for: SecretsService.deepInfra)
    }

    var ownCloudURL: String? { store.secret(for: SecretsService.ownCloudURL) }
    var ownCloudUser: String? { store.secret(for: SecretsService.ownCloudUser) }
    var ownCloudPassword: String? { store.secret(for: SecretsService.ownCloudPassword) }

    func saveOwnCloud(url: String, user: String, password: String) throws {
        try store.setSecret(url, for: SecretsService.ownCloudURL)
        try store.setSecret(user, for: SecretsService.ownCloudUser)
        try store.setSecret(password, for: SecretsService.ownCloudPassword)
    }
}
