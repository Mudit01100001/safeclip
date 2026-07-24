import AppKit
import KeyboardShortcuts
import SafeClipCore
import ServiceManagement

/// Owns the startup sequence (docs/DESIGN.md §2) and all surface controllers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var menuBar: MenuBarController?
    private var panelController: FloatingPanelController?
    private var settingsController: SettingsWindowController?
    private var onboardingController: OnboardingWindowController?
    private var monitor: (any ClipboardMonitoring)?
    private var screenWatcher: ScreenRecordWatcher?
    private var maintenanceTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    /// Retained across a pick so it isn't deallocated mid-overlay.
    private let colorPicker = ScreenColorPicker()
    private var snippetExpander: SnippetExpander?
    private var syncService: SyncService?
    private let updateService = UpdateService()

    static var databaseURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SafeClip/history.db")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 1. Encryption key — without it, nothing else starts.
        let keychain = KeychainManager()
        guard let masterKey = obtainMasterKey(keychain) else {
            NSApp.terminate(nil)
            return
        }

        // 2. Encrypted store.
        let store: HistoryStore
        do {
            store = try HistoryStore(
                databaseURL: Self.databaseURL,
                keyMaterial: KeyMaterial(masterKeyData: masterKey)
            )
        } catch {
            fatalAlert(
                title: "SafeClip can't open its history database",
                message: "\(error.localizedDescription)\n\nThe file may be corrupt: \(Self.databaseURL.path)"
            )
            NSApp.terminate(nil)
            return
        }

        // 3. Root state + surfaces.
        // Safety-led default: enable ClickFix/pastejacking warnings once for
        // installs created before it became a default (mirrors the shortcut
        // migration below). Respects a later user opt-out — runs only once.
        var loadedSettings = SettingsStore.load()
        if !UserDefaults.standard.bool(forKey: "clickFixDefaultOnMigrated") {
            loadedSettings.clickFixDetection = true
            SettingsStore.save(loadedSettings)
            UserDefaults.standard.set(true, forKey: "clickFixDefaultOnMigrated")
        }
        // The caret-proximity threshold first shipped too high to ever trigger
        // the pointer fallback on one screen; reset it once to a working value.
        if !UserDefaults.standard.bool(forKey: "caretProximityResetMigrated") {
            loadedSettings.caretProximityPoints = 500
            SettingsStore.save(loadedSettings)
            UserDefaults.standard.set(true, forKey: "caretProximityResetMigrated")
        }
        let state = AppState(store: store, settings: loadedSettings)
        appState = state
        // E2E folder sync (#12) — experimental, off until the user sets it up.
        let sync = SyncService(appState: state)
        syncService = sync
        state.onWillDelete = { [weak sync] items in sync?.recordDeletion(items) }
        state.onLocalChange = { [weak sync] in sync?.scheduleSync() }
        panelController = FloatingPanelController(appState: state)
        settingsController = SettingsWindowController(appState: state, syncService: sync, updateService: updateService)
        menuBar = MenuBarController(
            appState: state,
            actions: .init(
                showPanel: { [weak self] in self?.panelController?.toggle() },
                pickColor: { [weak self] in self?.pickColor() },
                openSettings: { [weak self] in self?.settingsController?.open() },
                checkForUpdates: { [weak self] in self?.updateService.checkForUpdates() },
                sendFeedback: { Feedback.compose() },
                clearAll: { [weak state] in state?.clearAll() },
                quit: { NSApp.terminate(nil) }
            )
        )

        // 4. Capture pipeline.
        let monitor = PollingClipboardMonitor()
        monitor.onCapture = { [weak state] capture in state?.handleCapture(capture) }
        monitor.onAccessDenied = { [weak self] in self?.handlePasteboardDenied() }
        self.monitor = monitor

        state.onCaptureToggled = { [weak self] enabled in
            guard let self, let monitor = self.monitor else { return }
            enabled ? monitor.start() : monitor.stop()
        }
        state.onDisplayStateChanged = { [weak self] in self?.menuBar?.refreshIcon() }
        state.onSettingsApplied = { [weak self] settings in
            self?.syncLoginItem(settings.launchAtLogin)
            self?.appState?.runMaintenance()
            self?.menuBar?.refreshIcon()
            self?.snippetExpander?.setEnabled(settings.expandSnippets)
        }

        // Auto-expand snippets (#11) — opt-in + Accessibility-gated; the expander
        // installs nothing unless the setting is on AND trust is granted.
        let expander = SnippetExpander(appState: state)
        snippetExpander = expander
        expander.setEnabled(state.settings.expandSnippets)

        // 5. Screen-recording privacy (F8).
        let watcher = ScreenRecordWatcher()
        watcher.onChange = { [weak self] recording in
            self?.appState?.isRecordingScreen = recording
            self?.menuBar?.refreshIcon()
        }
        screenWatcher = watcher
        watcher.start()

        // Caret anchoring (opt-in): when on, pre-enable the newly-focused app's
        // accessibility tree so Chromium/Electron apps expose the caret by the
        // first ⌥V (the tree builds asynchronously). No-op on native apps and
        // when the toggle is off. Read-only — see CaretLocator.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncService?.scheduleSync() // pull peer changes when we come forward
                guard let settings = self?.appState?.settings,
                      settings.caretAnchoring, settings.assistChromiumApps else { return }
                CaretLocator.prewarmFrontmostApp()
            }
        }

        // 6. Global shortcuts. One-time reset so existing installs pick up the
        //    v2 defaults (⌥V panel / ⌥C OCR) instead of keeping the old ⌃⇧V.
        if !UserDefaults.standard.bool(forKey: "shortcutsV2Migrated") {
            KeyboardShortcuts.reset(.togglePanel, .captureOCR)
            UserDefaults.standard.set(true, forKey: "shortcutsV2Migrated")
        }

        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            MainActor.assumeIsolated { self?.panelController?.toggle() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureOCR) { [weak self] in
            MainActor.assumeIsolated { self?.runScreenOCR() }
        }
        for (slot, name) in KeyboardShortcuts.Name.quickPaste.enumerated() {
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                MainActor.assumeIsolated { self?.quickPaste(slot: slot) }
            }
        }
        KeyboardShortcuts.onKeyUp(for: .pickColor) { [weak self] in
            MainActor.assumeIsolated { self?.pickColor() }
        }

        // 7. Expiry/limit maintenance — at launch, then hourly (F9).
        state.runMaintenance()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.appState?.runMaintenance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer

        // E2E folder sync — starts periodic sync only if the user enabled it.
        sync.start()

        #if DEBUG
        // Automated scroll diagnosis: SAFECLIP_SCROLL_TEST=1 opens the panel on
        // launch so it writes /tmp/safeclip-scroll-diag.txt without any UI input.
        if ProcessInfo.processInfo.environment["SAFECLIP_SCROLL_TEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.panelController?.show()
            }
        }
        // SAFECLIP_SELFTEST=<N> runs N automated show/scroll/click cycles with
        // real synthetic input and writes one aggregate line to
        // /tmp/safeclip-selftest.txt — moves the real cursor, so it's opt-in
        // only (never baked into the default scheme like SCROLL_TEST above).
        if let raw = ProcessInfo.processInfo.environment["SAFECLIP_SELFTEST"], let n = Int(raw), n > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.panelController?.runSelfTest(iterations: n)
            }
        }
        #endif

        // Replay onboarding on demand (Settings → About).
        state.onReplayOnboarding = { [weak self] in self?.presentOnboarding() }

        // 8. Install-location gate. Running from the mounted .dmg (or a Gatekeeper
        //    App Translocation path) means permission grants and Sparkle updates
        //    are pinned to a randomized, read-only path and get discarded once the
        //    app is moved — so setting anything up here is wasted. Ask the user to
        //    move it to Applications first, and don't onboard or capture until they
        //    relaunch from a real install location.
        if Self.isRunningFromDiskImageOrTranslocated() {
            guard presentMoveToApplicationsNudge() else { return } // "Quit" terminates
        }

        // 9. Onboarding + capture gate. Clipboard capture NEVER begins until the
        //    user has accepted both the Terms and the Privacy Policy — skipping or
        //    closing the wizard records no consent and leaves capture off. The
        //    wizard re-appears every launch until that consent is given (so there
        //    is always a path to it), and once more after a material onboarding
        //    version bump for someone who already consented. A legacy
        //    `hasCompletedOnboarding` flag (set before versioning) counts as v1.
        let defaults = UserDefaults.standard
        let hasConsent = defaults.bool(forKey: "hasAcceptedTerms")
            && defaults.bool(forKey: "hasAcceptedPrivacyPolicy")
        let onboardedVersion = defaults.integer(forKey: "onboardedVersion")
        let effectiveVersion = onboardedVersion > 0
            ? onboardedVersion
            : (defaults.bool(forKey: "hasCompletedOnboarding") ? 1 : 0)
        if hasConsent {
            monitor.start()
        }
        if !hasConsent || effectiveVersion < Self.onboardingVersion {
            presentOnboarding()
        }
        menuBar?.refreshIcon()
    }

    /// True when the app is running from a mounted disk image or a Gatekeeper
    /// App Translocation path rather than a real install location. Mounted `.dmg`
    /// volumes live under `/Volumes`; translocated copies live under a randomized
    /// `…/AppTranslocation/…` path. Dev builds run from DerivedData under the home
    /// directory, so this never fires while developing.
    private static func isRunningFromDiskImageOrTranslocated() -> Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    /// Asks the user to move the app to Applications before continuing. Returns
    /// `true` if they chose to continue anyway (an escape hatch for the rare
    /// legit case of an app installed on an external volume); returns `false`
    /// after terminating when they choose Quit.
    private func presentMoveToApplicationsNudge() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move SafeClip to your Applications folder"
        alert.informativeText = """
        You're running SafeClip from its installer disk image. For its \
        permissions (Screen Recording, Accessibility) and automatic updates to \
        work, it needs to live in your Applications folder.

        Drag SafeClip onto the Applications folder in the installer window, then \
        open it from there. SafeClip will quit so you can do this.
        """
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Continue Anyway")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
            return false
        }
        return true
    }

    /// Bumped only when the onboarding flow changes materially (not per app
    /// release), so existing users are re-shown the wizard once. v2 added the
    /// consolidated permissions step (Enable + Open Settings for Accessibility
    /// and Screen Recording).
    private static let onboardingVersion = 2

    /// The user's previously-recorded consent, used to pre-check the boxes on a
    /// replay/re-show so they aren't forced to re-accept unchanged terms.
    private func storedConsent() -> OnboardingResult {
        let d = UserDefaults.standard
        return OnboardingResult(
            acceptedTerms: d.bool(forKey: "hasAcceptedTerms"),
            acceptedPrivacy: d.bool(forKey: "hasAcceptedPrivacyPolicy"),
            acceptedMarketing: d.bool(forKey: "hasAcceptedMarketing")
        )
    }

    /// Presents the onboarding wizard (first run, the every-launch re-prompt until
    /// consent, a version-bump re-show, and the Settings → About replay). Terms,
    /// Privacy Policy, and marketing consent are each recorded separately (DPDP Act
    /// 2023 §6 — no bundling consent into one flag).
    ///
    /// Capture begins only once Terms + Privacy are both accepted here — a Skip or
    /// a bare close records no consent and leaves capture off (the launch gate
    /// re-shows this wizard until consent exists). Consent is OR-merged so closing
    /// or skipping a re-show can never downgrade an earlier acceptance.
    private func presentOnboarding() {
        guard let state = appState else { return }
        let onboarding = OnboardingWindowController(
            appState: state, initialConsent: storedConsent()
        ) { [weak self] result in
            guard let self else { return }
            self.onboardingController = nil

            let defaults = UserDefaults.standard
            let terms = defaults.bool(forKey: "hasAcceptedTerms") || result.acceptedTerms
            let privacy = defaults.bool(forKey: "hasAcceptedPrivacyPolicy") || result.acceptedPrivacy
            defaults.set(terms, forKey: "hasAcceptedTerms")
            defaults.set(privacy, forKey: "hasAcceptedPrivacyPolicy")
            defaults.set(defaults.bool(forKey: "hasAcceptedMarketing") || result.acceptedMarketing, forKey: "hasAcceptedMarketing")
            defaults.set(true, forKey: "hasCompletedOnboarding")
            defaults.set(Self.onboardingVersion, forKey: "onboardedVersion")
            defaults.set("1.0", forKey: "termsVersion")
            defaults.set("1.0", forKey: "privacyPolicyVersion")
            defaults.set(Date().timeIntervalSince1970, forKey: "termsRespondedAt")

            // Only now that consent is in place does capture begin. Skipping or
            // closing without accepting leaves `terms`/`privacy` false, so this
            // stays off and the launch gate will re-present the wizard.
            if terms && privacy {
                self.monitor?.start() // no-op if already running
                if let settings = self.appState?.settings {
                    self.syncLoginItem(settings.launchAtLogin)
                }
            }
        }
        onboardingController = onboarding
        onboarding.present()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        screenWatcher?.stop()
        maintenanceTimer?.invalidate()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    // MARK: - Quick-paste (⌃⌘1…⌃⌘0)

    /// Places the `slot`-th history item (0-based; matches the panel's order)
    /// on the clipboard for the user's own ⌘V, confirming with a brief toast.
    /// Pastejacking-flagged items are *not* placed silently — the user must go
    /// through the panel, which warns first.
    private func quickPaste(slot: Int) {
        guard let state = appState else { return }
        // Same guard the panel's paste paths apply (performPaste): while
        // history is hidden (screen recording / Privacy Mode) the user can't
        // see what a slot holds, so never place it blind or preview it in a
        // toast. Without this, ⌃⌘1..0 quietly bypassed the privacy mode.
        if state.historyHidden {
            menuBar?.showToast(
                symbol: "eye.slash",
                tint: .secondary,
                title: "Hidden while screen recording",
                snippet: nil
            )
            return
        }
        let clips = state.clips
        guard clips.indices.contains(slot) else {
            menuBar?.showToast(
                symbol: "clipboard",
                tint: .secondary,
                title: "Nothing in slot \(slot + 1)",
                snippet: nil
            )
            return
        }
        let item = clips[slot]
        if item.flagReason == .clickfix {
            menuBar?.showToast(
                symbol: "exclamationmark.triangle.fill",
                tint: .red,
                title: "Flagged item. Open the panel to paste",
                snippet: nil
            )
            return
        }
        state.paste(item, optionHeld: false)
        menuBar?.showToast(
            symbol: "doc.on.clipboard.fill",
            tint: .accentColor,
            title: "Copied. Press ⌘V",
            snippet: Self.quickPastePreview(item)
        )
    }

    /// One-line, non-sensitive preview for the quick-paste toast.
    private static func quickPastePreview(_ item: ClipItem) -> String? {
        if item.isConcealed { return nil } // never surface a concealed value
        switch item.kind {
        case .image:
            return item.plainText // "Image W×H"
        case .fileList:
            return item.plainText
                .split(separator: "\n").first
                .map { URL(fileURLWithPath: String($0)).lastPathComponent }
        case .text:
            return item.plainText
                .split(separator: "\n", omittingEmptySubsequences: false).first
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    // MARK: - Eyedropper (⌥P)

    /// Picks a color with the custom magnifier loupe (owner's eyedropper icon)
    /// and copies its hex into history. Falls back to the system sampler until
    /// Screen Recording is granted, or in the sandboxed build.
    private func pickColor() {
        colorPicker.pick { [weak self] color in
            guard let color else { return } // user cancelled (Esc)
            guard let self else { return }
            let hex = Self.hexString(from: color)
            self.appState?.addColorPick(hex)
            self.menuBar?.showToast(
                symbol: "eyedropper",
                tint: .accentColor,
                title: "Color copied. Press ⌘V",
                snippet: hex
            )
        }
    }

    private static func hexString(from color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // MARK: - Screen OCR (⌥C)

    /// Runs the region-screenshot → OCR → clipboard flow, then confirms via a
    /// menu-bar toast. The recognized text lands on the clipboard (and is
    /// captured into history like any copy); the screenshot is never stored.
    private func runScreenOCR() {
        Task { @MainActor in
            switch await ScreenOCRService.capture() {
            case .copied(let text):
                let snippet = text
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                menuBar?.showOCRToast(title: "Text copied", snippet: snippet)
            case .noText:
                menuBar?.showOCRToast(title: "No text found in selection", snippet: nil)
            case .cancelled:
                break // user dismissed the crosshair — stay silent
            case .unavailable:
                menuBar?.showOCRToast(
                    title: "Screen OCR isn't available in this build",
                    snippet: nil
                )
            }
        }
    }

    // MARK: - Failure paths (PRD §12)

    /// Key unreadable ≠ key missing. Missing → generate fresh. Unreadable →
    /// the user chooses between resetting (losing history) and quitting;
    /// never silently lose data.
    private func obtainMasterKey(_ keychain: KeychainManager) -> Data? {
        do {
            return try keychain.loadOrCreateMasterKey()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "SafeClip can't read its encryption key"
            alert.informativeText = """
                The encryption key in your Keychain exists but can't be read \
                (\(error)). Without it, existing history is unreadable.

                Reset generates a new key and erases the unreadable history. \
                Quit leaves everything untouched so you can investigate.
                """
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Reset Key (Erase History)")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertSecondButtonReturn else { return nil }

            try? keychain.deleteMasterKey()
            try? FileManager.default.removeItem(at: Self.databaseURL)
            return try? keychain.loadOrCreateMasterKey()
        }
    }

    private func handlePasteboardDenied() {
        appState?.pasteboardAccessDenied = true
        appState?.setCaptureEnabled(false)
        menuBar?.refreshIcon()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SafeClip can't read the clipboard"
        alert.informativeText = """
            macOS clipboard access for SafeClip is set to "Never Allow", so \
            nothing can be captured. Allow it under System Settings → Privacy \
            & Security, then resume capture from the menu bar.
            """
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func fatalAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func syncLoginItem(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            // Common for dev builds running from DerivedData; non-fatal.
            NSLog("SafeClip: login item sync failed: \(error)")
        }
    }
}
