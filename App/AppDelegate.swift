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
        let state = AppState(store: store, settings: SettingsStore.load())
        appState = state
        panelController = FloatingPanelController(appState: state)
        settingsController = SettingsWindowController(appState: state)
        menuBar = MenuBarController(
            appState: state,
            actions: .init(
                showPanel: { [weak self] in self?.panelController?.toggle() },
                openSettings: { [weak self] in self?.settingsController?.open() },
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
        }

        // 5. Screen-recording privacy (F8).
        let watcher = ScreenRecordWatcher()
        watcher.onChange = { [weak self] recording in
            self?.appState?.isRecordingScreen = recording
            self?.menuBar?.refreshIcon()
        }
        screenWatcher = watcher
        watcher.start()

        // 6. Global shortcut.
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            MainActor.assumeIsolated { self?.panelController?.toggle() }
        }

        // 7. Expiry/limit maintenance — at launch, then hourly (F9).
        state.runMaintenance()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.appState?.runMaintenance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer

        // 8. Onboarding gate — capture starts only after first-run consent.
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            monitor.start()
        } else {
            let onboarding = OnboardingWindowController(appState: state) { [weak self] accepted in
                let defaults = UserDefaults.standard
                defaults.set(true, forKey: "hasCompletedOnboarding")
                defaults.set(accepted, forKey: "hasAcceptedTerms")
                defaults.set("1.0", forKey: "termsVersion")
                defaults.set(Date().timeIntervalSince1970, forKey: "termsRespondedAt")
                self?.onboardingController = nil
                self?.monitor?.start()
                if let settings = self?.appState?.settings {
                    self?.syncLoginItem(settings.launchAtLogin)
                }
            }
            onboardingController = onboarding
            onboarding.present()
        }
        menuBar?.refreshIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        screenWatcher?.stop()
        maintenanceTimer?.invalidate()
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
