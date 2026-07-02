import AppKit
import SafeClipCore
import SwiftUI

/// SwiftUI content of the floating panel (docs/DESIGN.md §4):
/// search field → list → ClickFix warning (when relevant) → hint bar.
struct ClipboardPanelView: View {
    @Bindable var model: PanelViewModel
    /// Where the callout beak points (set per-show by the controller).
    var arrow: PanelArrowSpec
    @FocusState private var searchFocused: Bool
    /// Frame of the selected row (in the list's "panelScroll" space), so the
    /// native scroll view keeps the selection visible during keyboard nav.
    @State private var selectedRowFrame: CGRect = .zero

    var body: some View {
        let shape = CalloutShape(arrow: arrow)
        VStack(spacing: 0) {
            searchField
            Divider()
            if showChipBar {
                chipBar
                Divider()
            }
            content
            if !model.showingSnippets,
               let selected = model.selectedItem, selected.flagReason == .clickfix {
                clickFixWarning
            }
            if model.hasMultiSelection {
                multiSelectionBar
            }
            Divider()
            HintBarView(stripByDefault: model.stripByDefault, snippetsMode: model.showingSnippets)
        }
        // Reserve the beak strip on the arrow edge, then fill whatever size the
        // window currently is (the controller sizes it per show). The shaped
        // background fills the beak strip so body + beak read as one surface.
        .padding(arrow.edge == .bottom ? .bottom : .top, PanelArrowSpec.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.regularMaterial)
            }
        }
        // Behind the glass: a just-above-threshold alpha fill that makes the
        // callout a real mouse-event target. The window server derives a
        // non-opaque window's clickable region from rendered alpha, and the
        // Liquid Glass surface contributes almost none to the window's own
        // backing — without this, scroll and clicks over the panel hit-test
        // straight through to the window BEHIND it (SELFTEST 2 Jul 2026:
        // 17/20 scrolls + 20/20 clicks routed to the window underneath).
        // Shape-accurate, so the hit region and the window shadow both still
        // match the visible callout exactly. ~0.05 is the documented cutoff.
        .background { shape.fill(Color.black.opacity(0.06)) }
        .clipShape(shape)
        .onChange(of: model.focusEpoch, initial: true) {
            searchFocused = true
        }
        .onChange(of: model.searchText) {
            model.recomputeFilter()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search history…", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    /// The chip bar appears when there are saved snippets to switch to or any
    /// categories to filter by.
    private var showChipBar: Bool { model.hasSnippets || !model.categories.isEmpty }

    private var chipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if model.hasSnippets {
                    snippetChip
                }
                // "All" + categories represent clipboard history. "All" always
                // appears alongside snippets so there's a way back to history.
                categoryChip(
                    title: "All",
                    isSelected: !model.showingSnippets && model.selectedCategory == nil
                ) {
                    model.selectCategory(nil)
                }
                ForEach(model.categories, id: \.self) { category in
                    categoryChip(
                        title: category,
                        isSelected: !model.showingSnippets && model.selectedCategory == category
                    ) {
                        model.selectCategory(model.selectedCategory == category ? nil : category)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private var snippetChip: some View {
        Button {
            model.showSnippets(!model.showingSnippets)
        } label: {
            Label("Snippets", systemImage: "bookmark.fill")
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    model.showingSnippets
                        ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
                .foregroundStyle(
                    model.showingSnippets ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary)
                )
        }
        .buttonStyle(.plain)
    }

    private func categoryChip(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if model.historyHidden {
            // Snippets are equally sensitive on a screen share, so the same
            // privacy treatment covers whichever list is active.
            if activeListIsEmpty {
                PanelPlaceholderView(
                    symbol: "eye.slash",
                    title: "Hidden while screen recording",
                    caption: "History reappears when recording or Privacy Mode ends."
                )
            } else {
                // Blur, don't blank: keep the shape of the list so the panel
                // still reads as itself on a screen share, but no content is
                // legible. Interaction is off so nothing can be pasted blind.
                // The rows are ALSO masked at the source (privacyHidden on
                // each row view) — the blur is cosmetic, not the protection —
                // and the subtree is dropped from the accessibility tree so
                // an a11y client can't read what the eyes can't.
                activeList
                    .blur(radius: 10)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .overlay(alignment: .bottom) {
                        Label(
                            "Hidden while screen recording",
                            systemImage: "eye.slash"
                        )
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 12)
                    }
            }
        } else if model.showingSnippets {
            if model.filteredSnippets.isEmpty {
                PanelPlaceholderView(
                    symbol: "bookmark",
                    title: model.searchText.isEmpty ? "No saved snippets" : "No matching snippets",
                    caption: model.searchText.isEmpty
                        ? "Add snippets in Settings → Snippets."
                        : "Try a different search."
                )
            } else {
                snippetListView
            }
        } else if model.filtered.isEmpty {
            PanelPlaceholderView(
                symbol: "doc.on.clipboard",
                title: model.searchText.isEmpty ? "No clipboard history yet" : "No matches",
                caption: model.searchText.isEmpty
                    ? "Copy something and it'll appear here."
                    : "Try a different search."
            )
        } else {
            listView
        }
    }

    private var activeListIsEmpty: Bool {
        model.showingSnippets ? model.filteredSnippets.isEmpty : model.filtered.isEmpty
    }

    @ViewBuilder
    private var activeList: some View {
        if model.showingSnippets { snippetListView } else { listView }
    }

    private var snippetListView: some View {
        // Native NSScrollView (not SwiftUI's ScrollView) so the wheel/trackpad
        // scroll works inside the floating panel. Selection-frame reporting keeps
        // the keyboard-selected row visible.
        NativeScrollView(revealFrame: selectedRowFrame) {
            // VStack, NOT LazyVStack: inside the native scroll view's hosting
            // document, a LazyVStack only lays out visible rows, so it never
            // reports the full content height and there's nothing to scroll.
            VStack(spacing: 2) {
                ForEach(Array(model.filteredSnippets.enumerated()), id: \.element.id) { index, snippet in
                    SnippetRowView(
                        snippet: snippet,
                        isSelected: index == model.selectedSnippetIndex,
                        isJustCopied: model.justCopiedID == snippet.id,
                        privacyHidden: model.historyHidden
                    )
                        .id(snippet.id)
                        .reportsSelectedRowFrame(index == model.selectedSnippetIndex, into: $selectedRowFrame)
                        .onTapGesture {
                            model.selectSnippet(index)
                            model.clickPasteSnippet(snippet)
                        }
                }
            }
            .padding(6)
            .coordinateSpace(name: "panelScroll")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        NativeScrollView(revealFrame: selectedRowFrame) {
            // VStack, NOT LazyVStack — see snippetListView: a LazyVStack in the
            // native scroll view's document never reports full height, so the
            // list can't scroll. History is capped (~200), so VStack is fine.
            VStack(spacing: 2) {
                ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                    if index == model.imageSectionStart {
                        imageSectionHeader
                    }
                    ClipRowView(
                        item: item,
                        isSelected: index == model.selectedIndex,
                        masked: item.isConcealed && model.maskConcealed,
                        multiOrder: model.multiOrder(of: item),
                        isJustCopied: model.justCopiedID == item.id,
                        onCopyText: { model.copyImageText(item) },
                        privacyHidden: model.historyHidden
                    )
                    .id(item.id)
                    .reportsSelectedRowFrame(index == model.selectedIndex, into: $selectedRowFrame)
                    .onTapGesture {
                        // ⌘-click builds an ordered multipaste set; a plain
                        // click pastes that one item immediately.
                        if NSEvent.modifierFlags.contains(.command) {
                            model.toggleMultiSelect(item)
                        } else {
                            model.select(index)
                            model.clickPaste(item, optionHeld: false)
                        }
                    }
                    .contextMenu { contextMenu(for: item) }
                }
            }
            .padding(6)
            .coordinateSpace(name: "panelScroll")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
        Button(item.isBurn ? "Don't Burn After Paste" : "Burn After Paste") {
            model.toggleBurn(item)
        }
        Button("Copy Again") { model.copyAgain(item) }
        categoryMenu(for: item)
        if item.isConcealed, let source = item.sourceBundle {
            Button("Always Show Copies from \(Self.appName(for: source))") {
                model.stopConcealing(source: source)
            }
        }
        Divider()
        Button("Delete", role: .destructive) { model.delete(item) }
    }

    @ViewBuilder
    private func categoryMenu(for item: ClipItem) -> some View {
        Menu("Category") {
            Button {
                promptNewCategory(for: item)
            } label: {
                Label("New Category…", systemImage: "plus")
            }
            if !model.categories.isEmpty {
                Divider()
                ForEach(model.categories, id: \.self) { category in
                    Button {
                        model.setCategory(item, item.category == category ? nil : category)
                    } label: {
                        if item.category == category {
                            Label(category, systemImage: "checkmark")
                        } else {
                            Text(category)
                        }
                    }
                }
            }
            if item.category != nil {
                Divider()
                Button("Remove from Category") { model.setCategory(item, nil) }
            }
        }
    }

    /// Prompts for a new collection name. Showing the alert dismisses the panel
    /// (it resigns key); the captured `item` keeps the assignment correct.
    private func promptNewCategory(for item: ClipItem) {
        let alert = NSAlert()
        alert.messageText = "New Category"
        alert.informativeText = "Name a collection for this item."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "e.g. Work, Snippets"
        alert.accessoryView = field
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            model.setCategory(item, field.stringValue)
        }
    }

    /// Friendly name for a source bundle ID, falling back to the ID itself.
    static func appName(for bundleID: String) -> String {
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
            let name = Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
        else { return bundleID }
        return name
    }

    private var imageSectionHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo")
            Text("Appeared in images")
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var multiSelectionBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
            Text("\(model.multiSelection.count) selected")
                .fontWeight(.medium)
            Text("· ⌘-click to add · ↩ paste in order")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Clear") { model.clearMultiSelection() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.12))
    }

    private var clickFixWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Looks like a shell command copied from a website. Don't paste into Terminal.")
                .font(.caption)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12))
    }
}

struct ClipRowView: View {
    let item: ClipItem
    let isSelected: Bool
    let masked: Bool
    /// 1-based position in the multipaste selection, or nil when not selected.
    var multiOrder: Int? = nil
    /// True for a brief window right after a click-to-paste — flashes the row
    /// green so the user sees which item was copied before the panel closes.
    var isJustCopied: Bool = false
    /// Copies the text recognized inside an image clip (hover action).
    var onCopyText: (() -> Void)? = nil
    /// True while history is hidden (screen recording / Privacy Mode). Masks
    /// the row's text at the SOURCE with no hover reveal — the blur alone
    /// isn't enough, because the real string would still sit in the view/
    /// accessibility tree (and these rows render inside a native
    /// NSHostingView, which outer SwiftUI redaction doesn't reach).
    var privacyHidden: Bool = false
    /// Concealed rows mask their preview at rest but reveal while hovered, so
    /// the list stays unreadable at a glance yet any item can be checked on
    /// demand. (Many apps over-apply `org.nspasteboard.ConcealedType` — e.g.
    /// Claude, WhatsApp — so this isn't only real passwords.)
    @State private var hovering = false
    @State private var copiedText = false

    private var isMasked: Bool { privacyHidden || (masked && !hovering) }

    var body: some View {
        HStack(spacing: 8) {
            leadingBadge
                .frame(width: 14)
            if let swatch {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(
                        .sRGB,
                        red: swatch.red, green: swatch.green, blue: swatch.blue,
                        opacity: swatch.alpha
                    ))
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    )
            }
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Text(displayText)
                .font(.system(.body, design: isMasked ? .monospaced : .default))
                .lineLimit(1)
                // Keep the file format (extension) visible on long names.
                .truncationMode(item.kind == .fileList ? .middle : .tail)
            Spacer(minLength: 8)
            if isJustCopied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            if item.kind == .image, hovering || copiedText, let onCopyText {
                Button {
                    onCopyText()
                    withAnimation(.easeOut(duration: 0.15)) { copiedText = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                        withAnimation(.easeIn(duration: 0.2)) { copiedText = false }
                    }
                } label: {
                    Label(
                        copiedText ? "Copied!" : "Copy Text",
                        systemImage: copiedText ? "checkmark.circle.fill" : "text.viewfinder"
                    )
                    .font(.caption2)
                    .foregroundStyle(copiedText ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                }
                .buttonStyle(.borderless)
                .help("Copy the text recognized inside this image")
            }
            if let multiOrder {
                Text("\(multiOrder)")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.white)
                    .frame(width: 16, height: 16)
                    .background(Color.accentColor, in: Circle())
            }
            Text(trailingDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isJustCopied ? 2 : 0)
        )
        .scaleEffect(isJustCopied ? 0.97 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.5), value: isJustCopied)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(helpText)
    }

    private var rowBackground: AnyShapeStyle {
        if isJustCopied { return AnyShapeStyle(Color.accentColor.opacity(0.6)) }
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.22)) }
        if multiOrder != nil { return AnyShapeStyle(Color.accentColor.opacity(0.12)) }
        return AnyShapeStyle(.clear)
    }

    private var thumbnail: NSImage? {
        guard item.kind == .image, !isMasked, let data = item.thumbnailData else { return nil }
        return NSImage(data: data)
    }

    /// A swatch is shown when the whole clip is a single CSS color (designer
    /// workflow). Masked rows never resolve a swatch.
    private var swatch: ClipColor? {
        guard item.kind == .text, !isMasked else { return nil }
        return ClipColor.parse(item.plainText)
    }

    private var isSVG: Bool {
        item.kind == .text && !isMasked && isLikelySVGMarkup(item.plainText)
    }

    /// The system document/folder icon for the first path of a file copy.
    private var fileIcon: NSImage? {
        guard item.kind == .fileList,
              let path = item.plainText.split(separator: "\n").first else { return nil }
        return NSWorkspace.shared.icon(forFile: String(path))
    }

    private var displayText: String {
        if isMasked { return "••••••••••••" }
        switch item.kind {
        case .image:
            return item.plainText // "Image W×H" placeholder
        case .fileList:
            let paths = item.plainText.split(separator: "\n")
            let first = paths.first.map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? "Files"
            return paths.count > 1 ? "\(first) +\(paths.count - 1) more" : first
        case .text:
            let firstLine = item.plainText
                .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                .first.map(String.init) ?? item.plainText
            return firstLine.trimmingCharacters(in: .whitespaces)
        }
    }

    @ViewBuilder
    private var leadingBadge: some View {
        if item.isPinned {
            Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange)
        } else if let reason = item.flagReason {
            switch reason {
            case .clickfix:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.red)
            case .concealed:
                Image(systemName: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            case .apiKey, .card, .privateKey:
                Image(systemName: "key.fill")
                    .font(.caption).foregroundStyle(.yellow)
            }
        } else if item.isBurn {
            Image(systemName: "flame.fill").font(.caption).foregroundStyle(.red)
        } else if item.kind == .image {
            Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
        } else if item.kind == .fileList {
            // Real document/folder icon (Excel, PPT, PDF, folder, …).
            if let fileIcon {
                Image(nsImage: fileIcon).resizable().frame(width: 14, height: 14)
            } else {
                Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(.secondary)
            }
        } else if isSVG {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.caption).foregroundStyle(.purple)
        }
    }

    private var trailingDetail: String {
        var parts: [String] = []
        if item.isBurn { parts.append("burns") }
        switch item.kind {
        case .image:
            parts.append(ByteCountFormatter.string(
                fromByteCount: Int64(item.charCount), countStyle: .file
            ))
        case .fileList:
            parts.append(item.charCount == 1 ? "1 file" : "\(item.charCount) files")
        case .text:
            if item.charCount > 80 {
                parts.append("\(item.charCount.formatted()) chars")
            }
        }
        parts.append(Self.relativeTime(item.lastUsedAt ?? item.createdAt))
        return parts.joined(separator: " · ")
    }

    private var helpText: String {
        // No tooltips while history is hidden — a tooltip renders in its own
        // window, outside the blurred (and capture-excluded) panel.
        if privacyHidden { return "" }
        var lines: [String] = []
        if let reason = item.flagReason { lines.append(reason.displayName) }
        if item.isBurn {
            // The honest tooltip required by F7: burn is best-effort.
            lines.append(
                "Deleted from history after one paste. Content is briefly readable by other apps during the paste itself (see Terms §3)."
            )
        }
        if masked { lines.append("Preview hidden. Hover to reveal, or press Return to paste.") }
        return lines.joined(separator: "\n")
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

/// One saved-snippet row in the panel: bookmark glyph, label, and a one-line
/// body preview. Clicking places the body on the clipboard for the user's ⌘V.
struct SnippetRowView: View {
    let snippet: Snippet
    let isSelected: Bool
    var isJustCopied: Bool = false
    /// Masks label/body at the source while history is hidden (screen
    /// recording / Privacy Mode) — same reasoning as ClipRowView.privacyHidden.
    var privacyHidden: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bookmark.fill")
                .font(.caption)
                .foregroundStyle(.tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(privacyHidden
                    ? "••••••••••••"
                    : (snippet.label.isEmpty ? snippet.bodyPreview : snippet.label))
                    .font(.body)
                    .lineLimit(1)
                if !privacyHidden, !snippet.label.isEmpty, !snippet.bodyPreview.isEmpty {
                    Text(snippet.bodyPreview)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isJustCopied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(snippetRowBackground, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isJustCopied ? 2 : 0)
        )
        .scaleEffect(isJustCopied ? 0.97 : 1)
        .animation(.spring(response: 0.18, dampingFraction: 0.5), value: isJustCopied)
        .contentShape(Rectangle())
        .help(privacyHidden ? "" : (snippet.label.isEmpty ? snippet.bodyPreview : snippet.label))
    }

    private var snippetRowBackground: AnyShapeStyle {
        if isJustCopied { return AnyShapeStyle(Color.accentColor.opacity(0.6)) }
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.22)) }
        return AnyShapeStyle(.clear)
    }
}

struct PanelPlaceholderView: View {
    let symbol: String
    let title: String
    let caption: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct HintBarView: View {
    let stripByDefault: Bool
    /// Snippet rows paste a single body and aren't pinned/deleted from the panel,
    /// so the hint set is trimmed to what actually applies.
    var snippetsMode: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if snippetsMode {
                hint("↩", "paste")
                hint("⎋", "close")
            } else {
                hint("↩", stripByDefault ? "paste" : "paste rich")
                hint("⌥↩", stripByDefault ? "keep format" : "plain")
                hint("⌘⌫", "delete")
                hint("⌘P", "pin")
                hint("⎋", "close")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key).font(.caption.bold())
            Text(label).font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}
