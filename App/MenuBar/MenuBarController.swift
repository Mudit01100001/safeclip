import AppKit
import KeyboardShortcuts

/// The always-present `NSStatusItem` (docs/DESIGN.md §3). App control only —
/// clip history lives in the floating panel, never in this menu.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    struct Actions {
        var showPanel: () -> Void
        var openSettings: () -> Void
        var clearAll: () -> Void
        var quit: () -> Void
    }

    private let statusItem: NSStatusItem
    private let appState: AppState
    private let actions: Actions

    init(appState: AppState, actions: Actions) {
        self.appState = appState
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        guard let button = statusItem.button else { return }
        let (symbol, description): (String, String) =
            if appState.historyHidden {
                ("eye.slash", "SafeClip — history hidden")
            } else if !appState.captureEnabled {
                ("pause.circle", "SafeClip — capture paused")
            } else {
                ("list.clipboard", "SafeClip — capturing")
            }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.image?.isTemplate = true
        button.toolTip = description
    }

    // Rebuilt on every open so state checkmarks are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let showTitle: String =
            if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) {
                "Show History (\(shortcut))"
            } else {
                "Show History"
            }
        menu.addItem(makeItem(showTitle, #selector(showPanel)))
        menu.addItem(.separator())

        let capture = makeItem(
            appState.captureEnabled ? "Pause Capture" : "Resume Capture",
            #selector(toggleCapture)
        )
        capture.state = appState.captureEnabled ? .off : .on
        menu.addItem(capture)

        let privacy = makeItem("Privacy Mode (Hide History)", #selector(togglePrivacyMode))
        privacy.state = appState.manualPrivacyMode ? .on : .off
        privacy.toolTip = "Hide history instantly — for screen shares SafeClip can't detect on its own."
        menu.addItem(privacy)

        if appState.pasteboardAccessDenied {
            menu.addItem(.separator())
            let denied = makeItem("⚠︎ Clipboard access denied — open System Settings…", #selector(openPasteboardSettings))
            menu.addItem(denied)
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Clear All History…", #selector(clearAll)))
        menu.addItem(.separator())
        let prefs = makeItem("Settings…", #selector(openSettings))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        menu.addItem(makeItem("About SafeClip", #selector(openAbout)))
        menu.addItem(.separator())
        let quit = makeItem("Quit SafeClip", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func showPanel() { actions.showPanel() }

    @objc private func toggleCapture() {
        appState.setCaptureEnabled(!appState.captureEnabled)
        refreshIcon()
    }

    @objc private func togglePrivacyMode() {
        appState.manualPrivacyMode.toggle()
        refreshIcon()
    }

    @objc private func openSettings() { actions.openSettings() }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "All encrypted history rows are deleted. This cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear All")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            actions.clearAll()
        }
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openPasteboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { actions.quit() }
}
