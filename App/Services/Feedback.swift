import AppKit

/// Opens the user's mail client with a pre-filled feedback email — version
/// and OS info in the template so beta reports arrive self-describing. A
/// mailto: URL, not a network call: SafeClip itself still sends nothing.
@MainActor
enum Feedback {
    private static let address = "m14ahlawat@gmail.com"

    static func compose() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "SafeClip feedback — v\(version) (\(build))"),
            URLQueryItem(
                name: "body",
                value: """


                ——— please keep the lines below ———
                SafeClip \(version) (\(build))
                \(os)
                """
            ),
        ]
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
