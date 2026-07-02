import AppKit
import SwiftUI

/// A vertically scrolling container backed by a real AppKit `NSScrollView`.
///
/// The floating panel scrolls reliably with mouse and trackpad through this,
/// because SwiftUI's own `ScrollView` never delivered wheel events dependably
/// inside the floating, non-activating `NSPanel` (the Sessions 8–11 scroll
/// saga). `NSScrollView` handles the wheel natively in its own `scrollWheel(_:)`,
/// independent of the panel's key/activation subtleties — so the list scrolls
/// whether or not SafeClip is the active app.
///
/// Arbitrary SwiftUI content is hosted as the (flipped, top-down) document view.
/// The caller passes `revealFrame` — the selected row's frame in the content's
/// `"panelScroll"` coordinate space — so arrow-key navigation keeps the
/// selection on screen; it only scrolls when that frame actually moves, so the
/// user's own wheel/trackpad scrolling is never yanked back.
struct NativeScrollView<Content: View>: NSViewRepresentable {
    var revealFrame: CGRect
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .allowed
        scrollView.automaticallyAdjustsContentInsets = false

        // The document is a flipped container (top-down layout, so scrollToVisible
        // coordinates match the row frames) that wraps the SwiftUI hosting view.
        // NSHostingView itself can't be flipped (it redeclares isFlipped non-open).
        let documentView = FlippedView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let hosting = ClickThroughHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        // Drive the document height from the SwiftUI content's fitting height at
        // the clip width, so the document is taller than the viewport (and thus
        // scrollable) whenever the list overflows.
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.setContentHuggingPriority(.defaultHigh, for: .vertical)
        documentView.addSubview(hosting)
        scrollView.documentView = documentView
        context.coordinator.hosting = hosting

        // Pin the document leading/trailing/top + width to the clip view (not the
        // bottom), so its height is the hosting view's intrinsic SwiftUI content
        // height and it scrolls whenever that exceeds the viewport.
        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            documentView.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: clip.topAnchor),
            documentView.widthAnchor.constraint(equalTo: clip.widthAnchor),
            hosting.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: documentView.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.hosting?.rootView = content
        guard revealFrame != .zero, revealFrame != context.coordinator.lastRevealed else { return }
        context.coordinator.lastRevealed = revealFrame
        // Defer to after this layout pass so the document view has its new size.
        DispatchQueue.main.async {
            scrollView.documentView?.scrollToVisible(revealFrame)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var hosting: NSHostingView<Content>?
        var lastRevealed: CGRect = .zero
    }
}

/// A flipped container so the document lays out top-to-bottom (a natural list)
/// and its frame coordinates match what `scrollToVisible` expects.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// An `NSHostingView` that responds to the very first click even when its
/// window isn't key yet. AppKit's default (`acceptsFirstMouse(for:) == false`)
/// swallows the first click on a background window just to bring it to key
/// status, without passing the click through to the tapped control — the
/// classic cause of "clicking works, but only the second time." Since the
/// panel's activation is already intermittent (see FloatingPanelController's
/// SCROLLACT diagnostics), every hosting view in the panel needs this so a
/// click always registers on the first try regardless of key/active timing.
class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension View {
    /// When `isSelected`, publishes this row's frame (in the `"panelScroll"`
    /// coordinate space, which the list root declares) into `frame`, so the
    /// enclosing `NativeScrollView` can reveal it during keyboard navigation.
    /// Uses `GeometryReader` + main-actor `onChange`/`onAppear` rather than a
    /// preference, whose action is `@Sendable` and fights Swift 6 strict
    /// concurrency. The frame is in content space, so it does *not* change while
    /// the user scrolls — only when the selection (or layout above it) moves.
    func reportsSelectedRowFrame(_ isSelected: Bool, into frame: Binding<CGRect>) -> some View {
        background {
            if isSelected {
                GeometryReader { geo in
                    Color.clear
                        .onAppear { frame.wrappedValue = geo.frame(in: .named("panelScroll")) }
                        .onChange(of: geo.frame(in: .named("panelScroll"))) { _, new in
                            frame.wrappedValue = new
                        }
                }
            }
        }
    }
}
