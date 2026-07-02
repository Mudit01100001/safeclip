import Foundation
import GRDB

/// Encrypted clipboard history persistence (PRD §9 schema).
///
/// Every content column is AES-256-GCM ciphertext; the only cleartext columns
/// are structural (`char_count`, timestamps, flags) or one-way
/// (`content_hash`, an HMAC — see `KeyMaterial`). All access is serialized
/// through a GRDB `DatabaseQueue`. `PRAGMA secure_delete` is on so deleted
/// rows (burn-after-paste, Clear All) are zeroed in the database file rather
/// than left in free pages — F6 requires deletion, not hiding.
public final class HistoryStore: Sendable {
    private let dbQueue: DatabaseQueue
    private let keys: KeyMaterial
    private let encryptor: EncryptionService

    /// Stored plain text is capped; beyond this the text is truncated with an
    /// ellipsis while `char_count` keeps the original length (PRD §12).
    public static let maxStoredCharacters = 1_000_000

    public convenience init(databaseURL: URL, keyMaterial: KeyMaterial) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA secure_delete = ON")
        }
        let queue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try self.init(dbQueue: queue, keyMaterial: keyMaterial)
    }

    /// In-memory store for tests.
    public static func inMemory(keyMaterial: KeyMaterial) throws -> HistoryStore {
        try HistoryStore(dbQueue: DatabaseQueue(), keyMaterial: keyMaterial)
    }

    init(dbQueue: DatabaseQueue, keyMaterial: KeyMaterial) throws {
        self.dbQueue = dbQueue
        self.keys = keyMaterial
        self.encryptor = EncryptionService(key: keyMaterial.encryptionKey)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
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
        // v0.2.0: images and file lists in history (owner-revised scope).
        // Existing rows default to kind 'text'.
        migrator.registerMigration("v2-kinds-and-thumbnails") { db in
            try db.alter(table: "clips") { t in
                t.add(column: "kind", .text).notNull().defaults(to: ClipKind.text.rawValue)
                t.add(column: "thumb_cipher", .blob)
                t.add(column: "thumb_nonce", .blob)
            }
        }
        // v3: optional user-assigned category, stored encrypted like content
        // (filtering is done in memory, so encryption costs nothing here).
        migrator.registerMigration("v3-category") { db in
            try db.alter(table: "clips") { t in
                t.add(column: "cat_cipher", .blob)
                t.add(column: "cat_nonce", .blob)
            }
        }
        // v4: encrypted OCR text for image clips, so images are searchable by
        // the text inside them. Recognized on-device after capture.
        migrator.registerMigration("v4-ocr-text") { db in
            try db.alter(table: "clips") { t in
                t.add(column: "ocr_cipher", .blob)
                t.add(column: "ocr_nonce", .blob)
            }
        }
        // v5: saved snippets — curated, reusable text the user keeps around,
        // in their own table (never swept by expiry/limit). Label and body are
        // AES-256-GCM ciphertext like clip content.
        migrator.registerMigration("v5-snippets") { db in
            try db.create(table: "snippets") { t in
                t.primaryKey("id", .text)
                t.column("label_cipher", .blob).notNull()
                t.column("label_nonce", .blob).notNull()
                t.column("body_cipher", .blob).notNull()
                t.column("body_nonce", .blob).notNull()
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .integer).notNull()
                t.column("last_used_at", .integer)
            }
        }
        // v6: optional encrypted typed trigger for auto-expand (#11).
        migrator.registerMigration("v6-snippet-trigger") { db in
            try db.alter(table: "snippets") { t in
                t.add(column: "trigger_cipher", .blob)
                t.add(column: "trigger_nonce", .blob)
            }
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - Writes

    public func insert(_ capture: CaptureInput, now: Date = Date()) throws -> InsertOutcome {
        let originalCount = capture.countOverride ?? capture.plainText.count
        if capture.kind == .text,
           capture.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .skippedEmpty
        }
        var text = capture.plainText
        if capture.kind == .text, text.count > Self.maxStoredCharacters {
            text = String(text.prefix(Self.maxStoredCharacters)) + "⋯"
        }

        // Dedup identity: the payload bytes for images (the placeholder text
        // would collide distinct images), the text itself otherwise.
        let hash: String =
            if capture.kind == .image, let payload = capture.richData {
                keys.contentHash(payload)
            } else {
                keys.contentHash(text)
            }
        let epoch = Int64(now.timeIntervalSince1970)
        let encryptor = self.encryptor

        return try dbQueue.write { db in
            if let existing = try Row.fetchOne(
                db,
                sql: "SELECT id, is_flagged FROM clips WHERE content_hash = ?",
                arguments: [hash]
            ) {
                let id: String = existing["id"]
                // Re-copying bumps recency instead of duplicating (PRD §9).
                try db.execute(
                    sql: "UPDATE clips SET last_used_at = ? WHERE id = ?",
                    arguments: [epoch, id]
                )
                // A re-copy may carry a flag the stored row predates (e.g. the
                // user enabled pattern detection after the first copy).
                let alreadyFlagged: Bool = existing["is_flagged"]
                if let reason = capture.flagReason, !alreadyFlagged {
                    try db.execute(
                        sql: "UPDATE clips SET is_flagged = 1, flag_reason = ? WHERE id = ?",
                        arguments: [reason.rawValue, id]
                    )
                }
                return .updatedExisting(UUID(uuidString: id) ?? UUID())
            }

            let id = UUID()
            let (cipher, nonce) = try encryptor.encrypt(Data(text.utf8))
            var richCipher: Data?
            var richNonce: Data?
            if let rich = capture.richData {
                let sealed = try encryptor.encrypt(rich)
                richCipher = sealed.ciphertext
                richNonce = sealed.nonce
            }
            var thumbCipher: Data?
            var thumbNonce: Data?
            if let thumb = capture.thumbnailData {
                let sealed = try encryptor.encrypt(thumb)
                thumbCipher = sealed.ciphertext
                thumbNonce = sealed.nonce
            }
            try db.execute(
                sql: """
                    INSERT INTO clips
                      (id, kind, ciphertext, nonce, rich_cipher, rich_nonce, rich_type,
                       thumb_cipher, thumb_nonce,
                       content_hash, char_count, source_bundle,
                       is_pinned, is_burn, is_flagged, flag_reason, created_at, last_used_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, NULL)
                    """,
                arguments: [
                    id.uuidString, capture.kind.rawValue, cipher, nonce, richCipher, richNonce,
                    capture.richData != nil ? capture.richType : nil,
                    thumbCipher, thumbNonce,
                    hash, originalCount, capture.sourceBundle,
                    capture.isBurn, capture.flagReason != nil,
                    capture.flagReason?.rawValue, epoch,
                ]
            )
            return .inserted(id)
        }
    }

    public func delete(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM clips WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func deleteAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM clips")
        }
    }

    public func setPinned(id: UUID, _ pinned: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET is_pinned = ? WHERE id = ?",
                arguments: [pinned, id.uuidString]
            )
        }
    }

    public func setBurn(id: UUID, _ burn: Bool) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET is_burn = ? WHERE id = ?",
                arguments: [burn, id.uuidString]
            )
        }
    }

    /// Assigns (or, with `nil`, clears) the item's category. The label is
    /// encrypted on disk; passing an empty/whitespace string clears it.
    public func setCategory(id: UUID, _ category: String?) throws {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        let encryptor = self.encryptor
        try dbQueue.write { db in
            if let trimmed, !trimmed.isEmpty {
                let (cipher, nonce) = try encryptor.encrypt(Data(trimmed.utf8))
                try db.execute(
                    sql: "UPDATE clips SET cat_cipher = ?, cat_nonce = ? WHERE id = ?",
                    arguments: [cipher, nonce, id.uuidString]
                )
            } else {
                try db.execute(
                    sql: "UPDATE clips SET cat_cipher = NULL, cat_nonce = NULL WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
        }
    }

    /// Clears the flag on every row (`is_flagged` → 0, `flag_reason` → NULL).
    /// Lets the user un-mask items mislabeled by an earlier scan without
    /// erasing history. Content and pins are untouched.
    @discardableResult
    public func resetAllFlags() throws -> Int {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE clips SET is_flagged = 0, flag_reason = NULL")
            return db.changesCount
        }
    }

    /// Clears the concealed flag on every row recorded under `sourceBundle`,
    /// un-masking copies from an app that over-applies `ConcealedType` (e.g. a
    /// dictation or chat app). Other flag reasons and other sources untouched.
    @discardableResult
    public func unconcealSource(_ sourceBundle: String) throws -> Int {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET is_flagged = 0, flag_reason = NULL WHERE flag_reason = ? AND source_bundle = ?",
                arguments: [FlagReason.concealed.rawValue, sourceBundle]
            )
            return db.changesCount
        }
    }

    /// Stores encrypted OCR text for an image clip (searchable text-in-images).
    /// No-op style: passing empty/whitespace clears it.
    public func setOCRText(id: UUID, _ text: String?) throws {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let encryptor = self.encryptor
        try dbQueue.write { db in
            if let trimmed, !trimmed.isEmpty {
                let (cipher, nonce) = try encryptor.encrypt(Data(trimmed.utf8))
                try db.execute(
                    sql: "UPDATE clips SET ocr_cipher = ?, ocr_nonce = ? WHERE id = ?",
                    arguments: [cipher, nonce, id.uuidString]
                )
            } else {
                try db.execute(
                    sql: "UPDATE clips SET ocr_cipher = NULL, ocr_nonce = NULL WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
        }
    }

    public func markUsed(id: UUID, now: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clips SET last_used_at = ? WHERE id = ?",
                arguments: [Int64(now.timeIntervalSince1970), id.uuidString]
            )
        }
    }

    /// Deletes unpinned items whose last activity is older than the cutoff.
    /// Uses last-touched rather than strictly created_at so a re-copied item
    /// stays alive (dedup bumps `last_used_at` instead of inserting).
    @discardableResult
    public func sweepExpired(olderThan cutoff: Date) throws -> Int {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM clips
                    WHERE is_pinned = 0
                      AND COALESCE(last_used_at, created_at) < ?
                    """,
                arguments: [Int64(cutoff.timeIntervalSince1970)]
            )
            return db.changesCount
        }
    }

    /// Keeps at most `maxItems` unpinned items, pruning the oldest.
    /// Pinned items are exempt and don't count toward the limit.
    @discardableResult
    public func enforceLimit(_ maxItems: Int) throws -> Int {
        guard maxItems > 0 else { return 0 }
        return try dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM clips
                    WHERE is_pinned = 0 AND id NOT IN (
                        SELECT id FROM clips
                        WHERE is_pinned = 0
                        ORDER BY COALESCE(last_used_at, created_at) DESC
                        LIMIT ?
                    )
                    """,
                arguments: [maxItems]
            )
            return db.changesCount
        }
    }

    // MARK: - Snippets

    /// Inserts a new snippet. Empty label *and* body are rejected (returns nil).
    /// New snippets sort after all existing ones.
    @discardableResult
    public func insertSnippet(label: String, body: String, trigger: String? = nil, now: Date = Date()) throws -> Snippet? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty || !body.isEmpty else { return nil }
        let cleanTrigger = Self.cleanTrigger(trigger)
        let id = UUID()
        let epoch = Int64(now.timeIntervalSince1970)
        let encryptor = self.encryptor
        return try dbQueue.write { db in
            let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(sort_order) FROM snippets") ?? -1
            let order = maxOrder + 1
            let (labelCipher, labelNonce) = try encryptor.encrypt(Data(trimmedLabel.utf8))
            let (bodyCipher, bodyNonce) = try encryptor.encrypt(Data(body.utf8))
            let triggerSealed = try cleanTrigger.map { try encryptor.encrypt(Data($0.utf8)) }
            try db.execute(
                sql: """
                    INSERT INTO snippets
                      (id, label_cipher, label_nonce, body_cipher, body_nonce,
                       trigger_cipher, trigger_nonce, sort_order, created_at, last_used_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                    """,
                arguments: [
                    id.uuidString, labelCipher, labelNonce, bodyCipher, bodyNonce,
                    triggerSealed?.ciphertext, triggerSealed?.nonce, order, epoch,
                ]
            )
            return Snippet(
                id: id, label: trimmedLabel, body: body, trigger: cleanTrigger,
                sortOrder: order, createdAt: now
            )
        }
    }

    /// Updates an existing snippet's label, body, and trigger in place.
    public func updateSnippet(id: UUID, label: String, body: String, trigger: String? = nil) throws {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrigger = Self.cleanTrigger(trigger)
        let encryptor = self.encryptor
        try dbQueue.write { db in
            let (labelCipher, labelNonce) = try encryptor.encrypt(Data(trimmedLabel.utf8))
            let (bodyCipher, bodyNonce) = try encryptor.encrypt(Data(body.utf8))
            let triggerSealed = try cleanTrigger.map { try encryptor.encrypt(Data($0.utf8)) }
            try db.execute(
                sql: """
                    UPDATE snippets
                       SET label_cipher = ?, label_nonce = ?, body_cipher = ?, body_nonce = ?,
                           trigger_cipher = ?, trigger_nonce = ?
                     WHERE id = ?
                    """,
                arguments: [
                    labelCipher, labelNonce, bodyCipher, bodyNonce,
                    triggerSealed?.ciphertext, triggerSealed?.nonce, id.uuidString,
                ]
            )
        }
    }

    /// Normalizes a trigger: trimmed, nil when empty.
    private static func cleanTrigger(_ trigger: String?) -> String? {
        let trimmed = trigger?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    public func deleteSnippet(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM snippets WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func markSnippetUsed(id: UUID, now: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE snippets SET last_used_at = ? WHERE id = ?",
                arguments: [Int64(now.timeIntervalSince1970), id.uuidString]
            )
        }
    }

    /// Persists a new ordering: `sort_order` is rewritten to each id's position
    /// in `orderedIDs`. Ids not present are left untouched.
    public func reorderSnippets(_ orderedIDs: [UUID]) throws {
        try dbQueue.write { db in
            for (index, id) in orderedIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE snippets SET sort_order = ? WHERE id = ?",
                    arguments: [index, id.uuidString]
                )
            }
        }
    }

    /// All snippets in user order (sort_order ASC), oldest-created breaking ties.
    public func fetchSnippets() throws -> [Snippet] {
        let encryptor = self.encryptor
        let rows = try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM snippets ORDER BY sort_order ASC, created_at ASC"
            )
        }
        return rows.compactMap { Self.decryptSnippet($0, encryptor: encryptor) }
    }

    private static func decryptSnippet(_ row: Row, encryptor: EncryptionService) -> Snippet? {
        guard
            let idString: String = row["id"],
            let id = UUID(uuidString: idString),
            let labelCipher: Data = row["label_cipher"],
            let labelNonce: Data = row["label_nonce"],
            let bodyCipher: Data = row["body_cipher"],
            let bodyNonce: Data = row["body_nonce"],
            let labelData = try? encryptor.decrypt(ciphertext: labelCipher, nonce: labelNonce),
            let bodyData = try? encryptor.decrypt(ciphertext: bodyCipher, nonce: bodyNonce),
            let label = String(data: labelData, encoding: .utf8),
            let body = String(data: bodyData, encoding: .utf8)
        else { return nil }
        var trigger: String?
        if let tCipher: Data = row["trigger_cipher"], let tNonce: Data = row["trigger_nonce"],
           let tData = try? encryptor.decrypt(ciphertext: tCipher, nonce: tNonce) {
            trigger = String(data: tData, encoding: .utf8)
        }
        let createdEpoch: Int64 = row["created_at"]
        let lastUsedEpoch: Int64? = row["last_used_at"]
        return Snippet(
            id: id,
            label: label,
            body: body,
            trigger: trigger,
            sortOrder: row["sort_order"],
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdEpoch)),
            lastUsedAt: lastUsedEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    // MARK: - Reads

    public func count() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clips") ?? 0
        }
    }

    /// Decrypts and returns the full history, pinned items first, then most
    /// recently used. Rows that fail to decrypt (corruption, key mismatch) are
    /// skipped rather than failing the whole fetch.
    public func fetchAll() throws -> [ClipItem] {
        let encryptor = self.encryptor
        let rows = try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM clips
                    ORDER BY is_pinned DESC, COALESCE(last_used_at, created_at) DESC
                    """
            )
        }
        return rows.compactMap { row in Self.decryptRow(row, encryptor: encryptor) }
    }

    private static func decryptRow(_ row: Row, encryptor: EncryptionService) -> ClipItem? {
        guard
            let idString: String = row["id"],
            let id = UUID(uuidString: idString),
            let cipher: Data = row["ciphertext"],
            let nonce: Data = row["nonce"],
            let plainData = try? encryptor.decrypt(ciphertext: cipher, nonce: nonce),
            let plain = String(data: plainData, encoding: .utf8)
        else { return nil }

        var rich: Data?
        if let richCipher: Data = row["rich_cipher"], let richNonce: Data = row["rich_nonce"] {
            rich = try? encryptor.decrypt(ciphertext: richCipher, nonce: richNonce)
        }
        var thumbnail: Data?
        if let thumbCipher: Data = row["thumb_cipher"], let thumbNonce: Data = row["thumb_nonce"] {
            thumbnail = try? encryptor.decrypt(ciphertext: thumbCipher, nonce: thumbNonce)
        }
        var category: String?
        if let catCipher: Data = row["cat_cipher"], let catNonce: Data = row["cat_nonce"],
           let catData = try? encryptor.decrypt(ciphertext: catCipher, nonce: catNonce) {
            category = String(data: catData, encoding: .utf8)
        }
        var ocrText: String?
        if let ocrCipher: Data = row["ocr_cipher"], let ocrNonce: Data = row["ocr_nonce"],
           let ocrData = try? encryptor.decrypt(ciphertext: ocrCipher, nonce: ocrNonce) {
            ocrText = String(data: ocrData, encoding: .utf8)
        }

        let createdEpoch: Int64 = row["created_at"]
        let lastUsedEpoch: Int64? = row["last_used_at"]
        let reason: String? = row["flag_reason"]
        let kindRaw: String? = row["kind"]

        return ClipItem(
            id: id,
            kind: kindRaw.flatMap(ClipKind.init(rawValue:)) ?? .text,
            plainText: plain,
            richData: rich,
            richType: row["rich_type"],
            thumbnailData: thumbnail,
            charCount: row["char_count"],
            sourceBundle: row["source_bundle"],
            isPinned: row["is_pinned"],
            isBurn: row["is_burn"],
            isFlagged: row["is_flagged"],
            flagReason: reason.flatMap(FlagReason.init(rawValue:)),
            category: category,
            ocrText: ocrText,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdEpoch)),
            lastUsedAt: lastUsedEpoch.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    // MARK: - Sync (#12 E2E folder sync)

    /// Every live clip as a sync record, hashed with the *shared* sync key so
    /// the same content converges across the user's devices.
    public func exportLiveRecords(syncKeys: SyncKeyMaterial) throws -> [SyncRecord] {
        try fetchAll().map { SyncRecord.live($0, keys: syncKeys) }
    }

    /// Reconciles the local store to the merged change log: inserts content that
    /// isn't here yet, applies newer metadata (pin/burn/last-used/category/flag/
    /// OCR) by last-writer-wins, and deletes clips a newer tombstone removed.
    /// Content identity is the shared `syncHash`; matching local rows are found
    /// by re-hashing their content with the same key.
    @discardableResult
    public func applySync(_ merged: [SyncRecord], syncKeys: SyncKeyMaterial) throws -> SyncApplyStats {
        let live = try fetchAll()
        var localBySync: [String: ClipItem] = [:]
        for item in live {
            localBySync[syncKeys.syncHash(Self.canonicalBytes(of: item))] = item
        }
        let encryptor = self.encryptor
        let keys = self.keys
        var stats = SyncApplyStats()
        try dbQueue.write { db in
            for record in merged {
                let local = localBySync[record.syncHash]
                if record.deleted {
                    if let local, (local.lastUsedAt ?? local.createdAt) < record.updatedAt {
                        try db.execute(
                            sql: "DELETE FROM clips WHERE id = ?",
                            arguments: [local.id.uuidString]
                        )
                        stats.deleted += 1
                    }
                } else if let payload = record.payload {
                    if let local {
                        if (local.lastUsedAt ?? local.createdAt) < record.updatedAt {
                            try Self.updateMetadata(db, id: local.id, from: payload, encryptor: encryptor)
                            stats.updated += 1
                        }
                    } else if try Self.insertImported(db, payload: payload, keys: keys, encryptor: encryptor) {
                        stats.inserted += 1
                    }
                }
            }
        }
        return stats
    }

    private static func canonicalBytes(of item: ClipItem) -> Data {
        item.kind == .image ? (item.richData ?? Data(item.plainText.utf8)) : Data(item.plainText.utf8)
    }

    /// Updates the mutable metadata of an existing row from a newer sync payload
    /// (the content itself is identical — same `syncHash` — so it isn't rewritten).
    private static func updateMetadata(
        _ db: Database, id: UUID, from payload: SyncPayload, encryptor: EncryptionService
    ) throws {
        try db.execute(
            sql: """
                UPDATE clips
                   SET is_pinned = ?, is_burn = ?, is_flagged = ?, flag_reason = ?, last_used_at = ?
                 WHERE id = ?
                """,
            arguments: [
                payload.isPinned, payload.isBurn, payload.flagReason != nil,
                payload.flagReason?.rawValue,
                payload.lastUsedAt.map { Int64($0.timeIntervalSince1970) }, id.uuidString,
            ]
        )
        try setEncryptedColumn(db, id: id, value: payload.category, encryptor: encryptor,
                               cipherColumn: "cat_cipher", nonceColumn: "cat_nonce")
        try setEncryptedColumn(db, id: id, value: payload.ocrText, encryptor: encryptor,
                               cipherColumn: "ocr_cipher", nonceColumn: "ocr_nonce")
    }

    /// Sets (or clears, when nil/empty) a pair of encrypted cipher/nonce columns.
    private static func setEncryptedColumn(
        _ db: Database, id: UUID, value: String?, encryptor: EncryptionService,
        cipherColumn: String, nonceColumn: String
    ) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            let (cipher, nonce) = try encryptor.encrypt(Data(trimmed.utf8))
            try db.execute(
                sql: "UPDATE clips SET \(cipherColumn) = ?, \(nonceColumn) = ? WHERE id = ?",
                arguments: [cipher, nonce, id.uuidString]
            )
        } else {
            try db.execute(
                sql: "UPDATE clips SET \(cipherColumn) = NULL, \(nonceColumn) = NULL WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    /// Inserts a clip received from another device, preserving its timestamps and
    /// metadata. Identity is the local `content_hash`; if that content is already
    /// present this is a no-op (returns false).
    private static func insertImported(
        _ db: Database, payload: SyncPayload, keys: KeyMaterial, encryptor: EncryptionService
    ) throws -> Bool {
        let hash = keys.contentHash(payload.canonicalBytes)
        if try Row.fetchOne(db, sql: "SELECT 1 FROM clips WHERE content_hash = ?", arguments: [hash]) != nil {
            return false
        }
        let id = UUID()
        let (cipher, nonce) = try encryptor.encrypt(Data(payload.plainText.utf8))
        let rich = try payload.richData.map { try encryptor.encrypt($0) }
        let thumb = try payload.thumbnailData.map { try encryptor.encrypt($0) }
        let category = try payload.category
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { try encryptor.encrypt(Data($0.utf8)) }
        let ocr = try payload.ocrText
            .flatMap { $0.isEmpty ? nil : $0 }
            .map { try encryptor.encrypt(Data($0.utf8)) }
        try db.execute(
            sql: """
                INSERT INTO clips
                  (id, kind, ciphertext, nonce, rich_cipher, rich_nonce, rich_type,
                   thumb_cipher, thumb_nonce, cat_cipher, cat_nonce, ocr_cipher, ocr_nonce,
                   content_hash, char_count, source_bundle,
                   is_pinned, is_burn, is_flagged, flag_reason, created_at, last_used_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                id.uuidString, payload.kind.rawValue, cipher, nonce,
                rich?.ciphertext, rich?.nonce, payload.richData != nil ? payload.richType : nil,
                thumb?.ciphertext, thumb?.nonce, category?.ciphertext, category?.nonce,
                ocr?.ciphertext, ocr?.nonce,
                hash, payload.charCount, payload.sourceBundle,
                payload.isPinned, payload.isBurn, payload.flagReason != nil,
                payload.flagReason?.rawValue,
                Int64(payload.createdAt.timeIntervalSince1970),
                payload.lastUsedAt.map { Int64($0.timeIntervalSince1970) },
            ]
        )
        return true
    }

    // MARK: - Test hooks

    /// Raw column access for security assertions in tests
    /// ("ciphertext must not contain plaintext").
    func rawRows() throws -> [Row] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM clips")
        }
    }

    /// Raw snippet rows for the encryption-at-rest assertion in tests.
    func rawSnippetRows() throws -> [Row] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM snippets")
        }
    }
}
