import Foundation
import Testing

@testable import SafeClipCore

@Suite("Content classifier")
struct ContentClassifierTests {
    // MARK: - Color parsing

    @Test func parsesSixDigitHex() {
        let color = ClipColor.parse("#FF8800")
        #expect(color == ClipColor(red: 1, green: 0x88 / 255.0, blue: 0, alpha: 1))
    }

    @Test func parsesShorthandHex() {
        // #abc expands to #aabbcc.
        let color = ClipColor.parse("#abc")
        let expected = ClipColor(
            red: 0xaa / 255.0, green: 0xbb / 255.0, blue: 0xcc / 255.0, alpha: 1
        )
        #expect(color == expected)
    }

    @Test func parsesEightDigitHexWithAlpha() {
        let color = ClipColor.parse("#00000080")
        #expect(color?.alpha == 0x80 / 255.0)
        #expect(color?.red == 0)
    }

    @Test func parsesRGBAndRGBA() {
        #expect(ClipColor.parse("rgb(255, 0, 0)") == ClipColor(red: 1, green: 0, blue: 0))
        #expect(ClipColor.parse("rgba(0, 0, 0, 0.5)") == ClipColor(red: 0, green: 0, blue: 0, alpha: 0.5))
    }

    @Test func toleratesSurroundingWhitespace() {
        #expect(ClipColor.parse("  #fff  ") == ClipColor(red: 1, green: 1, blue: 1))
    }

    @Test func rejectsNonColorText() {
        // Whole-string only — text that merely mentions a color isn't one.
        #expect(ClipColor.parse("my favourite color is #fff today") == nil)
        #expect(ClipColor.parse("hello world") == nil)
        #expect(ClipColor.parse("#xyz") == nil)
        #expect(ClipColor.parse("#12") == nil)            // wrong length
        #expect(ClipColor.parse("rgb(300, 0, 0)") == nil) // out of range
        #expect(ClipColor.parse("") == nil)
    }

    // MARK: - SVG detection

    @Test func detectsSVGMarkup() {
        #expect(isLikelySVGMarkup("<svg viewBox=\"0 0 10 10\"></svg>"))
        #expect(isLikelySVGMarkup("  <svg xmlns=\"http://www.w3.org/2000/svg\"/>"))
        #expect(isLikelySVGMarkup("<?xml version=\"1.0\"?><svg></svg>"))
    }

    @Test func ignoresNonSVG() {
        #expect(!isLikelySVGMarkup("<html><body>hi</body></html>"))
        #expect(!isLikelySVGMarkup("just some text"))
        #expect(!isLikelySVGMarkup("the <svg> tag is great"))
    }
}
