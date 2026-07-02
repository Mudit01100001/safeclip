import SwiftUI

struct AboutView: View {
    let appState: AppState

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

            Text("The clipboard manager that doesn't betray you: encrypted history, plain-text paste, and a picker that appears right where you're typing.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            Button("Show Onboarding Again") { appState.replayOnboarding() }

            Divider().frame(width: 320)

            Text("© 2026 SafeClip. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
