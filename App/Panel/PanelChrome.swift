import SwiftUI

/// Which edge the callout beak sits on. The panel sits *above* the anchor
/// (beak on the bottom, pointing down) whenever there's room, else below.
enum PanelArrowEdge {
    case top
    case bottom
}

/// Where the callout beak points, computed per-show by `FloatingPanelController`
/// and handed to `ClipboardPanelView`.
struct PanelArrowSpec: Equatable {
    var edge: PanelArrowEdge
    /// Centre x of the beak in the panel's own coordinates (points from the
    /// left edge). Clamped onto the flat edge between the rounded corners.
    var offsetX: CGFloat

    static let height: CGFloat = 9
    static let width: CGFloat = 22
}

/// The panel outline: a rounded-rect body with a triangular beak merged into
/// one path on the arrow edge, so the body and beak read as a single surface
/// (no seam, no mismatched materials). Used both as the glass/material
/// background and as the content clip.
struct CalloutShape: Shape {
    var arrow: PanelArrowSpec
    var cornerRadius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        let beakH = PanelArrowSpec.height
        let beakW = PanelArrowSpec.width

        // The rounded body occupies everything except the beak strip.
        let bodyRect: CGRect
        switch arrow.edge {
        case .top:
            bodyRect = CGRect(x: rect.minX, y: rect.minY + beakH,
                              width: rect.width, height: rect.height - beakH)
        case .bottom:
            bodyRect = CGRect(x: rect.minX, y: rect.minY,
                              width: rect.width, height: rect.height - beakH)
        }

        var path = Path(roundedRect: bodyRect, cornerRadius: cornerRadius)

        // Beak, clamped so its base stays on the flat edge between corners.
        let minCX = rect.minX + cornerRadius + beakW / 2
        let maxCX = rect.maxX - cornerRadius - beakW / 2
        let cx = min(max(arrow.offsetX, minCX), maxCX)

        var beak = Path()
        switch arrow.edge {
        case .bottom:
            let baseY = bodyRect.maxY
            beak.move(to: CGPoint(x: cx - beakW / 2, y: baseY))
            beak.addLine(to: CGPoint(x: cx + beakW / 2, y: baseY))
            beak.addLine(to: CGPoint(x: cx, y: baseY + beakH)) // tip down
        case .top:
            let baseY = bodyRect.minY
            beak.move(to: CGPoint(x: cx - beakW / 2, y: baseY))
            beak.addLine(to: CGPoint(x: cx + beakW / 2, y: baseY))
            beak.addLine(to: CGPoint(x: cx, y: baseY - beakH)) // tip up
        }
        beak.closeSubpath()
        path.addPath(beak)
        return path
    }
}
