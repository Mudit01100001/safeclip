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
    static let panelWidth: CGFloat = 380
    /// The body grows up to this when there's room, and shrinks (list scrolls)
    /// down to `minBodyHeight` so the panel can still open *above* a caret that
    /// sits high on screen — instead of a fixed-tall panel falling below it.
    private static let maxBodyHeight: CGFloat = 442
    private static let minBodyHeight: CGFloat = 240
    private static let cornerRadius: CGFloat = 18
    /// Gap between the beak tip and the caret/cursor it points at.
    private static let anchorGap: CGFloat = 3

    private let panel: FloatingPanel
    private let model: PanelViewModel
    private let appState: AppState
    /// One SwiftUI surface for the whole window (body + beak as one callout).
    private let hostingView: NSHostingView<ClipboardPanelView>
    private var keyMonitor: Any?
    /// Forwards scroll-wheel events to the list: a non-activating panel doesn't
    /// receive them through the normal responder chain (only the scrollbar
    /// thumb, a direct mouse drag, works otherwise).
    private var scrollMonitor: Any?

    /// The largest the window ever gets (created at this size, shrunk per show).
    private static var maxWindowSize: NSSize {
        NSSize(width: panelWidth, height: maxBodyHeight + PanelArrowSpec.height)
    }

    init(appState: AppState) {
        self.appState = appState
        let model = PanelViewModel(appState: appState)
        self.model = model

        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.maxWindowSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        // One SwiftUI view paints the whole callout — rounded body + beak — as
        // a single Liquid Glass (macOS 26+) / material surface, so there's no
        // seam between body and beak. Geometry is updated per show in layout().
        hostingView = NSHostingView(
            rootView: ClipboardPanelView(
                model: model,
                arrow: PanelArrowSpec(edge: .bottom, offsetX: Self.panelWidth / 2)
            )
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
        // Excluded from screen capture (screenshots AND recordings) — clipboard
        // history should never end up in someone else's capture. Always on.
        panel.sharingType = .none
        panel.delegate = self
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }

        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        model.onRequestPaste = { [weak self] item, optionHeld in
            self?.performPaste(item: item, optionHeld: optionHeld)
        }
        model.onRequestPasteCombined = { [weak self] items in
            self?.performCombinedPaste(items)
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? hide() : show()
    }

    /// Opens above the anchor — the text caret when caret anchoring is enabled
    /// and granted, otherwise the mouse cursor — with the arrow pointing at it,
    /// clamped to the screen that contains it (F2 — incl. notch / multi-monitor).
    func show() {
        model.prepareForShow()
        layout(for: resolveAnchor())
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        applyOverlayScrollerStyle()
    }

    /// Make the list scrollbar overlay (auto-hiding). Retried because the
    /// SwiftUI scroll view may not exist yet on the first frame.
    private func applyOverlayScrollerStyle() {
        for delay in [0.0, 0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      let scrollView = Self.firstScrollView(in: self.panel.contentView) else { return }
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
            }
        }
    }

    private static func firstScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scrollView = view as? NSScrollView { return scrollView }
        for subview in view.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }

    /// What the panel points at, in AppKit screen coordinates. `topY`/`bottomY`
    /// are the visual top and bottom edges of the target (equal for the mouse).
    private struct Anchor {
        var x: CGFloat
        var topY: CGFloat
        var bottomY: CGFloat
        var screen: NSScreen?
    }

    private func resolveAnchor() -> Anchor {
        // Caret first (opt-in, read-only Accessibility) — but only when it's
        // near the pointer, since the pointer is where the user is looking. If
        // the caret is far away (an inactive field across the window), anchor at
        // the pointer instead. Threshold is user-tunable.
        if appState.settings.caretAnchoring,
           let caret = CaretLocator.caretRect(assistChromium: appState.settings.assistChromiumApps) {
            let mouse = NSEvent.mouseLocation
            let distance = (pow(mouse.x - caret.midX, 2) + pow(mouse.y - caret.midY, 2)).squareRoot()
            if distance <= appState.settings.caretProximityPoints {
                #if DEBUG
                NSLog("SafeClip panel: anchoring to caret \(caret) (dist \(Int(distance)) ≤ \(Int(appState.settings.caretProximityPoints)))")
                #endif
                return Anchor(
                    x: caret.midX,
                    topY: caret.maxY,       // AppKit y grows up, so the top edge is maxY
                    bottomY: caret.minY,
                    screen: screen(containing: CGPoint(x: caret.midX, y: caret.midY))
                )
            }
            #if DEBUG
            NSLog("SafeClip panel: caret \(Int(distance))pt from pointer > \(Int(appState.settings.caretProximityPoints)) — using pointer")
            #endif
        }
        let mouse = NSEvent.mouseLocation
        #if DEBUG
        NSLog("SafeClip panel: anchoring to mouse \(mouse) (caretAnchoring=\(appState.settings.caretAnchoring))")
        #endif
        return Anchor(x: mouse.x, topY: mouse.y, bottomY: mouse.y, screen: screen(containing: mouse))
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }

    /// Moves and *sizes* the window so the beak points at `anchor`, preferring
    /// to sit **above** it (so the panel never covers the field being typed
    /// into — owner request, 15 June 2026). The body height adapts to the room
    /// available on the chosen side: a caret high on screen gets a shorter panel
    /// **above** it (list scrolls) rather than a fixed-tall panel dumped below.
    private func layout(for anchor: Anchor) {
        let bodyW = Self.panelWidth
        let beakH = PanelArrowSpec.height
        let visible = anchor.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // Horizontal: centre the body on the anchor, clamped to the screen.
        let originX = max(visible.minX, min(anchor.x - bodyW / 2, visible.maxX - bodyW))

        // Room for the body (excluding the beak + gap) on each side of the anchor.
        let availableAbove = visible.maxY - anchor.topY - Self.anchorGap - beakH
        let availableBelow = anchor.bottomY - Self.anchorGap - beakH - visible.minY

        // Prefer above when it can show a usable panel; else below; else the
        // roomier side.
        let placeAbove: Bool
        if availableAbove >= Self.minBodyHeight {
            placeAbove = true
        } else if availableBelow >= Self.minBodyHeight {
            placeAbove = false
        } else {
            placeAbove = availableAbove >= availableBelow
        }

        let available = max(0, placeAbove ? availableAbove : availableBelow)
        let bodyH = min(Self.maxBodyHeight, max(Self.minBodyHeight, available))
        let windowH = bodyH + beakH

        let rawOriginY = placeAbove
            ? anchor.topY + Self.anchorGap
            : anchor.bottomY - Self.anchorGap - windowH
        let originY = max(visible.minY, min(rawOriginY, visible.maxY - windowH))

        // Beak x within the window, aimed at the anchor but kept on the flat
        // edge between the rounded corners (the shape clamps too, belt + braces).
        let minBeakX = Self.cornerRadius + PanelArrowSpec.width / 2
        let maxBeakX = bodyW - Self.cornerRadius - PanelArrowSpec.width / 2
        let beakX = max(minBeakX, min(anchor.x - originX, maxBeakX))

        hostingView.rootView = ClipboardPanelView(
            model: model,
            arrow: PanelArrowSpec(edge: placeAbove ? .bottom : .top, offsetX: beakX)
        )
        let frame = NSRect(x: originX, y: originY, width: bodyW, height: windowH)
        #if DEBUG
        NSLog("SafeClip panel: placeAbove=\(placeAbove) bodyH=\(bodyH) anchorX=\(anchor.x) top=\(anchor.topY) bottom=\(anchor.bottomY) availAbove=\(availableAbove) availBelow=\(availableBelow) frame=\(frame) visible=\(visible)")
        #endif
        // display:false — the panel isn't on screen yet (show() orders it front
        // after this), so defer the redraw and avoid forcing a layout pass while
        // the hosting view is already laying out (the layoutSubtree recursion log).
        panel.setFrame(frame, display: false)
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
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated { () -> Bool in
                // Resolve the scroll view *live* under the cursor each event —
                // caching it at show time raced the SwiftUI layout and made
                // scrolling work only intermittently.
                guard self.panel.isVisible, event.window == self.panel,
                      let hit = self.panel.contentView?.hitTest(event.locationInWindow),
                      let scrollView = hit.enclosingScrollView else { return false }
                scrollView.scrollWheel(with: event)
                return true
            }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
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
            if model.hasMultiSelection {
                model.pasteMultiSelection() // combined, in click order
            } else {
                model.pasteSelected(optionHeld: event.modifierFlags.contains(.option))
            }
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
        // While history is hidden (screen recording / Privacy Mode) the list is
        // blurred and unreadable — don't let a stray Return paste an item the
        // user can't actually see.
        guard !appState.historyHidden else { return }
        hide()
        if item.flagReason == .clickfix, !confirmClickFixPaste(item) {
            return
        }
        appState.paste(item, optionHeld: optionHeld)
        // The user presses ⌘V themselves — by design (PRD §8.1).
    }

    /// Multipaste: places several clips combined for one ⌘V. Warns once if any
    /// selected item looks like a pastejacking payload.
    private func performCombinedPaste(_ items: [ClipItem]) {
        guard !appState.historyHidden else { return }
        hide()
        if let flagged = items.first(where: { $0.flagReason == .clickfix }),
           !confirmClickFixPaste(flagged) {
            return
        }
        appState.pasteCombined(items)
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
