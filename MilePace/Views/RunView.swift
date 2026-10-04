import SwiftUI
import SwiftData
import UIKit
import CoreLocation

@MainActor
struct RunView: View {
    @Environment(LocationTracker.self) private var tracker
    @Environment(\.modelContext) private var modelContext

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile
    @AppStorage(SettingsKey.runZone) private var zoneChoice: RunZoneTarget = .off
    @AppStorage(SettingsKey.runMode) private var runMode: RunMode = .free
    @AppStorage(SettingsKey.roadWorkoutName) private var workoutName: String = ""
    @AppStorage(SettingsKey.metronomeEnabled) private var metronomeEnabled: Bool = false
    @AppStorage(SettingsKey.metronomeBPM) private var metronomeBPM: Int = AppSettings.defaultMetronomeBPM
    @AppStorage(SettingsKey.metronomeVolume) private var metronomeVolume: Double = AppSettings.defaultMetronomeVolume

    @State private var summary: RunSummary?

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    private var guardRange: ClosedRange<Double>? {
        return zoneChoice.range(in: zones)
    }

    private var metronome: Metronome {
        return Metronome.shared
    }

    private var selectedWorkout: RoadWorkoutSpec {
        let presets = RoadWorkoutPresets.all
        return presets.first(where: { $0.name == workoutName }) ?? presets[0]
    }

    private func repRange(for spec: RoadWorkoutSpec) -> ClosedRange<Double> {
        return spec.target.range(zones: zones, goalMile: goalMile)
    }

    private func rangeText(_ range: ClosedRange<Double>) -> String {
        return "\(formatPace(secondsPerMile: range.lowerBound))–\(formatPace(secondsPerMile: range.upperBound)) /mi"
    }

    var body: some View {
        NavigationStack {
            Group {
                if tracker.phase == .idle {
                    idleView
                } else {
                    activeView
                }
            }
            .navigationTitle("Run")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $summary) { item in
            RunSummaryView(summary: item,
                           onSave: { notes in save(item, notes: notes) },
                           onDiscard: { discard() })
        }
    }

    // MARK: Idle

    private var zoneDescription: String {
        guard let range = guardRange else {
            return "No pace cues. Mile splits are still announced if enabled."
        }
        return "\(zoneChoice.title) zone: \(formatPace(secondsPerMile: range.lowerBound)) to \(formatPace(secondsPerMile: range.upperBound)) per mile"
    }

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "figure.run")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Mode")
                        .font(.headline)
                    Picker("Mode", selection: $runMode) {
                        ForEach(RunMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if runMode == .free {
                    freeRunOptions
                } else {
                    workoutOptions
                }

                metronomeRow

                permissionOrStart

                if let message = tracker.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
    }

    private var freeRunOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pace guard")
                .font(.headline)
            Picker("Zone", selection: $zoneChoice) {
                ForEach(RunZoneTarget.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.segmented)
            Text(zoneDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var workoutOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Workout")
                .font(.headline)
            Picker("Workout", selection: selectedWorkoutBinding) {
                ForEach(RoadWorkoutPresets.all) { spec in
                    Text("\(spec.name)  ·  \(rangeText(repRange(for: spec)))").tag(spec.name)
                }
            }
            .pickerStyle(.menu)
            .tint(.orange)
            let spec = selectedWorkout
            Text("\(spec.name): target \(rangeText(repRange(for: spec))). Warm up first, then tap Start Reps.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedWorkoutBinding: Binding<String> {
        return Binding(get: { selectedWorkout.name },
                       set: { workoutName = $0 })
    }

    private var metronomeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Metronome", isOn: $metronomeEnabled)
                .font(.headline)
                .tint(.orange)
            if metronomeEnabled {
                Stepper(value: $metronomeBPM, in: ClickTrack.bpmRange, step: 2) {
                    Text("\(metronomeBPM) spm")
                        .font(.system(.body, design: .rounded).monospacedDigit())
                }
            }
        }
    }

    @ViewBuilder
    private var permissionOrStart: some View {
        if tracker.authorization == .notDetermined {
            VStack(spacing: 8) {
                Text("MilePace needs your location to measure pace and distance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                FilledActionButton(title: "Allow Location Access") {
                    tracker.requestAuthorization()
                }
            }
        } else if tracker.isDenied {
            VStack(spacing: 8) {
                Text("Location access is off. Turn on While Using the App for MilePace in Settings to track runs.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                FilledActionButton(title: "Open Settings") {
                    openSystemSettings()
                }
            }
        } else {
            FilledActionButton(title: "Start Run", height: 80) {
                startRun()
            }
        }
    }

    // MARK: Active

    /// The range current pace is judged against: the rep target during a rep, nothing during other
    /// workout phases, the pace-guard zone on a free run.
    private var activeRange: ClosedRange<Double>? {
        if let workout = tracker.workout {
            return workout.isInRep ? repRange(for: workout.spec) : nil
        }
        return guardRange
    }

    private var paceColor: Color {
        guard let range = activeRange, let pace = tracker.currentPace else { return .primary }
        return range.contains(pace) ? .primary : .red
    }

    private var cadenceText: String {
        guard let spm = tracker.cadence.currentSPM, spm.isFinite, spm > 0 else { return "--" }
        return "\(Int(spm.rounded()))"
    }

    /// Average cadence once there are at least two minutes of running.
    private var averageCadence: Double? {
        guard tracker.elapsed >= 120 else { return nil }
        return tracker.cadence.averageSPM(movingSeconds: tracker.elapsed)
    }

    private var activeView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if tracker.phase == .paused {
                        Text("PAUSED")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                    workoutBanner
                    BigMetricTile(title: "Current pace",
                                  value: formatPace(secondsPerMile: tracker.currentPace),
                                  unit: "/mi",
                                  valueSize: 96,
                                  valueColor: paceColor)
                    HStack(spacing: 12) {
                        BigMetricTile(title: "Average",
                                      value: formatPace(secondsPerMile: tracker.averagePace),
                                      unit: "/mi",
                                      valueSize: 40)
                        BigMetricTile(title: "Distance",
                                      value: formatMiles(tracker.distanceMeters),
                                      unit: "mi",
                                      valueSize: 40)
                    }
                    HStack(spacing: 12) {
                        BigMetricTile(title: "Time",
                                      value: formatDuration(tracker.elapsed),
                                      valueSize: 40)
                        BigMetricTile(title: "Cadence",
                                      value: cadenceText,
                                      unit: "spm",
                                      valueSize: 40)
                    }
                    metronomeChips
                    splitsSection
                }
                .padding()
            }

            VStack(spacing: 10) {
                if tracker.phase == .paused {
                    FilledActionButton(title: "Resume", color: .green) {
                        tracker.resume()
                    }
                } else {
                    FilledActionButton(title: "Pause", color: .orange) {
                        tracker.pause()
                    }
                }
                HoldToEndButton(title: "Hold to End") {
                    endRun()
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var workoutBanner: some View {
        if let workout = tracker.workout {
            VStack(spacing: 8) {
                Text(workout.phaseTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                switch workout.phase {
                case .warmup:
                    Text("Warm up at an easy pace.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FilledActionButton(title: "Start Reps", color: .green) {
                        tracker.startReps()
                    }
                case .rep, .recovery:
                    Text(countdownText(for: workout))
                        .font(.roundedDigits(56))
                    if workout.isInRep {
                        Text("Target \(rangeText(repRange(for: workout.spec)))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Button("Skip") {
                        tracker.skipPhase()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                case .cooldown:
                    Text("Cool down easy. End the run when you are done.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func countdownText(for workout: RoadWorkoutSession) -> String {
        let left = workout.remaining(elapsed: tracker.elapsed, distance: tracker.distanceMeters)
        if let seconds = left.seconds {
            return formatDuration(seconds.rounded(.up))
        }
        if let meters = left.meters {
            return "\(formatMiles(meters)) mi"
        }
        return "--"
    }

    private var metronomeChips: some View {
        HStack(spacing: 12) {
            Button {
                toggleMetronome()
            } label: {
                Text("♩ \(metronome.bpm)")
                    .font(.system(.headline, design: .rounded).monospacedDigit())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(metronome.isRunning ? Color.white : Color.primary)
                    .background(metronome.isRunning ? Color.orange : Color(.secondarySystemBackground), in: Capsule())
            }
            .buttonStyle(.plain)

            if let average = averageCadence {
                Button {
                    matchMetronomeToCadence(average)
                } label: {
                    Text("Set to my cadence +5%")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var splitsSection: some View {
        if !tracker.splits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mile splits")
                    .font(.headline)
                ForEach(Array(tracker.splits.enumerated()), id: \.offset) { item in
                    HStack {
                        Text("Mile \(item.offset + 1)")
                        Spacer()
                        Text(formatDuration(item.element))
                            .font(.roundedDigits(20, weight: .semibold))
                    }
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    private func startRun() {
        let freeRange = guardRange
        let interval = AppSettings.cueInterval
        let spec: RoadWorkoutSpec? = runMode == .workout ? selectedWorkout : nil
        let targetRange: ClosedRange<Double>? = spec.map { repRange(for: $0) }
        let tracker = self.tracker

        Coach.shared.resetZoneGuard()
        Coach.shared.resetRepGuard()

        if let spec = spec {
            tracker.beginWorkout(spec)
        } else {
            tracker.clearWorkout()
        }

        tracker.onMile = { mile, split, average in
            Coach.shared.announceMile(mile, split: split, average: average)
        }
        tracker.onTick = { pace in
            if let workout = tracker.workout {
                // Pace guard only runs during reps, against the rep's target range.
                if workout.isInRep {
                    Coach.shared.evaluateRepZone(pace: pace, zone: targetRange)
                }
            } else {
                Coach.shared.evaluateZone(pace: pace, zone: freeRange)
            }
        }
        tracker.onDistanceCue = { cue in
            Coach.shared.announceDistanceCue(cue, interval: interval, zone: spec == nil ? freeRange : nil)
        }
        tracker.onWorkoutEvent = { event in
            if let spec = spec, let targetRange = targetRange {
                Coach.shared.announceWorkoutEvent(event, spec: spec, repRange: targetRange)
            }
        }
        tracker.start()

        guard tracker.phase != .idle else { return }
        metronome.setBPM(metronomeBPM)
        metronome.setVolume(Float(min(max(metronomeVolume, 0.1), 1.0)))
        if metronomeEnabled {
            metronome.start()
        }
    }

    private func endRun() {
        metronome.stop()
        summary = tracker.stop()
        tracker.onMile = nil
        tracker.onTick = nil
        tracker.onDistanceCue = nil
        tracker.onWorkoutEvent = nil
    }

    private func toggleMetronome() {
        if metronome.isRunning {
            metronome.stop()
        } else {
            metronome.setVolume(Float(min(max(metronomeVolume, 0.1), 1.0)))
            metronome.start()
        }
    }

    private func matchMetronomeToCadence(_ average: Double) {
        let bpm = ClickTrack.suggestedBPM(averageCadence: average)
        metronomeBPM = bpm
        metronome.setBPM(bpm)
    }

    private func save(_ item: RunSummary, notes: String) {
        let record = RunRecord(date: item.date,
                               distanceMeters: item.distanceMeters,
                               durationSeconds: item.durationSeconds,
                               averagePace: item.averagePace,
                               splits: item.splits,
                               notes: notes.isEmpty ? (item.workoutName ?? "") : notes,
                               route: item.route,
                               averageCadence: item.averageCadence ?? 0)
        modelContext.insert(record)
        summary = nil
        tracker.reset()
    }

    private func discard() {
        summary = nil
        tracker.reset()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct RunSummaryView: View {
    let summary: RunSummary
    let onSave: (String) -> Void
    let onDiscard: () -> Void

    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                if summary.route.count >= 2 {
                    Section {
                        RunMapView(route: summary.route, averagePace: summary.averagePace)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
                Section("Run") {
                    if let name = summary.workoutName {
                        row("Workout", name)
                    }
                    row("Distance", "\(formatMiles(summary.distanceMeters)) mi")
                    row("Time", formatDuration(summary.durationSeconds))
                    row("Average pace", "\(formatPace(secondsPerMile: summary.averagePace)) /mi")
                    if let cadence = summary.averageCadence, cadence > 0 {
                        row("Average cadence", "\(Int(cadence.rounded())) spm")
                    }
                }
                if !summary.splits.isEmpty {
                    Section("Mile splits") {
                        ForEach(Array(summary.splits.enumerated()), id: \.offset) { item in
                            row("Mile \(item.offset + 1)", formatDuration(item.element))
                        }
                    }
                }
                Section("Notes") {
                    TextField("How did it feel?", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Button("Save Run") {
                        onSave(notes)
                    }
                    .fontWeight(.semibold)
                    Button("Discard", role: .destructive) {
                        onDiscard()
                    }
                }
            }
            .navigationTitle("Run Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded).monospacedDigit())
        }
    }
}
