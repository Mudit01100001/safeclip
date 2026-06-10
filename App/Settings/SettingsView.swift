import SwiftUI

struct SettingsView: View {
    let appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettingsView(appState: appState)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            AdvancedSettingsView(appState: appState)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 600)
    }
}
