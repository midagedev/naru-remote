import Foundation
import Security

public protocol ConnectionCredentialStoreProtocol: Sendable {
    func savePassword(_ password: String, for credentialRef: String) async throws
    func password(for credentialRef: String) async throws -> String?
    func deletePassword(for credentialRef: String) async throws
}

public enum ConnectionCredentialStoreError: Error, Equatable, LocalizedError {
    case emptyCredentialRef
    case invalidPasswordData
    case keychainStatus(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptyCredentialRef:
            "Credential reference is required."
        case .invalidPasswordData:
            "Stored credential could not be decoded."
        case .keychainStatus(let status):
            "Keychain operation failed with status \(status)."
        }
    }
}

public actor InMemoryConnectionCredentialStore: ConnectionCredentialStoreProtocol {
    private var passwords: [String: String]

    public init(passwords: [String: String] = [:]) {
        self.passwords = passwords
    }

    public func savePassword(_ password: String, for credentialRef: String) throws {
        let key = try Self.normalizedCredentialRef(credentialRef)
        passwords[key] = password
    }

    public func password(for credentialRef: String) throws -> String? {
        let key = try Self.normalizedCredentialRef(credentialRef)
        return passwords[key]
    }

    public func deletePassword(for credentialRef: String) throws {
        let key = try Self.normalizedCredentialRef(credentialRef)
        passwords.removeValue(forKey: key)
    }

    private static func normalizedCredentialRef(_ credentialRef: String) throws -> String {
        let normalized = credentialRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConnectionCredentialStoreError.emptyCredentialRef
        }

        return normalized
    }
}

/// `KeychainConnectionCredentialStore` has no mutable state — only the
/// immutable `service` string — and Keychain APIs (`SecItemAdd`,
/// `SecItemCopyMatching`, `SecItemDelete`) are documented thread-safe.
/// It is therefore a plain `Sendable final class`; it does not need
/// actor isolation or `@unchecked Sendable`.  The protocol's `async`
/// methods are satisfied by `nonisolated` async stubs that perform
/// the synchronous Keychain calls on the calling actor's context.
public final class KeychainConnectionCredentialStore: ConnectionCredentialStoreProtocol, Sendable {
    private let service: String

    public init(service: String = "com.naruremote.vnc-password") {
        self.service = service
    }

    public func savePassword(_ password: String, for credentialRef: String) async throws {
        let key = try Self.normalizedCredentialRef(credentialRef)
        let data = Data(password.utf8)
        var query = baseQuery(for: key)

        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConnectionCredentialStoreError.keychainStatus(status)
        }
    }

    public func password(for credentialRef: String) async throws -> String? {
        let key = try Self.normalizedCredentialRef(credentialRef)
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw ConnectionCredentialStoreError.keychainStatus(status)
        }

        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw ConnectionCredentialStoreError.invalidPasswordData
        }

        return password
    }

    public func deletePassword(for credentialRef: String) async throws {
        let key = try Self.normalizedCredentialRef(credentialRef)
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ConnectionCredentialStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(for credentialRef: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: credentialRef
        ]
    }

    private static func normalizedCredentialRef(_ credentialRef: String) throws -> String {
        let normalized = credentialRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConnectionCredentialStoreError.emptyCredentialRef
        }

        return normalized
    }
}
