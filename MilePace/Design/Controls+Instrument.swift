import SwiftUI
import UIKit

// MARK: - Buttons

/// Press feedback without any system chrome.
struct InstrumentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

enum BracketStyle {
    /// 2 pt foreground border.
    case plain
    /// Signal fill, onSignal text, no border.
    case signal
    /// Foreground fill, background text.
    case inverted
    /// Plan purple fill, onSignal text, no border.
    case plan
    /// Transparent with a 2 pt background-colored border and text, for use on a foreground fill.
    case outlineOnInverted
}

/// The look of a bracket button, shared by `BracketButton` and share links.
struct BracketLabel: View {
    let title: String
    var style: BracketStyle = .plain
    var minHeight: CGFloat = 56
    var fullWidth: Bool = true
    var size: Theme.Size = .body

    private var textColor: Color {
        switch style {
        case .plain: return Theme.fg
        case .signal: return Theme.onSignal
        case .inverted: return Theme.bg
        case .plan: return Theme.onSignal
        case .outlineOnInverted: return Theme.bg
        }
    }

    private var fillColor: Color {
        switch style {
        case .plain: return Theme.bg
        case .signal: return Theme.signal
        case .inverted: return Theme.fg
        case .plan: return Theme.plan
        case .outlineOnInverted: return Color.clear
        }
    }

    private var maxWidth: CGFloat? {
        return fullWidth ? CGFloat.infinity : nil
    }

    var body: some View {
        Text("[ \(title) ]")
            .font(Theme.mono(size))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, Theme.s3)
            .frame(maxWidth: maxWidth, minHeight: minHeight)
            .background(fillColor)
            .overlay(border)
    }

    private var borderColor: Color? {
        switch style {
        case .plain: return Theme.fg
        case .outlineOnInverted: return Theme.bg
        case .signal, .inverted, .plan: return nil
        }
    }

    @ViewBuilder
    private var border: some View {
        if let color = borderColor {
            Rectangle()
                .strokeBorder(color, lineWidth: Theme.rule)
        }
    }
}

/// "[ title ]" button. Brackets mean tappable.
struct BracketButton: View {
    let title: String
    var style: BracketStyle = .plain
    var minHeight: CGFloat = 56
    var fullWidth: Bool = true
    var size: Theme.Size = .body
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            BracketLabel(title: title,
                         style: style,
                         minHeight: minHeight,
                         fullWidth: fullWidth,
                         size: size)
        }
        .buttonStyle(InstrumentButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// Bordered row that only fires after being held, so pocket taps cannot end a run. A ten-cell gauge
/// fills from "." to "#" while pressed.
struct HoldBar: View {
    let title: String
    let duration: Double
    let action: () -> Void

    @State private var pressStart: Date? = nil

    private static let gaugeCells = 10

    init(title: String, duration: Double = 1.0, action: @escaping () -> Void) {
        self.title = title
        self.duration = duration
        self.action = action
    }

    private func progress(at date: Date) -> Double {
        guard let start = pressStart, duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }

    var body: some View {
        HStack(spacing: Theme.s3) {
            Text(title)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
            Spacer(minLength: 0)
            TimelineView(.animation(minimumInterval: 0.05, paused: pressStart == nil)) { context in
                gauge(progress: progress(at: context.date))
            }
        }
        .padding(.horizontal, Theme.s3)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Theme.bg)
        .overlay(Rectangle().strokeBorder(Theme.fg, lineWidth: Theme.rule))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: duration,
                            maximumDistance: 60,
                            perform: {
                                pressStart = nil
                                action()
                            },
                            onPressingChanged: { pressing in
                                pressStart = pressing ? Date() : nil
                            })
        .accessibilityLabel(title)
    }

    private func gauge(progress: Double) -> some View {
        let total = HoldBar.gaugeCells
        let filled = min(total, max(0, Int((progress * Double(total)).rounded(.down))))
        return HStack(spacing: 0) {
            Text(String(repeating: "#", count: filled))
                .foregroundStyle(Theme.fg)
            Text(String(repeating: ".", count: total - filled))
                .foregroundStyle(Theme.dim)
        }
        .font(Theme.mono(.body))
    }
}

// MARK: - Tab strip

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case run
    case track
    case log
    case set

    var id: String { rawValue }
}

/// Bottom bar: five equal text cells under a 2 pt rule; the selected cell is inverted.
struct TabStrip: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            SolidRule()
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        cell(tab)
                    }
                    .buttonStyle(InstrumentButtonStyle())
                }
            }
        }
        .background(Theme.bg.ignoresSafeArea(edges: .bottom))
    }

    private func cell(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Text(tab.rawValue)
            .font(Theme.mono(.body))
            .foregroundStyle(selected ? Theme.bg : Theme.fg)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(selected ? Theme.fg : Theme.bg)
    }
}

// MARK: - Settings-style rows

/// "[x] title" / "[ ] title". Tap toggles. Replaces Toggle.
struct CheckRow: View {
    let title: String
    @Binding var isOn: Bool
    var ruled: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                isOn.toggle()
            } label: {
                HStack(spacing: 0) {
                    Text((isOn ? "[x] " : "[ ] ") + title)
                        .font(Theme.mono(.body))
                        .foregroundStyle(Theme.fg)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Theme.s2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(InstrumentButtonStyle())
            if ruled {
                DashedRule()
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One option of a `ChoiceRow`.
struct Choice<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }

    init(_ value: Value, _ title: String) {
        self.value = value
        self.title = title
    }
}

/// Options laid out inline; the selected one is inverted. Replaces segmented pickers.
struct ChoiceRow<Value: Hashable>: View {
    let label: String?
    let options: [Choice<Value>]
    @Binding var selection: Value
    let ruled: Bool

    init(label: String? = nil, options: [Choice<Value>], selection: Binding<Value>, ruled: Bool = true) {
        self.label = label
        self.options = options
        self._selection = selection
        self.ruled = ruled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = label {
                Text(label)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, Theme.s2)
            }
            HStack(spacing: Theme.s1) {
                ForEach(options) { option in
                    optionButton(option)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Theme.s2)
            if ruled {
                DashedRule()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionButton(_ option: Choice<Value>) -> some View {
        let selected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(Theme.mono(.body))
                .foregroundStyle(selected ? Theme.bg : Theme.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(selected ? Theme.fg : Theme.bg)
                .contentShape(Rectangle())
        }
        .buttonStyle(InstrumentButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "cadence ....  [-] 166 [+]" with whole-number steps.
struct StepperRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let format: (Int) -> String
    let keyWidth: Int
    let ruled: Bool

    init(title: String,
         value: Binding<Int>,
         range: ClosedRange<Int>,
         step: Int = 1,
         format: @escaping (Int) -> String = { "\($0)" },
         keyWidth: Int = 10,
         ruled: Bool = true) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.format = format
        self.keyWidth = keyWidth
        self.ruled = ruled
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.s2) {
                Text(ReadoutFormat.leader(title, width: keyWidth))
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                stepButton("[\u{2212}]", delta: -step, hint: "decrease")
                Text(format(value))
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 70)
                stepButton("[+]", delta: step, hint: "increase")
            }
            .padding(.vertical, 2)
            if ruled {
                DashedRule()
            }
        }
    }

    private func stepButton(_ label: String, delta: Int, hint: String) -> some View {
        return Button {
            adjust(by: delta)
        } label: {
            Text(label)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(InstrumentButtonStyle())
        .accessibilityLabel(title + " " + hint)
    }

    private func adjust(by delta: Int) {
        let next = value + delta
        value = min(range.upperBound, max(range.lowerBound, next))
    }
}

// MARK: - Text fields

/// "key ....  [ field ]": a dotted key and a bordered text box for short values.
struct FieldRow: View {
    let key: String
    let placeholder: String
    @Binding var text: String
    var note: String? = nil
    var keyboard: UIKeyboardType = .numbersAndPunctuation
    var fieldWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.s2) {
                Text(ReadoutFormat.leader(key, width: 10))
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                TextField(placeholder, text: $text)
                    .font(Theme.mono(.body))
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tint(Theme.fg)
                    .foregroundStyle(Theme.fg)
                    .padding(.horizontal, Theme.s2)
                    .frame(width: fieldWidth, height: 44)
                    .overlay(Rectangle().strokeBorder(Theme.fg, lineWidth: Theme.rule))
            }
            .padding(.vertical, Theme.s1)
            if let note = note {
                Text(note)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
                    .padding(.bottom, Theme.s1)
            }
            DashedRule()
        }
    }
}

/// A bordered multi-line text box.
struct BoxedField: View {
    let placeholder: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 1...4

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(Theme.mono(.body))
            .lineLimit(lines)
            .tint(Theme.fg)
            .foregroundStyle(Theme.fg)
            .padding(Theme.s2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .overlay(Rectangle().strokeBorder(Theme.fg, lineWidth: Theme.rule))
    }
}
