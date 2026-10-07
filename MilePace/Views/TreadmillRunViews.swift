import SwiftUI

/// The big clock of a treadmill run: there is no pace without GPS, so time is the hero.
struct TreadmillTimeHero: View {
    let elapsed: Double

    var body: some View {
        HeroReadout(label: "time", value: formatDuration(elapsed), unit: "", size: .giant)
            .padding(.horizontal, Theme.s3)
            .padding(.top, Theme.s3)
            .padding(.bottom, Theme.s2)
    }
}

/// "pedometer ... ≈ 2.31 mi" while the phone's pedometer gives a distance; nothing otherwise.
struct TreadmillPedometerRow: View {
    let meters: Double?

    var body: some View {
        if let meters = meters {
            ReadoutRow(key: "pedometer", value: "\u{2248} " + formatMiles(meters) + " mi")
        }
    }
}

/// "treadmill distance (mi)" on the run summary: the runner types what the treadmill shows.
struct TreadmillDistanceEntry: View {
    @Binding var text: String
    /// Average pace for the typed distance, "--:--" until there is one.
    let averagePaceText: String
    /// Whether the field still needs a value; shows the hint.
    let needsValue: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("treadmill distance")
            FieldRow(key: "miles",
                     placeholder: "0.00",
                     text: $text,
                     note: needsValue ? "type the distance from the treadmill display to save." : nil,
                     keyboard: .decimalPad)
            ReadoutRow(key: "avg /mi", value: averagePaceText)
        }
    }
}

/// The distance field on the unfinished-run card, drawn for the inverted (black on white) card.
struct TreadmillDraftField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text("treadmill distance (mi)")
                .font(Theme.mono(.micro))
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .font(Theme.mono(.body))
                .tint(Theme.bg)
                .foregroundStyle(Theme.bg)
                .padding(Theme.s2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .overlay(Rectangle().strokeBorder(Theme.bg, lineWidth: Theme.rule))
        }
    }
}
