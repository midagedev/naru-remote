import Foundation
import Security

public protocol ConnectionCredentialStoreProtocol: Sendable {
    func savePassword(_ password: String, for credentialRef: String) throws
    func password(for credentialRef: String) throws -> String?
    func deletePassword(for credentialRef: String) throws
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

public final class InMemoryConnectionCredentialStore: ConnectionCredentialStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var passwords: [String: String]

    public init(passwords: [String: String] = [:]) {
        self.passwords = passwords
    }

    public func savePassword(_ password: String, for credentialRef: String) throws {
        let key = try normalizedCredentialRef(credentialRef)
        lock.lock()
        passwords[key] = password
        lock.unlock()
    }

    public func password(for credentialRef: String) throws -> String? {
        let key = try normalizedCredentialRef(credentialRef)
        lock.lock()
        defer { lock.unlock() }
        return passwords[key]
    }

    public func deletePassword(for credentialRef: String) throws {
        let key = try normalizedCredentialRef(credentialRef)
        lock.lock()
        passwords.removeValue(forKey: key)
        lock.unlock()
    }

    private func normalizedCredentialRef(_ credentialRef: String) throws -> String {
        let normalized = credentialRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConnectionCredentialStoreError.emptyCredentialRef
        }

        return normalized
    }
}

public final class KeychainConnectionCredentialStore: ConnectionCredentialStoreProtocol, @unchecked Sendable {
    private let service: String

    public init(service: String = "com.naruremote.vnc-password") {
        self.service = service
    }

    public func savePassword(_ password: String, for credentialRef: String) throws {
        let key = try normalizedCredentialRef(credentialRef)
        let data = Data(password.utf8)
        var query = baseQuery(for: key)

        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ConnectionCredentialStoreError.keychainStatus(status)
        }
    }

    public func password(for credentialRef: String) throws -> String? {
        let key = try normalizedCredentialRef(credentialRef)
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

    public func deletePassword(for credentialRef: String) throws {
        let key = try normalizedCredentialRef(credentialRef)
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

    private func normalizedCredentialRef(_ credentialRef: String) throws -> String {
        let normalized = credentialRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ConnectionCredentialStoreError.emptyCredentialRef
        }

        return normalized
    }
}
