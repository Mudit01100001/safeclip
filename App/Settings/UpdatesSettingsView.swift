import AppKit
import SwiftUI

struct UpdatesSettingsView: View {
    @ObservedObject var updateService: UpdateService

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    private var lastChecked: String {
        guard let date = updateService.lastUpdateCheckDate else { return "Never checked" }
        let formatter = RelativeDateTimeFormatter()
        return "Last checked \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(version)
                        Text(lastChecked)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Check for Updates…") { updateService.checkForUpdates() }
                        .disabled(!UpdateService.isSupported || !updateService.canCheckForUpdates)
                }
            }

            Section {
                Toggle("Automatically check for updates", isOn: autoCheckBinding)
                    .disabled(!UpdateService.isSupported)
            } footer: {
                ExpandableText(text: footerText)
            }
        }
        .formStyle(.grouped)
    }

    private var footerText: String {
        guard UpdateService.isSupported else {
            return "Updates for the App Store build are handled by the App Store, not SafeClip."
        }
        return "This is the only network call SafeClip ever makes: a request to safeclip.app asking whether a newer version exists, nothing about your clipboard content or usage. It's off until you turn it on here or click \"Check for Updates…\" yourself; when on, SafeClip checks about once a day and shows you the release notes before installing anything, it never updates silently. Each release is signed with a private key only Mudit holds, and SafeClip verifies that signature before installing, so a compromised download or a tampered update feed can't get in."
    }

    /// Turning this on means SafeClip starts making an unprompted network call
    /// on its own schedule, so it gets the same explicit-consent treatment as
    /// the caret-anchoring Accessibility opt-in (GeneralSettingsView).
    private var autoCheckBinding: Binding<Bool> {
        Binding(
            get: { updateService.automaticallyChecksForUpdates },
            set: { wantsOn in
                if wantsOn {
                    guard confirmAutoCheckConsent() else { return }
                }
                updateService.automaticallyChecksForUpdates = wantsOn
            }
        )
    }

    private func confirmAutoCheckConsent() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Let SafeClip check for updates automatically?"
        alert.informativeText = """
            SafeClip will contact safeclip.app roughly once a day to see if a \
            newer version is available. This is the only network request \
            SafeClip makes; it sends nothing about your clipboard content, \
            usage, or device, and no clipboard data ever leaves your Mac.

            You'll still see the release notes and choose to install, updates \
            never happen silently. Turn this off here at any time, or just use \
            "Check for Updates…" to check by hand instead.
            """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
