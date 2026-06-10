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
        let source = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        // 1) File copies — checked before text because Finder also puts the
        //    file *name* on the pasteboard as a plain string.
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            onCapture?(
                PasteboardCapture(
                    kind: .fileList,
                    plainText: urls.map(\.path).joined(separator: "\n"),
                    countOverride: urls.count,
                    sourceBundle: source,
                    isConcealed: concealed
                )
            )
            return
        }

        // 2) Text. When both a string and an image are present (spreadsheet
        //    cells, rich editors) the string wins — known trade-off: a
        //    browser "Copy Image" that includes a URL string captures the URL.
        if let plain = pasteboard.string(forType: .string), !plain.isEmpty {
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
                    sourceBundle: source,
                    isConcealed: concealed
                )
            )
            return
        }

        // 3) Pure image (screenshots, "Copy Image").
        if let capture = Self.readImage(from: pasteboard, source: source, concealed: concealed) {
            onCapture?(capture)
        }
    }

    // MARK: - Image capture (v0.2.0)

    /// Raw payloads beyond this are skipped entirely — clipboard history is
    /// not a media library (PRD §12 size-cap edge case).
    static let maxImageBytes = 10 * 1024 * 1024

    private static func readImage(
        from pasteboard: NSPasteboard,
        source: String?,
        concealed: Bool
    ) -> PasteboardCapture? {
        let rawPNG = pasteboard.data(forType: .png)
        let rawTIFF = rawPNG == nil ? pasteboard.data(forType: .tiff) : nil
        guard let raw = rawPNG ?? rawTIFF, raw.count <= maxImageBytes else { return nil }
        guard let rep = NSBitmapImageRep(data: raw) else { return nil }

        // Normalize TIFF to PNG (smaller, deterministic for dedup); keep
        // already-PNG payloads byte-identical.
        let payload: Data
        if rawPNG != nil {
            payload = raw
        } else if let png = rep.representation(using: .png, properties: [:]),
                  png.count <= maxImageBytes {
            payload = png
        } else {
            return nil
        }

        return PasteboardCapture(
            kind: .image,
            plainText: "Image \(rep.pixelsWide)×\(rep.pixelsHigh)",
            richData: payload,
            richType: "public.png",
            thumbnailData: thumbnail(of: rep),
            countOverride: payload.count,
            sourceBundle: source,
            isConcealed: concealed
        )
    }

    /// Small PNG preview for the panel row, stored encrypted like the payload.
    private static func thumbnail(of rep: NSBitmapImageRep, maxDimension: CGFloat = 96) -> Data? {
        let width = CGFloat(rep.pixelsWide)
        let height = CGFloat(rep.pixelsHigh)
        guard width > 0, height > 0 else { return nil }
        let scale = min(1, maxDimension / max(width, height))
        let target = NSSize(width: max(1, width * scale), height: max(1, height * scale))

        guard let thumbRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: thumbRep) else { return nil }
        NSGraphicsContext.current = context
        rep.draw(in: NSRect(origin: .zero, size: target))
        context.flushGraphics()
        return thumbRep.representation(using: .png, properties: [:])
    }
}
