import CryptoKit
import Foundation
import GRDB
import Testing

@testable import SafeClipCore

@Suite("Image & file history (v0.2.0)")
struct BinaryKindsTests {
    private func makeKeys() -> KeyMaterial {
        KeyMaterial(masterKeyData: SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    /// A fake PNG payload: real magic bytes so the on-disk leak test is honest.
    private func fakePNG(seed: UInt8) -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(Data(repeating: seed, count: 256))
        return data
    }

    @Test func imageRoundTripWithThumbnail() throws {
        let store = try HistoryStore.inMemory(keyMaterial: makeKeys())
        let payload = fakePNG(seed: 1)
        let thumb = fakePNG(seed: 2)
        _ = try store.insert(
            CaptureInput(
                kind: .image,
                plainText: "Image 1280×800",
                richData: payload,
                richType: "public.png",
                thumbnailData: thumb,
                countOverride: payload.count
            )
        )
        let item = try #require(try store.fetchAll().first)
        #expect(item.kind == .image)
        #expect(item.richData == payload)
        #expect(item.thumbnailData == thumb)
        #expect(item.charCount == payload.count)
        #expect(item.plainText == "Image 1280×800")
    }

    @Test func imagePayloadIsEncryptedOnDisk() throws {
        let store = try HistoryStore.inMemory(keyMaterial: makeKeys())
        let payload = fakePNG(seed: 7)
        _ = try store.insert(
            CaptureInput(kind: .image, plainText: "Image 10×10", richData: payload,
                         richType: "public.png", thumbnailData: payload)
        )
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47])
        for row in try store.rawRows() {
            let rich: Data? = row["rich_cipher"]
            let thumb: Data? = row["thumb_cipher"]
            #expect(rich?.range(of: pngMagic) == nil, "image bytes leak: PNG magic in rich_cipher")
            #expect(thumb?.range(of: pngMagic) == nil, "thumbnail bytes leak")
        }
    }

    @Test func imagesDedupByPayloadNotPlaceholder() throws {
        let store = try HistoryStore.inMemory(keyMaterial: makeKeys())
        // Two *different* images sharing identical placeholder text must both
        // be kept…
        _ = try store.insert(
            CaptureInput(kind: .image, plainText: "Image 10×10", richData: fakePNG(seed: 1), richType: "public.png")
        )
        _ = try store.insert(
            CaptureInput(kind: .image, plainText: "Image 10×10", richData: fakePNG(seed: 2), richType: "public.png")
        )
        #expect(try store.count() == 2)
        // …while re-copying the same image deduplicates.
        let again = try store.insert(
            CaptureInput(kind: .image, plainText: "Image 10×10", richData: fakePNG(seed: 1), richType: "public.png")
        )
        guard case .updatedExisting = again else {
            Issue.record("expected dedup, got \(again)")
            return
        }
        #expect(try store.count() == 2)
    }

    @Test func fileListRoundTrip() throws {
        let store = try HistoryStore.inMemory(keyMaterial: makeKeys())
        let paths = "/Users/mudit/Documents/report.pdf\n/Users/mudit/Pictures/cat.heic"
        _ = try store.insert(CaptureInput(kind: .fileList, plainText: paths, countOverride: 2))
        let item = try #require(try store.fetchAll().first)
        #expect(item.kind == .fileList)
        #expect(item.plainText == paths)
        #expect(item.charCount == 2, "charCount carries the file count for file lists")
    }

    @Test func textRowsStillDefaultToTextKind() throws {
        let store = try HistoryStore.inMemory(keyMaterial: makeKeys())
        _ = try store.insert(CaptureInput(plainText: "plain old text"))
        let item = try #require(try store.fetchAll().first)
        #expect(item.kind == .text)
        #expect(item.thumbnailData == nil)
    }

    /// Opens a database created with the *frozen* v1 schema containing a
    /// legacy row, then verifies the v2 migration adds the new columns
    /// without losing the row, which reads back as `.text`.
    @Test func v1DatabaseMigratesCleanly() throws {
        let keys = makeKeys()
        let encryptor = EncryptionService(key: keys.encryptionKey)
        let dbQueue = try DatabaseQueue()

        // Frozen copy of the v1 migration (duplicated by design — migrations
        // never change after shipping; see HistoryStore.migrate).
        var v1 = DatabaseMigrator()
        v1.registerMigration("v1") { db in
            try db.create(table: "clips") { t in
                t.primaryKey("id", .text)
                t.column("ciphertext", .blob).notNull()
                t.column("nonce", .blob).notNull()
                t.column("rich_cipher", .blob)
                t.column("rich_nonce", .blob)
                t.column("rich_type", .text)
                t.column("content_hash", .text).notNull().unique()
                t.column("char_count", .integer).notNull()
                t.column("source_bundle", .text)
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("is_burn", .boolean).notNull().defaults(to: false)
                t.column("is_flagged", .boolean).notNull().defaults(to: false)
                t.column("flag_reason", .text)
                t.column("created_at", .integer).notNull()
                t.column("last_used_at", .integer)
            }
            try db.create(index: "idx_clips_created", on: "clips", columns: ["created_at"])
        }
        try v1.migrate(dbQueue)

        let legacyText = "row written before the v2 schema existed"
        let (cipher, nonce) = try encryptor.encrypt(Data(legacyText.utf8))
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clips (id, ciphertext, nonce, content_hash, char_count, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, cipher, nonce, keys.contentHash(legacyText),
                            legacyText.count, 1_700_000_000]
            )
        }

        // Opening the store runs the v2 migration on the legacy database.
        let store = try HistoryStore(dbQueue: dbQueue, keyMaterial: keys)
        let items = try store.fetchAll()
        #expect(items.count == 1)
        #expect(items[0].kind == .text)
        #expect(items[0].plainText == legacyText)

        // And new-style rows insert fine post-migration.
        _ = try store.insert(
            CaptureInput(kind: .image, plainText: "Image 4×4", richData: fakePNG(seed: 9), richType: "public.png")
        )
        #expect(try store.count() == 2)
    }
}
