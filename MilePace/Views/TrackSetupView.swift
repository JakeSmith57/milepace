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
        NavigationStack {
            List {
                ForEach(PresetGroup.allCases) { group in
                    Section(group.title) {
                        ForEach(WorkoutPresets.presets(in: group)) { preset in
                            presetButton(preset)
                        }
                    }
                }
                Section("Custom") {
                    Button {
                        editing = SetupItem(spec: WorkoutPresets.customSpec(zones: zones))
                    } label: {
                        Label("Custom workout", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("Track")
        }
        .sheet(item: $editing) { item in
            WorkoutEditorView(spec: item.spec)
        }
    }

    private func presetButton(_ preset: WorkoutPreset) -> some View {
        let spec = preset.spec(zones: zones, goalMile: goalMile)
        return Button {
            editing = SetupItem(spec: spec)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(summaryLine(for: spec))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryLine(for spec: WorkoutSpec) -> String {
        var text = "\(formatSplit(spec.targetRepSeconds)) per rep"
        if spec.repDistance != 400 {
            text += "  ·  \(formatSplit(spec.targetPer400)) per 400"
        }
        if spec.totalReps > 1 {
            text += "  ·  rest \(formatDuration(Double(spec.restSeconds)))"
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $name)
                    Stepper("Reps: \(reps)", value: $reps, in: 1...30)
                    Picker("Rep distance", selection: $distance) {
                        ForEach(distanceOptions, id: \.self) { meters in
                            Text("\(meters) m").tag(meters)
                        }
                    }
                    Stepper("Sets: \(sets)", value: $sets, in: 1...8)
                }

                Section {
                    HStack {
                        Text("Target per rep")
                        Spacer()
                        TextField("m:ss.s", text: $targetText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    if let spec = currentSpec {
                        Text("\(formatSplit(spec.targetPer400)) per 400 m")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if spec.lapsPerRep > 1 {
                            Text("\(spec.lapsPerRep) lap taps per rep")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Enter a time like 82.5 or 2:05")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Target")
                }

                Section("Rest") {
                    Stepper("Between reps: \(formatDuration(Double(restSeconds)))",
                            value: $restSeconds, in: 0...900, step: 5)
                    if sets > 1 {
                        Stepper("Between sets: \(formatDuration(Double(setRestSeconds)))",
                                value: $setRestSeconds, in: 0...900, step: 15)
                    }
                }

                Section {
                    Button {
                        if let spec = currentSpec {
                            session = SetupItem(spec: spec)
                        }
                    } label: {
                        Text("Start Workout")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(currentSpec == nil)
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .fullScreenCover(item: $session) { item in
            TrackSessionView(spec: item.spec) {
                session = nil
                dismiss()
            }
        }
    }
}
