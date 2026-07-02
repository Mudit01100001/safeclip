import SwiftUI

struct SettingsView: View {
    let appState: AppState
    let syncService: SyncService
    @ObservedObject var updateService: UpdateService

    var body: some View {
        TabView {
            GeneralSettingsView(appState: appState)
                .tabItem { Label("General", systemImage: "gearshape") }
            SnippetsSettingsView(appState: appState)
                .tabItem { Label("Snippets", systemImage: "bookmark") }
            SyncSettingsView(appState: appState, sync: syncService)
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
            PrivacySettingsView(appState: appState)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            UpdatesSettingsView(updateService: updateService)
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            AdvancedSettingsView(appState: appState)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
            AboutView(appState: appState)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 720, height: 600)
    }
}
