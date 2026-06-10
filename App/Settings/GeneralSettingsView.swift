import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    let appState: AppState

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open panel:", name: .togglePanel)
            } footer: {
                Text("The panel opens at your cursor, like the emoji picker. SafeClip never simulates ⌘V — you press it yourself, so the app needs no Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Capture images", isOn: appState.settingsBinding(\.captureImages))
                Toggle("Capture file copies", isOn: appState.settingsBinding(\.captureFiles))
            } header: {
                Text("What gets captured")
            } footer: {
                Text("Images are stored encrypted (PNG, up to 10 MB — larger copies are skipped). File copies store the file locations, not the file contents; pasting re-references the original files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Picker("Keep at most", selection: appState.settingsBinding(\.historyLimit)) {
                    Text("50 items").tag(50)
                    Text("100 items").tag(100)
                    Text("200 items").tag(200)
                    Text("500 items").tag(500)
                    Text("Unlimited").tag(0)
                }
                Picker("Auto-delete items after", selection: appState.settingsBinding(\.expiryDays)) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Never").tag(0)
                }
            }

            Section {
                Toggle(
                    "Paste as plain text by default",
                    isOn: appState.settingsBinding(\.stripFormattingByDefault)
                )
            } footer: {
                Text("⌥Return flips the default for a single paste. Rich formatting is always captured either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: appState.settingsBinding(\.launchAtLogin))
            }
        }
        .formStyle(.grouped)
    }
}
