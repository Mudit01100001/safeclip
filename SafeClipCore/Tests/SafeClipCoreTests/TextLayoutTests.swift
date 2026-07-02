import CoreGraphics
import Foundation
import Testing

@testable import SafeClipCore

@Suite("Structure-aware OCR layout")
struct TextLayoutTests {
    /// Convenience: a block at a normalized (Vision, bottom-left origin) box.
    private func block(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> OCRTextBlock {
        OCRTextBlock(text: text, boundingBox: CGRect(x: x, y: y, width: w, height: h))
    }

    @Test func emptyInputYieldsEmptyString() {
        #expect(TextLayout.reconstruct([]) == "")
        #expect(TextLayout.reconstruct([block("   ", x: 0, y: 0, w: 0.1, h: 0.1)]) == "")
    }

    @Test func ordersBlocksTopToBottomRegardlessOfInputOrder() {
        // Adjacent single-spaced lines (so no paragraph break is inferred).
        let first = block("First", x: 0.1, y: 0.80, w: 0.3, h: 0.04)
        let second = block("Second", x: 0.1, y: 0.75, w: 0.3, h: 0.04)
        // Fed in the wrong (bottom-first) order on purpose.
        #expect(TextLayout.reconstruct([second, first]) == "First\nSecond")
    }

    @Test func keepsColumnsOnOneRowSeparatedBySpaces() {
        let name = block("Name", x: 0.1, y: 0.5, w: 0.2, h: 0.05)
        let value = block("Value", x: 0.6, y: 0.5, w: 0.2, h: 0.05)
        let result = TextLayout.reconstruct([name, value])
        #expect(!result.contains("\n"))          // same visual row → one line
        #expect(result.hasPrefix("Name"))
        #expect(result.hasSuffix("Value"))
        #expect(result.contains("  "))            // a real column gap, not a single space
    }

    @Test func insertsBlankLineForParagraphGap() {
        let p1a = block("Para1", x: 0.1, y: 0.90, w: 0.3, h: 0.04)
        let p1b = block("Para1b", x: 0.1, y: 0.84, w: 0.3, h: 0.04) // tight under p1a
        let p2 = block("Para2", x: 0.1, y: 0.50, w: 0.3, h: 0.04)   // far below → new paragraph
        #expect(TextLayout.reconstruct([p1a, p1b, p2]) == "Para1\nPara1b\n\nPara2")
    }
}
