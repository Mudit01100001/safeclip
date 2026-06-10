import CryptoKit
import Foundation
import Testing

@testable import SafeClipCore

@Suite("Encryption")
struct EncryptionTests {
    private func makeKeys() -> KeyMaterial {
        KeyMaterial(masterKeyData: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    @Test func roundTripRestoresPlaintext() throws {
        let service = EncryptionService(key: makeKeys().encryptionKey)
        let plaintext = Data("correct horse battery staple — пароль — 🔑".utf8)
        let (cipher, nonce) = try service.encrypt(plaintext)
        #expect(cipher != plaintext)
        let decrypted = try service.decrypt(ciphertext: cipher, nonce: nonce)
        #expect(decrypted == plaintext)
    }

    @Test func wrongKeyFailsToDecrypt() throws {
        let service = EncryptionService(key: makeKeys().encryptionKey)
        let other = EncryptionService(key: makeKeys().encryptionKey)
        let (cipher, nonce) = try service.encrypt(Data("secret".utf8))
        #expect(throws: (any Error).self) {
            try other.decrypt(ciphertext: cipher, nonce: nonce)
        }
    }

    @Test func tamperedCiphertextFailsAuthentication() throws {
        let service = EncryptionService(key: makeKeys().encryptionKey)
        var (cipher, nonce) = try service.encrypt(Data("secret".utf8))
        #expect(cipher.startIndex == 0, "encrypt must return canonical zero-based Data")
        cipher[cipher.startIndex] ^= 0xFF
        #expect(throws: (any Error).self) {
            try service.decrypt(ciphertext: cipher, nonce: nonce)
        }
    }

    @Test func nonceIsUniquePerEncryption() throws {
        let service = EncryptionService(key: makeKeys().encryptionKey)
        let plaintext = Data("same input".utf8)
        var nonces = Set<Data>()
        for _ in 0..<50 {
            let (_, nonce) = try service.encrypt(plaintext)
            #expect(nonce.count == 12)
            nonces.insert(nonce)
        }
        #expect(nonces.count == 50, "GCM nonces must never repeat under one key")
    }

    @Test func dedupHashIsStableAndKeyed() {
        let masterA = Data(repeating: 0xAA, count: 32)
        let masterB = Data(repeating: 0xBB, count: 32)
        let keysA = KeyMaterial(masterKeyData: masterA)
        let keysA2 = KeyMaterial(masterKeyData: masterA)
        let keysB = KeyMaterial(masterKeyData: masterB)

        let text = "hunter2"
        #expect(keysA.contentHash(text) == keysA2.contentHash(text), "same key → same hash (dedup works)")
        #expect(keysA.contentHash(text) != keysB.contentHash(text), "hash must depend on the key — a plain SHA-256 of a weak password would be offline-guessable")
        #expect(keysA.contentHash(text).count == 64)
        #expect(keysA.contentHash(text) != keysA.contentHash("hunter3"))
    }
}
