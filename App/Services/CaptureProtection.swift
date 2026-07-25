import AppKit

/// Screen-capture protection for the windows that show clipboard history, a
/// just-copied value, or the color-picker loupe. These are excluded from screen
/// capture (`.none`) so they can never leak into someone else's screenshot or
/// recording — one of SafeClip's core privacy promises (they're invisible in
/// QuickTime, ⌘⇧5, Zoom/Meet screen-share, etc.).
///
/// **Release builds are always protected** — there is no runtime lever to lift
/// it, so the shipped app can never be recorded. The same exclusion also stops
/// the owner from recording the app for marketing previews, so a Debug build can
/// lift it via the local `DeveloperFlags.allowScreenRecording` toggle (developer
/// option, never committed on, ignored by release). See DeveloperFlags.swift.
enum CaptureProtection {
    /// Whether capture-sensitive windows may be recorded. Debug builds honor the
    /// local developer toggle; release builds never allow it.
    static var recordingAllowed: Bool {
        #if DEBUG
        return DeveloperFlags.allowScreenRecording
        #else
        return false
        #endif
    }

    /// The `sharingType` to assign to every capture-sensitive window: excluded
    /// (`.none`) normally, readable (`.readOnly`) only when recording is allowed.
    static var sharingType: NSWindow.SharingType {
        recordingAllowed ? .readOnly : .none
    }
}
