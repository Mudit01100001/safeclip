import AppKit
import SafeClipCore

/// Auto-expand snippets (#11): watches typed characters globally and, when the
/// user types a snippet's trigger, deletes the trigger and inserts the body.
///
/// This is the one feature that **breaks the zero-permission pillar** — it both
/// monitors keystrokes and synthesizes them — so it is **opt-in, default OFF, and
/// gated behind Accessibility** (like caret anchoring). It never touches the
/// clipboard. Disabled → nothing is installed and no keys are observed.
@MainActor
final class SnippetExpander {
    private weak var appState: AppState?
    private var monitors: [Any] = []
    private var buffer = ""
    /// True while we delete-and-insert, so our own synthesized keys are ignored.
    private var expanding = false

    /// Tag stamped on every event we synthesize (via the event source) so the
    /// monitor never feeds our own keystrokes back into the buffer.
    private static let syntheticTag: Int64 = 0x5AFE_C0DE
    private static let maxBuffer = 60
    /// Backspace (kVK_Delete) virtual key.
    private static let backspaceKey: CGKeyCode = 0x33

    init(appState: AppState) { self.appState = appState }

    var isActive: Bool { !monitors.isEmpty }

    func setEnabled(_ on: Bool) {
        on ? start() : stop()
    }

    private func start() {
        guard monitors.isEmpty, AXIsProcessTrusted() else { return }
        buffer = ""
        let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) }
        })
        if let keys { monitors.append(keys) }
        // A click moves to a new context — drop any half-typed trigger.
        let clicks = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.buffer = "" }
            }
        )
        if let clicks { monitors.append(clicks) }
    }

    private func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        buffer = ""
    }

    private func handleKey(_ event: NSEvent) {
        guard !expanding else { return }
        // Never re-process the keystrokes we synthesize.
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == Self.syntheticTag { return }

        // A shortcut (⌘/⌃/⌥) isn't typing — reset the trigger buffer.
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            buffer = ""
            return
        }

        switch event.keyCode {
        case 51: // backspace
            if !buffer.isEmpty { buffer.removeLast() }
            return
        case 36, 76, 48, 53, 123, 124, 125, 126: // return, tab, esc, arrows → boundary
            buffer = ""
            return
        default:
            break
        }

        guard let chars = event.characters, !chars.isEmpty,
              let scalar = chars.unicodeScalars.first, scalar.value >= 0x20 else { return }
        buffer.append(contentsOf: chars)
        if buffer.count > Self.maxBuffer { buffer = String(buffer.suffix(Self.maxBuffer)) }
        matchAndExpand()
    }

    private func matchAndExpand() {
        guard let snippets = appState?.snippets else { return }
        // Longest trigger first, so ";sigfull" beats ";sig".
        let candidates = snippets
            .compactMap { snippet -> (String, Snippet)? in
                guard let trigger = snippet.trigger, !trigger.isEmpty else { return nil }
                return (trigger, snippet)
            }
            .sorted { $0.0.count > $1.0.count }
        for (trigger, snippet) in candidates where buffer.hasSuffix(trigger) {
            buffer = ""
            expand(snippet, triggerLength: trigger.count)
            return
        }
    }

    private func expand(_ snippet: Snippet, triggerLength: Int) {
        expanding = true
        // Let the trigger's final character land in the focused app first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self else { return }
            self.deleteBackward(triggerLength)
            self.insertText(snippet.body)
            self.appState?.markSnippetUsed(snippet)
            // Release the guard after the synthesized events have flushed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.expanding = false }
        }
    }

    // MARK: - Synthesis (Accessibility-gated; tagged so we ignore our own keys)

    private func taggedSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = Self.syntheticTag
        return source
    }

    private func deleteBackward(_ count: Int) {
        guard count > 0, let source = taggedSource() else { return }
        for _ in 0..<count {
            CGEvent(keyboardEventSource: source, virtualKey: Self.backspaceKey, keyDown: true)?
                .post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: source, virtualKey: Self.backspaceKey, keyDown: false)?
                .post(tap: .cghidEventTap)
        }
    }

    private func insertText(_ text: String) {
        guard !text.isEmpty, let source = taggedSource() else { return }
        var utf16 = Array(text.utf16)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
