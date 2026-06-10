import SwiftUI

struct AboutView: View {
    private static let repoURL = "https://github.com/Mudit01100001/safeclip"

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("SafeClip").font(.title.bold())
            Text(version).foregroundStyle(.secondary)

            Text("The clipboard manager that doesn't betray you — encrypted history, plain-text paste, and a picker that appears right where you're typing.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            VStack(spacing: 6) {
                Link("Source code on GitHub", destination: URL(string: Self.repoURL)!)
                Link("Terms of Use", destination: URL(string: "\(Self.repoURL)/blob/main/TERMS.md")!)
                Link("Report an issue", destination: URL(string: "\(Self.repoURL)/issues")!)
            }

            Divider().frame(width: 320)

            VStack(spacing: 2) {
                Text("Open source under the MIT License.")
                Text("Built with GRDB.swift (MIT) and KeyboardShortcuts (MIT).")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
