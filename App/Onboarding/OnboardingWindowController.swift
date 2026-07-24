import AppKit
import SwiftUI

/// First-launch onboarding (PRD §7). Explicitly finishing (Start/Skip) is
/// distinct from simply closing the window: the `completed` flag lets the
/// caller re-show onboarding next launch if the user dismissed it without
/// finishing (e.g. closed it to move the app out of the DMG). TERMS §9 still
/// makes continued use acceptance.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private var completion: ((_ result: OnboardingResult, _ completed: Bool) -> Void)?
    private var finished = false

    convenience init(
        appState: AppState,
        initialConsent: OnboardingResult = OnboardingResult(
            acceptedTerms: false, acceptedPrivacy: false, acceptedMarketing: false
        ),
        completion: @escaping (_ result: OnboardingResult, _ completed: Bool) -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to SafeClip"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.1, alpha: 1)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        self.completion = completion
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: OnboardingView(appState: appState, initialConsent: initialConsent) { [weak self] result in
                // Reaching Start or Skip is an explicit finish.
                self?.finish(result: result, completed: true)
            }
        )
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(result: OnboardingResult, completed: Bool) {
        guard !finished else { return }
        finished = true
        completion?(result, completed)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Bare close (red button / ⌘W) — not an explicit finish, so `completed`
        // is false. The `finished` guard means this no-ops after Start/Skip.
        finish(
            result: OnboardingResult(acceptedTerms: false, acceptedPrivacy: false, acceptedMarketing: false),
            completed: false
        )
    }
}
