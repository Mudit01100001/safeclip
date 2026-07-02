import Foundation

/// The syncable snapshot of a clip's content + metadata. Lives only inside an
/// encrypted change-log file (`SyncCodec`), never in cleartext on disk.
public struct SyncPayload: Sendable, Equatable, Codable {
    public var kind: ClipKind
    public var plainText: String
    public var richData: Data?
    public var richType: String?
    public var thumbnailData: Data?
    public var charCount: Int
    public var sourceBundle: String?
    public var isPinned: Bool
    public var isBurn: Bool
    public var flagReason: FlagReason?
    public var category: String?
    public var ocrText: String?
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(_ item: ClipItem) {
        kind = item.kind
        plainText = item.plainText
        richData = item.richData
        richType = item.richType
        thumbnailData = item.thumbnailData
        charCount = item.charCount
        sourceBundle = item.sourceBundle
        isPinned = item.isPinned
        isBurn = item.isBurn
        flagReason = item.flagReason
        category = item.category
        ocrText = item.ocrText
        createdAt = item.createdAt
        lastUsedAt = item.lastUsedAt
    }

    /// A fresh `ClipItem` from this payload (new local id; identity is the
    /// content, tracked by `content_hash`/`syncHash`, not the id).
    public func makeClipItem() -> ClipItem {
        ClipItem(
            kind: kind,
            plainText: plainText,
            richData: richData,
            richType: richType,
            thumbnailData: thumbnailData,
            charCount: charCount,
            sourceBundle: sourceBundle,
            isPinned: isPinned,
            isBurn: isBurn,
            isFlagged: flagReason != nil,
            flagReason: flagReason,
            category: category,
            ocrText: ocrText,
            createdAt: createdAt,
            lastUsedAt: lastUsedAt
        )
    }

    /// The bytes the sync hash is taken over — image payload for images (the
    /// "Image W×H" placeholder would collide distinct images), the text
    /// otherwise. Mirrors `HistoryStore`'s dedup identity.
    public var canonicalBytes: Data {
        kind == .image ? (richData ?? Data(plainText.utf8)) : Data(plainText.utf8)
    }
}

/// Counts of what `HistoryStore.applySync` changed locally.
public struct SyncApplyStats: Sendable, Equatable {
    public var inserted = 0
    public var updated = 0
    public var deleted = 0
    public init() {}
    public var total: Int { inserted + updated + deleted }
}

/// One entry in a device's change log: either a live clip or a tombstone for one
/// the user deleted. `syncHash` is the cross-device identity; `updatedAt` is the
/// last-writer-wins version.
public struct SyncRecord: Sendable, Equatable, Codable {
    public let syncHash: String
    public var updatedAt: Date
    public var deleted: Bool
    public var payload: SyncPayload?

    public init(syncHash: String, updatedAt: Date, deleted: Bool, payload: SyncPayload?) {
        self.syncHash = syncHash
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.payload = payload
    }

    /// A live record for a clip, hashed with the shared sync key.
    public static func live(_ item: ClipItem, keys: SyncKeyMaterial) -> SyncRecord {
        let payload = SyncPayload(item)
        return SyncRecord(
            syncHash: keys.syncHash(payload.canonicalBytes),
            updatedAt: item.lastUsedAt ?? item.createdAt,
            deleted: false,
            payload: payload
        )
    }

    /// A tombstone for a clip the user deleted, hashed with the shared sync key.
    public static func tombstone(_ item: ClipItem, at date: Date, keys: SyncKeyMaterial) -> SyncRecord {
        let payload = SyncPayload(item)
        return SyncRecord(
            syncHash: keys.syncHash(payload.canonicalBytes),
            updatedAt: date,
            deleted: true,
            payload: nil
        )
    }
}
