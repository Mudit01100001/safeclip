import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens the floating history panel at the cursor. Default ⌥V (PRD §7).
    /// Rebindable in Settings → General.
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.option]))

    /// Captures a screen region, OCRs it, and copies the recognized text to the
    /// clipboard — the image is never stored. Default ⌥C. Rebindable in
    /// Settings → General.
    static let captureOCR = Self("captureOCR", default: .init(.c, modifiers: [.option]))

    /// Quick-paste the top 10 history items without opening the panel: each
    /// places the Nth item on the clipboard for the user's own ⌘V (no ⌘V is
    /// synthesized — the zero-permission pillar holds). Defaults ⌃⌘1…⌃⌘9 then
    /// ⌃⌘0 for the 10th, matching the panel's top-to-bottom order. Rebindable
    /// (or clearable to disable) in Settings → General.
    static let quickPaste: [Self] = {
        let digits: [(KeyboardShortcuts.Key, Int)] = [
            (.one, 1), (.two, 2), (.three, 3), (.four, 4), (.five, 5),
            (.six, 6), (.seven, 7), (.eight, 8), (.nine, 9), (.zero, 0),
        ]
        return digits.map { key, digit in
            Self("quickPaste\(digit)", default: .init(key, modifiers: [.command, .control]))
        }
    }()
}
