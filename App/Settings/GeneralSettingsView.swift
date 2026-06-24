import AppKit
import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    let appState: AppState

    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Open panel:", name: .togglePanel)
                KeyboardShortcuts.Recorder("Capture text from screen (OCR):", name: .captureOCR)
                KeyboardShortcuts.Recorder("Pick a color (eyedropper):", name: .pickColor)
            } header: {
                Text("Shortcuts")
            } footer: {
                ExpandableText(text: "The panel opens at your cursor, like the emoji picker. Capture-text drags a region like ⌘⇧4, reads the text in it, and copies that text to your clipboard; the screenshot is never saved. Pick-a-color opens the system eyedropper and copies the hex of whatever pixel you click. SafeClip never simulates ⌘V; you press it yourself, so the app needs no Accessibility permission.")
            }

            Section {
                Picker("Modifier for all slots", selection: quickPasteModifierBinding) {
                    ForEach(QuickPasteModifier.allCases) { Text($0.label).tag($0) }
                }
                DisclosureGroup("Customize individual slots") {
                    ForEach(Array(KeyboardShortcuts.Name.quickPaste.enumerated()), id: \.offset) { index, name in
                        KeyboardShortcuts.Recorder("Item \(index + 1):", name: name)
                    }
                }
            } header: {
                Text("Quick-paste")
            } footer: {
                ExpandableText(text: "⌃⌘1–9 and ⌃⌘0 place the top 10 history items on the clipboard for your own ⌘V, without opening the panel. Pick one base modifier for all ten, or expand to rebind individual slots. Clear a shortcut to disable that slot.")
            }

            Section {
                Toggle("Open above the text cursor", isOn: caretAnchoringBinding)
                    .disabled(!CaretLocator.isSupported)
                Toggle(
                    "Also find the cursor in Chromium/Electron apps (Claude, Arc, …)",
                    isOn: appState.settingsBinding(\.assistChromiumApps)
                )
                .disabled(!CaretLocator.isSupported || !appState.settings.caretAnchoring)
                if CaretLocator.isSupported, appState.settings.caretAnchoring, !CaretLocator.isTrusted {
                    Label(
                        "Waiting for Accessibility access. Grant it to this build in System Settings, then reopen the panel. (Rebuilding the app can reset the grant.)",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Button("Open Accessibility Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                if CaretLocator.isSupported, appState.settings.caretAnchoring {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Open at the pointer when the caret is more than \(Int(appState.settings.caretProximityPoints)) pt away")
                            .font(.caption)
                        Slider(
                            value: appState.settingsBinding(\.caretProximityPoints),
                            in: 150...3000, step: 50
                        )
                        Text("Lower = open at the pointer more often · higher = stick to the caret")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        CaretProximityPreview(thresholdPoints: appState.settings.caretProximityPoints)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Panel position")
            } footer: {
                ExpandableText(text: caretFooter)
            }

            Section {
                Toggle("Capture images", isOn: appState.settingsBinding(\.captureImages))
                Toggle("Search text inside images (OCR)", isOn: appState.settingsBinding(\.indexImageText))
                    .disabled(!appState.settings.captureImages)
                    .padding(.leading, 16)
                Toggle("Capture file copies", isOn: appState.settingsBinding(\.captureFiles))
            } header: {
                Text("What gets captured")
            } footer: {
                ExpandableText(text: "Images are stored encrypted (PNG, up to 10 MB; larger copies are skipped). When enabled, the text inside each copied image is recognized on-device with Apple Vision, so nothing leaves your Mac, and stored encrypted so you can search images by their contents. File copies store the file locations, not the file contents; pasting re-references the original files.")
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

    private var caretFooter: String {
        guard CaretLocator.isSupported else {
            return "Anchoring to the text cursor isn't available in the App Store build."
        }
        return "By default the panel opens just above your mouse pointer. Turn the first option on to have it open above the blinking text cursor instead, with a pointer aimed at it. SafeClip reads only the cursor's on-screen location (never your keystrokes or the text in the field) using macOS Accessibility access (grant once; revoke any time in System Settings → Privacy & Security → Accessibility). The second option covers apps built on Chromium/Electron (Claude, Arc, …), which hide their cursor position until asked: SafeClip switches on that app's accessibility info so the cursor can be located. That's the one thing SafeClip writes via Accessibility, and it only enables reading the cursor; it still never types, pastes, or reads your text. Turn it off to keep strictly to native apps."
    }

    /// Changing the base modifier re-binds all ten quick-paste slots at once.
    private var quickPasteModifierBinding: Binding<QuickPasteModifier> {
        Binding(
            get: { appState.settings.quickPasteModifier },
            set: { newValue in
                appState.updateSettings { $0.quickPasteModifier = newValue }
                KeyboardShortcuts.Name.applyQuickPasteModifier(newValue.flags)
            }
        )
    }

    /// Setting this ON shows an in-app explanation *before* the macOS
    /// Accessibility prompt (R1); cancelling leaves it off.
    private var caretAnchoringBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.caretAnchoring },
            set: { wantsOn in
                if wantsOn {
                    guard confirmCaretConsent() else { return }
                    appState.updateSettings { $0.caretAnchoring = true }
                    CaretLocator.requestTrust()
                } else {
                    appState.updateSettings { $0.caretAnchoring = false }
                }
            }
        )
    }

    private func confirmCaretConsent() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Let SafeClip anchor the panel to your text cursor?"
        alert.informativeText = """
            To open the panel right above where you're typing, SafeClip needs \
            macOS Accessibility access. It uses that access for one thing only: \
            to read the on-screen location of the blinking text cursor.

            SafeClip never reads your keystrokes, never reads the text in the \
            field, and never types or pastes for you. You always press ⌘V \
            yourself. (For Chromium/Electron apps like Claude it asks the app \
            to turn on its accessibility info so the cursor can be located, \
            which only enables reading the cursor's position.) Turn this off \
            here, or revoke access in System Settings → Privacy & Security → \
            Accessibility, at any time.
            """
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
