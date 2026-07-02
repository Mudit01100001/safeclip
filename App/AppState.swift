import AppKit
import SafeClipCore
import SwiftUI

/// The shared modifier applied to every numeric quick-paste slot, so the user
/// can re-base all ten at once instead of rebinding each.
enum QuickPasteModifier: String, Codable, CaseIterable, Identifiable, Sendable {
    case controlCommand, optionCommand, controlOption, shiftCommand

    var id: String { rawValue }

    var label: String {
        switch self {
        case .controlCommand: "⌃⌘  Control-Command"
        case .optionCommand: "⌥⌘  Option-Command"
        case .controlOption: "⌃⌥  Control-Option"
        case .shiftCommand: "⇧⌘  Shift-Command"
        }
    }

    var flags: NSEvent.ModifierFlags {
        switch self {
        case .controlCommand: [.control, .command]
        case .optionCommand: [.option, .command]
        case .controlOption: [.control, .option]
        case .shiftCommand: [.shift, .command]
        }
    }
}

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
    var clickFixDetection: Bool = true            // safety-led default ON (one-time migration enables it for existing installs)
    var captureConcealed: Bool = true             // Mudit copies passwords and wants them captured
    var maskConcealedPreviews: Bool = true        // …but masked in the panel
    var autoBurnConcealed: Bool = false
    var ignoreConcealedFrom: [String] = []        // source bundles whose ConcealedType mark we ignore (e.g. dictation/chat apps that over-apply it)
    var captureImages: Bool = true                // v0.2.0 — encrypted, PNG-normalized, ≤10 MB
    var indexImageText: Bool = true               // OCR copied images on-device so they're searchable
    var captureFiles: Bool = true                 // v0.2.0 — stores paths, not file contents
    var clearClipboardAfterSensitivePaste: Int = 35  // seconds; 0 = off
    var caretAnchoring: Bool = false              // opt-in: panel above the text caret (read-only AX)
    var assistChromiumApps: Bool = true           // with caret anchoring: switch on Chromium/Electron a11y so the caret is readable there
    var caretProximityPoints: Double = 500        // anchor to the caret only within this many points of the pointer; else use the pointer
    var quickPasteModifier: QuickPasteModifier = .controlCommand  // base modifier for ⌃⌘1…0 quick-paste slots
    var expandSnippets: Bool = false              // opt-in #11: type a trigger → expand snippet (needs Accessibility; synthesizes keystrokes)
    var syncEnabled: Bool = false                 // opt-in #12: E2E-encrypted history sync via a shared folder (experimental)
    // Debug builds default OFF so only the build you explicitly launch runs —
    // a Debug build registering itself as a login item is what resurrected
    // stale DerivedData bundles during development. Release ships ON.
    #if DEBUG
    var launchAtLogin: Bool = false
    #else
    var launchAtLogin: Bool = true
    #endif
}

// Tolerant decoding: fields added in later versions fall back to their
// defaults instead of failing the decode and silently resetting *all*
// settings (which is what synthesized Codable would do).
extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? d.historyLimit
        expiryDays = try c.decodeIfPresent(Int.self, forKey: .expiryDays) ?? d.expiryDays
        stripFormattingByDefault = try c.decodeIfPresent(Bool.self, forKey: .stripFormattingByDefault) ?? d.stripFormattingByDefault
        screenRecordingPrivacy = try c.decodeIfPresent(Bool.self, forKey: .screenRecordingPrivacy) ?? d.screenRecordingPrivacy
        exclusionList = try c.decodeIfPresent([String].self, forKey: .exclusionList) ?? d.exclusionList
        patternDetectionEnabled = try c.decodeIfPresent(Bool.self, forKey: .patternDetectionEnabled) ?? d.patternDetectionEnabled
        detectAPIKeys = try c.decodeIfPresent(Bool.self, forKey: .detectAPIKeys) ?? d.detectAPIKeys
        detectCards = try c.decodeIfPresent(Bool.self, forKey: .detectCards) ?? d.detectCards
        detectPrivateKeys = try c.decodeIfPresent(Bool.self, forKey: .detectPrivateKeys) ?? d.detectPrivateKeys
        autoBurnFlagged = try c.decodeIfPresent(Bool.self, forKey: .autoBurnFlagged) ?? d.autoBurnFlagged
        clickFixDetection = try c.decodeIfPresent(Bool.self, forKey: .clickFixDetection) ?? d.clickFixDetection
        captureConcealed = try c.decodeIfPresent(Bool.self, forKey: .captureConcealed) ?? d.captureConcealed
        maskConcealedPreviews = try c.decodeIfPresent(Bool.self, forKey: .maskConcealedPreviews) ?? d.maskConcealedPreviews
        autoBurnConcealed = try c.decodeIfPresent(Bool.self, forKey: .autoBurnConcealed) ?? d.autoBurnConcealed
        ignoreConcealedFrom = try c.decodeIfPresent([String].self, forKey: .ignoreConcealedFrom) ?? d.ignoreConcealedFrom
        captureImages = try c.decodeIfPresent(Bool.self, forKey: .captureImages) ?? d.captureImages
        indexImageText = try c.decodeIfPresent(Bool.self, forKey: .indexImageText) ?? d.indexImageText
        captureFiles = try c.decodeIfPresent(Bool.self, forKey: .captureFiles) ?? d.captureFiles
        clearClipboardAfterSensitivePaste = try c.decodeIfPresent(Int.self, forKey: .clearClipboardAfterSensitivePaste) ?? d.clearClipboardAfterSensitivePaste
        caretAnchoring = try c.decodeIfPresent(Bool.self, forKey: .caretAnchoring) ?? d.caretAnchoring
        assistChromiumApps = try c.decodeIfPresent(Bool.self, forKey: .assistChromiumApps) ?? d.assistChromiumApps
        caretProximityPoints = try c.decodeIfPresent(Double.self, forKey: .caretProximityPoints) ?? d.caretProximityPoints
        quickPasteModifier = try c.decodeIfPresent(QuickPasteModifier.self, forKey: .quickPasteModifier) ?? d.quickPasteModifier
        expandSnippets = try c.decodeIfPresent(Bool.self, forKey: .expandSnippets) ?? d.expandSnippets
        syncEnabled = try c.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? d.syncEnabled
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
    }
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
    var kind: ClipKind = .text
    var plainText: String
    var richData: Data?
    var richType: String?
    var thumbnailData: Data?
    /// Image byte count / file count; nil for text (uses character count).
    var countOverride: Int?
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
    /// User-authored saved snippets (curated, persistent — separate from the
    /// rolling clipboard history). Surfaced in the panel and Settings → Snippets.
    private(set) var snippets: [Snippet] = []
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
    var onReplayOnboarding: (() -> Void)?
    /// Called with items about to be removed so the sync engine can record a
    /// tombstone (it needs the content to compute the shared sync hash) before
    /// the row is gone. No-op unless sync is configured.
    var onWillDelete: (([ClipItem]) -> Void)?
    /// Called after a user-initiated change so the sync engine can publish it
    /// (debounced). No-op unless sync is configured.
    var onLocalChange: (() -> Void)?

    /// Re-presents the first-run onboarding wizard on demand (Settings → About).
    func replayOnboarding() { onReplayOnboarding?() }

    init(store: HistoryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        reloadHistory()
        reloadSnippets()
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

        switch capture.kind {
        case .image where !settings.captureImages: return
        case .fileList where !settings.captureFiles: return
        default: break
        }

        var flagReason: FlagReason?
        var burn = false

        // Some apps over-apply ConcealedType (dictation tools like Wispr Flow
        // paste into the focused app, which then gets recorded as the source;
        // chat apps mark copies concealed too). The user can opt those sources
        // out so their copies aren't masked as passwords.
        let ignoresConcealed = capture.sourceBundle
            .map { settings.ignoreConcealedFrom.contains($0) } ?? false
        let isConcealed = capture.isConcealed && !ignoresConcealed

        // Scan text FIRST so an active pastejacking threat is recognised even
        // when the source app marked the copy concealed — a shell command
        // copied from a browser address bar is tagged ConcealedType by Safari,
        // and ClickFix must outrank password-masking. (Pattern/ClickFix
        // scanning is text-only; image bytes and file paths aren't commands.)
        if capture.kind == .text {
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

        // Concealed (password-manager) content: mask it — unless the scan
        // already found a more urgent pastejacking flag, which stays visible.
        if isConcealed, flagReason != .clickfix {
            // Honouring the user's decision: captured by default, flagged so
            // the panel masks it, optionally burned.
            guard settings.captureConcealed else { return }
            flagReason = .concealed
            burn = settings.autoBurnConcealed
        }

        let input = CaptureInput(
            kind: capture.kind,
            plainText: capture.plainText,
            richData: capture.richData,
            richType: capture.richType,
            thumbnailData: capture.thumbnailData,
            sourceBundle: capture.sourceBundle,
            flagReason: flagReason,
            isBurn: burn,
            countOverride: capture.countOverride
        )
        do {
            let outcome = try store.insert(input)
            if settings.historyLimit > 0 {
                try store.enforceLimit(settings.historyLimit)
            }
            reloadHistory()
            if case .inserted = outcome { onLocalChange?() }
            // Index text inside newly-stored images on-device so they're
            // searchable. Runs after insert so the image appears immediately;
            // the OCR text fills in shortly after.
            if case .inserted(let id) = outcome,
               capture.kind == .image,
               settings.indexImageText,
               let imageData = capture.richData {
                indexImageText(id: id, imageData: imageData)
            }
        } catch {
            NSLog("SafeClip: capture insert failed: \(error)")
        }
    }

    /// On-device OCR of a stored image, written back as encrypted, searchable
    /// `ocr_text`. Best-effort and silent — failure just leaves it unindexed.
    private func indexImageText(id: UUID, imageData: Data) {
        Task { @MainActor [weak self] in
            let text = await OCRService.recognizeText(in: imageData)
            #if DEBUG
            NSLog("SafeClip OCR-index: image \(imageData.count) bytes → \(text?.count ?? -1) chars recognized")
            #endif
            guard let text, let self else { return }
            try? self.store.setOCRText(id: id, text)
            self.reloadHistory()
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
            onWillDelete?([item])
            try? store.delete(id: item.id) // F7: burn after paste
        }
        reloadHistory()
        onLocalChange?()
    }

    /// "Copy again" from the context menu — same placement path as paste.
    func copyAgain(_ item: ClipItem) {
        paste(item, optionHeld: false)
    }

    /// Places text on the clipboard marked as our own write, so the monitor does
    /// NOT capture it into history. Used for the sync recovery phrase, which is
    /// the shared key and must never be stored.
    func copyToClipboard(_ text: String) {
        pasteService.placePlainText(text)
    }

    /// Multipaste: combines several items (in the given order) into one
    /// plain-text payload on the clipboard for a single ⌘V. Like every paste
    /// path it never synthesizes ⌘V — the user presses it.
    func pasteCombined(_ items: [ClipItem], separator: String = "\n") {
        guard !items.isEmpty else { return }
        let combined = items.map(\.plainText).joined(separator: separator)
        pasteService.placePlainText(combined)
        for item in items { try? store.markUsed(id: item.id) }
        reloadHistory()
    }

    /// Adds a hex color picked with the eyedropper to history and places it on
    /// the clipboard for ⌘V. Attributed to SafeClip; renders as a swatch.
    func addColorPick(_ hex: String) {
        let input = CaptureInput(
            kind: .text,
            plainText: hex,
            sourceBundle: Bundle.main.bundleIdentifier
        )
        _ = try? store.insert(input)
        pasteService.placePlainText(hex) // marked as our write, so the monitor skips it
        reloadHistory()
    }

    /// Copies the text recognized inside an image clip to the clipboard. Runs
    /// OCR on demand (and caches it) when the image hasn't been indexed yet.
    func copyImageText(_ item: ClipItem) {
        if let text = item.ocrText, !text.isEmpty {
            pasteService.placePlainText(text)
            return
        }
        guard item.kind == .image, let data = item.richData else { return }
        Task { @MainActor [weak self] in
            guard let text = await OCRService.recognizeText(in: data), let self else { return }
            try? self.store.setOCRText(id: item.id, text)
            self.pasteService.placePlainText(text)
            self.reloadHistory()
        }
    }

    func deleteItem(_ item: ClipItem) {
        onWillDelete?([item])
        try? store.delete(id: item.id)
        reloadHistory()
        onLocalChange?()
    }

    func togglePin(_ item: ClipItem) {
        try? store.setPinned(id: item.id, !item.isPinned)
        reloadHistory()
        onLocalChange?()
    }

    func toggleBurn(_ item: ClipItem) {
        try? store.setBurn(id: item.id, !item.isBurn)
        reloadHistory()
        onLocalChange?()
    }

    /// Assigns or clears an item's category (collection). `nil`/empty clears it.
    func setCategory(_ item: ClipItem, _ category: String?) {
        try? store.setCategory(id: item.id, category)
        reloadHistory()
        onLocalChange?()
    }

    func clearAll() {
        onWillDelete?(clips) // F6 — record tombstones so the clear propagates
        try? store.deleteAll()
        reloadHistory()
        onLocalChange?()
    }

    /// Clears flags on all items (un-masks anything an earlier scan mislabeled)
    /// without deleting history.
    func resetAllFlags() {
        _ = try? store.resetAllFlags()
        reloadHistory()
    }

    /// Stops treating copies recorded under `bundleID` as concealed: adds the
    /// app to the ignore list (future copies) and un-masks the existing ones.
    func stopConcealing(source bundleID: String) {
        updateSettings { settings in
            if !settings.ignoreConcealedFrom.contains(bundleID) {
                settings.ignoreConcealedFrom.append(bundleID)
            }
        }
        _ = try? store.unconcealSource(bundleID)
        reloadHistory()
    }

    /// Re-enables concealed masking for `bundleID` (removes it from the ignore
    /// list). Already-stored rows stay un-masked until copied again.
    func resumeConcealing(source bundleID: String) {
        updateSettings { $0.ignoreConcealedFrom.removeAll { $0 == bundleID } }
    }

    // MARK: - Snippets (#9)

    func reloadSnippets() {
        snippets = (try? store.fetchSnippets()) ?? []
    }

    @discardableResult
    func addSnippet(label: String, body: String, trigger: String? = nil) -> Snippet? {
        let created = try? store.insertSnippet(label: label, body: body, trigger: trigger)
        reloadSnippets()
        return created ?? nil
    }

    func updateSnippet(_ snippet: Snippet, label: String, body: String, trigger: String? = nil) {
        try? store.updateSnippet(id: snippet.id, label: label, body: body, trigger: trigger)
        reloadSnippets()
    }

    func deleteSnippet(_ snippet: Snippet) {
        try? store.deleteSnippet(id: snippet.id)
        reloadSnippets()
    }

    /// Bumps a snippet's recency without placing it (used by auto-expand).
    func markSnippetUsed(_ snippet: Snippet) {
        try? store.markSnippetUsed(id: snippet.id)
    }

    /// Persists a new snippet ordering (drag-to-reorder in Settings).
    func reorderSnippets(_ orderedIDs: [UUID]) {
        try? store.reorderSnippets(orderedIDs)
        reloadSnippets()
    }

    /// Places a snippet's body on the clipboard for the user's own ⌘V — the
    /// same pillar-safe path as every paste (no synthesized keystrokes). The
    /// write is marked as ours, so it isn't re-captured into history.
    func pasteSnippet(_ snippet: Snippet) {
        pasteService.placePlainText(snippet.body)
        try? store.markSnippetUsed(id: snippet.id)
        reloadSnippets()
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
