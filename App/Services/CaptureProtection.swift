import AppKit

/// Screen-capture protection for the windows that show clipboard history, a
/// just-copied value, or the color-picker loupe. Normally these are excluded
/// from screen capture (`.none`) so they can never leak into someone else's
/// screenshot or recording — one of SafeClip's core privacy promises (they're
/// invisible in QuickTime, ⌘⇧5, Zoom/Meet screen-share, etc.).
///
/// That same exclusion means the OWNER can't record the app for marketing
/// previews either. This is the single, owner-only lever to lift it — nobody
/// else can, and it's off by default:
///
///   • **Debug build (Xcode ⌘R): always recordable.** Debug builds are never
///     distributed, so this can't affect any shipped install.
///   • **Release build: only if a hidden default is set,** then relaunch:
///       `defaults write com.mudit.safeclip allowScreenRecording -bool YES`
///     There is no UI for it and the app is closed-source, so it's
///     undiscoverable; and even if someone flipped it, it would only un-protect
///     *their own* windows on *their own* machine, never anyone else's.
///
/// Turn the release lever back off with:
///   `defaults write com.mudit.safeclip allowScreenRecording -bool NO`
enum CaptureProtection {
    static let recordingDefaultsKey = "allowScreenRecording"

    /// Whether capture-sensitive windows may be recorded on this machine.
    static var recordingAllowed: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: recordingDefaultsKey)
        #endif
    }

    /// The `sharingType` to assign to every capture-sensitive window: excluded
    /// (`.none`) normally, readable (`.readOnly`) only when recording is allowed.
    static var sharingType: NSWindow.SharingType {
        recordingAllowed ? .readOnly : .none
    }
}
