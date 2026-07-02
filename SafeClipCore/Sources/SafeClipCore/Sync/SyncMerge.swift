import Foundation

/// Last-writer-wins merge of change-log record sets, keyed by `syncHash`.
///
/// Every device feeds in its own records plus every peer's; the result is the
/// agreed state per `syncHash`. The winner rule is order-independent so all
/// devices converge on the same result regardless of which files they read
/// first:
///   1. higher `updatedAt` wins (a strict total order on dates);
///   2. on a tie, a tombstone beats a live record (a delete is the safer call);
///   3. on a further tie, a pinned record wins (pinning is "sticky").
/// A remaining exact tie means the records are equivalent for sync purposes
/// (same content, same version, same pin state), so either is fine.
public enum SyncMerge {
    public static func merge(_ sets: [[SyncRecord]]) -> [SyncRecord] {
        var map: [String: SyncRecord] = [:]
        for set in sets {
            for record in set {
                if let existing = map[record.syncHash] {
                    map[record.syncHash] = winner(existing, record)
                } else {
                    map[record.syncHash] = record
                }
            }
        }
        return Array(map.values)
    }

    static func winner(_ a: SyncRecord, _ b: SyncRecord) -> SyncRecord {
        if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt ? a : b }
        if a.deleted != b.deleted { return a.deleted ? a : b }
        let aPinned = a.payload?.isPinned ?? false
        let bPinned = b.payload?.isPinned ?? false
        if aPinned != bPinned { return aPinned ? a : b }
        return a
    }
}
