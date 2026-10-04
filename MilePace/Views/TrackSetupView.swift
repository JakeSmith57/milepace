import SwiftUI

/// Identifiable wrapper so a spec can drive `sheet(item:)` and `fullScreenCover(item:)`.
struct SetupItem: Identifiable {
    let id = UUID()
    var spec: WorkoutSpec
}

/// Track tab: preset list, with a setup sheet that leads into the session.
@MainActor
struct TrackSetupView: View {
    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile

    @State private var editing: SetupItem?

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "track", right: "goal " + formatSplit(PaceZones.goalPer400) + "/400")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PresetGroup.allCases) { group in
                        groupSection(group)
                    }
                    SectionHeader("custom")
                    BracketButton(title: "custom workout") {
                        editing = SetupItem(spec: WorkoutPresets.customSpec(zones: zones))
                    }
                    .padding(.top, Theme.s3)
                    .padding(.bottom, Theme.s3)
                }
                .padding(.horizontal, Theme.s3)
            }
        }
        .instrumentScreen()
        .sheet(item: $editing) { item in
            WorkoutEditorView(spec: item.spec)
        }
    }

    private func groupSection(_ group: PresetGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(group.title.lowercased())
            ForEach(WorkoutPresets.presets(in: group)) { preset in
                presetButton(preset)
            }
        }
    }

    private func presetButton(_ preset: WorkoutPreset) -> some View {
        let spec = preset.spec(zones: zones, goalMile: goalMile)
        return Button {
            editing = SetupItem(spec: spec)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ReadoutRow(key: preset.name,
                           value: formatSplit(spec.targetRepSeconds),
                           ruled: false,
                           leaders: false)
                Text(summaryLine(for: spec))
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, Theme.s2)
                DashedRule()
            }
        }
        .buttonStyle(InstrumentButtonStyle())
    }

    private func summaryLine(for spec: WorkoutSpec) -> String {
        var text = "per rep"
        if spec.repDistance != 400 {
            text += " \u{00B7} " + formatSplit(spec.targetPer400) + " per 400"
        }
        if spec.totalReps > 1 {
            text += " \u{00B7} rest " + formatDuration(Double(spec.restSeconds))
        }
        return text
    }
}

/// Setup sheet: edit reps, distance, target and rest, then start the session.
@MainActor
struct WorkoutEditorView: View {
    static let distances: [Int] = [200, 300, 400, 600, 800, 1000, 1200, 1609]

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var reps: Int
    @State private var distance: Int
    @State private var targetText: String
    @State private var restSeconds: Int
    @State private var sets: Int
    @State private var setRestSeconds: Int
    @State private var session: SetupItem?

    init(spec: WorkoutSpec) {
        _name = State(initialValue: spec.name)
        _reps = State(initialValue: spec.reps)
        _distance = State(initialValue: spec.repDistance)
        _targetText = State(initialValue: formatSplit(spec.targetRepSeconds))
        _restSeconds = State(initialValue: spec.restSeconds)
        _sets = State(initialValue: spec.sets)
        _setRestSeconds = State(initialValue: spec.setRestSeconds)
    }

    private var parsedTarget: Double? {
        guard let value = parseTime(targetText), value >= 10, value <= 3600 else { return nil }
        return value
    }

    private var currentSpec: WorkoutSpec? {
        guard let target = parsedTarget else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutSpec(name: trimmed.isEmpty ? "Workout" : trimmed,
                           reps: reps,
                           repDistance: distance,
                           targetRepSeconds: target,
                           restSeconds: restSeconds,
                           sets: sets,
                           setRestSeconds: setRestSeconds)
    }

    private var distanceOptions: [Int] {
        var options = WorkoutEditorView.distances
        if !options.contains(distance) {
            options.append(distance)
            options.sort()
        }
        return options
    }

    /// The rep distance as an index into `distanceOptions`, so a stepper can walk the list.
    private var distanceIndex: Binding<Int> {
        return Binding(get: { distanceOptions.firstIndex(of: distance) ?? 0 },
                       set: { newIndex in
                           let options = distanceOptions
                           guard !options.isEmpty else { return }
                           distance = options[min(max(newIndex, 0), options.count - 1)]
                       })
    }

    private func distanceText(_ index: Int) -> String {
        let options = distanceOptions
        guard index >= 0, index < options.count else { return "--" }
        return "\(options[index]) m"
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "setup", right: "")
            HStack {
                BracketButton(title: "back", minHeight: 44, fullWidth: false) {
                    dismiss()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.top, Theme.s2)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    workoutSection
                    targetSection
                    restSection
                    BracketButton(title: "start workout",
                                  style: .signal,
                                  minHeight: 80,
                                  isEnabled: currentSpec != nil) {
                        if let spec = currentSpec {
                            session = SetupItem(spec: spec)
                        }
                    }
                    .padding(.top, Theme.s4)
                    .padding(.bottom, Theme.s3)
                }
                .padding(.horizontal, Theme.s3)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .instrumentScreen()
        .fullScreenCover(item: $session) { item in
            TrackSessionView(spec: item.spec) {
                session = nil
                dismiss()
            }
        }
    }

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("workout")
            FieldRow(key: "name",
                     placeholder: "workout",
                     text: $name,
                     keyboard: .default,
                     fieldWidth: 200)
            StepperRow(title: "reps", value: $reps, range: 1...30)
            StepperRow(title: "rep dist",
                       value: distanceIndex,
                       range: 0...(distanceOptions.count - 1),
                       format: { index in distanceText(index) })
            StepperRow(title: "sets", value: $sets, range: 1...8)
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("target")
            FieldRow(key: "per rep",
                     placeholder: "m:ss.s",
                     text: $targetText,
                     note: currentSpec == nil ? "enter a time like 82.5 or 2:05" : nil)
            if let spec = currentSpec {
                Text(formatSplit(spec.targetPer400) + " per 400 m")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, Theme.s2)
                if spec.lapsPerRep > 1 {
                    Text("\(spec.lapsPerRep) lap taps per rep")
                        .font(Theme.mono(.micro))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("rest")
            StepperRow(title: "btw reps",
                       value: $restSeconds,
                       range: 0...900,
                       step: 5,
                       format: { formatDuration(Double($0)) })
            if sets > 1 {
                StepperRow(title: "btw sets",
                           value: $setRestSeconds,
                           range: 0...900,
                           step: 15,
                           format: { formatDuration(Double($0)) })
            }
        }
    }
}
