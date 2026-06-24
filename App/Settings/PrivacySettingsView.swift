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
                ExpandableText(text: "Detects the macOS capture UI automatically and blurs the history. App-based sharing (Zoom, Meet) can't be detected without extra permissions, so use Privacy Mode in the menu bar before a call. Separately, the floating panel and menu-bar pop-ups are always excluded from screenshots and screen recordings at the window level, so clipboard contents can't be captured.")
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
                ExpandableText(text: "Password managers mark copies as concealed (org.nspasteboard.ConcealedType). SafeClip stores them encrypted like everything else, masks their preview, and can wipe the system clipboard afterwards, the same safety net password managers use.")
            }

            Section {
                if appState.settings.ignoreConcealedFrom.isEmpty {
                    Text("None. Copies marked concealed are masked as passwords.")
                        .foregroundStyle(.secondary)
                }
                ForEach(appState.settings.ignoreConcealedFrom, id: \.self) { bundleID in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(Self.displayName(for: bundleID))
                            Text(bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            appState.resumeConcealing(source: bundleID)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button("Add App…") { addUnconcealApp() }
            } header: {
                Text("Apps not treated as passwords")
            } footer: {
                ExpandableText(text: "Some apps tag normal copies as concealed: dictation tools like Wispr Flow paste into the focused app (so it's recorded as the source), and chat apps mark copies too. Listed apps' copies are shown normally instead of masked. You can also right-click any masked item → \u{201C}Always Show Copies from …\u{201D}")
            }

            Section {
                if appState.settings.exclusionList.isEmpty {
                    Text("No apps excluded. Everything is captured (and encrypted).")
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
                ExpandableText(text: "Copies made in excluded apps are never stored at all. Off by default so password copies are captured. Exclude your password manager here if you'd rather they never land in history.")
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

    private func addUnconcealApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.message = "Choose apps whose copies should never be masked as passwords"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let bundleIDs = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        for id in bundleIDs {
            appState.stopConcealing(source: id) // adds to the list + un-masks existing rows
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
