import Foundation

/// A CSS-style color value parsed from a clipboard string, so the panel can
/// render a swatch next to color clips (designer workflow — Supaste parity).
/// Components are 0…1. Parsing is deliberately *whole-string*: ordinary text
/// that merely mentions "#fff" must not be treated as a color.
public struct ClipColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Parses `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb(r,g,b)`, and
    /// `rgba(r,g,b,a)` (r/g/b 0–255, a 0–1). Returns nil for anything else,
    /// including strings that only *contain* a color token.
    public static func parse(_ raw: String) -> ClipColor? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 30 else { return nil }
        if s.hasPrefix("#") { return parseHex(String(s.dropFirst())) }
        let lower = s.lowercased()
        if lower.hasPrefix("rgb") { return parseRGB(lower) }
        return nil
    }

    private static func parseHex(_ hex: String) -> ClipColor? {
        let chars = Array(hex)
        guard chars.allSatisfy(\.isHexDigit) else { return nil }

        func component(_ slice: ArraySlice<Character>) -> Double? {
            guard let value = Int(String(slice), radix: 16) else { return nil }
            return Double(value) / 255
        }
        // Expand shorthand nibbles (#abc → #aabbcc) by repeating each char.
        let expanded: [Character]
        switch chars.count {
        case 3, 4: expanded = chars.flatMap { [$0, $0] }
        case 6, 8: expanded = chars
        default: return nil
        }
        guard
            let r = component(expanded[0..<2]),
            let g = component(expanded[2..<4]),
            let b = component(expanded[4..<6])
        else { return nil }
        let a = expanded.count == 8 ? (component(expanded[6..<8]) ?? 1) : 1
        return ClipColor(red: r, green: g, blue: b, alpha: a)
    }

    private static func parseRGB(_ s: String) -> ClipColor? {
        let pattern =
            #"^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*(?:,\s*(0|1|0?\.\d+)\s*)?\)$"#
        guard
            let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
        else { return nil }

        func group(_ index: Int) -> String? {
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: s) else { return nil }
            return String(s[range])
        }
        guard
            let rs = group(1), let gs = group(2), let bs = group(3),
            let r = Int(rs), let g = Int(gs), let b = Int(bs),
            r <= 255, g <= 255, b <= 255
        else { return nil }
        let alpha = group(4).flatMap(Double.init) ?? 1
        return ClipColor(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: alpha)
    }
}

/// True when the text is (the start of) an SVG document, so the panel can badge
/// it as vector markup rather than plain text. Conservative: requires an actual
/// `<svg` tag near the start.
public func isLikelySVGMarkup(_ raw: String) -> Bool {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard s.hasPrefix("<") else { return false }
    let head = s.prefix(512).lowercased()
    if head.hasPrefix("<svg") { return true }
    return head.hasPrefix("<?xml") && head.contains("<svg")
}
