import AppKit
import SafeClipCore

/// Selection, filtering, and intent routing for the floating panel.
/// Key events arrive via the controller's local event monitor; SwiftUI only
/// renders state and forwards clicks.
@MainActor
@Observable
final class PanelViewModel {
    private let appState: AppState
    var searchText = ""
    /// When set, only items in this category are shown (nil = all).
    var selectedCategory: String?
    private(set) var filtered: [ClipItem] = []
    private(set) var selectedIndex = 0
    /// Bumped each time the panel shows so the view refocuses the search field.
    private(set) var focusEpoch = 0

    /// Set by the controller: hides the panel, runs the ClickFix confirmation
    /// if needed, then performs the paste.
    var onRequestPaste: ((ClipItem, Bool) -> Void)?
    /// Set by the controller: multipaste — places the combined items for one ⌘V.
    var onRequestPasteCombined: (([ClipItem]) -> Void)?

    /// Ordered ids the user ⌘-clicked for a combined paste (multipaste).
    private(set) var multiSelection: [UUID] = []

    init(appState: AppState) {
        self.appState = appState
    }

    var historyHidden: Bool { appState.historyHidden }
    var maskConcealed: Bool { appState.settings.maskConcealedPreviews }
    var stripByDefault: Bool { appState.settings.stripFormattingByDefault }

    var selectedItem: ClipItem? {
        filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil
    }

    /// Distinct category names present in history, sorted for the filter bar.
    var categories: [String] {
        var seen = Set<String>()
        for clip in appState.clips {
            if let category = clip.category, !category.isEmpty { seen.insert(category) }
        }
        return seen.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var hasMultiSelection: Bool { !multiSelection.isEmpty }

    /// 1-based position of an item within the multipaste selection, if selected.
    func multiOrder(of item: ClipItem) -> Int? {
        multiSelection.firstIndex(of: item.id).map { $0 + 1 }
    }

    func toggleMultiSelect(_ item: ClipItem) {
        if let index = multiSelection.firstIndex(of: item.id) {
            multiSelection.remove(at: index)
        } else {
            multiSelection.append(item.id)
        }
    }

    func clearMultiSelection() {
        multiSelection.removeAll()
    }

    /// Pastes the multi-selection combined, in click order. Falls back to the
    /// single selected item when nothing is multi-selected.
    func pasteMultiSelection() {
        guard hasMultiSelection else {
            pasteSelected(optionHeld: false)
            return
        }
        let byID = Dictionary(appState.clips.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items = multiSelection.compactMap { byID[$0] }
        clearMultiSelection()
        guard !items.isEmpty else { return }
        onRequestPasteCombined?(items)
    }

    func prepareForShow() {
        appState.reloadHistory()
        searchText = ""
        clearMultiSelection()
        // Keep the chosen category only if it still exists.
        if let selectedCategory, !categories.contains(selectedCategory) {
            self.selectedCategory = nil
        }
        selectedIndex = 0
        recomputeFilter()
        focusEpoch += 1
    }

    func recomputeFilter() {
        var result = appState.clips
        if let selectedCategory {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter { clip in
                clip.plainText.localizedCaseInsensitiveContains(searchText)
                    || (clip.ocrText?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        filtered = result
        selectedIndex = filtered.isEmpty ? 0 : min(selectedIndex, filtered.count - 1)
    }

    func selectCategory(_ category: String?) {
        selectedCategory = category
        selectedIndex = 0
        recomputeFilter()
    }

    func setCategory(_ item: ClipItem, _ category: String?) {
        appState.setCategory(item, category)
        recomputeFilter()
    }

    func select(_ index: Int) {
        guard filtered.indices.contains(index) else { return }
        selectedIndex = index
    }

    func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + filtered.count) % filtered.count
    }

    func pasteSelected(optionHeld: Bool) {
        guard let item = selectedItem else { return }
        onRequestPaste?(item, optionHeld)
    }

    func paste(_ item: ClipItem, optionHeld: Bool) {
        onRequestPaste?(item, optionHeld)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        delete(item)
    }

    func delete(_ item: ClipItem) {
        appState.deleteItem(item)
        recomputeFilter()
    }

    func togglePinSelected() {
        guard let item = selectedItem else { return }
        togglePin(item)
    }

    func togglePin(_ item: ClipItem) {
        appState.togglePin(item)
        recomputeFilter()
    }

    func toggleBurn(_ item: ClipItem) {
        appState.toggleBurn(item)
        recomputeFilter()
    }

    func copyAgain(_ item: ClipItem) {
        appState.copyAgain(item)
        recomputeFilter()
    }

    func stopConcealing(source: String) {
        appState.stopConcealing(source: source)
        recomputeFilter()
    }
}
