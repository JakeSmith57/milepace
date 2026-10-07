import SwiftUI

/// One routine as a follow-along checklist. Shown as a sheet. The checks live only in this view's state
/// and reset when the sheet closes.
@MainActor
struct RoutineDetailView: View {
    let routine: Routine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var checked: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace",
                       center: routine.title,
                       right: "",
                       accessory: StatusAccessory(title: "close", action: { dismiss() }))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s3) {
                    intro
                    ForEach(routine.exercises) { exercise in
                        RoutineExerciseBlock(exercise: exercise,
                                             isChecked: checked.contains(exercise.name),
                                             onToggle: { toggle(exercise) },
                                             onOpen: { url in openURL(url) })
                    }
                    resetButton
                }
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, Theme.s3)
            }
        }
        .instrumentScreen()
    }

    private var intro: some View {
        return VStack(alignment: .leading, spacing: Theme.s2) {
            Text(routine.when)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
            Text(routine.why)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var resetButton: some View {
        if !checked.isEmpty {
            BracketButton(title: "reset") {
                checked.removeAll()
            }
        }
    }

    private func toggle(_ exercise: RoutineExercise) {
        if checked.contains(exercise.name) {
            checked.remove(exercise.name)
        } else {
            checked.insert(exercise.name)
        }
    }
}

/// One exercise: tap the name row to check it off; the video button opens the link.
private struct RoutineExerciseBlock: View {
    let exercise: RoutineExercise
    let isChecked: Bool
    let onToggle: () -> Void
    let onOpen: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Button(action: onToggle) {
                titleRow
            }
            .buttonStyle(InstrumentButtonStyle())
            Text(exercise.how)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            videoButton
            DashedRule()
        }
    }

    private var titleRow: some View {
        return HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
            Text((isChecked ? "[x] " : "[ ] ") + exercise.name)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(exercise.dose)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var videoButton: some View {
        if let url = exercise.videoURL {
            BracketButton(title: exercise.isSearchLink ? "videos" : "video",
                          minHeight: 44,
                          fullWidth: false,
                          size: .micro) {
                onOpen(url)
            }
        }
    }
}
