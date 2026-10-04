import SwiftUI
import UIKit

extension Font {
    /// Large rounded digits with fixed-width numerals so clocks do not jitter.
    static func roundedDigits(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        return Font.system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension SplitVerdict {
    /// Green for fast or on pace, red for slow.
    var color: Color {
        switch self {
        case .fast, .onPace: return .green
        case .slow: return .red
        }
    }
}

/// Large labelled number used on the run and track screens.
struct BigMetricTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var valueSize: CGFloat = 56
    var valueColor: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.roundedDigits(valueSize))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Full-width filled button.
struct FilledActionButton: View {
    let title: String
    var color: Color = .orange
    var height: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(color, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// Button that only fires after being held for one second, so pocket taps cannot end a run.
struct HoldToEndButton: View {
    static let holdDuration: Double = 1.0

    let title: String
    let action: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            Color.red.opacity(0.25)
            GeometryReader { proxy in
                Color.red
                    .frame(width: proxy.size.width * progress)
            }
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: HoldToEndButton.holdDuration,
                            maximumDistance: 60,
                            perform: {
                                progress = 0
                                action()
                            },
                            onPressingChanged: { pressing in
                                if pressing {
                                    withAnimation(.linear(duration: HoldToEndButton.holdDuration)) {
                                        progress = 1
                                    }
                                } else {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        progress = 0
                                    }
                                }
                            })
    }
}

/// Table of completed reps: lap splits, rep time and delta versus target.
struct WorkoutResultsTable: View {
    let spec: WorkoutSpec
    let repTimes: [Double]
    let lapSplits: [[Double]]

    private func deltaColor(_ delta: Double) -> Color {
        return SplitVerdict.verdict(delta: delta).color
    }

    private func lapLine(forRep index: Int) -> String {
        guard index < lapSplits.count else { return "" }
        return lapSplits[index].map { formatSplit($0) }.joined(separator: "  ·  ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if repTimes.isEmpty {
                Text("No reps completed.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(repTimes.enumerated()), id: \.offset) { item in
                let delta = item.element - spec.targetRepSeconds
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Rep \(item.offset + 1)")
                            .font(.headline)
                        Spacer()
                        Text(formatSplit(item.element))
                            .font(.roundedDigits(20, weight: .semibold))
                        Text(formatDelta(delta))
                            .font(.roundedDigits(17, weight: .semibold))
                            .foregroundStyle(deltaColor(delta))
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                    if spec.lapsPerRep > 1 {
                        Text(lapLine(forRep: item.offset))
                            .font(.system(.footnote, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
            if !repTimes.isEmpty {
                let average = repTimes.reduce(0, +) / Double(repTimes.count)
                let averageDelta = average - spec.targetRepSeconds
                HStack {
                    Text("Average")
                        .font(.headline)
                    Spacer()
                    Text(formatSplit(average))
                        .font(.roundedDigits(20, weight: .semibold))
                    Text(formatDelta(averageDelta))
                        .font(.roundedDigits(17, weight: .semibold))
                        .foregroundStyle(deltaColor(averageDelta))
                        .frame(minWidth: 56, alignment: .trailing)
                }
                Text("Target \(formatSplit(spec.targetRepSeconds)) per rep")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
