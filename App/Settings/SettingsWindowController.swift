import AppKit
import SwiftUI

/// A regular activating window — unlike the panel it *should* take focus
/// (docs/DESIGN.md §5). Opened only from the menu bar since LSUIElement apps
/// have no standard app menu.
@MainActor
final class SettingsWindowController: NSWindowController {
    private var scrollerTimer: Timer?

    convenience init(appState: AppState, syncService: SyncService) {
        // Wider than the tab strip needs so the system-rendered tabs (which sit
        // in the title bar) centre clear of the traffic lights instead of being
        // shoved right. Autosave name bumped so this new width takes effect even
        // where the old 560-wide frame was already remembered.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SafeClip Settings"
        window.contentView = NSHostingView(
            rootView: SettingsView(appState: appState, syncService: syncService)
        )
        window.center()
        window.setFrameAutosaveName("SafeClipSettingsWide")
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func open() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Explicit user intent ("Settings…" clicked) justifies activation.
        NSApp.activate(ignoringOtherApps: true)
        startScrollerStyling()
    }

    /// SwiftUI Forms/Lists default to legacy always-on scrollers, and a `TabView`
    /// only builds a tab's scroll view when you first switch to it — so a one-time
    /// pass styles only the General tab. A light repeating pass (a no-op while the
    /// window is hidden) catches every tab as it appears.
    private func startScrollerStyling() {
        scrollerTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let window = self?.window, window.isVisible,
                      let content = window.contentView else { return }
                Self.applyOverlayScrollers(in: content)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scrollerTimer = timer
    }

    private static func applyOverlayScrollers(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
        }
        for subview in view.subviews { applyOverlayScrollers(in: subview) }
    }
}
