import AppKit
import ScreenCaptureKit
import SwiftUI

/// One sampled pixel color (Sendable so it can cross the actor boundary).
struct PixelColor: Sendable, Equatable {
    let r: Double
    let g: Double
    let b: Double
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    var swiftUI: Color { Color(.sRGB, red: r, green: g, blue: b) }
    var hex: String {
        String(format: "#%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
    }
}

/// Loupe geometry, all measured from the supplied eyedropper icon's alpha
/// channel. The icon is square; the teardrop tip is the **pick point** (it sits
/// on the cursor), the transparent hole shows the magnified pixels. Shared by
/// the view (rendering) and the controller (window placement) so they agree.
enum LoupeGeometry {
    static let holeCenterXFrac: CGFloat = 0.5
    static let holeCenterYFrac: CGFloat = 0.5609
    static let holeRadiusFrac: CGFloat = 0.2323
    /// Outer bulb radius (concentric with the hole) — gives the frame its
    /// thickness. From the icon: bottom edge 0.852 − centre 0.5609 ≈ 0.291.
    static let outerRadiusFrac: CGFloat = 0.291
    static let tipXFrac: CGFloat = 0.4958
    static let tipYFrac: CGFloat = 0.1479
    /// Vertical band reserved above and below the icon for the hex caption.
    static let hexBand: CGFloat = 30

    static func containerSize(side: CGFloat) -> CGSize {
        CGSize(width: side, height: side + 2 * hexBand)
    }

    /// The tip position from the container's top-left (y grows down), for
    /// placing the window so the tip lands on the cursor. Mirrors vertically
    /// when `flipped` (panel hangs above the cursor near the screen bottom).
    static func tip(side: CGFloat, flipped: Bool) -> CGPoint {
        let yInIcon = flipped ? side * (1 - tipYFrac) : side * tipYFrac
        return CGPoint(x: side * tipXFrac, y: hexBand + yInIcon)
    }
}

/// The eyedropper teardrop as a vector shape — a bulb circle plus a cone whose
/// sides are tangent to it, meeting at the tip — so it can be filled with Liquid
/// Glass (a raster PNG can't be). Solid (no hole); the magnified circle is
/// composited over the centre, so the glass reads as the surrounding frame.
struct TeardropLoupeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let c = CGPoint(
            x: rect.minX + LoupeGeometry.holeCenterXFrac * s,
            y: rect.minY + LoupeGeometry.holeCenterYFrac * s
        )
        let r = LoupeGeometry.outerRadiusFrac * s
        let tip = CGPoint(
            x: rect.minX + LoupeGeometry.tipXFrac * s,
            y: rect.minY + LoupeGeometry.tipYFrac * s
        )
        var path = Path()
        let d = hypot(tip.x - c.x, tip.y - c.y)
        // Degenerate (tip inside the bulb): just the circle.
        guard d > r else {
            path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            return path
        }
        // ONE continuous teardrop silhouette — no separate circle + triangle, so
        // there's no overlap region that the fill turns into a visible cutout.
        // The bulb is the *major* arc of the circle (the side away from the tip);
        // the two cone sides run from the tangent points to a rounded tip.
        let theta = atan2(tip.y - c.y, tip.x - c.x) // bulb → tip direction
        let beta = acos(r / d)                       // half-angle of the tangents
        let p1 = CGPoint(x: c.x + r * cos(theta + beta), y: c.y + r * sin(theta + beta))
        let p2 = CGPoint(x: c.x + r * cos(theta - beta), y: c.y + r * sin(theta - beta))
        let tipRadius = max(2, s * 0.03)
        // Tip rounded between points backed off along each cone side.
        func backOff(from edge: CGPoint) -> CGPoint {
            let dx = tip.x - edge.x, dy = tip.y - edge.y
            let len = max(hypot(dx, dy), 0.0001)
            return CGPoint(x: tip.x - dx / len * tipRadius, y: tip.y - dy / len * tipRadius)
        }
        let t1 = backOff(from: p1)
        let t2 = backOff(from: p2)

        path.move(to: p1)
        // Major arc p1 → p2 the long way (through the back of the bulb).
        let steps = 48
        let startA = theta + beta
        let endA = theta - beta + 2 * .pi
        for i in 1...steps {
            let a = startA + (endA - startA) * CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a)))
        }
        // Down the right cone side, round the tip, back up the left side, close.
        path.addLine(to: t2)
        path.addQuadCurve(to: t1, control: tip)
        path.closeSubpath()
        return path
    }
}

/// Drives the loupe view: the magnified patch, the sampled color, the hex, and
/// whether it's flipped (hanging above the cursor near the screen bottom).
@MainActor
@Observable
final class LoupeModel {
    var magnified: NSImage?
    var color: Color = .black
    var hex = ""
    var flipped = false
}

/// The magnifier loupe: live magnified pixels in the centre, a thick ring of the
/// sampled color around the inside of the circle (so the color reads large, not
/// just one zoomed pixel), the teardrop frame on top with its tip on the cursor,
/// and the hex caption above (or below, when flipped). Liquid Glass on macOS 26+.
struct ColorLoupeView: View {
    @Bindable var model: LoupeModel
    let side: CGFloat

    var body: some View {
        let g = LoupeGeometry.self
        let size = LoupeGeometry.containerSize(side: side)
        let flipped = model.flipped
        let holeY = side * (flipped ? (1 - g.holeCenterYFrac) : g.holeCenterYFrac)
        ZStack(alignment: .topLeading) {
            iconLayer(holeX: side * g.holeCenterXFrac, holeY: holeY, flipped: flipped)
                .frame(width: side, height: side)
                .offset(y: g.hexBand)
            // Hex sits at the BOTTOM of the loupe in the regular state (loupe
            // hangs below the cursor) and moves to the TOP when flipped (loupe
            // hangs above the cursor near the screen bottom) — always on the
            // outer side, away from the cursor.
            hexPill
                .position(
                    x: side / 2,
                    y: flipped ? g.hexBand / 2 : (g.hexBand + side + g.hexBand / 2)
                )
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func iconLayer(holeX: CGFloat, holeY: CGFloat, flipped: Bool) -> some View {
        let diameter = side * LoupeGeometry.holeRadiusFrac * 2
        return ZStack(alignment: .topLeading) {
            teardropFrame(flipped: flipped) // glass frame (bottom)
            loupeContents(diameter: diameter) // magnified pixels cover the centre
                .position(x: holeX, y: holeY)
        }
        .frame(width: side, height: side)
    }

    private func teardropFrame(flipped: Bool) -> some View {
        // No stroke: stroking the compound path traces the bulb circle AND the
        // cone's chord separately, drawing the internal seam that read as "a
        // triangle on a circle". The glass fill is a single smooth teardrop.
        glassTeardrop(TeardropLoupeShape())
            .scaleEffect(x: 1, y: flipped ? -1 : 1) // tip points up, or down when flipped
            .shadow(color: .black.opacity(0.45), radius: 2)
    }

    @ViewBuilder
    private func glassTeardrop(_ shape: TeardropLoupeShape) -> some View {
        if #available(macOS 26.0, *) {
            // One continuous teardrop (see TeardropLoupeShape) filled with bright,
            // interactive Liquid Glass and a clean rim — now that it's a single
            // outline, a thin stroke reads as a glass edge, not a seam.
            Color.clear
                .frame(width: side, height: side)
                .glassEffect(.regular.tint(.white.opacity(0.18)).interactive(), in: shape)
                .overlay(shape.stroke(.white.opacity(0.28), lineWidth: 0.75).frame(width: side, height: side))
                .brightness(0.05)
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.stroke(.white.opacity(0.25), lineWidth: 0.75))
                .frame(width: side, height: side)
        }
    }

    /// Magnified pixels filling the circle, with a thick ring of the sampled
    /// color around the inside edge (a large swatch) on top.
    private func loupeContents(diameter: CGFloat) -> some View {
        let ringWidth = diameter * 0.16
        return ZStack {
            Circle().fill(.black.opacity(0.15))
            if let img = model.magnified {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: diameter, height: diameter)
            }
            Circle().strokeBorder(model.color, lineWidth: ringWidth)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private var hexPill: some View {
        Text(model.hex.isEmpty ? "—" : model.hex)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .modifier(GlassCapsule())
            .fixedSize()
    }
}

/// Glass capsule background on macOS 26+, material below.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
        }
    }
}

/// Captures the small patch of screen under the cursor for the magnifier loupe.
///
/// An `actor` so the non-Sendable ScreenCaptureKit objects never cross a
/// concurrency boundary. `SCShareableContent` is fetched once and cached
/// (enumerating windows is the slow part); only the tiny `sourceRect` changes
/// per frame, and our own overlay + loupe windows are excluded so the magnifier
/// never captures itself.
actor LoupeSampler {
    private var content: SCShareableContent?

    private func currentContent() async -> SCShareableContent? {
        if let content { return content }
        content = try? await SCShareableContent.current
        return content
    }

    func sample(
        displayID: CGDirectDisplayID, rectPt: CGRect, outPixels: Int,
        excluding excludedWindowIDs: Set<CGWindowID>
    ) async -> (tiff: Data, center: PixelColor)? {
        guard
            let content = await currentContent(),
            let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }

        let excluded = content.windows.filter { excludedWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let config = SCStreamConfiguration()
        config.sourceRect = rectPt
        config.width = outPixels
        config.height = outPixels
        config.showsCursor = false

        guard
            let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
        else { return nil }

        let rep = NSBitmapImageRep(cgImage: image)
        let center = rep.colorAt(x: image.width / 2, y: image.height / 2)?.usingColorSpace(.sRGB)
        let color = center.map {
            PixelColor(r: Double($0.redComponent), g: Double($0.greenComponent), b: Double($0.blueComponent))
        } ?? PixelColor(r: 0, g: 0, b: 0)
        guard let tiff = rep.tiffRepresentation else { return nil }
        return (tiff, color)
    }
}
