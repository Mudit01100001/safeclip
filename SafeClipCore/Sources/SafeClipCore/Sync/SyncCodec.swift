import Foundation

public enum SyncCodecError: Error, Equatable {
    case truncated
}

/// Encodes/decodes a device's change-log file. The records are JSON, then
/// AES-256-GCM encrypted with the shared sync key, so the file written into the
/// user's synced folder (iCloud Drive, Dropbox, …) is ciphertext end to end —
/// the cloud provider never sees clipboard content.
///
/// On-disk layout: `nonce (12 bytes) || ciphertext+tag`.
public enum SyncCodec {
    private static let nonceLength = 12

    public static func encode(_ records: [SyncRecord], using keys: SyncKeyMaterial) throws -> Data {
        let json = try JSONEncoder().encode(records)
        let (ciphertext, nonce) = try keys.encryptor.encrypt(json)
        return nonce + ciphertext
    }

    public static func decode(_ data: Data, using keys: SyncKeyMaterial) throws -> [SyncRecord] {
        guard data.count > nonceLength else { throw SyncCodecError.truncated }
        let nonce = Data(data.prefix(nonceLength))
        let ciphertext = Data(data.dropFirst(nonceLength))
        let json = try keys.encryptor.decrypt(ciphertext: ciphertext, nonce: nonce)
        return try JSONDecoder().decode([SyncRecord].self, from: json)
    }
}
