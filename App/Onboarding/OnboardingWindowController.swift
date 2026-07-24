import AppKit
import SwiftUI

/// First-launch onboarding (PRD §7). Skipping or closing the window records no
/// consent, so clipboard capture stays off and the wizard re-appears next launch
/// until the user accepts (AppDelegate gates capture on that consent). TERMS §9
/// still makes continued use acceptance of the Terms.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private var completion: ((_ result: OnboardingResult) -> Void)?
    private var finished = false

    convenience init(
        appState: AppState,
        initialConsent: OnboardingResult = OnboardingResult(
            acceptedTerms: false, acceptedPrivacy: false, acceptedMarketing: false
        ),
        completion: @escaping (_ result: OnboardingResult) -> Void
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
                self?.finish(result: result)
            }
        )
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(result: OnboardingResult) {
        guard !finished else { return }
        finished = true
        completion?(result)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // A bare close (red button / ⌘W) reports no consent, same as Skip. The
        // `finished` guard means this no-ops after an explicit Start/Skip.
        finish(result: OnboardingResult(acceptedTerms: false, acceptedPrivacy: false, acceptedMarketing: false))
    }
}
