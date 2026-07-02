#!/usr/bin/swift
// Signs a release artifact for Sparkle's appcast (ed25519, RFC 8032 — the
// same standard Sparkle 2.x uses internally, so no Sparkle-project binaries
// are needed). Reads the private key generated once into the login Keychain
// under service "com.mudit.safeclip.sparkle" / account "ed25519-private-key"
// (never printed; see CLAUDE.md Session 15 for how it was created).
//
// Usage: Scripts/sparkle_sign.swift path/to/SafeClip-X.Y.Z.dmg
// Prints the two attributes the appcast <enclosure> needs:
//   sparkle:edSignature="..."  length="..."
import CryptoKit
import Foundation
import Security

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("Usage: sparkle_sign.swift <path-to-dmg>\n".data(using: .utf8)!)
    exit(1)
}
let fileURL = URL(fileURLWithPath: CommandLine.arguments[1])

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.mudit.safeclip.sparkle",
    kSecAttrAccount as String: "ed25519-private-key",
    kSecReturnData as String: true,
]
var item: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &item)
guard status == errSecSuccess,
      let data = item as? Data,
      let base64 = String(data: data, encoding: .utf8),
      let keyData = Data(base64Encoded: base64)
else {
    FileHandle.standardError.write("Couldn't read the Sparkle signing key from the Keychain (status \(status)). Was it ever generated?\n".data(using: .utf8)!)
    exit(1)
}

let privateKey = try! Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
let fileData = try! Data(contentsOf: fileURL)
let signature = try! privateKey.signature(for: fileData)

print("sparkle:edSignature=\"\(signature.base64EncodedString())\" length=\"\(fileData.count)\"")
