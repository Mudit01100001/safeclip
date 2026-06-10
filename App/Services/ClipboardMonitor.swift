import AppKit
import SafeClipCore

/// Seam for the capture mechanism (PRD §15 / F5). Today there is one polling
/// implementation; when Apple ships a richer detect-before-read API for
/// clipboard managers this protocol is where the second implementation lands.
@MainActor
protocol ClipboardMonitoring: AnyObject {
    var onCapture: ((PasteboardCapture) -> Void)? { get set }
    var onAccessDenied: (() -> Void)? { get set }
    var isRunning: Bool { get }
    func start()
    func stop()
}

/// `changeCount` polling at 200ms (PRD §8). The poll itself is one integer
/// comparison; pasteboard *reads* happen only when the count moved.
///
/// macOS pasteboard privacy (the PRD's "macOS 16" model, shipping in current
/// macOS): the first programmatic read triggers one system prompt ("allow
/// SafeClip to paste from other apps"). After the user chooses Always Allow,
/// capture is silent. If the user denies, reads return nothing — we detect
/// the explicit deny via `accessBehavior` and surface guidance instead of
/// failing silently (F5 acceptance: degrade to paused + clear prompt).
@MainActor
final class PollingClipboardMonitor: ClipboardMonitoring {
    var onCapture: ((PasteboardCapture) -> Void)?
    var onAccessDenied: (() -> Void)?

    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        if #available(macOS 15.4, *) {
            if NSPasteboard.general.accessBehavior == .alwaysDeny {
                onAccessDenied?()
                return
            }
        }
        // Skip whatever was on the pasteboard before capture began.
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let types = pasteboard.types, !types.isEmpty else { return }
        let typeNames = Set(types.map(\.rawValue))

        // Our own paste — re-capturing it would resurrect burned items.
        if typeNames.contains(PasteboardConvention.safeClipMarker) { return }
        // nspasteboard.org convention: transient data is never stored.
        if typeNames.contains(PasteboardConvention.transient) { return }

        let concealed = typeNames.contains(PasteboardConvention.concealed)

        // v1 is text-only (PRD §13): pure image/file copies are ignored.
        guard let plain = pasteboard.string(forType: .string), !plain.isEmpty else { return }

        var richData: Data?
        var richType: String?
        if let rtf = pasteboard.data(forType: .rtf) {
            richData = rtf
            richType = "public.rtf"
        } else if let html = pasteboard.data(forType: .html) {
            richData = html
            richType = "public.html"
        }

        onCapture?(
            PasteboardCapture(
                plainText: plain,
                richData: richData,
                richType: richType,
                sourceBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                isConcealed: concealed
            )
        )
    }
}
