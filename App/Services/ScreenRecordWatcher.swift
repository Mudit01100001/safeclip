import AppKit

/// Best-effort screen-recording detection without any permission (F8).
///
/// Honest limitation (ROADMAP risk register): macOS has no public
/// "someone is recording the screen" query that works without holding the
/// Screen Recording permission ourselves — which would violate the
/// zero-permission pledge. What we can see permission-free:
///  - the ⌘⇧5 system capture UI (`screencaptureui`) while a screenshot or
///    recording is being set up / running
///
/// Conferencing-app sharing (Zoom, Meet) is not reliably detectable, which is
/// why the menu bar also offers a one-click manual Privacy Mode that hides
/// history instantly before a call.
@MainActor
final class ScreenRecordWatcher {
    var onChange: ((Bool) -> Void)?
    private(set) var isRecordingLikely = false
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let suspicious = NSWorkspace.shared.runningApplications.contains { app in
            app.bundleIdentifier == "com.apple.screencaptureui"
        }
        if suspicious != isRecordingLikely {
            isRecordingLikely = suspicious
            onChange?(suspicious)
        }
    }
}
