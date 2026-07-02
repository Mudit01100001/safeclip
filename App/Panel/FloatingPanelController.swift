import AppKit
import SafeClipCore
import SwiftUI

/// NSPanel for the floating clipboard list. SafeClip is **activated** while the
/// panel is open so the panel captures scroll-wheel and key events exclusively —
/// a non-activating panel lets the wheel leak through to the app behind it (e.g.
/// the editor underneath keeps scrolling). Focus is handed back to the app the
/// user came from on dismiss (paste / Escape / toggle), so their own ⌘V still
/// lands in their document. The list scrolls via a real `NSScrollView`
/// (`NativeScrollView`).
///
/// Borderless panels return `false` from `canBecomeKey` by default, so it's
/// overridden here — without it the panel could never take the search field.
private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
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
    private let hostingView: ClickThroughHostingView<ClipboardPanelView>
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    /// Global fallback for scroll — confirmed necessary by SELFTEST on 2 Jul
    /// 2026 (missed_seen_elsewhere=7/7 misses, 0 lost entirely): most real
    /// wheel events over the panel are routed by the window server to some
    /// other destination instead of SafeClip's own dispatch, even while
    /// panel.isKeyWindow/NSApp.isActive read true, so the LOCAL monitor above
    /// never fires for them. A global monitor sees them anyway and can
    /// manually forward — it can't consume, so the misdirected destination
    /// still gets the event too, but a rare visible double-scroll beats
    /// silently failing most of the time.
    private var globalScrollMonitor: Any?
    /// Global monitor — sees mouse-down events destined for *other* apps'
    /// windows (local monitors can't). Closes the panel on any such click
    /// without consuming it, so the click still reaches its real target.
    /// Covers cases `windowDidResignKey` misses, like clicking the Finder
    /// desktop, which doesn't make any window key.
    private var outsideClickMonitor: Any?
    /// The app that was frontmost when the panel opened. The non-activating panel
    /// doesn't steal activation, so normal dismissal needs no restore — but a
    /// ClickFix confirmation modal *does* activate SafeClip, so we hand focus back
    /// to this app afterward, keeping the user's ⌘V landing in their document.
    private weak var previousApp: NSRunningApplication?
    #if DEBUG
    /// Logs only the first real wheel event forwarded per show(), so a single
    /// scroll attempt after opening the panel tells us whether real trackpad
    /// input actually reaches forwardScroll() and in what activation state —
    /// the fixed-delay SCROLLDIAG check can't see this because it calls
    /// scrollWheel(with:) directly, bypassing event delivery entirely.
    private var loggedScrollThisShow = false
    /// Reset on every show() — SCROLLACT lines below are timestamped relative
    /// to this, so we can see exactly how long activation survives after we
    /// request it (SCROLLDIAG always reads aa=1 at a fixed +0.2s, but that
    /// can't tell us if activation is quietly revoked a moment later, before
    /// the user gets a chance to actually scroll).
    private var activationLogStart: Date?
    /// Set unconditionally at the top of forwardScroll() (before any guard),
    /// so SELFTEST can tell "the event never reached our monitor at all" apart
    /// from "it reached us but the guard or the scroll view itself failed."
    private var scrollForwardInvoked = false
    /// Set when the global scroll fallback (see globalScrollMonitor) fires —
    /// tells SELFTEST an event was routed elsewhere instead of to us, rather
    /// than never being generated at all.
    private var globalScrollSeenThisIteration = false
    /// Set inside outsideClickMonitor's callback — lets SELFTEST tell whether
    /// our OWN "click outside closes the panel" feature is the reason a
    /// synthetic click never reached the row (self-inflicted, not a hitbox bug).
    private var outsideClickFiredThisIteration = false
    /// Set when outsideClickMonitor decided a misrouted click was actually
    /// inside our own frame and replayed it via panel.sendEvent(_:) instead of
    /// dismissing — tells SELFTEST whether that replay path actually ran (as
    /// opposed to the click registering via ordinary local delivery).
    private var clickReplayedThisIteration = false
    #endif

    /// The largest the window ever gets (created at this size, shrunk per show).
    private static var maxWindowSize: NSSize {
        NSSize(width: panelWidth, height: maxBodyHeight + PanelArrowSpec.height)
    }

    init(appState: AppState) {
        self.appState = appState
        let model = PanelViewModel(appState: appState)
        self.model = model

        // Borderless: the panel paints its own rounded callout shape (no system
        // titlebar). SafeClip is activated on show so the panel captures scroll
        // exclusively (no wheel leak to the app behind it); FloatingPanel
        // overrides canBecomeKey so a borderless panel still takes the search
        // field.
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.maxWindowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        // One SwiftUI view paints the whole callout — rounded body + beak — as
        // a single Liquid Glass (macOS 26+) / material surface, so there's no
        // seam between body and beak. Geometry is updated per show in layout().
        hostingView = ClickThroughHostingView(
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
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow
        // Excluded from screen capture (screenshots AND recordings) — clipboard
        // history should never end up in someone else's capture. In DEBUG it's
        // made capturable TEMPORARILY so the panel can be screenshotted while
        // diagnosing scroll; release builds are always `.none`.
        #if DEBUG
        panel.sharingType = .readOnly
        #else
        panel.sharingType = .none
        #endif
        panel.delegate = self

        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        model.onRequestPaste = { [weak self] item, optionHeld in
            self?.performPaste(item: item, optionHeld: optionHeld)
        }
        model.onRequestPasteCombined = { [weak self] items in
            self?.performCombinedPaste(items)
        }
        model.onRequestPasteSnippet = { [weak self] snippet in
            self?.performSnippetPaste(snippet)
        }

        #if DEBUG
        if ProcessInfo.processInfo.environment["SAFECLIP_SCROLL_TEST"] == "1" {
            let center = NotificationCenter.default
            center.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    guard let start = self.activationLogStart else { return }
                    NSLog("SCROLLACT resign t=\(String(format: "%.2f", Date().timeIntervalSince(start)))")
                }
            }
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                MainActor.assumeIsolated {
                    guard let start = self.activationLogStart else { return }
                    NSLog("SCROLLACT become t=\(String(format: "%.2f", Date().timeIntervalSince(start)))")
                }
            }
        }
        #endif
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if isVisible {
            let target = previousApp
            hide()
            restoreFocus(to: target)
        } else {
            show()
        }
    }

    /// Opens above the anchor — the text caret when caret anchoring is enabled
    /// and granted, otherwise the mouse cursor — with the arrow pointing at it,
    /// clamped to the screen that contains it (F2 — incl. notch / multi-monitor).
    func show() {
        // Capture the app to return focus to on dismiss — BEFORE we activate
        // (and before the caret probe reads its focused element).
        previousApp = NSWorkspace.shared.frontmostApplication
        model.prepareForShow()
        layout(for: resolveAnchor())
        // (Tried temporarily switching to .regular activation policy here to
        // see if it fixed misrouted input — it didn't: both live testing and
        // the SELFTEST harness's own synthetic clicks still misrouted to
        // whatever was genuinely frontmost, including Xcode itself, and the
        // repeated policy flips introduced their own instability. Reverted.)
        // Activate SafeClip so the panel captures the scroll wheel and keys
        // exclusively (otherwise the wheel leaks to the app behind it). Focus is
        // handed back to `previousApp` on dismiss so the user's ⌘V lands right.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        #if DEBUG
        loggedScrollThisShow = false
        activationLogStart = Date()
        // Only when explicitly testing — keeps normal debug runs clean (the
        // diagnostic also nudges the scroll position to prove it moves).
        if ProcessInfo.processInfo.environment["SAFECLIP_SCROLL_TEST"] == "1" {
            logScrollDiagnostics()
        }
        #endif
    }

    #if DEBUG
    /// Prints the one fact that decides what's wrong with scrolling: is the list
    /// content taller than the viewport? If not, it's a layout bug (nothing to
    /// scroll); if it is and scrolling still fails, it's an event-delivery bug.
    private func logScrollDiagnostics() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }
            guard let scrollView = self.listScrollView() else {
                NSLog("SCROLLDIAG noview")
                return
            }
            let docH = scrollView.documentView?.frame.height ?? -1
            let clipH = scrollView.contentView.bounds.height
            let line = "SCROLLDIAG d=\(Int(docH)) c=\(Int(clipH)) s=\(docH > clipH ? 1 : 0)"
                + " r=\(self.model.filtered.count) pk=\(self.panel.isKeyWindow ? 1 : 0) aa=\(NSApp.isActive ? 1 : 0)"
            // Prove the scroll mechanism actually moves the content. Reset to 0
            // first — the panel is a singleton whose scroll offset carries over
            // between shows, so a stale non-zero offset would falsely read as
            // "didn't move" if the target happened to match where it already was.
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let before = scrollView.contentView.bounds.origin.y
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 250))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let after = scrollView.contentView.bounds.origin.y

            // The check above only proves the clip view CAN be repositioned
            // directly (contentView.scroll(to:)) — that's a different code path
            // from what real input uses. Native wheel delivery and forwardScroll()
            // both go through scrollWheel(with:), which does its own hit-testing
            // and elasticity math before touching the clip view. Exercise that
            // exact call with a synthesized wheel event so a pass here actually
            // means real trackpad/mouse input will move the list.
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let wheelBefore = scrollView.contentView.bounds.origin.y
            var wheelAfter = wheelBefore
            var wheelEventCreated = false
            if let cgEvent = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                wheel1: -80, wheel2: 0, wheel3: 0
            ), let wheelEvent = NSEvent(cgEvent: cgEvent) {
                wheelEventCreated = true
                scrollView.scrollWheel(with: wheelEvent)
                wheelAfter = scrollView.contentView.bounds.origin.y
            }

            let full = line
                + " m1=\(after != before ? 1 : 0)"
                + " wc=\(wheelEventCreated ? 1 : 0) m2=\(wheelAfter != wheelBefore ? 1 : 0)"
            NSLog(full)
            try? full.write(
                toFile: "/tmp/safeclip-scroll-diag.txt", atomically: true, encoding: .utf8
            )
        }
    }

    /// SAFECLIP_SELFTEST=<N> runs N automated show→scroll→click→hide cycles
    /// with real OS-level input (CGEvent.post to the HID event tap) — not a
    /// direct method call like the checks above, which proved the code CAN
    /// work but never proved a genuine event reaches it. This replaces the
    /// whole manual "relaunch, click/scroll N times by hand, paste back logs"
    /// cycle with one relaunch and one aggregate line. Moves the real cursor
    /// and posts real clicks — only ever run deliberately, never on a normal
    /// debug launch.
    func runSelfTest(iterations: Int) {
        let originalMouse = NSEvent.mouseLocation
        Task { @MainActor in
            let delays: [Double] = [0.1, 0.3, 0.6, 1.0, 1.5]
            var scrollHits = 0
            var fwdMissed = 0  // event never reached forwardScroll at all
            var fwdNoMove = 0  // reached forwardScroll, but the view didn't move
            var missedButSeenElsewhere = 0  // event went to another app instead of us
            var missedAndSeenNowhere = 0  // event seemingly never delivered anywhere
            var clickHits = 0
            var clickPointMissing = 0
            var clickSelfClosed = 0    // our own outsideClickMonitor hid the panel
            var clickPanelClosedOther = 0  // panel closed for some other reason
            var clickReplayed = 0      // click was misrouted but replayed via sendEvent
            var clickReplayedButMissed = 0  // replayed, panel stayed open, still no paste
            var byDelay: [Double: (hit: Int, total: Int)] = [:]

            for i in 0..<iterations {
                let delay = delays[i % delays.count]
                show()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                var scrollOK = false
                scrollForwardInvoked = false
                globalScrollSeenThisIteration = false
                if let scrollView = listScrollView(), let point = screenPointNearListTop() {
                    scrollView.contentView.scroll(to: .zero)
                    scrollView.reflectScrolledClipView(scrollView.contentView)
                    let before = scrollView.contentView.bounds.origin.y
                    postSyntheticScroll(at: point)
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    let after = scrollView.contentView.bounds.origin.y
                    scrollOK = after != before
                    if !scrollOK {
                        if scrollForwardInvoked {
                            fwdNoMove += 1
                        } else {
                            fwdMissed += 1
                            if globalScrollSeenThisIteration { missedButSeenElsewhere += 1 }
                            else { missedAndSeenNowhere += 1 }
                        }
                    }
                }
                if scrollOK { scrollHits += 1 }
                var bucket = byDelay[delay] ?? (hit: 0, total: 0)
                bucket.total += 1
                if scrollOK { bucket.hit += 1 }
                byDelay[delay] = bucket

                var clickOK = false
                outsideClickFiredThisIteration = false
                clickReplayedThisIteration = false
                if let point = screenPointNearListTop() {
                    postSyntheticClick(at: point)
                    try? await Task.sleep(nanoseconds: 60_000_000)
                    clickOK = model.justCopiedID != nil
                    if clickReplayedThisIteration {
                        clickReplayed += 1
                        if !clickOK { clickReplayedButMissed += 1 }
                    }
                    if !clickOK, !panel.isVisible {
                        if outsideClickFiredThisIteration { clickSelfClosed += 1 } else { clickPanelClosedOther += 1 }
                    }
                } else {
                    clickPointMissing += 1
                }
                if clickOK { clickHits += 1 }
                // The 0.45s flash-then-paste delay means justCopiedID is still
                // set from this click when the loop hides/reshows for the next
                // iteration — clear it so it can't bleed into the next read.
                if clickOK {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }

                hide()
                try? await Task.sleep(nanoseconds: 300_000_000)
            }

            let byDelayStr = delays.map { d -> String in
                let b = byDelay[d] ?? (hit: 0, total: 0)
                return "\(d):\(b.hit)/\(b.total)"
            }.joined(separator: ",")
            let report = "SELFTEST n=\(iterations) scroll=\(scrollHits)/\(iterations)"
                + " fwd_missed=\(fwdMissed) fwd_no_move=\(fwdNoMove)"
                + " missed_seen_elsewhere=\(missedButSeenElsewhere) missed_seen_nowhere=\(missedAndSeenNowhere)"
                + " click=\(clickHits)/\(iterations) click_point_missing=\(clickPointMissing)"
                + " click_self_closed=\(clickSelfClosed) click_panel_closed_other=\(clickPanelClosedOther)"
                + " click_replayed=\(clickReplayed) click_replayed_but_missed=\(clickReplayedButMissed)"
                + " by_delay{\(byDelayStr)}"
            NSLog(report)
            try? report.write(toFile: "/tmp/safeclip-selftest.txt", atomically: true, encoding: .utf8)

            // Put the real cursor back where the user left it.
            if let restoreEvent = CGEvent(
                mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: toCGPoint(originalMouse), mouseButton: .left
            ) {
                restoreEvent.post(tap: .cghidEventTap)
            }
        }
    }

    /// A point near the top of the visible list, in CG global (top-left
    /// origin) coordinates suitable for CGEvent posting. Verified to fall
    /// inside the panel's own frame before use, so a coordinate-conversion
    /// bug can't send a synthetic click into whatever's underneath instead.
    private func screenPointNearListTop() -> CGPoint? {
        guard let scrollView = listScrollView() else { return nil }
        let windowRect = scrollView.convert(scrollView.bounds, to: nil)
        let windowPoint = NSPoint(x: windowRect.midX, y: windowRect.maxY - 20)
        let screenPoint = panel.convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin
        guard panel.frame.contains(screenPoint) else { return nil }
        return toCGPoint(screenPoint)
    }

    /// AppKit screen coordinates (bottom-left origin, per-display, negative Y
    /// possible on secondary displays) → CG global coordinates (top-left
    /// origin) for CGEvent posting.
    private func toCGPoint(_ appKitScreenPoint: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: appKitScreenPoint.x, y: primaryHeight - appKitScreenPoint.y)
    }

    private func postSyntheticScroll(at point: CGPoint) {
        let move = CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: point, mouseButton: .left
        )
        move?.post(tap: .cghidEventTap)
        guard let scrollEvent = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
            wheel1: -80, wheel2: 0, wheel3: 0
        ) else { return }
        scrollEvent.location = point
        scrollEvent.post(tap: .cghidEventTap)
    }

    private func postSyntheticClick(at point: CGPoint) {
        let down = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseDown,
            mouseCursorPosition: point, mouseButton: .left
        )
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(
            mouseEventSource: nil, mouseType: .leftMouseUp,
            mouseCursorPosition: point, mouseButton: .left
        )
        up?.post(tap: .cghidEventTap)
    }
    #endif

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

    /// Hides the panel. Because the panel is non-activating it never took focus
    /// from the user's app, so ordering it out is enough — key returns to the
    /// app the user was in and their ⌘V lands there. (Focus is only restored
    /// explicitly after a confirmation modal, which *does* activate SafeClip.)
    func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    /// Returns activation to the app that owned focus before the panel opened
    /// (skipping ourselves). Used only after a modal activated SafeClip.
    private func restoreFocus(to app: NSRunningApplication?) {
        guard let app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        app.activate()
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
        // Scroll: the native NSScrollView (NativeScrollView) handles the wheel
        // itself now that SafeClip is the active app. We also intercept wheel
        // events over the panel locally and forward them to that scroll view,
        // consuming them when it works — this is the ideal path since it also
        // keeps the wheel from reaching the app behind the panel.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.forwardScroll(event) }
            return handled ? nil : event
        }
        // Fallback: SELFTEST (2 Jul 2026) proved most real wheel events over
        // the panel never reach the local monitor above at all — the window
        // server routes them elsewhere despite panel.isKeyWindow/NSApp.isActive
        // reading true. A global monitor sees those misrouted events and can
        // still manually forward them. It can't consume, so whatever the OS
        // picked as the real destination still gets the event too (a rare
        // visible double-scroll), but that beats scroll silently failing most
        // of the time, which is what shipped before this fix.
        globalScrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return }
            MainActor.assumeIsolated {
                #if DEBUG
                if self.panel.isVisible, self.panel.frame.contains(NSEvent.mouseLocation) {
                    self.globalScrollSeenThisIteration = true
                }
                #endif
                _ = self.forwardScroll(event)
            }
        }
        // Any click outside SafeClip dismisses the panel. A GLOBAL monitor
        // (unlike the local ones above) sees mouse-down events bound for
        // other apps' windows — that's the only way to catch clicks on the
        // Finder desktop or another app, which never make any window key and
        // so never fire windowDidResignKey. Doesn't consume the event, so the
        // user's click still reaches and activates its real target normally.
        //
        // BUT: SELFTEST proved (click_self_closed=10/10, 2 Jul 2026) that the
        // exact same misrouting that breaks scroll also misroutes clicks
        // meant for our OWN panel — a global monitor can't tell "click on the
        // Finder desktop" apart from "click on our own row that the window
        // server misdelivered," so it was slamming the panel shut on its own
        // clicks before the row's tap gesture ever fired. Fix: check location
        // first. Inside our frame → replay the event into our own window via
        // sendEvent so the row still gets it (this is what makes the
        // misrouted click actually register at all, not just avoid closing);
        // outside → the original dismiss behavior.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            MainActor.assumeIsolated {
                if self.panel.isVisible, self.panel.frame.contains(NSEvent.mouseLocation) {
                    #if DEBUG
                    self.clickReplayedThisIteration = true
                    #endif
                    self.panel.sendEvent(event)
                    return
                }
                #if DEBUG
                self.outsideClickFiredThisIteration = true
                #endif
                self.hide()
            }
        }
    }

    private func removeKeyMonitor() {
        for monitor in [keyMonitor, scrollMonitor, globalScrollMonitor, outsideClickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        scrollMonitor = nil
        globalScrollMonitor = nil
        outsideClickMonitor = nil
    }

    /// Forwards a wheel event to the list's scroll view when the pointer is over
    /// the panel. `NSScrollView.scrollWheel(with:)` scrolls regardless of whether
    /// the panel is key/active, so this works even when native delivery doesn't.
    /// Returns true when consumed.
    private func forwardScroll(_ event: NSEvent) -> Bool {
        #if DEBUG
        scrollForwardInvoked = true
        if ProcessInfo.processInfo.environment["SAFECLIP_SCROLL_TEST"] == "1", !loggedScrollThisShow {
            loggedScrollThisShow = true
            let inFrame = panel.frame.contains(NSEvent.mouseLocation)
            let found = listScrollView() != nil
            NSLog("SCROLLFWD vis=\(panel.isVisible ? 1 : 0) in=\(inFrame ? 1 : 0) sv=\(found ? 1 : 0) pk=\(panel.isKeyWindow ? 1 : 0) aa=\(NSApp.isActive ? 1 : 0)")
        }
        #endif
        guard panel.isVisible,
              panel.frame.contains(NSEvent.mouseLocation),
              let scrollView = listScrollView() else { return false }
        scrollView.scrollWheel(with: event)
        return true
    }

    /// The list's `NSScrollView` (the one whose document is our `FlippedView`),
    /// located live in the hosted view tree.
    private func listScrollView() -> NSScrollView? {
        func search(_ view: NSView?) -> NSScrollView? {
            guard let view else { return nil }
            if let scrollView = view as? NSScrollView, scrollView.documentView is FlippedView {
                return scrollView
            }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        return search(panel.contentView)
    }

    /// Returns true to swallow the event; false lets it pass through
    /// (regular typing falls through to the focused search field).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard panel.isVisible else { return false }
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // escape — dismiss and return focus to the user's app (F2)
            let target = previousApp
            hide()
            restoreFocus(to: target)
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
        // Tear the panel (and its key monitor) down *before* any confirmation
        // modal; the clipboard is set last so it's ready when the user ⌘V's.
        let target = previousApp
        hide()
        if item.flagReason == .clickfix, !confirmClickFixPaste(item) {
            restoreFocus(to: target)
            return
        }
        // Hand activation back to the app the user came from BEFORE they ⌘V, so
        // their paste lands in the field they were editing without re-clicking it.
        // (Belt-and-braces on top of the non-activating panel.)
        restoreFocus(to: target)
        appState.paste(item, optionHeld: optionHeld)
        // The user presses ⌘V themselves — by design (PRD §8.1).
    }

    /// Multipaste: places several clips combined for one ⌘V. Warns once if any
    /// selected item looks like a pastejacking payload.
    private func performCombinedPaste(_ items: [ClipItem]) {
        guard !appState.historyHidden else { return }
        let target = previousApp
        hide()
        if let flagged = items.first(where: { $0.flagReason == .clickfix }), !confirmClickFixPaste(flagged) {
            restoreFocus(to: target)
            return
        }
        restoreFocus(to: target)
        appState.pasteCombined(items)
    }

    /// Saved snippet: places its body for the user's ⌘V. Snippets are
    /// user-authored, so there's no ClickFix gate — hide (restoring focus) and
    /// place for the user's own paste.
    private func performSnippetPaste(_ snippet: Snippet) {
        let target = previousApp
        hide()
        restoreFocus(to: target)
        appState.pasteSnippet(snippet)
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
