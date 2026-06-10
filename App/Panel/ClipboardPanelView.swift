import SafeClipCore
import SwiftUI

/// SwiftUI content of the floating panel (docs/DESIGN.md §4):
/// search field → list → ClickFix warning (when relevant) → hint bar.
struct ClipboardPanelView: View {
    @Bindable var model: PanelViewModel
    /// True when an NSGlassEffectView provides the chrome (macOS 26+) —
    /// the view then draws no background of its own.
    var glassChrome = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
            if let selected = model.selectedItem, selected.flagReason == .clickfix {
                clickFixWarning
            }
            Divider()
            HintBarView(stripByDefault: model.stripByDefault)
        }
        .frame(width: FloatingPanelController.panelSize.width,
               height: FloatingPanelController.panelSize.height)
        .background {
            if !glassChrome {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            }
        }
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

    @ViewBuilder
    private var content: some View {
        if model.historyHidden {
            PanelPlaceholderView(
                symbol: "eye.slash",
                title: "Hidden while screen recording",
                caption: "History reappears when recording or Privacy Mode ends."
            )
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

    private var listView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(
                            item: item,
                            isSelected: index == model.selectedIndex,
                            masked: item.isConcealed && model.maskConcealed
                        )
                        .id(item.id)
                        .onTapGesture {
                            model.select(index)
                            model.paste(item, optionHeld: false)
                        }
                        .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selectedIndex) {
                if let selected = model.selectedItem {
                    proxy.scrollTo(selected.id, anchor: nil)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
        Button(item.isBurn ? "Don't Burn After Paste" : "Burn After Paste") {
            model.toggleBurn(item)
        }
        Button("Copy Again") { model.copyAgain(item) }
        Divider()
        Button("Delete", role: .destructive) { model.delete(item) }
    }

    private var clickFixWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Looks like a shell command copied from a website — don't paste into Terminal.")
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

    var body: some View {
        HStack(spacing: 8) {
            leadingBadge
                .frame(width: 14)
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            Text(displayText)
                .font(.system(.body, design: masked ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Text(trailingDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .help(helpText)
    }

    private var thumbnail: NSImage? {
        guard item.kind == .image, !masked, let data = item.thumbnailData else { return nil }
        return NSImage(data: data)
    }

    private var displayText: String {
        if masked { return "••••••••••••" }
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
            Image(systemName: "doc.on.doc").font(.caption).foregroundStyle(.secondary)
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
        var lines: [String] = []
        if let reason = item.flagReason { lines.append(reason.displayName) }
        if item.isBurn {
            // The honest tooltip required by F7: burn is best-effort.
            lines.append(
                "Deleted from history after one paste. Content is briefly readable by other apps during the paste itself (see Terms §3)."
            )
        }
        if masked { lines.append("Preview hidden — press Return to paste.") }
        return lines.joined(separator: "\n")
    }

    private static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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

    var body: some View {
        HStack(spacing: 12) {
            hint("↩", stripByDefault ? "paste" : "paste rich")
            hint("⌥↩", stripByDefault ? "keep format" : "plain")
            hint("⌘⌫", "delete")
            hint("⌘P", "pin")
            hint("⎋", "close")
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
