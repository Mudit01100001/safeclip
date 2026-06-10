import Foundation

/// Result of scanning one captured pasteboard text.
public struct ScanResult: Sendable, Equatable {
    public let flagReason: FlagReason?
    public let detail: String?

    public static let clean = ScanResult(flagReason: nil, detail: nil)

    public init(flagReason: FlagReason?, detail: String?) {
        self.flagReason = flagReason
        self.detail = detail
    }
}

/// Heuristic scanner for sensitive or hostile clipboard content.
///
/// Two distinct jobs, both warn-only (never blocks capture or paste):
///  1. ClickFix / pastejacking (F11): clipboard overwritten while a browser is
///     frontmost with something that looks like a shell command. >50% of macOS
///     malware-loader activity in 2025 used this pattern (PRD §2).
///  2. Sensitive-pattern detection (F13, opt-in): API keys, card numbers
///     (Luhn-validated), private key blocks.
///
/// Regexes are compiled per call: scans run once per copy event (human
/// frequency), and per-call construction sidesteps Sendable concerns about
/// shared `NSRegularExpression` globals under strict concurrency.
public struct SecurityScanner: Sendable {
    public struct Options: Sendable, Equatable {
        public var detectClickFix: Bool
        public var detectAPIKeys: Bool
        public var detectCards: Bool
        public var detectPrivateKeys: Bool

        public init(
            detectClickFix: Bool = false,
            detectAPIKeys: Bool = false,
            detectCards: Bool = false,
            detectPrivateKeys: Bool = false
        ) {
            self.detectClickFix = detectClickFix
            self.detectAPIKeys = detectAPIKeys
            self.detectCards = detectCards
            self.detectPrivateKeys = detectPrivateKeys
        }

        public static let allOn = Options(
            detectClickFix: true, detectAPIKeys: true, detectCards: true, detectPrivateKeys: true
        )
    }

    /// Bundle IDs treated as browsers for the ClickFix heuristic (ROADMAP §8.1).
    public static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser", // Arc
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.chromium.Chromium",
    ]

    public init() {}

    /// Scans in priority order; the first hit wins.
    public func scan(text: String, sourceBundle: String?, options: Options) -> ScanResult {
        if options.detectClickFix,
           let bundle = sourceBundle,
           Self.browserBundleIDs.contains(bundle),
           Self.looksLikeShellAttack(text) {
            return ScanResult(
                flagReason: .clickfix,
                detail: "Copied from a browser and looks like a shell command"
            )
        }
        if options.detectPrivateKeys, Self.containsPrivateKey(text) {
            return ScanResult(flagReason: .privateKey, detail: "Private key block")
        }
        if options.detectAPIKeys, let label = Self.matchedAPIKeyLabel(text) {
            return ScanResult(flagReason: .apiKey, detail: label)
        }
        if options.detectCards, Self.containsCardNumber(text) {
            return ScanResult(flagReason: .card, detail: "Passes Luhn check")
        }
        return .clean
    }

    // MARK: - ClickFix / pastejacking

    static func looksLikeShellAttack(_ text: String) -> Bool {
        let patterns = [
            // curl/wget piped into a shell, with or without sudo
            #"(?:curl|wget)[^|\n]*\|\s*(?:sudo\s+)?(?:ba|z|da)?sh\b"#,
            // base64 decode piped into a shell
            #"\bbase64\b[^|\n]*\|\s*(?:sudo\s+)?(?:ba|z)?sh\b"#,
            // a command that starts with sudo (classic "fix" instruction)
            #"^\s*sudo\s+\S+"#,
            // osascript one-liners
            #"\bosascript\s+-e\b"#,
            // long base64 blob being echoed (staged payload)
            #"\becho\s+[A-Za-z0-9+/=]{40,}"#,
            // command substitution fetching remote content
            #"\$\((?:[^)]*\b(?:curl|wget)\b[^)]*)\)"#,
            // windows-style droppers pasted cross-platform
            #"\bpowershell\b.*(?:-enc\b|-e\b|iex\b)"#,
        ]
        return matchesAny(patterns, in: text)
    }

    // MARK: - Sensitive patterns (F13)

    static func containsPrivateKey(_ text: String) -> Bool {
        matchesAny([#"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"#], in: text)
    }

    static func matchedAPIKeyLabel(_ text: String) -> String? {
        // Specific prefixes first; most specific wins.
        let known: [(pattern: String, label: String)] = [
            (#"\bsk-ant-[A-Za-z0-9_\-]{32,}\b"#, "Anthropic API key"),
            (#"\bghp_[A-Za-z0-9]{36}\b"#, "GitHub personal access token"),
            (#"\bgithub_pat_[A-Za-z0-9_]{22,}\b"#, "GitHub fine-grained token"),
            (#"\bAKIA[A-Z0-9]{16}\b"#, "AWS access key"),
            (#"\bsk-[A-Za-z0-9_\-]{20,}\b"#, "OpenAI-style secret key"),
            (#"\bxox[bpars]-[A-Za-z0-9\-]{10,}\b"#, "Slack token"),
        ]
        for entry in known where matchesAny([entry.pattern], in: text) {
            return entry.label
        }
        // Lower confidence: the entire trimmed text is one opaque token.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 32, trimmed.count <= 64,
           matchesAny([#"^[A-Za-z0-9_\-]+$"#], in: trimmed),
           trimmed.rangeOfCharacter(from: .decimalDigits) != nil,
           trimmed.rangeOfCharacter(from: .letters) != nil {
            return "Possible API key or token"
        }
        return nil
    }

    static func containsCardNumber(_ text: String) -> Bool {
        // Candidate digit runs, allowing space/dash grouping, 13–19 digits.
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![0-9])(?:[0-9][ \-]?){12,18}[0-9](?![0-9])"#
        ) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)
        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let digits = text[r].filter(\.isNumber)
            if digits.count >= 13, digits.count <= 19, Self.luhnValid(String(digits)) {
                return true
            }
        }
        return false
    }

    /// Standard Luhn checksum (ROADMAP §8.2).
    static func luhnValid(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == digits.count, values.count >= 13, values.count <= 19 else {
            return false
        }
        var sum = 0
        for (index, digit) in values.reversed().enumerated() {
            if index % 2 == 1 {
                let doubled = digit * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }
        return sum % 10 == 0
    }

    // MARK: - Helpers

    private static func matchesAny(_ patterns: [String], in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .anchorsMatchLines]
            ) else { continue }
            if regex.firstMatch(in: text, range: range) != nil {
                return true
            }
        }
        return false
    }
}
