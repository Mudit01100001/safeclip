import AppKit
import KeyboardShortcuts
import SwiftUI

/// Three screens (PRD §7): terms consent → shortcut → privacy posture.
struct OnboardingView: View {
    let appState: AppState
    let onFinish: (_ acceptedTerms: Bool) -> Void

    @State private var page = 0
    @State private var termsUnderstood = false

    private static let termsURL = URL(string: "https://github.com/Mudit01100001/safeclip/blob/main/TERMS.md")!

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcomePage
                case 1: shortcutPage
                default: privacyPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)

            Divider()
            footer
        }
    }

    // MARK: - Page 1: Welcome + Terms

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "list.clipboard", title: "Welcome to SafeClip",
                   subtitle: "A clipboard manager that is private by design.")

            bullet("lock.shield", "History is encrypted on disk",
                   "AES-256, key in your macOS Keychain. A stolen disk or backup can't read it.")
            bullet("network.slash", "Nothing ever leaves your Mac",
                   "No servers, no accounts, no telemetry. The source code is public, so this is checkable.")
            bullet("hand.raised", "Honest about its limits",
                   "While you paste, the text briefly sits on the system clipboard where other apps could read it — true of every clipboard manager. SafeClip discloses it instead of overpromising.")

            Spacer()

            Toggle(isOn: $termsUnderstood) {
                HStack(spacing: 4) {
                    Text("I have read and understand the")
                    Link("Terms of Use", destination: Self.termsURL)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: - Page 2: Shortcut

    private var shortcutPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "keyboard", title: "One shortcut, at your cursor",
                   subtitle: "The panel opens where you're typing — not in the menu bar.")

            HStack {
                Spacer()
                KeyboardShortcuts.Recorder("Open panel:", name: .togglePanel)
                Spacer()
            }
            .padding(.vertical, 12)

            bullet("cursorarrow.rays", "Appears at the mouse cursor",
                   "Like the emoji picker. Type to search, arrows to choose.")
            bullet("return", "Return pastes plain text",
                   "⌥Return keeps the original formatting. SafeClip puts the item on the clipboard — you press ⌘V. That one extra keypress means SafeClip needs zero special permissions.")
            Spacer()
        }
    }

    // MARK: - Page 3: Privacy posture

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(symbol: "hand.raised.fill", title: "Your privacy posture",
                   subtitle: "Sensible defaults — everything here can change later in Settings.")

            Toggle(
                "Hide history while screen recording",
                isOn: appState.settingsBinding(\.screenRecordingPrivacy)
            )
            Toggle(
                "Capture passwords (masked in the panel)",
                isOn: appState.settingsBinding(\.captureConcealed)
            )

            bullet("eye.slash", "Privacy Mode in the menu bar",
                   "One click hides history instantly — for screen shares SafeClip can't detect.")
            bullet("flame", "Burn after paste",
                   "Right-click any item to delete it from history the moment you paste it once.")
            bullet("app.badge.checkmark", "App exclusions are off by default",
                   "Want your password manager's copies never stored at all? Add it under Settings → Privacy.")
            Spacer()
        }
    }

    // MARK: - Chrome

    private func header(symbol: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.title).foregroundStyle(.tint)
                Text(title).font(.title2.bold())
            }
            Text(subtitle).foregroundStyle(.secondary)
        }
    }

    private func bullet(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .frame(width: 22)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip") { onFinish(false) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            Spacer()
            if page > 0 {
                Button("Back") { page -= 1 }
            }
            if page < 2 {
                Button("Continue") { page += 1 }
                    .keyboardShortcut(.defaultAction)
                    .disabled(page == 0 && !termsUnderstood)
            } else {
                Button("Start Using SafeClip") { onFinish(termsUnderstood) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
