import AppKit
import ScreenCaptureKit
import SwiftUI

/// Borderless full-screen overlay that can still become key — a plain
/// borderless `NSWindow` returns NO from `canBecomeKeyWindow`. Mirrors
/// `FloatingPanel`.
private final class KeyableOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// A custom screen color picker with a magnifier loupe. A nearly-invisible
/// full-screen overlay consumes the click (so picking a color doesn't also click
/// the app underneath, like the system picker), while a small loupe window
/// follows the cursor showing the magnified pixels + a ring of the sampled color
/// inside the owner's eyedropper icon (its tip is the pick point).
///
/// **Dismissal is bulletproof** (it must never lock the Mac): the click and Esc
/// are handled by *both* local and global monitors, a watchdog force-dismisses
/// after a timeout, losing app-activation dismisses, and the system cursor stays
/// visible — so there is always a way out even if the overlay misbehaves.
///
/// Pixels are read in-process via ScreenCaptureKit (SafeClip is prompted once for
/// Screen Recording); until that's granted, and in the sandboxed build, it falls
/// back to the system `NSColorSampler`.
@MainActor
final class ScreenColorPicker {
    static var isSupported: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }

    /// Icon side in points (the visible magnified circle is `2·0.2323·side`).
    private static let loupeSide: CGFloat = 140
    /// Source patch captured around the cursor, in output pixels (odd → a true
    /// centre pixel under the pick point).
    private static let outPixels = 25
    /// Hard cap: the picker auto-dismisses after this, no matter what.
    private static let watchdogSeconds: TimeInterval = 30

    private let sampler = LoupeSampler()
    private let loupeModel = LoupeModel()

    private var overlay: KeyableOverlayWindow?
    private var loupeWindow: NSWindow?
    private var monitors: [Any] = []
    private var watchdog: Timer?
    private var resignObserver: NSObjectProtocol?
    private var completion: ((NSColor?) -> Void)?
    private var lastColor: PixelColor?
    private var capturing = false
    private var cursorHidden = false
    private var excludedWindows: Set<CGWindowID> = []

    func pick(completion: @escaping (NSColor?) -> Void) {
        self.completion = completion
        guard Self.isSupported else { return fallBackToSystemSampler() }
        // First-ever use: trigger the Screen Recording prompt for next time and
        // use the system sampler now (the SCK grant often needs a relaunch).
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            return fallBackToSystemSampler()
        }

        let frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let overlay = KeyableOverlayWindow(
            contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        overlay.level = .screenSaver
        overlay.isOpaque = false
        overlay.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        overlay.ignoresMouseEvents = false
        overlay.acceptsMouseMovedEvents = true
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlay.sharingType = .none
        overlay.makeKeyAndOrderFront(nil)
        self.overlay = overlay

        let loupe = makeLoupeWindow()
        self.loupeWindow = loupe
        loupe.orderFront(nil)

        excludedWindows = [
            CGWindowID(overlay.windowNumber), CGWindowID(loupe.windowNumber),
        ]

        NSApp.activate(ignoringOtherApps: true)
        // Hide the system cursor so the loupe *is* the cursor (its tip marks the
        // pixel). Safe now that the watchdog / global Esc / resign-active nets
        // guarantee dismissal; always unhidden in finish().
        NSCursor.hide()
        cursorHidden = true
        installMonitors()
        installSafetyNets()
        updateLoupe()
    }

    private func makeLoupeWindow() -> NSWindow {
        let size = LoupeGeometry.containerSize(side: Self.loupeSide)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true // clicks pass through to the overlay
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.sharingType = .none
        window.contentView = NSHostingView(
            rootView: ColorLoupeView(model: loupeModel, side: Self.loupeSide)
        )
        return window
    }

    private func fallBackToSystemSampler() {
        NSColorSampler().show { [weak self] color in
            MainActor.assumeIsolated { self?.finish(color) }
        }
    }

    // MARK: - Monitors + safety

    private func installMonitors() {
        func add(_ monitor: Any?) { if let monitor { monitors.append(monitor) } }

        // Mouse move/drag → reposition + refresh (local while we're key, global
        // as a backstop if key status is ever lost).
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        add(NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
            MainActor.assumeIsolated { self?.updateLoupe() }
            return event
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLoupe() }
        })

        // Click to pick. Local consumes it (so the app underneath isn't clicked);
        // the global backstop fires only if the overlay failed to consume it.
        add(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.commit() }
            return nil
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.commit() }
        })

        // Esc cancels — both local and global so it works even if not key.
        add(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.finish(nil) }
            return nil
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.finish(nil) }
        })
    }

    private func installSafetyNets() {
        // Hard cap so the overlay can never persist (timer runs on the main run
        // loop, which our capture work never blocks).
        let timer = Timer(timeInterval: Self.watchdogSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer

        // If we lose activation (anything steals focus), dismiss.
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil) }
        }
    }

    // MARK: - Loupe

    private func updateLoupe() {
        let mouse = NSEvent.mouseLocation
        positionLoupe(at: mouse)

        guard !capturing,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return }

        let scale = screen.backingScaleFactor
        let capturePts = CGFloat(Self.outPixels) / scale
        let localX = mouse.x - screen.frame.minX
        let localTop = screen.frame.maxY - mouse.y // SCK display space is top-left
        let rect = CGRect(
            x: localX - capturePts / 2, y: localTop - capturePts / 2,
            width: capturePts, height: capturePts
        )
        let displayID = CGDirectDisplayID(number.uint32Value)

        capturing = true
        Task { @MainActor in
            defer { capturing = false }
            guard let result = await sampler.sample(
                displayID: displayID, rectPt: rect, outPixels: Self.outPixels,
                excluding: excludedWindows
            ) else { return }
            if let image = NSImage(data: result.tiff) { loupeModel.magnified = image }
            lastColor = result.center
            loupeModel.color = result.center.swiftUI
            loupeModel.hex = result.center.hex
        }
    }

    /// Places the loupe so the icon's tip sits on the cursor; flips it to hang
    /// above the cursor when there isn't room for it below (near the screen
    /// bottom), and the hex caption flips with it.
    private func positionLoupe(at mouse: NSPoint) {
        guard let loupeWindow else { return }
        let side = Self.loupeSide
        let size = LoupeGeometry.containerSize(side: side)
        let visible = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main)?.visibleFrame ?? .infinite

        // Normal: container hangs below the tip. Flip if it would clip the bottom.
        let tipNormal = LoupeGeometry.tip(side: side, flipped: false)
        let roomBelow = mouse.y - visible.minY
        let neededBelow = size.height - tipNormal.y
        let flipped = roomBelow < neededBelow
        loupeModel.flipped = flipped

        let tip = LoupeGeometry.tip(side: side, flipped: flipped)
        // Place the window so container point `tip` lands on the cursor. Window
        // is bottom-left origin; container is top-left, so y flips.
        let originX = mouse.x - tip.x
        let originY = mouse.y + tip.y - size.height
        loupeWindow.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    private func commit() {
        finish(lastColor?.nsColor)
    }

    /// Single teardown for every dismissal path (idempotent via `completion`).
    private func finish(_ color: NSColor?) {
        guard let completion = self.completion else { return }
        self.completion = nil

        watchdog?.invalidate()
        watchdog = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        loupeWindow?.orderOut(nil)
        loupeWindow = nil
        overlay?.orderOut(nil)
        overlay = nil
        if cursorHidden {
            NSCursor.unhide()
            cursorHidden = false
        }
        excludedWindows = []
        lastColor = nil

        completion(color)
    }
}
