import AppKit
import KeyboardShortcuts
import SafeClipCore
import SwiftUI

/// The always-present `NSStatusItem` (docs/DESIGN.md §3). Holds app controls
/// plus a short "Recent" list of clips for always-in-the-corner access; the
/// full searchable history still lives in the floating panel.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    struct Actions {
        var showPanel: () -> Void
        var pickColor: () -> Void
        var openSettings: () -> Void
        var checkForUpdates: () -> Void
        var sendFeedback: () -> Void
        var clearAll: () -> Void
        var quit: () -> Void
    }

    private let statusItem: NSStatusItem
    private let appState: AppState
    private let actions: Actions
    private var toastPanel: NSPanel?
    private var toastDismissTask: Task<Void, Never>?
    /// Clips backing the "Recent" menu items, indexed by each item's `tag`.
    private var recentClips: [ClipItem] = []
    private static let recentMenuCount = 8

    init(appState: AppState, actions: Actions) {
        self.appState = appState
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        guard let button = statusItem.button else { return }
        let (symbol, description): (String, String) =
            if appState.historyHidden {
                ("eye.slash", "SafeClip: history hidden")
            } else if !appState.captureEnabled {
                ("pause.circle", "SafeClip: capture paused")
            } else {
                ("list.clipboard", "SafeClip: capturing")
            }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        button.image?.isTemplate = true
        button.toolTip = description
    }

    // Rebuilt on every open so state checkmarks are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let showTitle: String =
            if let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel) {
                "Show History (\(shortcut))"
            } else {
                "Show History"
            }
        menu.addItem(makeItem(showTitle, #selector(showPanel)))
        let pickColor = makeItem("Pick a Color…", #selector(pickColorAction))
        pickColor.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)
        menu.addItem(pickColor)
        addRecentSection(to: menu)
        menu.addItem(.separator())

        let capture = makeItem(
            appState.captureEnabled ? "Pause Capture" : "Resume Capture",
            #selector(toggleCapture)
        )
        capture.state = appState.captureEnabled ? .off : .on
        menu.addItem(capture)

        let privacy = makeItem("Privacy Mode (Hide History)", #selector(togglePrivacyMode))
        privacy.state = appState.manualPrivacyMode ? .on : .off
        privacy.toolTip = "Hide history instantly, for screen shares SafeClip can't detect on its own."
        menu.addItem(privacy)

        if appState.pasteboardAccessDenied {
            menu.addItem(.separator())
            let denied = makeItem("⚠︎ Clipboard access denied. Open System Settings…", #selector(openPasteboardSettings))
            menu.addItem(denied)
        }

        menu.addItem(.separator())
        menu.addItem(makeItem("Clear All History…", #selector(clearAll)))
        menu.addItem(.separator())
        let prefs = makeItem("Settings…", #selector(openSettings))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        let checkUpdates = makeItem("Check for Updates…", #selector(checkForUpdatesAction))
        checkUpdates.isEnabled = UpdateService.isSupported
        menu.addItem(checkUpdates)
        menu.addItem(makeItem("Send Feedback…", #selector(sendFeedbackAction)))
        menu.addItem(makeItem("About SafeClip", #selector(openAbout)))
        menu.addItem(.separator())
        let quit = makeItem("Quit SafeClip", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: - Recent clips

    /// Lists the most recent clips for one-click placement (then the user ⌘V's).
    /// Suppressed entirely while history is hidden (screen recording / Privacy
    /// Mode); concealed values stay masked.
    private func addRecentSection(to menu: NSMenu) {
        let clips = appState.historyHidden
            ? []
            : Array(appState.clips.prefix(Self.recentMenuCount))
        recentClips = clips
        guard !clips.isEmpty else { return }

        menu.addItem(.separator())
        let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (index, clip) in clips.enumerated() {
            let item = NSMenuItem(
                title: menuTitle(for: clip),
                action: #selector(pasteRecent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.image = Self.icon(for: clip)
            menu.addItem(item)
        }
    }

    private func menuTitle(for clip: ClipItem) -> String {
        if clip.isConcealed && appState.settings.maskConcealedPreviews {
            return "••••••••"
        }
        switch clip.kind {
        case .image:
            return clip.plainText // "Image W×H"
        case .fileList:
            // Middle-truncate so the file format (extension) stays visible.
            let name = clip.plainText.split(separator: "\n").first
                .map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? "Files"
            return Self.truncatedMiddle(name)
        case .text:
            let raw = clip.plainText
                .split(separator: "\n", omittingEmptySubsequences: false).first
                .map(String.init) ?? clip.plainText
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 48 ? String(trimmed.prefix(48)) + "…" : trimmed
        }
    }

    /// Keeps the start and end of a string (so a filename's extension survives).
    private static func truncatedMiddle(_ s: String, max: Int = 44) -> String {
        guard s.count > max else { return s }
        let head = s.prefix((max * 2) / 3)
        let tail = s.suffix(max / 3)
        return "\(head)…\(tail)"
    }

    private static func icon(for clip: ClipItem) -> NSImage? {
        // Plain text gets no icon (matches the floating panel, which leaves
        // text rows iconless).
        if clip.flagReason == nil, clip.kind == .text { return nil }
        // Real document/folder icon for file copies (reflects Excel, PPT, PDF,
        // folders, …); SF Symbols for everything else.
        if clip.flagReason == nil, clip.kind == .fileList,
           let path = clip.plainText.split(separator: "\n").first {
            let icon = NSWorkspace.shared.icon(forFile: String(path))
            icon.size = NSSize(width: 16, height: 16)
            return icon
        }
        let symbol: String
        switch clip.flagReason {
        case .clickfix: symbol = "exclamationmark.triangle"
        case .concealed: symbol = "lock"
        case .apiKey, .card, .privateKey: symbol = "key"
        case .none:
            switch clip.kind {
            case .image: symbol = "photo"
            case .fileList: symbol = "doc" // unreachable (handled above); keeps the switch total
            case .text: symbol = "doc.on.clipboard"
            }
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard recentClips.indices.contains(sender.tag) else { return }
        let clip = recentClips[sender.tag]
        // Don't place a pastejacking-flagged payload from a quick menu — send
        // the user to the panel, which warns before pasting.
        if clip.flagReason == .clickfix {
            actions.showPanel()
            return
        }
        appState.paste(clip, optionHeld: false)
    }

    // MARK: - Confirmation toast

    /// OCR capture confirmation (green viewfinder).
    func showOCRToast(title: String, snippet: String?) {
        showToast(symbol: "text.viewfinder", tint: .green, title: title, snippet: snippet)
    }

    /// Shows a brief, non-activating pop-up just below the menu-bar icon so an
    /// action (OCR, quick-paste) confirms without stealing focus from the
    /// user's app — they want to stay where they are. Auto-dismisses after ~1.8s.
    func showToast(symbol: String, tint: Color, title: String, snippet: String?) {
        guard let statusWindow = statusItem.button?.window else { return }

        toastDismissTask?.cancel()
        toastPanel?.orderOut(nil)

        let host = NSHostingController(
            rootView: ToastView(symbol: symbol, tint: tint, title: title, snippet: snippet)
        )
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.sharingType = .none // keep toast contents (e.g. a copied value) out of captures
        panel.hidesOnDeactivate = false
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)

        // Right-align under the status item, nudged just below the menu bar.
        let statusFrame = statusWindow.frame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: statusFrame.maxX - size.width,
            y: statusFrame.minY - size.height - 6
        ))
        panel.orderFrontRegardless() // show without activating SafeClip
        toastPanel = panel

        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            if self.toastPanel === panel { self.toastPanel = nil }
        }
    }

    // MARK: - Actions

    @objc private func showPanel() { actions.showPanel() }

    @objc private func pickColorAction() { actions.pickColor() }

    @objc private func toggleCapture() {
        appState.setCaptureEnabled(!appState.captureEnabled)
        refreshIcon()
    }

    @objc private func togglePrivacyMode() {
        appState.manualPrivacyMode.toggle()
        refreshIcon()
    }

    @objc private func openSettings() { actions.openSettings() }

    @objc private func checkForUpdatesAction() { actions.checkForUpdates() }

    @objc private func sendFeedbackAction() { actions.sendFeedback() }

    @objc private func clearAll() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "All encrypted history rows are deleted. This cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear All")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            actions.clearAll()
        }
    }

    @objc private func openAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openPasteboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() { actions.quit() }
}

/// Content of the menu-bar confirmation pop-up (OCR, quick-paste, …).
private struct ToastView: View {
    let symbol: String
    let tint: Color
    let title: String
    let snippet: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let snippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
