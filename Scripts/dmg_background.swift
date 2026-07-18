#!/usr/bin/swift
// Renders the SafeClip .dmg background image used by Scripts/release.sh when it
// lays out the installer window (the "drag SafeClip → Applications" canvas).
// Output is deterministic and committed to the repo (Scripts/assets/), so it's
// reviewable and the release script never depends on a design tool.
//
// It draws the dark canvas, the "SafeClip" wordmark, and a hand-drawn squiggly
// arrow pointing from where Finder places the app icon toward the Applications
// folder. The two ICONS themselves are placed by Finder (the real .app icon and
// the /Applications alias), not drawn here — so the geometry below (W/H and the
// icon centres) MUST stay in sync with the `osascript` layout in release.sh.
//
// Usage: Scripts/dmg_background.swift [output.png]
//   default output: Scripts/assets/dmg-background@2x.png
import AppKit

// ── Geometry (points). Keep in lockstep with release.sh's window bounds. ──────
let W = 640, H = 400
let scale = 2 // @2x for retina Finder windows
let iconCenterY = 200.0 // matches the AppleScript icon Y (top-left origin ⇒ same middle)
let appIconX = 160.0
let appsIconX = 480.0

let outPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Scripts/assets/dmg-background@2x.png"

// Bottom-left origin bitmap (AppKit default) — avoids the flipped-context text
// mirroring gotcha. Remember: TOP of the image is HIGH y.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: W * scale, pixelsHigh: H * scale,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("Couldn't allocate the bitmap") }
rep.size = NSSize(width: W, height: H) // point size ⇒ the rep is @2x

guard let gctx = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Couldn't create a graphics context")
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gctx

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let full = NSRect(x: 0, y: 0, width: W, height: H)

// ── Background: near-black vertical gradient + a cool glow rising from the
// bottom-centre (mirrors the site's /thanks install mockup). ──────────────────
let base = NSGradient(starting: rgb(16, 18, 27), ending: rgb(12, 14, 19))! // bottom→top
base.draw(in: full, angle: 90) // 90° ⇒ starting at the bottom, ending at the top
let glow = NSGradient(colors: [rgb(74, 110, 190, 0.30), rgb(74, 110, 190, 0)])!
glow.draw(
    fromCenter: NSPoint(x: W / 2, y: 0), radius: 0, // bottom-centre in bottom-left coords
    toCenter: NSPoint(x: W / 2, y: 0), radius: CGFloat(W) * 0.55,
    options: []
)

// ── "SafeClip" wordmark, centred near the top. ────────────────────────────────
let title = NSAttributedString(string: "SafeClip", attributes: [
    .font: NSFont.systemFont(ofSize: 40, weight: .semibold),
    .foregroundColor: NSColor.white.withAlphaComponent(0.92),
])
let tSize = title.size()
title.draw(at: NSPoint(x: (CGFloat(W) - tSize.width) / 2, y: CGFloat(H) - 98))

// ── Squiggly arrow from just past the app icon to just before Applications,
// at the icons' vertical centre. Coordinates are bottom-left, so the icon
// centre Y (top-left `iconCenterY`) maps to H - iconCenterY here. ─────────────
let y = CGFloat(H) - iconCenterY
let startX = CGFloat(appIconX) + 86 // clear of the ~128px app icon
let endX = CGFloat(appsIconX) - 92 // clear of the Applications folder
let amp: CGFloat = 14
let squiggle = NSBezierPath()
squiggle.lineWidth = 2.4
squiggle.lineCapStyle = .round
squiggle.lineJoinStyle = .round
squiggle.move(to: NSPoint(x: startX, y: y))
let span = endX - startX
squiggle.curve(
    to: NSPoint(x: startX + span * 0.34, y: y),
    controlPoint1: NSPoint(x: startX + span * 0.12, y: y + amp),
    controlPoint2: NSPoint(x: startX + span * 0.22, y: y - amp)
)
squiggle.curve(
    to: NSPoint(x: startX + span * 0.68, y: y),
    controlPoint1: NSPoint(x: startX + span * 0.46, y: y + amp),
    controlPoint2: NSPoint(x: startX + span * 0.56, y: y - amp)
)
squiggle.curve(
    to: NSPoint(x: endX, y: y),
    controlPoint1: NSPoint(x: startX + span * 0.80, y: y + amp),
    controlPoint2: NSPoint(x: startX + span * 0.92, y: y - amp * 0.4)
)
rgb(255, 255, 255, 0.60).setStroke()
squiggle.stroke()

// arrowhead pointing right at the end of the squiggle
let head = NSBezierPath()
head.lineWidth = 2.4
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: endX - 11, y: y + 8))
head.line(to: NSPoint(x: endX + 3, y: y))
head.line(to: NSPoint(x: endX - 11, y: y - 8))
rgb(255, 255, 255, 0.60).setStroke()
head.stroke()

NSGraphicsContext.restoreGraphicsState()

// ── Write the PNG (creating Scripts/assets/ if needed). ───────────────────────
let outURL = URL(fileURLWithPath: outPath)
try? FileManager.default.createDirectory(
    at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true
)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Couldn't encode PNG")
}
try! png.write(to: outURL)
print("wrote \(outPath) (\(W * scale)×\(H * scale) px)")
