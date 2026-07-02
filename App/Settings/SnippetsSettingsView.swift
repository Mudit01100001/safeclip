import SafeClipCore
import SwiftUI

/// Settings → Snippets: manage saved snippets (add, edit, reorder, delete).
/// Snippets surface in the floating panel behind the "Snippets" chip; pasting
/// one places its body for the user's own ⌘V (Tier-A — no synthesized typing).
struct SnippetsSettingsView: View {
    let appState: AppState
    @State private var editing: SnippetEditorTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if appState.snippets.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            expandSection
        }
        .sheet(item: $editing) { target in
            SnippetEditorView(initial: target.snippet) { label, body, trigger in
                if let snippet = target.snippet {
                    appState.updateSnippet(snippet, label: label, body: body, trigger: trigger)
                } else {
                    appState.addSnippet(label: label, body: body, trigger: trigger)
                }
            }
        }
    }

    /// Opt-in, Accessibility-gated auto-expand (#11). Off by default; enabling it
    /// prompts for Accessibility because it monitors and synthesizes keystrokes.
    private var expandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Expand snippets as you type", isOn: expandBinding)
                .toggleStyle(.switch)
                .disabled(!CaretLocator.isSupported)
            Text("Type a snippet's trigger (e.g. \u{201C};sig\u{201D}) in any app and SafeClip replaces it with the snippet. This one feature monitors and types keystrokes, so it needs Accessibility — it's the only part of SafeClip that does.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !CaretLocator.isSupported {
                Text("Not available in the App Store build.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else if appState.settings.expandSnippets, !CaretLocator.isTrusted {
                HStack(spacing: 8) {
                    Label("Waiting for Accessibility access. Grant it, then toggle this off and on.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
    }

    private var expandBinding: Binding<Bool> {
        Binding(
            get: { appState.settings.expandSnippets },
            set: { on in
                appState.updateSettings { $0.expandSnippets = on }
                if on, !CaretLocator.isTrusted { _ = CaretLocator.requestTrust() }
            }
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved Snippets").font(.headline)
                Text("Reusable text you can paste from the panel's Snippets tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editing = SnippetEditorTarget(snippet: nil)
            } label: {
                Label("Add Snippet", systemImage: "plus")
            }
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bookmark")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No snippets yet").font(.headline).foregroundStyle(.secondary)
            Text("Add an email signature, address, or any boilerplate you paste often.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var list: some View {
        List {
            ForEach(appState.snippets) { snippet in
                row(for: snippet)
            }
            .onMove(perform: move)
            .onDelete(perform: delete)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay(alignment: .bottom) { reorderHint }
    }

    private func row(for snippet: Snippet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(snippet.label.isEmpty ? snippet.bodyPreview : snippet.label)
                    .fontWeight(.medium)
                    .lineLimit(1)
                if !snippet.label.isEmpty, !snippet.bodyPreview.isEmpty {
                    Text(snippet.bodyPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let trigger = snippet.trigger, !trigger.isEmpty {
                Text(trigger)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .help("Auto-expand trigger")
            }
            Button("Edit") { editing = SnippetEditorTarget(snippet: snippet) }
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { editing = SnippetEditorTarget(snippet: snippet) }
        .contextMenu {
            Button("Edit") { editing = SnippetEditorTarget(snippet: snippet) }
            Button("Delete", role: .destructive) { appState.deleteSnippet(snippet) }
        }
    }

    private var reorderHint: some View {
        Text("Drag to reorder · swipe or right-click to delete")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = appState.snippets.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        appState.reorderSnippets(ids)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets where appState.snippets.indices.contains(index) {
            appState.deleteSnippet(appState.snippets[index])
        }
    }
}

/// Identifies what the editor sheet is editing — `snippet == nil` means a new one.
private struct SnippetEditorTarget: Identifiable {
    let id = UUID()
    let snippet: Snippet?
}

/// Add/edit sheet: label, body, and an optional auto-expand trigger.
private struct SnippetEditorView: View {
    let initial: Snippet?
    let onSave: (_ label: String, _ body: String, _ trigger: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var text: String
    @State private var trigger: String

    init(initial: Snippet?, onSave: @escaping (String, String, String) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _label = State(initialValue: initial?.label ?? "")
        _text = State(initialValue: initial?.body ?? "")
        _trigger = State(initialValue: initial?.trigger ?? "")
    }

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !text.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(initial == nil ? "New Snippet" : "Edit Snippet")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Label").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. Work email", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Content").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Trigger (optional)").font(.caption).foregroundStyle(.secondary)
                TextField("e.g. ;sig", text: $trigger)
                    .textFieldStyle(.roundedBorder)
                Text("If auto-expand is on, typing this in any app replaces it with the snippet. Use a distinctive prefix like \u{201C};\u{201D} or \u{201C}//\u{201D}.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(label, text, trigger)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
