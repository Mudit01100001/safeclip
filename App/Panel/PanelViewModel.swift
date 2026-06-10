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
    private(set) var filtered: [ClipItem] = []
    private(set) var selectedIndex = 0
    /// Bumped each time the panel shows so the view refocuses the search field.
    private(set) var focusEpoch = 0

    /// Set by the controller: hides the panel, runs the ClickFix confirmation
    /// if needed, then performs the paste.
    var onRequestPaste: ((ClipItem, Bool) -> Void)?

    init(appState: AppState) {
        self.appState = appState
    }

    var historyHidden: Bool { appState.historyHidden }
    var maskConcealed: Bool { appState.settings.maskConcealedPreviews }
    var stripByDefault: Bool { appState.settings.stripFormattingByDefault }

    var selectedItem: ClipItem? {
        filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil
    }

    func prepareForShow() {
        appState.reloadHistory()
        searchText = ""
        selectedIndex = 0
        recomputeFilter()
        focusEpoch += 1
    }

    func recomputeFilter() {
        let all = appState.clips
        filtered = searchText.isEmpty
            ? all
            : all.filter { $0.plainText.localizedCaseInsensitiveContains(searchText) }
        selectedIndex = filtered.isEmpty ? 0 : min(selectedIndex, filtered.count - 1)
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
}
