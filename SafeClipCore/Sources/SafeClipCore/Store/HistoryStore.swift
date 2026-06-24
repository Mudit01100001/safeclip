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

    // MARK: - Test hooks

    /// Raw column access for security assertions in tests
    /// ("ciphertext must not contain plaintext").
    func rawRows() throws -> [Row] {
        try dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM clips")
        }
    }
}
