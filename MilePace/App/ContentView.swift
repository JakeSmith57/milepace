import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RunView()
                .tabItem {
                    Label("Run", systemImage: "figure.run")
                }
            TrackSetupView()
                .tabItem {
                    Label("Track", systemImage: "stopwatch")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "chart.bar")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .tint(.orange)
    }
}
