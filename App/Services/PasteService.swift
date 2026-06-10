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

        var types: [NSPasteboard.PasteboardType] = [
            .string,
            .init(PasteboardConvention.safeClipMarker),
            .init(PasteboardConvention.source),
        ]
        if sensitive {
            types.append(.init(PasteboardConvention.concealed))
        }
        let richType: NSPasteboard.PasteboardType? =
            (asRich && item.richData != nil && item.richType != nil)
                ? .init(item.richType!) : nil
        if let richType {
            types.append(richType)
        }

        pasteboard.declareTypes(types, owner: nil)
        pasteboard.setString(item.plainText, forType: .string)
        pasteboard.setString("1", forType: .init(PasteboardConvention.safeClipMarker))
        pasteboard.setString(
            Bundle.main.bundleIdentifier ?? "com.mudit.safeclip",
            forType: .init(PasteboardConvention.source)
        )
        if sensitive {
            pasteboard.setString("1", forType: .init(PasteboardConvention.concealed))
        }
        if let richType, let richData = item.richData {
            pasteboard.setData(richData, forType: richType)
        }

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
