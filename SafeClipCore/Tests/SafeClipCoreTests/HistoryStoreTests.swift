import CryptoKit
import Foundation
import Testing

@testable import SafeClipCore

@Suite("History store")
struct HistoryStoreTests {
    private func makeStore() throws -> HistoryStore {
        let master = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        return try HistoryStore.inMemory(keyMaterial: KeyMaterial(masterKeyData: master))
    }

    @Test func insertAndFetchRoundTrip() throws {
        let store = try makeStore()
        let rich = Data("{\\rtf1 hello}".utf8)
        let outcome = try store.insert(
            CaptureInput(
                plainText: "hello world",
                richData: rich,
                richType: "public.rtf",
                sourceBundle: "com.apple.TextEdit"
            )
        )
        guard case .inserted = outcome else {
            Issue.record("expected .inserted, got \(outcome)")
            return
        }
        let items = try store.fetchAll()
        #expect(items.count == 1)
        #expect(items[0].plainText == "hello world")
        #expect(items[0].richData == rich)
        #expect(items[0].richType == "public.rtf")
        #expect(items[0].sourceBundle == "com.apple.TextEdit")
        #expect(items[0].charCount == 11)
    }

    @Test func storedBlobsContainNoPlaintext() throws {
        // The on-disk guarantee behind `strings history.db` showing nothing:
        // no raw column may contain the plaintext bytes (F1 acceptance).
        let store = try makeStore()
        let secret = "MySuperSecretPassword2026!"
        _ = try store.insert(CaptureInput(plainText: secret, richData: Data(secret.utf8), richType: "public.rtf"))

        let secretBytes = Data(secret.utf8)
        for row in try store.rawRows() {
            let cipher: Data = row["ciphertext"]
            let richCipher: Data? = row["rich_cipher"]
            let hash: String = row["content_hash"]
            #expect(cipher.range(of: secretBytes) == nil, "ciphertext leaks plaintext")
            #expect(richCipher?.range(of: secretBytes) == nil, "rich ciphertext leaks plaintext")
            #expect(!hash.contains(secret), "hash column leaks plaintext")
        }
    }

    @Test func identicalContentDeduplicates() throws {
        let store = try makeStore()
        let first = try store.insert(CaptureInput(plainText: "same text"), now: Date(timeIntervalSince1970: 1000))
        let second = try store.insert(CaptureInput(plainText: "same text"), now: Date(timeIntervalSince1970: 2000))

        guard case .inserted(let id) = first, case .updatedExisting(let bumpedID) = second else {
            Issue.record("expected inserted then updatedExisting, got \(first), \(second)")
            return
        }
        #expect(id == bumpedID)
        #expect(try store.count() == 1)
        let item = try #require(try store.fetchAll().first)
        #expect(item.lastUsedAt == Date(timeIntervalSince1970: 2000))
    }

    @Test func reCopyUpgradesFlagWhenDetectionTurnedOn() throws {
        let store = try makeStore()
        _ = try store.insert(CaptureInput(plainText: "AKIAIOSFODNN7EXAMPLE"))
        _ = try store.insert(CaptureInput(plainText: "AKIAIOSFODNN7EXAMPLE", flagReason: .apiKey))
        let item = try #require(try store.fetchAll().first)
        #expect(item.isFlagged)
        #expect(item.flagReason == .apiKey)
    }

    @Test func deleteRemovesRow() throws {
        let store = try makeStore()
        guard case .inserted(let id) = try store.insert(CaptureInput(plainText: "to delete")) else {
            Issue.record("insert failed")
            return
        }
        try store.delete(id: id)
        #expect(try store.count() == 0)
    }

    @Test func deleteAllEmptiesTheStore() throws {
        let store = try makeStore()
        for i in 0..<5 {
            _ = try store.insert(CaptureInput(plainText: "item \(i)"))
        }
        #expect(try store.count() == 5)
        try store.deleteAll()
        #expect(try store.count() == 0, "F6: after Clear All, zero item rows")
    }

    @Test func burnFlagPersists() throws {
        let store = try makeStore()
        _ = try store.insert(CaptureInput(plainText: "burn me", isBurn: true))
        let item = try #require(try store.fetchAll().first)
        #expect(item.isBurn)
    }

    @Test func pinnedItemsSortFirst() throws {
        let store = try makeStore()
        guard case .inserted(let oldID) = try store.insert(
            CaptureInput(plainText: "old pinned"), now: Date(timeIntervalSince1970: 1000)
        ) else { Issue.record("insert failed"); return }
        _ = try store.insert(CaptureInput(plainText: "newer unpinned"), now: Date(timeIntervalSince1970: 2000))
        try store.setPinned(id: oldID, true)

        let items = try store.fetchAll()
        #expect(items.first?.plainText == "old pinned")
    }

    @Test func sweepExpiredKeepsPinnedAndRecent() throws {
        let store = try makeStore()
        let old = Date(timeIntervalSince1970: 1000)
        let recent = Date(timeIntervalSince1970: 100_000)
        let cutoff = Date(timeIntervalSince1970: 50_000)

        guard case .inserted(let oldPinnedID) = try store.insert(CaptureInput(plainText: "old but pinned"), now: old)
        else { Issue.record("insert failed"); return }
        try store.setPinned(id: oldPinnedID, true)
        _ = try store.insert(CaptureInput(plainText: "old unpinned"), now: old)
        _ = try store.insert(CaptureInput(plainText: "recent"), now: recent)

        let deleted = try store.sweepExpired(olderThan: cutoff)
        #expect(deleted == 1)
        let texts = try store.fetchAll().map(\.plainText)
        #expect(texts.contains("old but pinned"), "F9: pinned items are exempt from expiry")
        #expect(texts.contains("recent"))
        #expect(!texts.contains("old unpinned"))
    }

    @Test func sweepUsesLastTouchedNotCreated() throws {
        let store = try makeStore()
        // Created long ago but re-copied recently → must survive.
        _ = try store.insert(CaptureInput(plainText: "kept alive"), now: Date(timeIntervalSince1970: 1000))
        _ = try store.insert(CaptureInput(plainText: "kept alive"), now: Date(timeIntervalSince1970: 100_000))
        try store.sweepExpired(olderThan: Date(timeIntervalSince1970: 50_000))
        #expect(try store.count() == 1)
    }

    @Test func enforceLimitPrunesOldestUnpinned() throws {
        let store = try makeStore()
        guard case .inserted(let pinnedID) = try store.insert(
            CaptureInput(plainText: "ancient pinned"), now: Date(timeIntervalSince1970: 1)
        ) else { Issue.record("insert failed"); return }
        try store.setPinned(id: pinnedID, true)
        for i in 0..<10 {
            _ = try store.insert(
                CaptureInput(plainText: "item \(i)"),
                now: Date(timeIntervalSince1970: TimeInterval(1000 + i))
            )
        }

        let pruned = try store.enforceLimit(5)
        #expect(pruned == 5)
        let items = try store.fetchAll()
        #expect(items.count == 6, "5 newest unpinned + 1 pinned")
        #expect(items.contains { $0.plainText == "ancient pinned" }, "pinned never pruned by limit")
        #expect(items.contains { $0.plainText == "item 9" })
        #expect(!items.contains { $0.plainText == "item 0" })
    }

    @Test func whitespaceOnlyContentIsSkipped() throws {
        let store = try makeStore()
        #expect(try store.insert(CaptureInput(plainText: "   \n\t ")) == .skippedEmpty)
        #expect(try store.insert(CaptureInput(plainText: "")) == .skippedEmpty)
        #expect(try store.count() == 0)
    }

    @Test func oversizedContentIsTruncatedButCountsOriginal() throws {
        let store = try makeStore()
        let huge = String(repeating: "x", count: HistoryStore.maxStoredCharacters + 500)
        _ = try store.insert(CaptureInput(plainText: huge))
        let item = try #require(try store.fetchAll().first)
        #expect(item.charCount == huge.count, "char_count keeps the original length")
        #expect(item.plainText.count == HistoryStore.maxStoredCharacters + 1, "stored text capped + ellipsis")
        #expect(item.plainText.hasSuffix("⋯"))
    }
}
