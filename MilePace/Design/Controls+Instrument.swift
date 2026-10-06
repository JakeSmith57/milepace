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

/// A bracket button that fires only after a short hold, for mid-run actions a stray tap must not trigger
/// (skipping a rep or a rest). The label dims while it is pressed.
struct HoldBracketButton: View {
    let title: String
    var style: BracketStyle = .plain
    var minHeight: CGFloat = 56
    var duration: Double = 0.6
    let action: () -> Void

    @State private var pressing = false

    var body: some View {
        BracketLabel(title: title, style: style, minHeight: minHeight)
            .opacity(pressing ? 0.5 : 1)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: duration,
                                maximumDistance: 40,
                                perform: {
                                    pressing = false
                                    action()
                                },
                                onPressingChanged: { isPressing in
                                    pressing = isPressing
                                })
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
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

// MARK: - Screens

/// The five screens. Today is home; the others are opened from it with `PlanStore.open(_:)` and left
/// with `PlanStore.goHome()`.
enum AppTab: String, CaseIterable, Identifiable {
    case today
    case run
    case track
    case log
    case set

    var id: String { rawValue }
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
            // Label and control side by side; stacked (label above) when the row is too narrow, such
            // as on a 320 pt wide screen.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.s2) {
                    label
                    Spacer(minLength: 0)
                    controls
                }
                VStack(alignment: .leading, spacing: 0) {
                    label
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        controls
                    }
                }
            }
            .padding(.vertical, 2)
            if ruled {
                DashedRule()
            }
        }
    }

    private var label: some View {
        Text(ReadoutFormat.leader(title, width: keyWidth))
            .font(Theme.mono(.body))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .fixedSize()
    }

    private var controls: some View {
        HStack(spacing: Theme.s2) {
            stepButton("[\u{2212}]", delta: -step, hint: "decrease")
            Text(format(value))
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 70)
            stepButton("[+]", delta: step, hint: "increase")
        }
    }

    private func stepButton(_ label: String, delta: Int, hint: String) -> some View {
        return Button {
            adjust(by: delta)
        } label: {
            Text(label)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .frame(minWidth: 44, minHeight: 44)
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
    /// Called when the runner submits the field or leaves it, not on every keystroke.
    var onCommit: (() -> Void)? = nil

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Side by side; the field goes under the key when the row is too narrow for both.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.s2) {
                    keyText
                    Spacer(minLength: 0)
                    field
                        .frame(width: fieldWidth)
                }
                VStack(alignment: .leading, spacing: Theme.s1) {
                    keyText
                    field
                        .frame(maxWidth: .infinity)
                }
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

    private var keyText: some View {
        Text(ReadoutFormat.leader(key, width: 10))
            .font(Theme.mono(.body))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .fixedSize()
    }

    private var field: some View {
        TextField(placeholder, text: $text)
            .font(Theme.mono(.body))
            .keyboardType(keyboard)
            .multilineTextAlignment(.trailing)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .tint(Theme.fg)
            .foregroundStyle(Theme.fg)
            .focused($focused)
            .onSubmit {
                onCommit?()
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused {
                    onCommit?()
                }
            }
            .padding(.horizontal, Theme.s2)
            .frame(height: 44)
            .overlay(Rectangle().strokeBorder(Theme.fg, lineWidth: Theme.rule))
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
