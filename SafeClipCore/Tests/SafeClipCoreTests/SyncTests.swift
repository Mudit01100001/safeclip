import CryptoKit
import Foundation
import Testing

@testable import SafeClipCore

@Suite("E2E folder sync")
struct SyncTests {
    private func makeStore() throws -> HistoryStore {
        let master = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return try HistoryStore.inMemory(keyMaterial: KeyMaterial(masterKeyData: master))
    }

    private func clip(_ text: String, at epoch: TimeInterval = 1000) -> ClipItem {
        ClipItem(plainText: text, charCount: text.count, createdAt: Date(timeIntervalSince1970: epoch))
    }

    // MARK: Recovery phrase

    @Test func recoveryPhraseRoundTrips() {
        let secret = SyncSecret.generate()
        #expect(secret.count == 32)
        let phrase = SyncSecret.phrase(from: secret)
        #expect(SyncSecret.secret(fromPhrase: phrase) == secret)
        // Tolerates messy whitespace/case, rejects non-32-byte input.
        #expect(SyncSecret.secret(fromPhrase: phrase.uppercased()) == secret)
        #expect(SyncSecret.secret(fromPhrase: "not a real phrase") == nil)
    }

    // MARK: Codec

    @Test func codecRoundTripsAndIsEncrypted() throws {
        let keys = SyncKeyMaterial(secret: SyncSecret.generate())
        let records = [SyncRecord.live(clip("secret text"), keys: keys)]
        let blob = try SyncCodec.encode(records, using: keys)
        // The clipboard text must not be readable in the file bytes.
        #expect(blob.range(of: Data("secret text".utf8)) == nil)
        #expect(try SyncCodec.decode(blob, using: keys) == records)
    }

    @Test func codecRejectsWrongKey() throws {
        let keys = SyncKeyMaterial(secret: SyncSecret.generate())
        let other = SyncKeyMaterial(secret: SyncSecret.generate())
        let blob = try SyncCodec.encode([SyncRecord.live(clip("x"), keys: keys)], using: keys)
        #expect(throws: (any Error).self) { try SyncCodec.decode(blob, using: other) }
    }

    // MARK: Merge

    @Test func mergeIsLastWriterWinsAndOrderIndependent() {
        let old = SyncRecord(syncHash: "h", updatedAt: Date(timeIntervalSince1970: 100),
                             deleted: false, payload: SyncPayload(clip("old")))
        let new = SyncRecord(syncHash: "h", updatedAt: Date(timeIntervalSince1970: 200),
                             deleted: false, payload: SyncPayload(clip("new")))
        #expect(SyncMerge.merge([[old], [new]]).first?.payload?.plainText == "new")
        #expect(SyncMerge.merge([[new], [old]]).first?.payload?.plainText == "new")
    }

    @Test func tombstoneWinsAtEqualVersion() {
        let live = SyncRecord(syncHash: "h", updatedAt: Date(timeIntervalSince1970: 300),
                              deleted: false, payload: SyncPayload(clip("x")))
        let dead = SyncRecord(syncHash: "h", updatedAt: Date(timeIntervalSince1970: 300),
                              deleted: true, payload: nil)
        #expect(SyncMerge.merge([[live], [dead]]).first?.deleted == true)
        #expect(SyncMerge.merge([[dead], [live]]).first?.deleted == true)
    }

    // MARK: End-to-end across two devices (different device keys, shared sync key)

    @Test func clipFromDeviceAReachesDeviceB() throws {
        let syncKeys = SyncKeyMaterial(secret: SyncSecret.generate())
        let deviceA = try makeStore()
        let deviceB = try makeStore()

        _ = try deviceA.insert(CaptureInput(plainText: "hello from A"))
        let merged = SyncMerge.merge([try deviceA.exportLiveRecords(syncKeys: syncKeys)])

        let stats = try deviceB.applySync(merged, syncKeys: syncKeys)
        #expect(stats.inserted == 1)
        #expect(try deviceB.fetchAll().contains { $0.plainText == "hello from A" })

        // Re-applying the same merge changes nothing (content identity).
        #expect(try deviceB.applySync(merged, syncKeys: syncKeys).total == 0)
    }

    @Test func deleteOnDeviceAPropagatesToDeviceB() throws {
        let syncKeys = SyncKeyMaterial(secret: SyncSecret.generate())
        let deviceA = try makeStore()
        let deviceB = try makeStore()

        _ = try deviceA.insert(CaptureInput(plainText: "ephemeral"))
        try deviceB.applySync(
            SyncMerge.merge([try deviceA.exportLiveRecords(syncKeys: syncKeys)]),
            syncKeys: syncKeys
        )
        #expect(try deviceB.fetchAll().count == 1)

        // A deletes it → publishes a tombstone with a newer version.
        let item = try deviceA.fetchAll().first { $0.plainText == "ephemeral" }!
        let tombstone = SyncRecord.tombstone(item, at: Date(timeIntervalSinceNow: 60), keys: syncKeys)
        try deviceA.delete(id: item.id)

        let merged = SyncMerge.merge([try deviceA.exportLiveRecords(syncKeys: syncKeys), [tombstone]])
        let stats = try deviceB.applySync(merged, syncKeys: syncKeys)
        #expect(stats.deleted == 1)
        #expect(try deviceB.fetchAll().isEmpty)
    }

    @Test func newerMetadataUpdatesExistingClip() throws {
        let syncKeys = SyncKeyMaterial(secret: SyncSecret.generate())
        let deviceA = try makeStore()
        let deviceB = try makeStore()

        _ = try deviceA.insert(CaptureInput(plainText: "pin me"))
        try deviceB.applySync(
            SyncMerge.merge([try deviceA.exportLiveRecords(syncKeys: syncKeys)]),
            syncKeys: syncKeys
        )
        let item = try deviceA.fetchAll().first { $0.plainText == "pin me" }!
        try deviceA.setPinned(id: item.id, true)
        try deviceA.markUsed(id: item.id, now: Date(timeIntervalSinceNow: 120)) // bump version

        let merged = SyncMerge.merge([try deviceA.exportLiveRecords(syncKeys: syncKeys)])
        let stats = try deviceB.applySync(merged, syncKeys: syncKeys)
        #expect(stats.updated == 1)
        #expect(try deviceB.fetchAll().first { $0.plainText == "pin me" }?.isPinned == true)
    }
}
