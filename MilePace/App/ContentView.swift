import SwiftUI
import UIKit

/// Four screens kept alive in a ZStack, with the instrument tab strip along the bottom.
struct ContentView: View {
    @AppStorage(SettingsKey.displayMode) private var displayMode: DisplayMode = .system

    @State private var selection: AppTab = .run
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    private var screens: some View {
        ZStack {
            RunView(isActive: selection == .run)
                .modifier(TabLayer(isSelected: selection == .run))
            TrackSetupView()
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
