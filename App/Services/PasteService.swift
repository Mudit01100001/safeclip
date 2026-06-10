import AppKit
import SafeClipCore

/// Writes a chosen item to `NSPasteboard` for the user's own ⌘V.
///
/// SafeClip never synthesizes keystrokes — that would require the
/// Accessibility permission, which is the zero-permission design pillar
/// (PRD §8.1). The trade: plaintext sits on the system pasteboard until the
/// receiving app reads it (the disclosed "paste window", TERMS §3).
///
/// Mitigations applied here:
///  - every write carries `safeClipMarker` so the monitor never re-captures it
///  - sensitive items (concealed or burn-flagged) are re-marked
///    `ConcealedType` so other well-behaved clipboard managers skip them
///  - sensitive items are wiped from the system pasteboard after a timeout if
///    nothing replaced them — the same pattern password managers use
@MainActor
final class PasteService {
    func place(item: ClipItem, asRich: Bool, clearAfterSeconds: Int) {
        let pasteboard = NSPasteboard.general
        let sensitive = item.isConcealed || item.isBurn

        switch item.kind {
        case .image:
            placeImage(item, on: pasteboard, sensitive: sensitive)
        case .fileList:
            placeFiles(item, on: pasteboard, sensitive: sensitive)
        case .text:
            placeText(item, on: pasteboard, asRich: asRich, sensitive: sensitive)
        }

        scheduleClearIfSensitive(
            pasteboard, sensitive: sensitive, clearAfterSeconds: clearAfterSeconds
        )
    }

    /// Images paste as images regardless of the plain/rich modifier; the
    /// "Image W×H" placeholder is display-only and never written out.
    private func placeImage(_ item: ClipItem, on pasteboard: NSPasteboard, sensitive: Bool) {
        pasteboard.clearContents()
        if let data = item.richData, let image = NSImage(data: data) {
            // NSImage provides multiple representations (PNG + TIFF) so
            // older receivers that only read TIFF still work.
            pasteboard.writeObjects([image])
        }
        markOwnWrite(pasteboard, sensitive: sensitive)
    }

    /// File lists paste as real file URLs (Finder pastes the files) plus the
    /// path text for plain-text fields.
    private func placeFiles(_ item: ClipItem, on pasteboard: NSPasteboard, sensitive: Bool) {
        pasteboard.clearContents()
        let urls = item.plainText
            .split(separator: "\n")
            .map { URL(fileURLWithPath: String($0)) as NSURL }
        if !urls.isEmpty {
            pasteboard.writeObjects(urls)
        }
        pasteboard.addTypes([.string], owner: nil)
        pasteboard.setString(item.plainText, forType: .string)
        markOwnWrite(pasteboard, sensitive: sensitive)
    }

    private func placeText(_ item: ClipItem, on pasteboard: NSPasteboard, asRich: Bool, sensitive: Bool) {
        var types: [NSPasteboard.PasteboardType] = [.string]
        let richType: NSPasteboard.PasteboardType? =
            (asRich && item.richData != nil && item.richType != nil)
                ? .init(item.richType!) : nil
        if let richType {
            types.append(richType)
        }

        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(item.plainText, forType: .string)
        if let richType, let richData = item.richData {
            pasteboard.setData(richData, forType: richType)
        }
        markOwnWrite(pasteboard, sensitive: sensitive)
    }

    /// Every SafeClip write carries the self-write marker (so the monitor
    /// never re-captures it) and the source convention; sensitive writes are
    /// re-marked concealed so other clipboard managers skip them.
    private func markOwnWrite(_ pasteboard: NSPasteboard, sensitive: Bool) {
        var types: [NSPasteboard.PasteboardType] = [
            .init(PasteboardConvention.safeClipMarker),
            .init(PasteboardConvention.source),
        ]
        if sensitive {
            types.append(.init(PasteboardConvention.concealed))
        }
        pasteboard.addTypes(types, owner: nil)
        pasteboard.setString("1", forType: .init(PasteboardConvention.safeClipMarker))
        pasteboard.setString(
            Bundle.main.bundleIdentifier ?? "com.mudit.safeclip",
            forType: .init(PasteboardConvention.source)
        )
        if sensitive {
            pasteboard.setString("1", forType: .init(PasteboardConvention.concealed))
        }
    }

    private func scheduleClearIfSensitive(
        _ pasteboard: NSPasteboard, sensitive: Bool, clearAfterSeconds: Int
    ) {
        guard sensitive, clearAfterSeconds > 0 else { return }
        let expectedChangeCount = pasteboard.changeCount
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(clearAfterSeconds))
            let pb = NSPasteboard.general
            // Only clear if the pasteboard still holds *our* sensitive write —
            // never stomp on something the user copied in the meantime.
            if pb.changeCount == expectedChangeCount {
                pb.clearContents()
            }
        }
    }
}
