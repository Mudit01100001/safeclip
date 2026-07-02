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
    /// When true the panel shows saved snippets instead of clipboard history.
    private(set) var showingSnippets = false
    /// All loaded snippets (whether the chip appears); `filteredSnippets` is the
    /// search-applied display list navigation/paste route to in snippet mode.
    private(set) var snippets: [Snippet] = []
    private(set) var filteredSnippets: [Snippet] = []
    private(set) var selectedSnippetIndex = 0
    private(set) var filtered: [ClipItem] = []
    /// Index in `filtered` where image-only (matched via OCR) results begin —
    /// the view draws an "Appeared in images" header there. nil when none.
    private(set) var imageSectionStart: Int?
    private(set) var selectedIndex = 0
    /// Bumped each time the panel shows so the view refocuses the search field.
    private(set) var focusEpoch = 0
    /// Id of the row (clip or snippet) flashing a "copied" highlight after a
    /// click-to-paste. The panel hides almost immediately on paste, so without
    /// this brief flash the user never sees which row their click landed on.
    private(set) var justCopiedID: UUID?

    /// Set by the controller: hides the panel, runs the ClickFix confirmation
    /// if needed, then performs the paste.
    var onRequestPaste: ((ClipItem, Bool) -> Void)?
    /// Set by the controller: multipaste — places the combined items for one ⌘V.
    var onRequestPasteCombined: (([ClipItem]) -> Void)?
    /// Set by the controller: places a saved snippet's body for the user's ⌘V.
    var onRequestPasteSnippet: ((Snippet) -> Void)?

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

    var hasSnippets: Bool { !snippets.isEmpty }

    var selectedSnippet: Snippet? {
        filteredSnippets.indices.contains(selectedSnippetIndex)
            ? filteredSnippets[selectedSnippetIndex] : nil
    }

    /// Switches the panel between clipboard history and saved snippets.
    func showSnippets(_ on: Bool) {
        showingSnippets = on
        selectedSnippetIndex = 0
        if on { clearMultiSelection() }
        recomputeFilter()
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
        appState.reloadSnippets()
        snippets = appState.snippets
        searchText = ""
        clearMultiSelection()
        // Keep the chosen category only if it still exists.
        if let selectedCategory, !categories.contains(selectedCategory) {
            self.selectedCategory = nil
        }
        // Don't open into an empty snippets view (e.g. the last one was deleted).
        if showingSnippets, snippets.isEmpty { showingSnippets = false }
        selectedIndex = 0
        selectedSnippetIndex = 0
        recomputeFilter()
        focusEpoch += 1
    }

    func recomputeFilter() {
        recomputeSnippetFilter()
        var base = appState.clips
        if let selectedCategory {
            base = base.filter { $0.category == selectedCategory }
        }
        if searchText.isEmpty {
            filtered = base
            imageSectionStart = nil
        } else {
            let query = searchText
            // Image clips that match only via their OCR text go into an
            // "Appeared in images" group shown at the TOP, then direct matches.
            let direct = base.filter { $0.plainText.localizedCaseInsensitiveContains(query) }
            let imageOnly = base.filter { clip in
                !clip.plainText.localizedCaseInsensitiveContains(query)
                    && (clip.ocrText?.localizedCaseInsensitiveContains(query) ?? false)
            }
            filtered = imageOnly + direct
            imageSectionStart = imageOnly.isEmpty ? nil : 0
        }
        selectedIndex = filtered.isEmpty ? 0 : min(selectedIndex, filtered.count - 1)
    }

    private func recomputeSnippetFilter() {
        if searchText.isEmpty {
            filteredSnippets = snippets
        } else {
            let query = searchText
            filteredSnippets = snippets.filter {
                $0.label.localizedCaseInsensitiveContains(query)
                    || $0.body.localizedCaseInsensitiveContains(query)
            }
        }
        selectedSnippetIndex = filteredSnippets.isEmpty
            ? 0 : min(selectedSnippetIndex, filteredSnippets.count - 1)
    }

    func selectCategory(_ category: String?) {
        showingSnippets = false
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

    func selectSnippet(_ index: Int) {
        guard filteredSnippets.indices.contains(index) else { return }
        selectedSnippetIndex = index
    }

    func moveSelection(_ delta: Int) {
        if showingSnippets {
            guard !filteredSnippets.isEmpty else { return }
            selectedSnippetIndex =
                (selectedSnippetIndex + delta + filteredSnippets.count) % filteredSnippets.count
        } else {
            guard !filtered.isEmpty else { return }
            selectedIndex = (selectedIndex + delta + filtered.count) % filtered.count
        }
    }

    func pasteSelected(optionHeld: Bool) {
        if showingSnippets {
            guard let snippet = selectedSnippet else { return }
            onRequestPasteSnippet?(snippet)
            return
        }
        guard let item = selectedItem else { return }
        onRequestPaste?(item, optionHeld)
    }

    func paste(_ item: ClipItem, optionHeld: Bool) {
        onRequestPaste?(item, optionHeld)
    }

    func paste(snippet: Snippet) {
        onRequestPasteSnippet?(snippet)
    }

    /// Click-to-paste: flashes the row briefly so the user sees which item
    /// they copied, then pastes. Keyboard paste (Return) skips the flash —
    /// the user already knows what's selected, so it stays instant.
    func clickPaste(_ item: ClipItem, optionHeld: Bool) {
        justCopiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.justCopiedID = nil
            self?.onRequestPaste?(item, optionHeld)
        }
    }

    /// Click-to-paste for a saved snippet — same brief flash as `clickPaste`.
    func clickPasteSnippet(_ snippet: Snippet) {
        justCopiedID = snippet.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.justCopiedID = nil
            self?.onRequestPasteSnippet?(snippet)
        }
    }

    func deleteSelected() {
        // Deletion only applies to history; saved snippets are managed in
        // Settings (a stray ⌘⌫ shouldn't destroy a curated snippet).
        guard !showingSnippets, let item = selectedItem else { return }
        delete(item)
    }

    func delete(_ item: ClipItem) {
        appState.deleteItem(item)
        recomputeFilter()
    }

    func togglePinSelected() {
        guard !showingSnippets, let item = selectedItem else { return }
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

    func copyImageText(_ item: ClipItem) {
        appState.copyImageText(item)
    }

    func stopConcealing(source: String) {
        appState.stopConcealing(source: source)
        recomputeFilter()
    }
}
