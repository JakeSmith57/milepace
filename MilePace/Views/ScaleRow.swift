import SwiftUI

/// A row of small numbers to tap: "effort ... 7" over 1 2 3 ... 10. The chosen number is inverted; tapping it
/// again clears it back to `unsetValue`.
struct ScaleRow: View {
    let title: String
    let range: ClosedRange<Int>
    @Binding var selection: Int
    /// The value that means "not set" (0 for effort, -1 for foot pain).
    let unsetValue: Int
    /// Shown instead of the number when the chosen value is 0, such as "none".
    let zeroLabel: String?

    init(title: String,
         range: ClosedRange<Int>,
         selection: Binding<Int>,
         unsetValue: Int,
         zeroLabel: String? = nil) {
        self.title = title
        self.range = range
        self._selection = selection
        self.unsetValue = unsetValue
        self.zeroLabel = zeroLabel
    }

    private var valueText: String {
        if selection == unsetValue || !range.contains(selection) {
            return "--"
        }
        if selection == 0, let label = zeroLabel {
            return "0 " + label
        }
        return String(selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                Text(title)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
            }
            .padding(.top, Theme.s2)
            HStack(spacing: 2) {
                ForEach(Array(range), id: \.self) { value in
                    cell(value)
                }
            }
            .padding(.bottom, Theme.s2)
            DashedRule()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ value: Int) -> some View {
        let selected = value == selection
        return Button {
            selection = selected ? unsetValue : value
        } label: {
            Text(String(value))
                .font(Theme.mono(.micro))
                .foregroundStyle(selected ? Theme.bg : Theme.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Theme.fg : Theme.bg)
                .overlay(Rectangle().strokeBorder(Theme.dim, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(InstrumentButtonStyle())
        .accessibilityLabel(title + " " + String(value))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The two optional after-run questions, effort and foot pain, with the foot advice under them when the pain
/// is 4 or more. Used on the run summary, the track results and both log detail screens.
struct EffortFootRows: View {
    @Binding var effort: Int
    @Binding var footPain: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScaleRow(title: "effort",
                     range: 1...10,
                     selection: $effort,
                     unsetValue: 0)
            ScaleRow(title: "big toe / foot pain",
                     range: 0...10,
                     selection: $footPain,
                     unsetValue: -1,
                     zeroLabel: "none")
            if footPain >= FootCheck.warnAt {
                Text(FootCheck.advice)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.s2)
            }
        }
    }
}
