import CryptoKit
import Foundation

/// Working keys for **end-to-end-encrypted sync**, derived from a single 32-byte
/// *shared* secret that the user transfers between their devices (the recovery
/// phrase). It is deliberately separate from `KeyMaterial`:
///
///  - `KeyMaterial` protects the on-disk history and is **per-device** (never
///    leaves the Mac — TERMS §2), so its keyed `content_hash` differs across
///    devices and can't be a sync identity.
///  - `SyncKeyMaterial` is **shared** across the user's devices, so its
///    `syncHash` is the same for the same content everywhere — the merge
///    identity — and its `encryptionKey` lets every device read the change-log
///    files. Whatever folder/cloud carries those files sees only ciphertext.
///
/// Two independent subkeys come out of HKDF-SHA256 so the same secret never
/// doubles as both cipher key and MAC key.
// @unchecked: SymmetricKey is an immutable, thread-safe value type that older
// SDKs don't declare Sendable (mirrors KeyMaterial).
public struct SyncKeyMaterial: @unchecked Sendable {
    public let encryptionKey: SymmetricKey
    private let hmacKey: SymmetricKey

    /// `secret` must be 32 bytes (see `SyncSecret`).
    public init(secret: Data) {
        let master = SymmetricKey(data: secret)
        self.encryptionKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            info: Data("SafeClip.sync.encryption.v1".utf8),
            outputByteCount: 32
        )
        self.hmacKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            info: Data("SafeClip.sync.hmac.v1".utf8),
            outputByteCount: 32
        )
    }

    /// Shared, keyed, one-way identity for a piece of content — identical on
    /// every device that holds the same secret, so the same clip converges.
    public func syncHash(_ data: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: hmacKey)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    public var encryptor: EncryptionService { EncryptionService(key: encryptionKey) }
}

/// Helpers for the 32-byte shared sync secret and its human-transferable form.
public enum SyncSecret {
    public static let byteCount = 32

    public static func generate() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// A copy-pasteable recovery phrase: the secret as lowercase hex in
    /// space-separated 4-character groups (easy to read back / type).
    public static func phrase(from secret: Data) -> String {
        let hex = secret.map { String(format: "%02x", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map { offset -> String in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 4, limitedBy: hex.endIndex) ?? hex.endIndex
            return String(hex[start..<end])
        }.joined(separator: " ")
    }

    /// Parses a recovery phrase back into the 32-byte secret, tolerating spaces
    /// and case. Returns nil when it isn't exactly 32 bytes of hex.
    public static func secret(fromPhrase phrase: String) -> Data? {
        let hex = phrase.lowercased().filter { $0.isHexDigit }
        guard hex.count == byteCount * 2 else { return nil }
        var data = Data(capacity: byteCount)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
