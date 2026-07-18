import AppKit
import KeyboardShortcuts
import SwiftUI

/// First-run setup wizard (PRD §7), styled per the owner's mockup: a dark glass
/// card with a large illustration up top, page dots, an icon + title, inline
/// controls, and a prominent Continue button (back chevron top-left).
///
/// Steps: welcome → plain-text paste (⌥Return) → shortcuts → privacy opt-ins →
/// permissions → Terms & Privacy. Closing or Skip records "not accepted"; all
/// consent is separate and unchecked by default (DPDP Act 2023 §6) — continued
/// use after skipping still counts as acceptance of the Terms (TERMS §9), but
/// the Privacy Policy and marketing checkboxes only ever reflect an explicit
/// tap, never a default.
struct OnboardingResult {
    let acceptedTerms: Bool
    let acceptedPrivacy: Bool
    let acceptedMarketing: Bool
}

struct OnboardingView: View {
    let appState: AppState
    let onFinish: (_ result: OnboardingResult) -> Void

    @State private var page = 0
    @State private var termsAccepted = false
    @State private var privacyAccepted = false
    @State private var marketingAccepted = false
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    // Live permission status, re-read whenever the window regains focus so the
    // rows flip to a green check the moment the user grants access in System
    // Settings (which happens in another process, out of SwiftUI's sight).
    @State private var accessibilityGranted = false
    @State private var screenRecordingGranted = false

    /// `initialConsent` pre-checks the Terms/Privacy boxes when onboarding is
    /// *replayed* for someone who already accepted (a version-bump re-show or the
    /// Settings → About replay), so they aren't forced to re-consent. First-run
    /// passes all-false, keeping DPDP §6's unchecked-by-default rule.
    init(
        appState: AppState,
        initialConsent: OnboardingResult = OnboardingResult(
            acceptedTerms: false, acceptedPrivacy: false, acceptedMarketing: false
        ),
        onFinish: @escaping (_ result: OnboardingResult) -> Void
    ) {
        self.appState = appState
        self.onFinish = onFinish
        _termsAccepted = State(initialValue: initialConsent.acceptedTerms)
        _privacyAccepted = State(initialValue: initialConsent.acceptedPrivacy)
        _marketingAccepted = State(initialValue: initialConsent.acceptedMarketing)
    }

    private static let stepCount = 6
    private var isLast: Bool { page == Self.stepCount - 1 }
    private var canFinish: Bool { termsAccepted && privacyAccepted }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                illustration
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                pageDots
                    .padding(.top, 22)
                    .padding(.bottom, 16)
                stepHeader
                    .padding(.horizontal, 32)
                stepControls
                    .padding(.horizontal, 32)
                    .padding(.top, 12)
                footer
                    .padding(24)
            }
        }
        // Fixed size — without it the hosting view sizes the window to the
        // content's unbounded ideal height and the card stretches absurdly tall.
        .frame(width: 620, height: 640)
        .preferredColorScheme(.dark)
        .onAppear(perform: refreshPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
        .sheet(isPresented: $showingTerms) {
            LegalDocumentSheet(resourceName: "TERMS", title: "Terms of Use")
        }
        .sheet(isPresented: $showingPrivacy) {
            LegalDocumentSheet(resourceName: "PRIVACY", title: "Privacy Policy")
        }
    }

    /// Re-reads the OS permission state. Called on appear and whenever the app
    /// becomes active again (e.g. returning from System Settings), so a grant
    /// made outside the app is reflected without a relaunch.
    private func refreshPermissions() {
        accessibilityGranted = CaretLocator.isSupported ? CaretLocator.isTrusted : true
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(white: 0.16), Color(white: 0.09)],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(.ultraThinMaterial.opacity(0.25))
        .ignoresSafeArea()
    }

    // MARK: - Top bar (back)

    private var topBar: some View {
        HStack {
            if page > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { page -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button("Skip") {
                onFinish(OnboardingResult(
                    acceptedTerms: false, acceptedPrivacy: false, acceptedMarketing: false
                ))
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    // MARK: - Page dots

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<Self.stepCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.3)))
                    .frame(width: i == page ? 22 : 7, height: 7)
            }
        }
    }

    // MARK: - Per-step header (icon + title)

    @ViewBuilder
    private var stepHeader: some View {
        let (symbol, title) = headerContent
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
    }

    private var headerContent: (String, String) {
        switch page {
        case 0: ("list.clipboard.fill", "A clipboard that's private by design")
        case 1: ("doc.on.clipboard.fill", "Plain text by default")
        case 2: ("keyboard.fill", "Open it from anywhere")
        case 3: ("hand.raised.fill", "Your privacy posture")
        case 4: ("lock.shield.fill", "Permissions")
        default: ("checkmark.seal.fill", "Terms & Privacy")
        }
    }

    // MARK: - Per-step controls

    @ViewBuilder
    private var stepControls: some View {
        switch page {
        case 0:
            caption("Encrypted on disk, nothing leaves your Mac, and honest about its limits. Press Continue to set it up.")
        case 1:
            caption("Return pastes plain text — formatting stripped so nothing pastes oddly. Hold ⌥ and press Return to keep the original formatting.")
            Toggle("Strip formatting on paste by default", isOn: appState.settingsBinding(\.stripFormattingByDefault))
                .toggleStyle(.switch)
                .padding(.top, 4)
        case 2:
            VStack(alignment: .leading, spacing: 10) {
                KeyboardShortcuts.Recorder("Open panel:", name: .togglePanel)
                KeyboardShortcuts.Recorder("Capture text from screen (OCR):", name: .captureOCR)
                KeyboardShortcuts.Recorder("Pick a color (eyedropper):", name: .pickColor)
            }
        case 3:
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Hide history while screen recording", isOn: appState.settingsBinding(\.screenRecordingPrivacy))
                Toggle("Capture passwords (masked in the panel)", isOn: appState.settingsBinding(\.captureConcealed))
                Toggle("Search text inside images (on-device OCR)", isOn: appState.settingsBinding(\.indexImageText))
            }
            .toggleStyle(.switch)
        case 4:
            permissionsControls
        default:
            termsControls
        }
    }

    private var permissionsControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption("Set these up now so every feature just works — no surprise system prompts later. Each is optional and used only for the feature named.")
            if CaretLocator.isSupported {
                permissionRow(
                    symbol: "text.cursor",
                    title: "Accessibility",
                    detail: "Opens the panel right at your text cursor and auto-expands snippet triggers. Reads the caret's position only — never your keystrokes or text.",
                    steps: "Privacy & Security → Accessibility → turn on SafeClip.",
                    granted: accessibilityGranted,
                    enable: { _ = CaretLocator.requestTrust() },
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
            }
            permissionRow(
                symbol: "rectangle.dashed.badge.record",
                title: "Screen Recording",
                detail: "Powers screen-text capture (⌥C) and the magnifier color picker (⌥P). Reads pixels only while you use them — nothing is recorded or stored.",
                steps: "Privacy & Security → Screen Recording → turn on SafeClip, then reopen it.",
                granted: screenRecordingGranted,
                enable: { CGRequestScreenCaptureAccess() },
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            )
            // macOS shows each system prompt only once; if it was already asked
            // (or dismissed), Enable silently does nothing — Open Settings is the
            // way back in. Kept for reference via Settings → About → Show Onboarding.
            Text("Tap **Enable** to let macOS ask. No prompt? It already asked once — tap **Open Settings** and flip SafeClip on.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionRow(
        symbol: String, title: String, detail: String, steps: String,
        granted: Bool, enable: @escaping () -> Void, settingsURL: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.callout.weight(.semibold))
                    if granted {
                        Label("On", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)
                    }
                    Spacer(minLength: 0)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !granted {
                    HStack(spacing: 8) {
                        Button("Enable", action: enable).controlSize(.small)
                        Button("Open Settings") {
                            if let url = URL(string: settingsURL) { NSWorkspace.shared.open(url) }
                        }
                        .controlSize(.small)
                    }
                    Text(steps)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // Both Terms and Privacy Policy consent are required, separate, and
    // unchecked by default (DPDP Act 2023 §6 — no bundled/pre-checked
    // consent). Marketing is optional and never gates Continue.
    private var termsControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption("SafeClip protects the on-disk history, but while you paste, text briefly sits on the system clipboard where other apps could read it — true of every clipboard manager. We disclose it rather than overpromise.")
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
                    Text("Optional — unsubscribe any time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
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

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer (Continue / Start)

    private var footer: some View {
        Button {
            if isLast {
                onFinish(OnboardingResult(
                    acceptedTerms: termsAccepted,
                    acceptedPrivacy: privacyAccepted,
                    acceptedMarketing: marketingAccepted
                ))
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { page += 1 }
            }
        } label: {
            Text(isLast ? "Start Using SafeClip" : "Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .keyboardShortcut(.defaultAction)
        .prominentGlassWhenAvailable()
        .controlSize(.large)
        .disabled(isLast && !canFinish)
    }

    // MARK: - Illustrations (schematic, on-brand)

    @ViewBuilder
    private var illustration: some View {
        Group {
            switch page {
            case 0: OnboardingVideo(resourceName: "onboarding-0-welcome") { panelMock }
            case 1: OnboardingVideo(resourceName: "onboarding-1-plaintext") { pasteMock }
            case 2: OnboardingVideo(resourceName: "onboarding-2-shortcuts") { shortcutMock }
            case 3: OnboardingVideo(resourceName: "onboarding-3-privacy") { privacyMock }
            case 4: OnboardingVideo(resourceName: "onboarding-4-permissions") { permissionsMock }
            default: termsMock
            }
        }
        .transition(.opacity)
    }

    private var illustrationCard: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.black.opacity(0.25))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            )
    }

    /// A realistic mini SafeClip panel so the first page reads as the actual app
    /// (search field, varied rows with a masked password + a highlighted
    /// selection, hint bar) rather than abstract bars. Owner can swap in real
    /// imagery later.
    private var panelMock: some View {
        illustrationCard.overlay {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("Search history…").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                Divider().opacity(0.25)
                VStack(spacing: 4) {
                    clipboardMockRow("doc.on.clipboard", .secondary, "Q3 planning notes", "2m", selected: false)
                    clipboardMockRow("link", .blue, "safeclip.app/download", "5m", selected: false)
                    clipboardMockRow("key.fill", .yellow, "••••••••••••", "8m", selected: true)
                    clipboardMockRow("photo", .secondary, "Screenshot 1280×800", "12m", selected: false)
                    clipboardMockRow("chevron.left.forwardslash.chevron.right", .purple, "func paste() { … }", "1h", selected: false)
                }
                .padding(8)
                Spacer(minLength: 0)
                Divider().opacity(0.25)
                HStack(spacing: 14) {
                    mockHint("↩", "paste"); mockHint("⌥↩", "rich")
                    mockHint("⌘P", "pin"); mockHint("⎋", "close")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
            }
        }
    }

    private func clipboardMockRow(
        _ icon: String, _ tint: Color, _ text: String, _ time: String, selected: Bool
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(tint)).frame(width: 16)
            Text(text)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            Spacer(minLength: 8)
            Text(time)
                .font(.caption2)
                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.white.opacity(0.05)),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
    }

    private func mockHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key).fontWeight(.bold)
            Text(label)
        }
    }

    private var pasteMock: some View {
        illustrationCard.overlay {
            HStack(spacing: 18) {
                keyCap("return", "Plain")
                keyCap("⌥ return", "Keep format")
            }
        }
    }

    private func keyCap(_ key: String, _ label: String) -> some View {
        VStack(spacing: 8) {
            Text(key)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.15)))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var shortcutMock: some View {
        illustrationCard.overlay {
            Image(systemName: "keyboard")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var privacyMock: some View {
        illustrationCard.overlay {
            Image(systemName: "lock.shield")
                .font(.system(size: 78))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
        }
    }

    private var permissionsMock: some View {
        illustrationCard.overlay {
            HStack(spacing: 26) {
                Image(systemName: "text.cursor").font(.system(size: 52))
                Image(systemName: "rectangle.dashed.badge.record").font(.system(size: 52))
            }
            .foregroundStyle(.tint)
            .symbolRenderingMode(.hierarchical)
        }
    }

    private var termsMock: some View {
        illustrationCard.overlay {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 78))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
        }
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
