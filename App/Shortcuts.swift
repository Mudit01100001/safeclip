import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Default ⌃⇧V (PRD §7). Rebindable in Settings → General.
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.control, .shift]))
}
