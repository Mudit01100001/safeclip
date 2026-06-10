import Foundation

/// Why an item was flagged by the security scanner or capture pipeline.
public enum FlagReason: String, Codable, Sendable, CaseIterable {
    case apiKey = "api_key"
    case card = "card"
    case privateKey = "private_key"
    case clickfix = "clickfix"
    /// The source app marked the pasteboard content as concealed
    /// (`org.nspasteboard.ConcealedType`) — typically a password manager.
    case concealed = "concealed"

    public var displayName: String {
        switch self {
        case .apiKey: "API key"
        case .card: "Card number"
        case .privateKey: "Private key"
        case .clickfix: "Possible pastejacking"
        case .concealed: "Password (concealed)"
        }
    }

    /// True for reasons that should warn the user before pasting.
    public var warnsBeforePaste: Bool {
        self == .clickfix
    }
}

/// What a history item fundamentally is. Added in v0.2.0 — images and file
/// copies were a v1 non-goal (PRD §13), revised by owner decision.
public enum ClipKind: String, Codable, Sendable {
    case text
    /// `richData` holds the encrypted image bytes (PNG-normalized),
    /// `thumbnailData` a small encrypted preview, `plainText` a searchable
    /// placeholder like "Image 1280×800" (display/search only — pasting an
    /// image always pastes the image).
    case image
    /// `plainText` holds the newline-joined POSIX paths — that *is* the
    /// plain-text representation; pasting re-creates real file URLs.
    case fileList = "file_list"
}

/// A decrypted clipboard history item, as held in memory while the app runs.
/// The on-disk representation is always ciphertext (see `HistoryStore`).
public struct ClipItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: ClipKind
    public var plainText: String
    public var richData: Data?
    public var richType: String?
    public var thumbnailData: Data?
    /// For `.text`: character count. For `.image`: stored byte count.
    /// For `.fileList`: number of files.
    public var charCount: Int
    public var sourceBundle: String?
    public var isPinned: Bool
    public var isBurn: Bool
    public var isFlagged: Bool
    public var flagReason: FlagReason?
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        kind: ClipKind = .text,
        plainText: String,
        richData: Data? = nil,
        richType: String? = nil,
        thumbnailData: Data? = nil,
        charCount: Int,
        sourceBundle: String? = nil,
        isPinned: Bool = false,
        isBurn: Bool = false,
        isFlagged: Bool = false,
        flagReason: FlagReason? = nil,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.plainText = plainText
        self.richData = richData
        self.richType = richType
        self.thumbnailData = thumbnailData
        self.charCount = charCount
        self.sourceBundle = sourceBundle
        self.isPinned = isPinned
        self.isBurn = isBurn
        self.isFlagged = isFlagged
        self.flagReason = flagReason
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    public var isConcealed: Bool { flagReason == .concealed }
}

/// Input to `HistoryStore.insert` — one captured pasteboard change.
public struct CaptureInput: Sendable {
    public var kind: ClipKind
    public var plainText: String
    public var richData: Data?
    public var richType: String?
    public var thumbnailData: Data?
    public var sourceBundle: String?
    public var flagReason: FlagReason?
    public var isBurn: Bool
    /// Overrides the dedup/display count for non-text kinds (image bytes,
    /// file count). Defaults to the plain text's character count.
    public var countOverride: Int?

    public init(
        kind: ClipKind = .text,
        plainText: String,
        richData: Data? = nil,
        richType: String? = nil,
        thumbnailData: Data? = nil,
        sourceBundle: String? = nil,
        flagReason: FlagReason? = nil,
        isBurn: Bool = false,
        countOverride: Int? = nil
    ) {
        self.kind = kind
        self.plainText = plainText
        self.richData = richData
        self.richType = richType
        self.thumbnailData = thumbnailData
        self.sourceBundle = sourceBundle
        self.flagReason = flagReason
        self.isBurn = isBurn
        self.countOverride = countOverride
    }
}

public enum InsertOutcome: Sendable, Equatable {
    /// A new row was written.
    case inserted(UUID)
    /// Identical content already existed; its `last_used_at` was bumped.
    case updatedExisting(UUID)
    /// Whitespace-only or empty content — nothing stored.
    case skippedEmpty
}
