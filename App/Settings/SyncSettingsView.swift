import AppKit
import SwiftUI

/// Settings → Sync: opt into end-to-end-encrypted history sync over a folder the
/// user already syncs (iCloud Drive, Dropbox, Syncthing…). Experimental.
struct SyncSettingsView: View {
    let appState: AppState
    @Bindable var sync: SyncService

    @State private var showPhrase = false
    @State private var importText = ""
    @State private var importError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                Divider()
                if sync.isEnabled {
                    enabledControls
                } else {
                    disabledControls
                }
                Divider()
                recoverySection
                Divider()
                limitationsNote
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.tint)
                Text("Sync history across your Macs").font(.headline)
                Text("Beta")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: Capsule())
                    .foregroundStyle(.orange)
            }
            Text("SafeClip writes encrypted change-log files into a folder you already sync (iCloud Drive, Dropbox, Syncthing…). Only your Macs hold the key, so the cloud provider sees nothing but ciphertext — there's no SafeClip server.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            statusRow
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch sync.status {
        case .off:
            label("Off", "circle", .secondary)
        case .idle:
            label("Ready", "circle", .secondary)
        case .syncing:
            label("Syncing…", "arrow.triangle.2.circlepath", .secondary)
        case .ok(let date, let stats):
            let suffix = stats.total > 0
                ? " · +\(stats.inserted) ~\(stats.updated) −\(stats.deleted)" : ""
            label("Last synced \(Self.relative(date))\(suffix)", "checkmark.circle.fill", .green)
        case .error(let message):
            label(message, "exclamationmark.triangle.fill", .red)
        }
    }

    private func label(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
            .padding(.top, 2)
    }

    // MARK: - Disabled

    private var disabledControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick a folder that syncs between your Macs. SafeClip keeps its encrypted files there.")
                .font(.callout)
            Button {
                if let folder = Self.chooseFolder() { sync.enable(folder: folder) }
            } label: {
                Label("Choose Folder & Turn On Sync", systemImage: "folder.badge.plus")
            }
            Text("Adding a second Mac? Enter that Mac's recovery phrase below first, then choose the same folder here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Enabled

    private var enabledControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let path = sync.folderDisplayPath {
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                }
            }
            HStack(spacing: 10) {
                Button {
                    sync.syncNow()
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    if let folder = Self.chooseFolder() { sync.enable(folder: folder) }
                } label: {
                    Label("Change Folder", systemImage: "folder")
                }
                Spacer()
                Button(role: .destructive) {
                    sync.disable()
                } label: {
                    Label("Turn Off", systemImage: "xmark.circle")
                }
            }
        }
    }

    // MARK: - Recovery phrase

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recovery phrase").font(.subheadline.weight(.semibold))
            Text("This is the shared key. Enter it on your other Macs to let them read the same synced history. Anyone with it can decrypt your synced clips, so keep it private — SafeClip never uploads it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if sync.hasSecret {
                if showPhrase, let phrase = sync.recoveryPhrase() {
                    Text(phrase)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    HStack {
                        Button("Copy") { appState.copyToClipboard(phrase) }
                        Button("Hide") { showPhrase = false }
                    }
                } else {
                    Button("Show Recovery Phrase") { showPhrase = true }
                }
            } else {
                Text("A key is created when you turn on sync.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Divider().padding(.vertical, 2)

            Text("Joining from another Mac").font(.caption.weight(.semibold))
            HStack(spacing: 8) {
                TextField("Paste the recovery phrase from your first Mac", text: $importText)
                    .textFieldStyle(.roundedBorder)
                Button("Use Key") {
                    importError = !sync.importPhrase(importText)
                    if !importError { importText = ""; showPhrase = false }
                }
                .disabled(importText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if importError {
                Text("That doesn't look like a valid recovery phrase.")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Good to know", systemImage: "info.circle").font(.caption.weight(.semibold))
            Text("Synced history is the union of your Macs: new clips and deletes propagate, and metadata (pins, categories) merges newest-wins. Images and files sync too, so the folder can grow — clear items you don't need. Devices must each sync within 30 days for deletes to stick.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose a folder that syncs between your Macs (e.g. inside iCloud Drive or Dropbox)."
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
