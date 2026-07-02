import AppKit
import SafeClipCore

/// End-to-end-encrypted history sync over a folder the user already syncs
/// (iCloud Drive, Dropbox, Syncthing…) — #12, owner-chosen transport.
///
/// Each device writes one AES-256-GCM-encrypted change-log file
/// (`<deviceID>.scsync`) into the shared folder and reads every peer's. The
/// folder/cloud provider only ever sees ciphertext — true E2E. Records are
/// merged last-writer-wins by a *shared* `syncHash` (so the same content
/// converges across devices), and explicit deletes propagate as tombstones.
///
/// The shared key never travels with the files; the user moves it between
/// devices once via a recovery phrase. It is intentionally separate from the
/// per-device on-disk key, which never leaves the Mac (TERMS §2).
///
/// **Experimental, off by default.** Heavy work (file I/O, crypto, DB) runs off
/// the main actor; only state and UI status are touched here.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case off
        case idle
        case syncing
        case ok(Date, SyncApplyStats)
        case error(String)
    }

    private(set) var status: Status = .off

    private weak var appState: AppState?
    private let store: HistoryStore
    private let keychain = KeychainManager(service: "SafeClip", account: "sync-secret")

    private var syncKeys: SyncKeyMaterial?
    /// syncHash → deletion time, for clips the user removed. Persisted to
    /// UserDefaults so a delete survives a quit before the next sync.
    private var tombstones: [String: Date] = [:]
    private var isSyncing = false
    private var debounceTimer: Timer?
    private var periodicTimer: Timer?

    private static let bookmarkKey = "syncFolderBookmark"
    private static let deviceIDKey = "syncDeviceID"
    private static let tombstoneKey = "syncTombstones"

    init(appState: AppState) {
        self.appState = appState
        self.store = appState.store
        loadSecret()
        loadTombstones()
    }

    // MARK: - Configuration state

    var isEnabled: Bool { appState?.settings.syncEnabled == true }
    var hasSecret: Bool { syncKeys != nil }
    var hasFolder: Bool { UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil }
    var isConfigured: Bool { hasSecret && hasFolder }

    /// The chosen folder's path for display (no security-scope side effects).
    var folderDisplayPath: String? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        return url?.path(percentEncoded: false)
    }

    private var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: Self.deviceIDKey) { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: Self.deviceIDKey)
        return fresh
    }

    // MARK: - Lifecycle

    /// Called at launch: begins periodic sync if it's enabled and set up.
    func start() {
        guard isEnabled, isConfigured else {
            status = isEnabled ? .idle : .off
            return
        }
        startPeriodic()
        syncNow()
    }

    /// Turns sync on, pointing it at `folder`. Generates a sync secret on first
    /// use (the user can read it out as a recovery phrase to add other devices).
    @discardableResult
    func enable(folder: URL) -> Bool {
        guard let bookmark = try? folder.bookmarkData(
            options: [], includingResourceValuesForKeys: nil, relativeTo: nil
        ) else {
            status = .error("Couldn't access that folder.")
            return false
        }
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        if syncKeys == nil { setSecret(SyncSecret.generate()) }
        appState?.updateSettings { $0.syncEnabled = true }
        start()
        return true
    }

    func disable() {
        appState?.updateSettings { $0.syncEnabled = false }
        debounceTimer?.invalidate(); debounceTimer = nil
        periodicTimer?.invalidate(); periodicTimer = nil
        status = .off
    }

    // MARK: - Recovery phrase (key transfer between devices)

    func recoveryPhrase() -> String? {
        loadSecretData().map { SyncSecret.phrase(from: $0) }
    }

    /// Imports a secret typed/pasted from another device. Returns false if the
    /// phrase isn't a valid 32-byte key.
    @discardableResult
    func importPhrase(_ phrase: String) -> Bool {
        guard let secret = SyncSecret.secret(fromPhrase: phrase) else { return false }
        setSecret(secret)
        if isEnabled, isConfigured { syncNow() }
        return true
    }

    // MARK: - Triggers

    /// Coalesces rapid local changes into one sync shortly after.
    func scheduleSync() {
        guard isEnabled, isConfigured else { return }
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
    }

    /// Records tombstones for clips the user removed, so the delete propagates.
    /// Must run *before* the rows are gone — it needs the content to compute the
    /// shared sync hash.
    func recordDeletion(_ items: [ClipItem]) {
        guard isEnabled, let keys = syncKeys else { return }
        let now = Date()
        for item in items {
            tombstones[SyncRecord.tombstone(item, at: now, keys: keys).syncHash] = now
        }
        saveTombstones()
        scheduleSync()
    }

    func syncNow() {
        guard isEnabled, isConfigured, !isSyncing else { return }
        isSyncing = true // set synchronously so two triggers can't both start
        Task { await performSync() }
    }

    // MARK: - The sync run

    private func performSync() async {
        defer { isSyncing = false }
        guard let keys = syncKeys, let (folder, stopAccess) = resolveFolder() else {
            status = .error("Sync folder is unavailable.")
            return
        }
        defer { stopAccess() }
        status = .syncing

        let device = deviceID
        let store = self.store
        let known = tombstones
        let cutoff = expiryCutoff()

        let outcome = await Task.detached {
            Self.runFileSync(
                folder: folder, deviceID: device, store: store,
                keys: keys, knownTombstones: known, expiryCutoff: cutoff
            )
        }.value

        tombstones = outcome.tombstones
        saveTombstones()
        if let error = outcome.error {
            status = .error(error)
        } else {
            status = .ok(Date(), outcome.stats)
            if outcome.stats.total > 0 { appState?.reloadHistory() }
        }
    }

    /// All file/crypto/DB work, off the main actor. `HistoryStore` serializes its
    /// own access, so it's safe to call from here.
    nonisolated private static func runFileSync(
        folder: URL, deviceID: String, store: HistoryStore,
        keys: SyncKeyMaterial, knownTombstones: [String: Date], expiryCutoff: Date?
    ) -> SyncOutcome {
        var tombstones = knownTombstones
        let fm = FileManager.default
        let ownURL = folder.appendingPathComponent("\(deviceID).scsync")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)

            // Recover any tombstones from our own previously published file.
            if let data = try? Data(contentsOf: ownURL),
               let records = try? SyncCodec.decode(data, using: keys) {
                for record in records where record.deleted {
                    tombstones[record.syncHash] = max(tombstones[record.syncHash] ?? .distantPast, record.updatedAt)
                }
            }

            // Gather our records + every peer's.
            var sets: [[SyncRecord]] = [try store.exportLiveRecords(syncKeys: keys)]
            sets.append(tombstones.map { SyncRecord(syncHash: $0.key, updatedAt: $0.value, deleted: true, payload: nil) })
            let peers = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in peers
            where file.pathExtension == "scsync" && file.lastPathComponent != ownURL.lastPathComponent {
                if let data = try? Data(contentsOf: file),
                   let records = try? SyncCodec.decode(data, using: keys) {
                    sets.append(records)
                }
            }

            var merged = SyncMerge.merge(sets)
            // Don't resurrect live items older than the local expiry window.
            if let expiryCutoff {
                merged = merged.filter { record in
                    record.deleted
                        || (record.payload.map { ($0.lastUsedAt ?? $0.createdAt) >= expiryCutoff } ?? false)
                }
            }

            let stats = try store.applySync(merged, syncKeys: keys)

            // Keep tombstones bounded: rebuild from the merged result, dropping
            // ones older than 30 days (assumes devices sync within that window).
            let pruneCutoff = Date().addingTimeInterval(-30 * 86_400)
            tombstones = Dictionary(
                uniqueKeysWithValues: merged
                    .filter { $0.deleted && $0.updatedAt > pruneCutoff }
                    .map { ($0.syncHash, $0.updatedAt) }
            )

            // Publish our file: current live records + tombstones.
            let live = try store.exportLiveRecords(syncKeys: keys)
            let ownRecords = live
                + tombstones.map { SyncRecord(syncHash: $0.key, updatedAt: $0.value, deleted: true, payload: nil) }
            try SyncCodec.encode(ownRecords, using: keys).write(to: ownURL, options: .atomic)

            return SyncOutcome(tombstones: tombstones, stats: stats, error: nil)
        } catch {
            return SyncOutcome(tombstones: tombstones, stats: SyncApplyStats(), error: error.localizedDescription)
        }
    }

    private struct SyncOutcome: Sendable {
        let tombstones: [String: Date]
        let stats: SyncApplyStats
        let error: String?
    }

    // MARK: - Helpers

    private func startPeriodic() {
        periodicTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        periodicTimer = timer
    }

    private func expiryCutoff() -> Date? {
        guard let days = appState?.settings.expiryDays, days > 0 else { return nil }
        return Date().addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    private func resolveFolder() -> (URL, () -> Void)? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale
        ) else { return nil }
        let started = url.startAccessingSecurityScopedResource()
        return (url, { if started { url.stopAccessingSecurityScopedResource() } })
    }

    // MARK: - Secret persistence (Keychain)

    private func loadSecret() {
        if let data = loadSecretData() { syncKeys = SyncKeyMaterial(secret: data) }
    }

    private func loadSecretData() -> Data? {
        (try? keychain.loadMasterKey()).flatMap { $0?.count == SyncSecret.byteCount ? $0 : nil }
    }

    private func setSecret(_ data: Data) {
        try? keychain.deleteMasterKey()
        try? keychain.storeMasterKey(data)
        syncKeys = SyncKeyMaterial(secret: data)
    }

    // MARK: - Tombstone persistence (UserDefaults)

    private func loadTombstones() {
        guard let raw = UserDefaults.standard.dictionary(forKey: Self.tombstoneKey) as? [String: Double] else { return }
        tombstones = raw.mapValues { Date(timeIntervalSinceReferenceDate: $0) }
    }

    private func saveTombstones() {
        let raw = tombstones.mapValues { $0.timeIntervalSinceReferenceDate }
        UserDefaults.standard.set(raw, forKey: Self.tombstoneKey)
    }
}
