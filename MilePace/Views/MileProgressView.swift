import SwiftUI
import Charts

/// The "mile" block at the top of Log: the progress chart, the readout line and the bests list.
///
/// The y axis is mile time with the faster times at the top. Swift Charts' `.automatic(reversed:)` domain
/// cannot take explicit bounds, so the marks plot negative seconds (-392 for 6:32) over a domain of
/// -slowest...-fastest, and the axis labels print the absolute value. Larger numbers (slower) sit lower.
struct MileProgressView: View {
    let snapshot: MileSnapshot

    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("mile")
            chart
                .frame(height: 180)
                .padding(.top, Theme.s3)
            legend
            emptyNote
            Text(MileProgress.summaryLine(latest: snapshot.latest, goal: snapshot.goal))
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
                .padding(.top, Theme.s2)
            bestsList
        }
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            goalRule
            planMarks
            resultMarks
            gpsMarks
        }
        .chartYScale(domain: (-snapshot.yDomain.upperBound)...(-snapshot.yDomain.lowerBound))
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        axisText(MileProgressView.axisDateFormatter.string(from: date).lowercased())
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let negative = value.as(Double.self) {
                        axisText(formatDuration(-negative))
                    }
                }
            }
        }
    }

    private func axisText(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.dim)
    }

    @ChartContentBuilder
    private var goalRule: some ChartContent {
        RuleMark(y: .value("Goal", -snapshot.goal))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .foregroundStyle(Theme.fg)
            .annotation(position: .top, alignment: .leading, spacing: 2) {
                Text("goal " + formatDuration(snapshot.goal))
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
            }
    }

    /// The plan's time trial and race targets: a thin dashed line with small hollow points.
    @ChartContentBuilder
    private var planMarks: some ChartContent {
        ForEach(Array(snapshot.plan.enumerated()), id: \.offset) { item in
            LineMark(x: .value("Date", item.element.date),
                     y: .value("Mile", -item.element.seconds),
                     series: .value("Series", "plan"))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Theme.dim)
            PointMark(x: .value("Date", item.element.date),
                      y: .value("Mile", -item.element.seconds))
                .symbol {
                    Circle()
                        .strokeBorder(Theme.dim, lineWidth: 1)
                        .frame(width: 7, height: 7)
                }
        }
    }

    /// Track time trials and races: filled blue points joined by a line. The only blue on the chart.
    @ChartContentBuilder
    private var resultMarks: some ChartContent {
        ForEach(Array(snapshot.results.enumerated()), id: \.offset) { item in
            LineMark(x: .value("Date", item.element.date),
                     y: .value("Mile", -item.element.seconds),
                     series: .value("Series", "result"))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Theme.signal)
            PointMark(x: .value("Date", item.element.date),
                      y: .value("Mile", -item.element.seconds))
                .symbol {
                    Circle()
                        .fill(Theme.signal)
                        .frame(width: 9, height: 9)
                }
        }
    }

    /// A run's fastest mile that is close to the track results: small hollow squares.
    @ChartContentBuilder
    private var gpsMarks: some ChartContent {
        ForEach(Array(snapshot.gpsPoints.enumerated()), id: \.offset) { item in
            PointMark(x: .value("Date", item.element.date),
                      y: .value("Mile", -item.element.seconds))
                .symbol {
                    Rectangle()
                        .strokeBorder(Theme.fg, lineWidth: 1)
                        .frame(width: 6, height: 6)
                }
        }
    }

    // MARK: Notes

    private var legend: some View {
        Text("\u{25CF} track mile   \u{25CB} plan   \u{25A1} fastest mile in a run")
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.top, Theme.s1)
    }

    @ViewBuilder
    private var emptyNote: some View {
        if snapshot.results.isEmpty {
            Text(emptyText)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .padding(.top, Theme.s2)
        }
    }

    private var emptyText: String {
        guard let first = nextTrial else { return "no track mile yet." }
        return "first time trial: " + ReadoutFormat.day(first.date)
    }

    /// The next planned time trial or race, else the first one in the plan.
    private var nextTrial: PlanMilePoint? {
        let today = Calendar.current.startOfDay(for: Date())
        return snapshot.plan.first(where: { $0.date >= today }) ?? snapshot.plan.first
    }

    // MARK: Bests

    private var bestsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("bests")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .padding(.top, Theme.s3)
            ForEach(MileProgress.bestDistances, id: \.self) { distance in
                bestRow(distance)
            }
        }
    }

    private func bestRow(_ distance: Double) -> some View {
        let best = snapshot.bests.first(where: { $0.distance == distance })
        let value: String
        if let best = best {
            value = MileProgress.timeText(best.seconds, distance: distance) + "  " + ReadoutFormat.day(best.date)
        } else {
            value = "\u{2014}"
        }
        return ReadoutRow(key: MileProgress.distanceLabel(distance), value: value, size: .micro, keyWidth: 8)
    }
}
