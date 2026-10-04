import SwiftUI
import UIKit

/// "Instrument" design tokens: pixel monospace type, black and white, one electric blue used as a fill.
enum Theme {
    // MARK: Colors

    private static func rgb(_ hex: UInt32) -> UIColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        return UIColor(red: red, green: green, blue: blue, alpha: 1.0)
    }

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        let darkColor = Theme.rgb(dark)
        let lightColor = Theme.rgb(light)
        return Color(uiColor: UIColor { traits in
            return traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }

    /// Page background: black in dark mode, white in light mode.
    static let bg: Color = Theme.dynamic(dark: 0x000000, light: 0xFFFFFF)
    /// Ink and rules: white in dark mode, black in light mode.
    static let fg: Color = Theme.dynamic(dark: 0xFFFFFF, light: 0x000000)
    /// Secondary text and dashed rules.
    static let dim: Color = Theme.dynamic(dark: 0x7D7D7D, light: 0x666666)
    /// Electric blue. Fills only, never text on `bg`.
    static let signal: Color = Color(uiColor: Theme.rgb(0x0A3CFF))
    /// Text on a `signal` or `plan` fill.
    static let onSignal: Color = Color(uiColor: Theme.rgb(0xFFFFFF))
    /// "Plan" purple: scheduled, from the plan. Fills only, never text on `bg`. Blue keeps meaning
    /// "on target right now".
    static let plan: Color = Color(uiColor: Theme.rgb(0x8B1EFF))

    // MARK: Type

    static let fontName = "DepartureMono-Regular"

    /// Departure Mono is drawn on an 11-unit grid, so sizes are multiples of 11.
    enum Size: CGFloat {
        case micro = 11.0
        case body = 22.0
        case title = 33.0
        case display = 44.0
        case hero = 99.0
        case giant = 132.0
    }

    static func mono(_ size: Size) -> Font {
        return Font.custom(Theme.fontName, fixedSize: size.rawValue)
    }

    // MARK: Space and lines

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 16
    static let s4: CGFloat = 24
    /// Solid foreground rule and border width.
    static let rule: CGFloat = 2
    /// Dim dashed row separator.
    static let dash = StrokeStyle(lineWidth: 1, dash: [3, 3])
}

extension DisplayMode {
    /// nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// Base look for a full screen: background, mono type, foreground ink and the blue tint.
struct InstrumentScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.mono(.body))
            .foregroundStyle(Theme.fg)
            .tint(Theme.signal)
            .background(Theme.bg.ignoresSafeArea())
    }
}

extension View {
    func instrumentScreen() -> some View {
        return modifier(InstrumentScreen())
    }
}
