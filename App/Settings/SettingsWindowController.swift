import AppKit
import SwiftUI

/// A regular activating window — unlike the panel it *should* take focus
/// (docs/DESIGN.md §5). Opened only from the menu bar since LSUIElement apps
/// have no standard app menu.
@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(appState: AppState) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SafeClip Settings"
        window.contentView = NSHostingView(rootView: SettingsView(appState: appState))
        window.center()
        window.setFrameAutosaveName("SafeClipSettings")
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func open() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Explicit user intent ("Settings…" clicked) justifies activation.
        NSApp.activate(ignoringOtherApps: true)
    }
}
