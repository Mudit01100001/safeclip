import CryptoKit
import Foundation

public enum EncryptionError: Error, Equatable {
    case malformedNonce
    case malformedCiphertext
}

/// AES-256-GCM encryption with a per-item random nonce (PRD §8).
///
/// Storage layout matches the PRD §9 schema: the 12-byte GCM nonce lives in its
/// own column; the `ciphertext` blob is ciphertext followed by the 16-byte
/// authentication tag. Tampering with either causes `decrypt` to throw.
public struct EncryptionService: Sendable {
    private static let tagLength = 16
    private let key: SymmetricKey

    public init(key: SymmetricKey) {
        self.key = key
    }

    public func encrypt(_ plaintext: Data) throws -> (ciphertext: Data, nonce: Data) {
        // AES.GCM.Nonce() draws 12 bytes from the system CSPRNG. A fresh nonce
        // per item is mandatory: GCM nonce reuse under one key reveals the
        // keystream (ROADMAP research log R5).
        let sealed = try AES.GCM.seal(plaintext, using: key)
        // sealed.ciphertext is a slice of the combined nonce|ct|tag buffer and
        // keeps slice indices through `+`; re-wrap so callers get a Data whose
        // startIndex is 0 (indexing a non-canonical Data traps).
        return (Data(sealed.ciphertext + sealed.tag), Data(sealed.nonce))
    }

    public func decrypt(ciphertext: Data, nonce: Data) throws -> Data {
        guard nonce.count == 12 else { throw EncryptionError.malformedNonce }
        guard ciphertext.count >= Self.tagLength else { throw EncryptionError.malformedCiphertext }
        let tag = ciphertext.suffix(Self.tagLength)
        let body = ciphertext.dropLast(Self.tagLength)
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce),
            ciphertext: body,
            tag: tag
        )
        return try AES.GCM.open(box, using: key)
    }
}
