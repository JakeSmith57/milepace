import SwiftUI

/// Completed reps of a track workout as a tape: rep time and delta versus target, lap splits
/// under each rep, then the average.
struct WorkoutResultsTable: View {
    let spec: WorkoutSpec
    let repTimes: [Double]
    let lapSplits: [[Double]]
    /// One-based rep numbers that GPS ended; they carry a small "gps" tag.
    var autoEnded: [Int] = []

    private func lapLine(forRep index: Int) -> String {
        guard index < lapSplits.count else { return "" }
        return lapSplits[index].map { formatSplit($0) }.joined(separator: " \u{00B7} ")
    }

    private func repRow(_ index: Int, _ time: Double) -> TapeRow {
        let delta = time - spec.targetRepSeconds
        return TapeRow(id: index + 1,
                       key: autoEnded.contains(index + 1) ? "\(index + 1) gps" : "\(index + 1)",
                       value: formatSplit(time),
                       note: ReadoutFormat.signedDelta(delta))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if repTimes.isEmpty {
                Text("no reps completed.")
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.dim)
                    .padding(.vertical, Theme.s2)
            } else {
                repList
                summary
            }
        }
    }

    private var repList: some View {
        VStack(alignment: .leading, spacing: 0) {
            TrackMicroLine("rep \u{00B7} time \u{00B7} target \u{00B7} \u{00B1}")
                .padding(.top, Theme.s2)
            TrackMicroLine(TrackLaps.targetText(seconds: spec.targetRepSeconds, meters: spec.repDistance)
                           + ". \u{00B1} is seconds against the target.")
                .padding(.bottom, Theme.s1)
            ForEach(Array(repTimes.enumerated()), id: \.offset) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Tape(rows: [repRow(item.offset, item.element)])
                    if spec.lapsPerRep > 1 {
                        Text(lapLine(forRep: item.offset))
                            .font(Theme.mono(.micro))
                            .foregroundStyle(Theme.dim)
                            .padding(.bottom, Theme.s1)
                    }
                    DashedRule()
                }
            }
        }
    }

    private var summary: some View {
        let average = repTimes.reduce(0, +) / Double(repTimes.count)
        let averageDelta = average - spec.targetRepSeconds
        return VStack(alignment: .leading, spacing: Theme.s2) {
            SectionHeader("average")
            ReadoutRow(key: "avg", value: formatSplit(average))
            ReadoutRow(key: "target", value: formatSplit(spec.targetRepSeconds))
            DeltaChip(delta: averageDelta)
                .padding(.top, Theme.s2)
        }
    }
}
