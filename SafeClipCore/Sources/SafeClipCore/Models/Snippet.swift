import Foundation

/// A user-authored saved snippet — a named, reusable piece of text the user
/// keeps around (email signature, address, boilerplate). Stored encrypted like
/// clipboard history; pasting one places its `body` on the pasteboard for the
/// user's own ⌘V (Tier-A — no synthesized keystrokes, see PRD §8.1).
///
/// Snippets live in their own table, separate from clipboard history: they are
/// curated and persistent, never swept by expiry or the history limit.
public struct Snippet: Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Short name shown in the list (e.g. "Work email").
    public var label: String
    /// The text placed on the clipboard when the snippet is used.
    public var body: String
    /// Optional typed trigger (e.g. ";sig"). When auto-expand is enabled and
    /// Accessibility is granted, typing this anywhere replaces it with `body`.
    /// nil/empty = no trigger (the snippet is panel-only).
    public var trigger: String?
    /// User-defined position in the list; lower sorts first.
    public var sortOrder: Int
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        body: String,
        trigger: String? = nil,
        sortOrder: Int = 0,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.body = body
        self.trigger = trigger
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    /// A one-line preview of the body for compact list rows.
    public var bodyPreview: String {
        body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
