import AppKit
import SwiftUI

/// Forces the enclosing `NSScrollView` to overlay (auto-hiding) scrollers, so a
/// list/form scrollbar only shows while scrolling, regardless of the system
/// "Show scroll bars" setting. Place as a background inside the scroll content.
struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { Self.apply(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(from: nsView) }
    }

    private static func apply(from view: NSView) {
        guard let scrollView = view.enclosingScrollView else { return }
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
    }
}

/// A secondary caption that clamps to `limit` lines and offers a "Show more /
/// less" toggle — but only when the text is actually long enough to truncate.
struct ExpandableText: View {
    let text: String
    var limit = 2

    @State private var expanded = false
    @State private var isTruncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : limit)
                .background(truncationProbe)
            if isTruncated {
                Button(expanded ? "Show less" : "Show more…") {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
                .buttonStyle(.plain)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tint)
            }
        }
    }

    /// Measures the clamped height against the full height; if the full text is
    /// taller, it's being truncated, so reveal the toggle.
    private var truncationProbe: some View {
        Text(text)
            .font(.caption)
            .lineLimit(limit)
            .background(
                GeometryReader { clamped in
                    Text(text)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { full in
                                Color.clear.onAppear {
                                    if full.size.height - clamped.size.height > 1 {
                                        isTruncated = true
                                    }
                                }
                            }
                        )
                        .hidden()
                }
            )
            .hidden()
    }
}

/// Schematic live preview for the caret-proximity setting: a pointer at the
/// centre, a dashed ring whose radius reflects the threshold, and two carets —
/// one inside (panel opens at the caret) and one outside (opens at the pointer).
struct CaretProximityPreview: View {
    let thresholdPoints: Double

    private let box = CGSize(width: 260, height: 120)
    private let maxThreshold: Double = 3000

    var body: some View {
        let maxRadius = box.height / 2 - 10
        let radius = max(8, min(maxRadius, CGFloat(thresholdPoints / maxThreshold) * maxRadius))
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)

            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.tint)
                .frame(width: radius * 2, height: radius * 2)

            Image(systemName: "cursorarrow")
                .foregroundStyle(.primary)

            // Caret inside the ring → used.
            caret(active: true)
                .offset(x: radius * 0.55, y: -radius * 0.35)
            // Caret outside the ring → ignored (pointer wins).
            caret(active: false)
                .offset(x: maxRadius + 22, y: radius * 0.4)
        }
        .frame(width: box.width, height: box.height)
        .overlay(alignment: .bottom) {
            Text("Inside the ring → opens at the caret · outside → at the pointer")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
    }

    private func caret(active: Bool) -> some View {
        Image(systemName: "character.cursor.ibeam")
            .font(.caption)
            .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
    }
}
