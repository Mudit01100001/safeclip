import AppKit
import SwiftUI

/// First-launch onboarding (PRD §7). Closing the window counts as skipping —
/// the app still works; TERMS §9 makes continued use acceptance.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private var completion: ((_ acceptedTerms: Bool) -> Void)?
    private var finished = false

    convenience init(appState: AppState, completion: @escaping (_ acceptedTerms: Bool) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to SafeClip"
        window.titlebarAppearsTransparent = true
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
        self.completion = completion
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: OnboardingView(appState: appState) { [weak self] accepted in
                self?.finish(accepted: accepted)
            }
        )
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(accepted: Bool) {
        guard !finished else { return }
        finished = true
        completion?(accepted)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Red-button close = skip.
        finish(accepted: false)
    }
}
