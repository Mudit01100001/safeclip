import CryptoKit
import Foundation
import Security

public enum KeychainError: Error {
    /// The key exists but could not be read (ACL denial, corruption).
    /// `OSStatus` carries the Security framework code for diagnostics.
    case unreadable(OSStatus)
    case unexpectedData
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)
}

/// Owns the 32-byte master key in the macOS login Keychain.
///
/// The item is created with the default access control list, which trusts only
/// the creating application's code signature — other apps that try to read it
/// trigger a user-facing Keychain prompt instead of a silent read (PRD §8.2).
/// `kSecAttrSynchronizable` is explicitly false: the master key must never
/// sync to iCloud Keychain; TERMS §2 promises it never leaves the device.
///
/// Upgrade path (tracked in ROADMAP): once release builds are Developer ID
/// signed, move to the data-protection keychain (`kSecUseDataProtectionKeychain`)
/// with `kSecAttrAccessControl`, which enforces the signature in kernel rather
/// than via the ACL prompt. The data-protection keychain requires a stable
/// application identifier, which ad-hoc/dev builds don't reliably have.
public struct KeychainManager: Sendable {
    public let service: String
    public let account: String

    public init(service: String = "SafeClip", account: String = "master-key") {
        self.service = service
        self.account = account
    }

    /// Loads the master key, generating and persisting a new one on first run.
    public func loadOrCreateMasterKey() throws -> Data {
        switch try loadMasterKey() {
        case .some(let data):
            return data
        case .none:
            let fresh = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            try storeMasterKey(fresh)
            return fresh
        }
    }

    /// Returns nil if no key exists. Throws if a key exists but is unreadable.
    public func loadMasterKey() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, data.count == 32 else {
                throw KeychainError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unreadable(status)
        }
    }

    public func storeMasterKey(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecAttrLabel as String: "SafeClip encryption key",
            kSecAttrDescription as String: "AES-256 master key for SafeClip's encrypted clipboard history",
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.writeFailed(status)
        }
    }

    /// Deletes the master key, rendering any existing history permanently
    /// unreadable. Only call after explicit user confirmation (PRD §12).
    public func deleteMasterKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
