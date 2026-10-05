import SwiftUI

/// Five screens kept alive in a ZStack. Today is the home screen; the other four open on top of it
/// and each has a `[ today ]` button back (see `PlanStore.open` and `PlanStore.goHome`).
@MainActor
struct ContentView: View {
    @AppStorage(SettingsKey.displayMode) private var displayMode: DisplayMode = .system

    @State private var selection: AppTab = .today

    var body: some View {
        screens
            .instrumentScreen()
            .preferredColorScheme(displayMode.colorScheme)
            .onChange(of: PlanStore.shared.pendingRoute) { _, route in
                if let route = route {
                    show(tab(for: route))
                }
            }
            .onChange(of: PlanStore.shared.requestedTab) { _, requested in
                if let requested = requested {
                    show(requested)
                    PlanStore.shared.requestedTab = nil
                }
            }
    }

    /// Switches to `screen`, unless a run or track session is being recorded: that screen stays.
    private func show(_ screen: AppTab) {
        let store = PlanStore.shared
        selection = ScreenRouting.resolve(current: selection,
                                          requested: screen,
                                          runInProgress: store.runInProgress,
                                          trackInProgress: store.trackInProgress)
    }

    /// The screen that handles a route from the today screen. That screen applies the route itself
    /// once it is showing.
    private func tab(for route: PlanRoute) -> AppTab {
        switch route {
        case .freeRun, .roadWorkout: return .run
        case .track: return .track
        }
    }

    private var screens: some View {
        ZStack {
            TodayView(isActive: selection == .today)
                .modifier(TabLayer(isSelected: selection == .today))
            RunView(isActive: selection == .run)
                .modifier(TabLayer(isSelected: selection == .run))
            TrackSetupView(isActive: selection == .track)
                .modifier(TabLayer(isSelected: selection == .track))
            HistoryView()
                .modifier(TabLayer(isSelected: selection == .log))
            SettingsView()
                .modifier(TabLayer(isSelected: selection == .set))
        }
    }
}

/// Shows a screen only while it is the selected one, without tearing it down.
private struct TabLayer: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}
