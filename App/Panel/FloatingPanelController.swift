import AppKit
import SafeClipCore
import SwiftUI

/// NSPanel that can take key status without activating the owning app —
/// the active app keeps focus while the user types in our search field.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating panel (docs/DESIGN.md §4). The panel is created once at
/// startup and shown/hidden, so the shortcut→visible path allocates nothing.
@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    static let panelSize = NSSize(width: 380, height: 442)

    private let panel: FloatingPanel
    private let model: PanelViewModel
    private let appState: AppState
    private var keyMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        self.model = PanelViewModel(appState: appState)

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }

        let host = NSHostingView(rootView: ClipboardPanelView(model: model))
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        panel.contentView = host

        model.onRequestPaste = { [weak self] item, optionHeld in
            self?.performPaste(item: item, optionHeld: optionHeld)
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Opens at the mouse cursor, clamped to the screen that contains it
    /// (F2 — including notched and multi-monitor setups).
    func show() {
        model.prepareForShow()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: Self.panelSize)

        var origin = NSPoint(x: mouse.x - 24, y: mouse.y - Self.panelSize.height - 10)
        if origin.y < visible.minY {
            origin.y = mouse.y + 10 // no room below the cursor — open above
        }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - Self.panelSize.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - Self.panelSize.height))

        panel.setFrame(NSRect(origin: origin, size: Self.panelSize), display: false)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere outside dismisses the panel, Escape-like.
        hide()
    }

    // MARK: - Keyboard (F14)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Local monitors fire on the main thread; assumeIsolated makes
            // that contract explicit. Bool result keeps the closure Sendable.
            let handled = MainActor.assumeIsolated { self.handleKey(event) }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Returns true to swallow the event; false lets it pass through
    /// (regular typing falls through to the focused search field).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel.isVisible else { return false }
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // escape — dismiss, no side effects (F2)
            hide()
            return true
        case 125: // down
            model.moveSelection(1)
            return true
        case 126: // up
            model.moveSelection(-1)
            return true
        case 36, 76: // return / keypad enter
            model.pasteSelected(optionHeld: event.modifierFlags.contains(.option))
            return true
        case 51 where command: // ⌘⌫ delete item
            model.deleteSelected()
            return true
        case 35 where command: // ⌘P pin
            model.togglePinSelected()
            return true
        default:
            return false
        }
    }

    // MARK: - Paste

    private func performPaste(item: ClipItem, optionHeld: Bool) {
        hide()
        if item.flagReason == .clickfix, !confirmClickFixPaste(item) {
            return
        }
        appState.paste(item, optionHeld: optionHeld)
        // The user presses ⌘V themselves — by design (PRD §8.1).
    }

    /// F11: flagged items warn before pasting, but never block.
    private func confirmClickFixPaste(_ item: ClipItem) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Possible pastejacking attack"
        alert.informativeText = """
            This was copied while a website was open and looks like a shell \
            command. Malicious sites overwrite the clipboard to trick you into \
            running commands in Terminal.

            Paste it only if you typed or copied it on purpose.
            """
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Paste Anyway")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
