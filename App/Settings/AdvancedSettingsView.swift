import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    let appState: AppState
    @State private var showingClearConfirm = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Detect sensitive patterns",
                    isOn: appState.settingsBinding(\.patternDetectionEnabled)
                )
                Group {
                    Toggle("API keys and tokens (ghp_, sk-, AKIA…)", isOn: appState.settingsBinding(\.detectAPIKeys))
                    Toggle("Credit card numbers (Luhn check)", isOn: appState.settingsBinding(\.detectCards))
                    Toggle("Private key blocks", isOn: appState.settingsBinding(\.detectPrivateKeys))
                    Toggle("Burn flagged items after one paste", isOn: appState.settingsBinding(\.autoBurnFlagged))
                }
                .disabled(!appState.settings.patternDetectionEnabled)
                .padding(.leading, 16)
            } header: {
                Text("Pattern detection")
            } footer: {
                Text("Off by default. Flagged items get a warning icon — they're still captured and encrypted. Heuristics can miss patterns or false-positive; don't rely on them as your only protection (Terms §3).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Warn on suspected pastejacking (ClickFix)",
                    isOn: appState.settingsBinding(\.clickFixDetection)
                )
            } footer: {
                Text("Warns when the clipboard was overwritten by a website with something that looks like a shell command — the #1 macOS malware-delivery trick. Warnings never block pasting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data") {
                Button("Export History…") { exportHistory() }
                Button("Clear All History…", role: .destructive) { showingClearConfirm = true }
                    .confirmationDialog(
                        "Clear all clipboard history?",
                        isPresented: $showingClearConfirm
                    ) {
                        Button("Clear All", role: .destructive) { appState.clearAll() }
                    } message: {
                        Text("All encrypted history rows are deleted. This cannot be undone.")
                    }
            }
        }
        .formStyle(.grouped)
    }

    private struct ExportEntry: Codable {
        let text: String
        let createdAt: Date
        let lastUsedAt: Date?
        let sourceBundle: String?
        let pinned: Bool
    }

    private func exportHistory() {
        let warning = NSAlert()
        warning.alertStyle = .warning
        warning.messageText = "Export decrypted history?"
        warning.informativeText =
            "The export file is plain JSON — unencrypted, readable by anything. It includes concealed items (passwords). Store it accordingly or delete it after use."
        warning.addButton(withTitle: "Cancel")
        warning.addButton(withTitle: "Export")
        NSApp.activate(ignoringOtherApps: true)
        guard warning.runModal() == .alertSecondButtonReturn else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SafeClip-export.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let entries = appState.clips.map {
            ExportEntry(
                text: $0.plainText,
                createdAt: $0.createdAt,
                lastUsedAt: $0.lastUsedAt,
                sourceBundle: $0.sourceBundle,
                pinned: $0.isPinned
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try (try encoder.encode(entries)).write(to: url, options: .completeFileProtection)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
