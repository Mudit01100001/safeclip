import AppKit
import ScreenCaptureKit

// ⚠️ WIP — NOT WIRED UP. `AppDelegate.pickColor` uses `NSColorSampler` instead.
// Two things must be fixed in the next session before enabling this:
//  1. The overlay is a plain borderless `NSWindow`, which returns NO from
//     `canBecomeKeyWindow` — so Esc/click never register, the full-screen
//     overlay never tears down, and it LOCKS the user out of window-switching
//     until SafeClip quits (confirmed in the owner's logs). Fix: subclass
//     NSWindow with `canBecomeKey = true` (like `FloatingPanel`), and/or a hard
//     dismissal path.
//  2. Add the magnifier — the owner is supplying a custom eyedropper-loupe icon
//     (teardrop frame with a TRANSPARENT centre circle) to draw over the live
//     magnified pixels. See the next-session notes in docs/ROADMAP.md + memory.
//
/// A custom screen color picker: a full-screen eyedropper cursor; click any
/// pixel to sample its color, Esc to cancel. Replaces the system color sampler's
/// circular loupe with the eyedropper look (owner request).
///
/// It reads the pixel in-process via ScreenCaptureKit, so — unlike the ⌥C OCR
/// path, which shells out to `screencapture` — SafeClip itself is prompted once
/// for Screen Recording. In the sandboxed build (where in-process capture is
/// blocked) it falls back to the system `NSColorSampler`.
@MainActor
final class ScreenColorPicker {
    static var isSupported: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil
    }

    private struct RGB: Sendable { let r: Double; let g: Double; let b: Double }

    private var overlay: NSWindow?
    private var monitors: [Any] = []
    private var completion: ((NSColor?) -> Void)?

    func pick(completion: @escaping (NSColor?) -> Void) {
        self.completion = completion
        guard Self.isSupported else {
            // Sandbox: no in-process capture — use the system sampler instead.
            NSColorSampler().show { [weak self] color in
                MainActor.assumeIsolated { self?.finish(color) }
            }
            return
        }

        let frame = NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
        let window = NSWindow(
            contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        // Nearly invisible, but solid enough to receive the click anywhere.
        window.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        overlay = window
        Self.eyedropperCursor().set()

        let down = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.commit() }
            return nil
        }
        let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isEscape = event.keyCode == 53
            if isEscape { MainActor.assumeIsolated { self?.finish(nil) } }
            return isEscape ? nil : event
        }
        monitors = [down, key].compactMap { $0 }
    }

    private static func eyedropperCursor() -> NSCursor {
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        guard let image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return .crosshair }
        // Hotspot at the dropper tip (lower-left of the glyph).
        return NSCursor(image: image, hotSpot: NSPoint(x: 3, y: image.size.height - 3))
    }

    private func commit() {
        let mouse = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { finish(nil); return }

        let displayID = CGDirectDisplayID(number.uint32Value)
        // Point under the cursor, in points from the display's top-left.
        let localX = mouse.x - screen.frame.minX
        let localTop = screen.frame.maxY - mouse.y
        let rect = CGRect(x: localX - 1, y: localTop - 1, width: 3, height: 3)

        Task { @MainActor in
            let rgb = await Self.sampleCenter(displayID: displayID, rect: rect)
            self.finish(rgb.map { NSColor(srgbRed: $0.r, green: $0.g, blue: $0.b, alpha: 1) })
        }
    }

    /// Captures a tiny block via ScreenCaptureKit and returns the centre pixel
    /// color. Runs off the main actor; all the ScreenCaptureKit objects stay
    /// local so nothing non-Sendable crosses back.
    nonisolated private static func sampleCenter(displayID: CGDirectDisplayID, rect: CGRect) async -> RGB? {
        guard
            let content = try? await SCShareableContent.current,
            let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = max(1, Int(rect.width))
        config.height = max(1, Int(rect.height))
        config.showsCursor = false

        guard
            let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            ),
            let color = NSBitmapImageRep(cgImage: image)
                .colorAt(x: image.width / 2, y: image.height / 2)?
                .usingColorSpace(.sRGB)
        else { return nil }

        return RGB(r: Double(color.redComponent), g: Double(color.greenComponent), b: Double(color.blueComponent))
    }

    private func finish(_ color: NSColor?) {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        overlay?.orderOut(nil)
        overlay = nil
        NSCursor.arrow.set()
        let completion = self.completion
        self.completion = nil
        completion?(color)
    }
}
