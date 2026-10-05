import SwiftUI
import SwiftData

@main
struct MilePaceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var tracker = LocationTracker()

    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tracker)
        }
        .modelContainer(AppModel.shared.container)
    }
}
