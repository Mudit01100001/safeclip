import CoreGraphics
import Foundation

/// One recognized piece of text and where it sits on the page, as reported by
/// Vision. `boundingBox` is normalized (0…1) with a bottom-left origin — the
/// Vision convention — so `maxY` is the *top* edge and larger y is higher up.
public struct OCRTextBlock: Sendable, Equatable {
    public let text: String
    public let boundingBox: CGRect

    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// Reassembles recognized text blocks into a layout that mirrors what the user
/// saw, instead of Vision's raw observation order (#10 structure-aware OCR).
///
/// Vision returns observations that are *roughly* top-to-bottom but makes no
/// promise about order, and it splits columns/tables into separate blocks with
/// no spacing. This:
///   1. orders blocks top-to-bottom, then left-to-right within a line;
///   2. groups blocks that share a row (vertical overlap) onto one line;
///   3. inserts spaces sized from the horizontal gaps, so columns stay aligned;
///   4. inserts a blank line where the vertical gap looks like a paragraph break.
///
/// Pure and side-effect free so it can be unit-tested without Vision.
public enum TextLayout {
    public static func reconstruct(_ blocks: [OCRTextBlock]) -> String {
        let cleaned = blocks.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !cleaned.isEmpty else { return "" }

        // Top-to-bottom: in Vision's bottom-left space, a higher midY is higher
        // on the page.
        let sorted = cleaned.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        // Group into lines by vertical overlap with the line being built.
        var lines: [[OCRTextBlock]] = []
        for block in sorted {
            if let last = lines.last, let ref = last.first,
               Self.verticallyOverlap(ref.boundingBox, block.boundingBox) {
                lines[lines.count - 1].append(block)
            } else {
                lines.append([block])
            }
        }

        var result = ""
        var previousBottom: CGFloat?  // top-down y (0 = top of page) of the last line's bottom edge
        for line in lines {
            let ordered = line.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let top = 1 - (ordered.map { $0.boundingBox.maxY }.max() ?? 0)
            let bottom = 1 - (ordered.map { $0.boundingBox.minY }.min() ?? 0)
            let height = max(bottom - top, 0.0001)
            // Blank line only on a clear paragraph/section gap — more than a full
            // line of empty space. Normal single-spaced rows (gap ≈ 0.2–0.5× the
            // line height, even in tables) must NOT trigger one.
            if let previousBottom, top - previousBottom > height * 1.2 {
                result += "\n"
            }
            result += Self.assembleLine(ordered)
            result += "\n"
            previousBottom = bottom
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Two boxes share a row when their vertical extents overlap by more than a
    /// third of the shorter box's height (tolerant of baseline jitter).
    private static func verticallyOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > min(a.height, b.height) * 0.3
    }

    /// Joins one row's blocks left-to-right, padding column gaps with spaces sized
    /// from each gap relative to the local character width (capped, so a wide gap
    /// can't explode into a wall of spaces).
    private static func assembleLine(_ ordered: [OCRTextBlock]) -> String {
        var line = ""
        var previousMaxX: CGFloat?
        for block in ordered {
            if let previousMaxX {
                let gap = block.boundingBox.minX - previousMaxX
                let charWidth = block.boundingBox.width / CGFloat(max(1, block.text.count))
                let spaces: Int =
                    if charWidth > 0 {
                        Int((gap / charWidth).rounded())
                    } else {
                        gap > 0.012 ? 1 : 0
                    }
                // Always at least one space between two blocks on the same row.
                line += String(repeating: " ", count: min(max(spaces, 1), 12))
            }
            line += block.text
            previousMaxX = block.boundingBox.maxX
        }
        return line
    }
}
