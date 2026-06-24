import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Opens the floating history panel at the cursor. Default ⌥V (PRD §7).
    /// Rebindable in Settings → General.
    static let togglePanel = Self("togglePanel", default: .init(.v, modifiers: [.option]))

    /// Captures a screen region, OCRs it, and copies the recognized text to the
    /// clipboard — the image is never stored. Default ⌥C. Rebindable in
    /// Settings → General.
    static let captureOCR = Self("captureOCR", default: .init(.c, modifiers: [.option]))

    /// Captures a pixel color from anywhere on screen (system eyedropper) and
    /// copies its hex to the clipboard. Default ⌥P. Rebindable in Settings.
    static let pickColor = Self("pickColor", default: .init(.p, modifiers: [.option]))

    /// Number keys 1…9 then 0, paired with the `quickPaste` names below.
    static let quickPasteKeys: [KeyboardShortcuts.Key] = [
        .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero,
    ]

    /// Quick-paste the top 10 history items without opening the panel: each
    /// places the Nth item on the clipboard for the user's own ⌘V (no ⌘V is
    /// synthesized — the zero-permission pillar holds). Defaults ⌃⌘1…⌃⌘9 then
    /// ⌃⌘0 for the 10th, matching the panel's top-to-bottom order. The base
    /// modifier is rebindable for all slots at once in Settings → General.
    static let quickPaste: [Self] = quickPasteKeys.enumerated().map { index, key in
        Self("quickPaste\((index + 1) % 10)", default: .init(key, modifiers: [.command, .control]))
    }

    /// Re-binds every quick-paste slot to the given base modifier at once, so
    /// the user can switch ⌃⌘ → ⌥⌘ etc. without editing all ten by hand.
    static func applyQuickPasteModifier(_ flags: NSEvent.ModifierFlags) {
        for (index, name) in quickPaste.enumerated() {
            KeyboardShortcuts.setShortcut(.init(quickPasteKeys[index], modifiers: flags), for: name)
        }
    }
}
