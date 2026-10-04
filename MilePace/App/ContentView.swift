import SwiftUI
import UIKit

/// Five screens kept alive in a ZStack, with the instrument tab strip along the bottom.
struct ContentView: View {
    @AppStorage(SettingsKey.displayMode) private var displayMode: DisplayMode = .system

    @State private var selection: AppTab = .today
    @State private var keyboardVisible: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            screens
            if !keyboardVisible {
                TabStrip(selection: $selection)
            }
        }
        .instrumentScreen()
        .preferredColorScheme(displayMode.colorScheme)
        .onChange(of: PlanStore.shared.pendingRoute) { _, route in
            if let route = route {
                selection = tab(for: route)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    /// The tab that handles a route from the today screen. That screen applies the route itself
    /// once its tab is showing.
    private func tab(for route: PlanRoute) -> AppTab {
        switch route {
        case .freeRun, .roadWorkout: return .run
        case .track: return .track
        }
    }

    private var screens: some View {
        ZStack {
            TodayView()
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

/// Shows a screen only while its tab is selected, without tearing it down.
private struct TabLayer: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}
