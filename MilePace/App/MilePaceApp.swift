import SwiftUI
import SwiftData

@main
struct MilePaceApp: App {
    @State private var tracker = LocationTracker()

    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tracker)
        }
        .modelContainer(for: [RunRecord.self, WorkoutRecord.self])
    }
}
