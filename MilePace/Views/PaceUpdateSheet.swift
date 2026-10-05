import SwiftUI

/// A mile time trial result that could replace the current mile time.
struct PaceOffer: Identifiable, Equatable {
    let id = UUID()
    /// Whole seconds.
    let seconds: Double
}

/// Shown after a mile time trial is saved: offer to retune the training paces to the new time.
struct PaceUpdateSheet: View {
    let offer: PaceOffer
    let currentSeconds: Double
    let onUpdate: () -> Void
    let onKeep: () -> Void
    /// A test week trial: the paces are left alone and the only choice is "ok".
    var practice: Bool = false

    private var oldText: String {
        return formatPace(secondsPerMile: currentSeconds)
    }

    private var newText: String {
        return formatPace(secondsPerMile: offer.seconds)
    }

    private var practiceChoices: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text("practice: paces not changed")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
            BracketButton(title: "ok", style: .signal, minHeight: 72) {
                onKeep()
            }
        }
    }

    private var realChoices: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text("update training paces from " + oldText + " to " + newText + "?")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
            BracketButton(title: "update paces", style: .signal, minHeight: 72) {
                onUpdate()
            }
            BracketButton(title: "keep " + oldText) {
                onKeep()
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "time trial", right: "", tag: practice ? "test" : "")
            VStack(alignment: .leading, spacing: Theme.s3) {
                HeroReadout(label: "mile", value: newText, size: .hero)
                    .padding(.top, Theme.s3)
                if practice {
                    practiceChoices
                } else {
                    realChoices
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.s3)
        }
        .instrumentScreen()
        .interactiveDismissDisabled()
    }
}
