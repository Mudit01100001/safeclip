# Onboarding videos

Drop screen-recordings here named exactly:

- `onboarding-0-welcome.mp4`
- `onboarding-1-plaintext.mp4`
- `onboarding-2-shortcuts.mp4`
- `onboarding-3-privacy.mp4`
- `onboarding-4-permissions.mp4`

(Step 5, Terms, has no video by design.)

Each is picked up automatically on the next `xcodegen` + build. A step whose
file isn't present here falls back to its built-in schematic illustration —
see `App/Onboarding/OnboardingVideoPlayer.swift` and the `illustration`
property in `App/Onboarding/OnboardingView.swift`.

Spec: mp4 (H.264), no audio, 10-20s, loop-friendly (end state ≈ start
state), ≤8MB each, 16:9. Record with the Debug build — the Release panel is
excluded from screen capture (`sharingType = .none`) by design.
