import AppKit
import SafeClipCore
import SwiftUI

/// All persisted preferences (PRD §10). Defaults follow the closed decisions
/// in CLAUDE.md: capture-everything by default, detection opt-in.
struct AppSettings: Codable, Equatable, Sendable {
    var historyLimit: Int = 200                   // 0 = unlimited
    var expiryDays: Int = 7                       // 0 = never
    var stripFormattingByDefault: Bool = true     // Return = plain, ⌥Return = rich
    var screenRecordingPrivacy: Bool = true
    var exclusionList: [String] = []              // empty by default — opt-in
    var patternDetectionEnabled: Bool = false     // opt-in master switch
    var detectAPIKeys: Bool = true
    var detectCards: Bool = true
    var detectPrivateKeys: Bool = true
    var autoBurnFlagged: Bool = false
    var clickFixDetection: Bool = false           // P2 feature, opt-in
    var captureConcealed: Bool = true             // Mudit copies passwords and wants them captured
    var maskConcealedPreviews: Bool = true        // …but masked in the panel
    var autoBurnConcealed: Bool = false
    var clearClipboardAfterSensitivePaste: Int = 35  // seconds; 0 = off
    var launchAtLogin: Bool = true
}

enum SettingsStore {
    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    static func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// One observed pasteboard change, as read by the clipboard monitor.
struct PasteboardCapture: Sendable {
    var plainText: String
    var richData: Data?
    var richType: String?
    var sourceBundle: String?
    /// The source app marked this content `org.nspasteboard.ConcealedType`.
    var isConcealed: Bool
}

/// Root observable state shared by all three UI surfaces (docs/DESIGN.md §6).
/// Owns the store and paste service; the AppDelegate owns the monitors and
/// reacts to the closures below.
@MainActor
@Observable
final class AppState {
    private(set) var clips: [ClipItem] = []
    private(set) var captureEnabled = true
    var isRecordingScreen = false
    var manualPrivacyMode = false
    var pasteboardAccessDenied = false
    private(set) var settings: AppSettings

    let store: HistoryStore
    private let scanner = SecurityScanner()
    private let pasteService = PasteService()

    // Wired by AppDelegate.
    var onCaptureToggled: ((Bool) -> Void)?
    var onSettingsApplied: ((AppSettings) -> Void)?
    var onDisplayStateChanged: (() -> Void)?

    init(store: HistoryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        reloadHistory()
    }

    /// Panel content is hidden while screen recording is suspected (F8) or
    /// the user toggled privacy mode in the menu bar.
    var historyHidden: Bool {
        (settings.screenRecordingPrivacy && isRecordingScreen) || manualPrivacyMode
    }

    // MARK: - Settings

    func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var copy = settings
        mutate(&copy)
        guard copy != settings else { return }
        settings = copy
        SettingsStore.save(copy)
        onSettingsApplied?(copy)
    }

    /// SwiftUI two-way binding into a settings field that persists on set.
    func settingsBinding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.updateSettings { $0[keyPath: keyPath] = newValue } }
        )
    }

    // MARK: - Capture pipeline

    func setCaptureEnabled(_ enabled: Bool) {
        guard captureEnabled != enabled else { return }
        captureEnabled = enabled
        onCaptureToggled?(enabled)
        onDisplayStateChanged?()
    }

    func handleCapture(_ capture: PasteboardCapture) {
        guard captureEnabled else { return }
        if let source = capture.sourceBundle, settings.exclusionList.contains(source) {
            return // F10: excluded apps leave no row at all
        }

        var flagReason: FlagReason?
        var burn = false

        if capture.isConcealed {
            // Password-manager copies. Honouring the user's decision: captured
            // by default, flagged so the panel masks them, optionally burned.
            guard settings.captureConcealed else { return }
            flagReason = .concealed
            burn = settings.autoBurnConcealed
        } else {
            let options = SecurityScanner.Options(
                detectClickFix: settings.clickFixDetection,
                detectAPIKeys: settings.patternDetectionEnabled && settings.detectAPIKeys,
                detectCards: settings.patternDetectionEnabled && settings.detectCards,
                detectPrivateKeys: settings.patternDetectionEnabled && settings.detectPrivateKeys
            )
            let result = scanner.scan(
                text: capture.plainText,
                sourceBundle: capture.sourceBundle,
                options: options
            )
            flagReason = result.flagReason
            // ClickFix items are kept visible with a warning — auto-deleting
            // evidence of an attack would hide it from the user.
            if let reason = flagReason, reason != .clickfix, settings.autoBurnFlagged {
                burn = true
            }
        }

        let input = CaptureInput(
            plainText: capture.plainText,
            richData: capture.richData,
            richType: capture.richType,
            sourceBundle: capture.sourceBundle,
            flagReason: flagReason,
            isBurn: burn
        )
        do {
            _ = try store.insert(input)
            if settings.historyLimit > 0 {
                try store.enforceLimit(settings.historyLimit)
            }
            reloadHistory()
        } catch {
            NSLog("SafeClip: capture insert failed: \(error)")
        }
    }

    // MARK: - History intents

    func reloadHistory() {
        clips = (try? store.fetchAll()) ?? []
    }

    /// Places an item on the pasteboard for the user's own ⌘V (PRD §8 — no
    /// synthesized keystrokes). `optionHeld` flips the plain/rich default.
    func paste(_ item: ClipItem, optionHeld: Bool) {
        let asRich = settings.stripFormattingByDefault ? optionHeld : !optionHeld
        let sensitive = item.isBurn || item.isConcealed
        pasteService.place(
            item: item,
            asRich: asRich,
            clearAfterSeconds: sensitive ? settings.clearClipboardAfterSensitivePaste : 0
        )
        try? store.markUsed(id: item.id)
        if item.isBurn {
            try? store.delete(id: item.id) // F7: burn after paste
        }
        reloadHistory()
    }

    /// "Copy again" from the context menu — same placement path as paste.
    func copyAgain(_ item: ClipItem) {
        paste(item, optionHeld: false)
    }

    func deleteItem(_ item: ClipItem) {
        try? store.delete(id: item.id)
        reloadHistory()
    }

    func togglePin(_ item: ClipItem) {
        try? store.setPinned(id: item.id, !item.isPinned)
        reloadHistory()
    }

    func toggleBurn(_ item: ClipItem) {
        try? store.setBurn(id: item.id, !item.isBurn)
        reloadHistory()
    }

    func clearAll() {
        try? store.deleteAll() // F6
        reloadHistory()
    }

    /// Expiry sweep + history-limit enforcement; runs at launch and hourly.
    func runMaintenance() {
        if settings.expiryDays > 0 {
            let cutoff = Date().addingTimeInterval(-TimeInterval(settings.expiryDays) * 86_400)
            _ = try? store.sweepExpired(olderThan: cutoff) // F9
        }
        if settings.historyLimit > 0 {
            _ = try? store.enforceLimit(settings.historyLimit)
        }
        reloadHistory()
    }
}
