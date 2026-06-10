import CryptoKit
import Foundation

/// Derives the working keys from the single 32-byte master key in the Keychain.
///
/// Two independent keys come out of HKDF-SHA256:
///  - `encryptionKey` — AES-256-GCM key for item content.
///  - `hmacKey`       — keyed hash for the dedup column.
///
/// Deviation from PRD §9 (improvement, see ROADMAP research log): the PRD
/// specified plain SHA-256 for `content_hash`. A plain hash of a *low-entropy*
/// secret (a human password) is offline-guessable by anyone who copies the
/// database file. Using HMAC with a key derived from the master key keeps
/// dedup exact-match semantics while making the hash useless without the
/// Keychain key. This matters precisely because SafeClip captures passwords.
// @unchecked: SymmetricKey is an immutable value type and thread-safe, but
// only newer SDKs declare it Sendable — this bridges the SDK gap (CI builds
// on older Xcode than local).
public struct KeyMaterial: @unchecked Sendable {
    public let encryptionKey: SymmetricKey
    private let hmacKey: SymmetricKey

    public init(masterKeyData: Data) {
        let master = SymmetricKey(data: masterKeyData)
        self.encryptionKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            info: Data("SafeClip.encryption.v1".utf8),
            outputByteCount: 32
        )
        self.hmacKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            info: Data("SafeClip.dedup-hmac.v1".utf8),
            outputByteCount: 32
        )
    }

    /// Keyed, one-way content identifier used for deduplication.
    public func contentHash(_ text: String) -> String {
        contentHash(Data(text.utf8))
    }

    /// Byte-level variant — used for image payloads, where the display
    /// placeholder ("Image 1280×800") would wrongly collide distinct images.
    public func contentHash(_ data: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: hmacKey)
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }
}
