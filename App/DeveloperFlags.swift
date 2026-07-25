/// Local developer flags — NOT product configuration, and NOT read by release
/// builds. These toggle developer-only behavior in **Debug builds only**. The
/// values committed here are the safe defaults; flip one on your own machine when
/// you need it, then flip it back. Nothing here can affect the shipped app.
///
/// Keep a local flip out of git (so it's never committed or pushed) with, once:
///
///     git update-index --skip-worktree App/DeveloperFlags.swift
///     # undo later with: git update-index --no-skip-worktree App/DeveloperFlags.swift
///
/// (Even without that, `CaptureProtection` ignores these in release builds, so a
/// stray commit could never enable recording in the shipped app — this is just to
/// keep your working tree clean.)
enum DeveloperFlags {
    /// DEVELOPER OPTION — flip to `true` on your machine to record the app for
    /// marketing previews. The floating panel, the color-picker loupe, and the
    /// "copied" toast are normally excluded from screen capture (a privacy
    /// feature) which also stops *you* from recording them; this lifts that
    /// exclusion. Debug builds only — release builds always keep the protection.
    static let allowScreenRecording = false
}
