import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PrivacySettingsView: View {
    let appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Hide history while screen recording",
                    isOn: appState.settingsBinding(\.screenRecordingPrivacy)
                )
            } footer: {
                Text("Detects the macOS capture UI automatically. App-based sharing (Zoom, Meet) can't be detected without extra permissions — use Privacy Mode in the menu bar before a call.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(
                    "Capture passwords (concealed copies)",
                    isOn: appState.settingsBinding(\.captureConcealed)
                )
                Toggle("Mask password previews in the panel", isOn: appState.settingsBinding(\.maskConcealedPreviews))
                    .disabled(!appState.settings.captureConcealed)
                Toggle("Burn passwords after one paste", isOn: appState.settingsBinding(\.autoBurnConcealed))
                    .disabled(!appState.settings.captureConcealed)
                Picker(
                    "Clear system clipboard after pasting sensitive items",
                    selection: appState.settingsBinding(\.clearClipboardAfterSensitivePaste)
                ) {
                    Text("Never").tag(0)
                    Text("After 10 seconds").tag(10)
                    Text("After 35 seconds").tag(35)
                    Text("After 60 seconds").tag(60)
                }
            } header: {
                Text("Passwords")
            } footer: {
                Text("Password managers mark copies as concealed (org.nspasteboard.ConcealedType). SafeClip stores them encrypted like everything else, masks their preview, and can wipe the system clipboard afterwards — the same safety net password managers use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if appState.settings.exclusionList.isEmpty {
                    Text("No apps excluded — everything is captured (and encrypted).")
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.settings.exclusionList, id: \.self) { bundleID in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Self.displayName(for: bundleID))
                            Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            appState.updateSettings { $0.exclusionList.removeAll { $0 == bundleID } }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add App…") { addApp() }
            } header: {
                Text("Excluded apps")
            } footer: {
                Text("Copies made in excluded apps are never stored at all. Off by default so password copies are captured — exclude your password manager here if you'd rather they never land in history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.message = "Choose apps whose copies SafeClip should never store"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let bundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        guard !bundleIDs.isEmpty else { return }
        appState.updateSettings { settings in
            for id in bundleIDs where !settings.exclusionList.contains(id) {
                settings.exclusionList.append(id)
            }
        }
    }

    private static func displayName(for bundleID: String) -> String {
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let name = Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
        else { return bundleID }
        return name
    }
}
