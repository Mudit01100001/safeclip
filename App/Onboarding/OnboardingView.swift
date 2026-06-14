import AppKit
import KeyboardShortcuts
import SwiftUI

struct OnboardingResult {
    let acceptedTerms: Bool
    let acceptedPrivacy: Bool
    let acceptedMarketing: Bool
}

/// Three screens (PRD §7): terms + privacy consent → shortcut → privacy posture.
struct OnboardingView: View {
    let appState: AppState
    let onFinish: (_ result: OnboardingResult) -> Void

    @State private var page = 0
    @State private var termsAccepted = false
    @State private var privacyAccepted = false
    @State private var marketingAccepted = false
    @State private var showingTerms = false
    @State private var showingPrivacy = false

    private var canContinueFromPage0: Bool { termsAccepted && privacyAccepted }

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
        .sheet(isPresented: $showingTerms) {
            LegalDocumentSheet(resourceName: "TERMS", title: "Terms of Use")
        }
        .sheet(isPresented: $showingPrivacy) {
            LegalDocumentSheet(resourceName: "PRIVACY", title: "Privacy Policy")
        }
    }

    // MARK: - Page 1: Welcome + Consent

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(symbol: "list.clipboard", title: "Welcome to SafeClip",
                   subtitle: "A clipboard manager that is private by design.")

            bullet("lock.shield", "Encrypted history on disk",
                   "AES-256, key in your macOS Keychain. A stolen disk or backup reveals nothing.")
            bullet("network.slash", "Nothing ever leaves your Mac",
                   "No servers, no accounts, no telemetry. Source code is public and auditable.")
            bullet("hand.raised", "Honest about its limits",
                   "While you paste, text briefly sits on the system clipboard — true of every clipboard manager. We disclose it.")

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                consentRow(
                    checked: $termsAccepted,
                    label: "I have read and agree to the Terms of Use",
                    buttonLabel: "View Terms",
                    action: { showingTerms = true }
                )
                consentRow(
                    checked: $privacyAccepted,
                    label: "I have read and agree to the Privacy Policy",
                    buttonLabel: "View Policy",
                    action: { showingPrivacy = true }
                )
                Divider()
                Toggle(isOn: $marketingAccepted) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Send me release announcements and updates")
                            .font(.callout)
                        Text("Optional — via GitHub; unsubscribe any time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func consentRow(
        checked: Binding<Bool>,
        label: String,
        buttonLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: checked) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(label).font(.callout)
            Spacer()
            Button(buttonLabel, action: action)
                .font(.callout)
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
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
            Button("Skip") {
                onFinish(OnboardingResult(
                    acceptedTerms: false, acceptedPrivacy: false, acceptedMarketing: false
                ))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
            if page > 0 {
                Button("Back") { page -= 1 }
            }
            if page < 2 {
                Button("Continue") { page += 1 }
                    .keyboardShortcut(.defaultAction)
                    .prominentGlassWhenAvailable()
                    .disabled(page == 0 && !canContinueFromPage0)
            } else {
                Button("Start Using SafeClip") {
                    onFinish(OnboardingResult(
                        acceptedTerms: termsAccepted,
                        acceptedPrivacy: privacyAccepted,
                        acceptedMarketing: marketingAccepted
                    ))
                }
                .keyboardShortcut(.defaultAction)
                .prominentGlassWhenAvailable()
            }
        }
        .padding(16)
    }
}

extension View {
    /// Liquid Glass prominent buttons on macOS 26+, bordered-prominent below.
    @ViewBuilder
    func prominentGlassWhenAvailable() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
