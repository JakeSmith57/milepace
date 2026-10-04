import SwiftUI

// MARK: - Rules

/// A horizontal line through the middle of its frame, for dashed strokes.
struct HLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// Solid 2 pt foreground rule: a section boundary.
struct SolidRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.fg)
            .frame(height: Theme.rule)
    }
}

/// Dashed dim rule: a row boundary in a readout.
struct DashedRule: View {
    var color: Color = Theme.dim

    var body: some View {
        HLine()
            .stroke(color, style: Theme.dash)
            .frame(height: 1)
    }
}

// MARK: - Status line

/// A small tappable word shown next to the left text of the status line, such as "[ diag ]".
struct StatusAccessory {
    let title: String
    let action: () -> Void
}

/// Block cursor that blinks while searching. Static when Reduce Motion is on.
struct BlinkingCursor: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            block(visible: true)
        } else {
            TimelineView(.periodic(from: Date(), by: 0.5)) { context in
                block(visible: isOn(at: context.date))
            }
        }
    }

    private func isOn(at date: Date) -> Bool {
        let beat = Int(date.timeIntervalSinceReferenceDate * 2)
        return beat % 2 == 0
    }

    private func block(visible: Bool) -> some View {
        Text("\u{2588}")
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.fg)
            .opacity(visible ? 1 : 0)
    }
}

/// One line of micro text under the safe area with a 2 pt rule below it.
struct StatusLine: View {
    let left: String
    let center: String
    let right: String
    var recording: Bool = false
    /// Shows a blinking block cursor after the center text.
    var searching: Bool = false
    var accessory: StatusAccessory? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leftGroup
                    .frame(maxWidth: .infinity, alignment: .leading)
                centerGroup
                    .frame(maxWidth: .infinity, alignment: .center)
                rightGroup
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, Theme.s3)
            .frame(minHeight: 36)
            SolidRule()
        }
    }

    private func micro(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.fg)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var leftGroup: some View {
        HStack(spacing: Theme.s2) {
            micro(left)
            if let accessory = accessory {
                Button(action: accessory.action) {
                    Text("[ \(accessory.title) ]")
                        .font(Theme.mono(.micro))
                        .foregroundStyle(Theme.fg)
                        .lineLimit(1)
                        .padding(.vertical, Theme.s2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(InstrumentButtonStyle())
            }
        }
    }

    private var centerGroup: some View {
        HStack(spacing: 2) {
            micro(center)
            if searching {
                BlinkingCursor()
            }
        }
    }

    @ViewBuilder
    private var rightGroup: some View {
        if recording {
            HStack(spacing: Theme.s2) {
                Text("rec")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.onSignal)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.signal)
                micro(right)
            }
        } else {
            micro(right)
        }
    }
}

// MARK: - Banner

/// Signal-filled band with onSignal text: the active workout, rep or lap.
struct Banner: View {
    let title: String
    var subtitle: String = ""
    var trailing: String = ""
    var trailingSub: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: Theme.s3) {
            VStack(alignment: .leading, spacing: 0) {
                line(title, size: .body)
                if !subtitle.isEmpty {
                    line(subtitle, size: .micro)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                line(trailing, size: .body)
                if !trailingSub.isEmpty {
                    line(trailingSub, size: .micro)
                }
            }
        }
        .foregroundStyle(Theme.onSignal)
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
        .frame(maxWidth: .infinity)
        .background(Theme.signal)
    }

    private func line(_ text: String, size: Theme.Size) -> some View {
        Text(text)
            .font(Theme.mono(size))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

// MARK: - Hero readout

/// A small dim label over one very large value, with an optional unit on the baseline.
struct HeroReadout: View {
    let label: String
    let value: String
    var unit: String = ""
    var size: Theme.Size = .giant

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
            HStack(alignment: .lastTextBaseline, spacing: Theme.s1) {
                Text(value)
                    .font(Theme.mono(size))
                    .tracking(-4)
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .layoutPriority(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.mono(.body))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pace meter

/// Eight cells: the middle two (3 and 4) are the target zone in signal blue, a block marks where
/// the current pace sits, and dots fill the rest. Faster is to the left, slower to the right.
struct PaceMeter: View {
    let pace: Double?
    let zone: ClosedRange<Double>?

    private var activeCell: Int? {
        guard let zone = zone, let pace = pace, pace.isFinite else { return nil }
        return PaceMeterModel.cell(pace: pace, zone: zone)
    }

    var body: some View {
        if zone != nil {
            VStack(spacing: Theme.s1) {
                HStack(spacing: 0) {
                    ForEach(0..<PaceMeterModel.defaultCells, id: \.self) { index in
                        cell(index)
                    }
                }
                HStack(spacing: 0) {
                    caption("faster")
                    Spacer(minLength: 0)
                    caption("on target")
                    Spacer(minLength: 0)
                    caption("slower")
                }
            }
            // Keeps its space but disappears until there is a pace to show.
            .opacity(activeCell == nil ? 0 : 1)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.dim)
    }

    private func cell(_ index: Int) -> some View {
        let inZone = PaceMeterModel.zoneCells().contains(index)
        let isActive = activeCell == index
        return ZStack {
            if inZone {
                Rectangle().fill(Theme.signal)
            } else {
                Text("\u{00B7}")
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.dim)
            }
            if isActive {
                Rectangle()
                    .fill(Theme.fg)
                    .frame(width: 10, height: 28)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
    }
}

// MARK: - Readout rows

/// "key ........   value" with a dashed rule below. The key is dim, padded with dot leaders to a
/// fixed width, and the value is right-aligned. `selected` inverts the row. With `leaders` off the
/// key is plain foreground text that may wrap to two lines (for long names).
struct ReadoutRow: View {
    let key: String
    let value: String
    var size: Theme.Size = .body
    var keyWidth: Int = 12
    var selected: Bool = false
    var ruled: Bool = true
    var leaders: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                keyText
                Spacer(minLength: 0)
                Text(value)
                    .foregroundStyle(selected ? Theme.bg : Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .layoutPriority(leaders ? 0 : 1)
            }
            .font(Theme.mono(size))
            .padding(.vertical, size == .micro ? 3 : Theme.s2)
            .padding(.horizontal, selected ? Theme.s2 : 0)
            .background(selected ? Theme.fg : Color.clear)
            if ruled {
                DashedRule()
            }
        }
    }

    @ViewBuilder
    private var keyText: some View {
        if leaders {
            Text(ReadoutFormat.leader(key, width: keyWidth))
                .foregroundStyle(selected ? Theme.bg : Theme.dim)
                .lineLimit(1)
                .fixedSize()
        } else {
            Text(key)
                .foregroundStyle(selected ? Theme.bg : Theme.fg)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Delta chip

/// Split verdict at display size: signal fill when on pace, an inverted block with words otherwise.
struct DeltaChip: View {
    let delta: Double

    private var isOnPace: Bool {
        return SplitVerdict.verdict(delta: delta) == .onPace
    }

    var body: some View {
        Text(ReadoutFormat.deltaWords(delta))
            .font(Theme.mono(.display))
            .foregroundStyle(isOnPace ? Theme.onSignal : Theme.bg)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2)
            .background(isOnPace ? Theme.signal : Theme.fg)
    }
}

// MARK: - Tape

struct TapeRow: Identifiable, Equatable {
    let id: Int
    let key: String
    let value: String
    var note: String = ""
}

/// A split list like a printout ("n ......  97.4 -0.6"), newest last, with a dashed tear line
/// at the bottom while it is live.
struct Tape: View {
    let rows: [TapeRow]
    var live: Bool = false
    var keyWidth: Int = 8
    /// Shows only the newest rows when set.
    var maxRows: Int? = nil

    private var visibleRows: [TapeRow] {
        guard let limit = maxRows, rows.count > limit else { return rows }
        return Array(rows.suffix(limit))
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(visibleRows) { row in
                rowView(row)
            }
            if live {
                HLine()
                    .stroke(Theme.fg, style: Theme.dash)
                    .frame(height: 1)
                    .padding(.top, Theme.s2)
            }
        }
    }

    private func rowView(_ row: TapeRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
            Text(ReadoutFormat.leader(row.key, width: keyWidth))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            Text(row.value)
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
            Text(row.note)
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
                .frame(width: 84, alignment: .trailing)
        }
        .font(Theme.mono(.body))
        .padding(.vertical, Theme.s1)
    }
}

// MARK: - Section header

/// Body-size heading with a solid 2 pt rule below.
struct SectionHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text(text)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
            SolidRule()
        }
        .padding(.top, Theme.s4)
    }
}
