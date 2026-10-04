import SwiftUI
import SwiftData
import UIKit
import CoreLocation

@MainActor
struct RunView: View {
    /// True while the Run tab is the selected tab. All tabs stay alive, so this drives GPS warm-up.
    let isActive: Bool

    @Environment(LocationTracker.self) private var tracker
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile
    @AppStorage(SettingsKey.runZone) private var zoneChoice: RunZoneTarget = .off
    @AppStorage(SettingsKey.runMode) private var runMode: RunMode = .free
    @AppStorage(SettingsKey.roadWorkoutName) private var workoutName: String = ""
    @AppStorage(SettingsKey.metronomeEnabled) private var metronomeEnabled: Bool = false
    @AppStorage(SettingsKey.metronomeBPM) private var metronomeBPM: Int = AppSettings.defaultMetronomeBPM
    @AppStorage(SettingsKey.metronomeVolume) private var metronomeVolume: Double = AppSettings.defaultMetronomeVolume
    @AppStorage(SettingsKey.diagnostics) private var diagnosticsEnabled: Bool = false

    @State private var summary: RunSummary?
    @State private var showDiagnostics: Bool = false

    init(isActive: Bool) {
        self.isActive = isActive
    }

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

    private var diagnosticsVisible: Bool {
        return diagnosticsEnabled && showDiagnostics
    }

    private var store: PlanStore {
        return PlanStore.shared
    }

    /// Today's unfinished plan session when it belongs on this tab (easy, long or road).
    private var todayRunIndex: Int? {
        guard let schedule = store.schedule else { return nil }
        return schedule.todays(today: store.todayOffset).first(where: { schedule.plan.sessions[$0].isRunTabSession })
    }

    var body: some View {
        VStack(spacing: 0) {
            statusLine
            if tracker.phase == .idle {
                idleContent
            } else {
                activeContent
            }
        }
        .instrumentScreen()
        .sheet(item: $summary) { item in
            RunSummaryView(summary: item,
                           onSave: { notes in save(item, notes: notes) },
                           onDiscard: { discard() })
        }
        .onAppear {
            syncWarmup()
            applyPendingRoute()
        }
        .onChange(of: isActive) { _, _ in
            syncWarmup()
            applyPendingRoute()
        }
        .onChange(of: PlanStore.shared.pendingRoute) { _, _ in
            applyPendingRoute()
        }
        .onChange(of: scenePhase) { _, _ in
            syncWarmup()
        }
        .onChange(of: diagnosticsEnabled) { _, enabled in
            if !enabled {
                showDiagnostics = false
            }
        }
    }

    // MARK: Plan

    @ViewBuilder
    private var planBar: some View {
        if let index = todayRunIndex, let schedule = store.schedule {
            PlanBar(text: "today: " + schedule.plan.sessions[index].title, actionTitle: "set up") {
                store.markActive(index)
                apply(PlanRoute.route(for: schedule.plan.sessions[index]))
            }
        }
    }

    /// Sets the idle run screen up for a plan route. Track routes belong to the track tab.
    private func apply(_ route: PlanRoute) {
        switch route {
        case .freeRun(let zone):
            runMode = .free
            zoneChoice = zone
        case .roadWorkout(let name):
            if RoadWorkoutPresets.all.contains(where: { $0.name == name }) {
                runMode = .workout
                workoutName = name
            } else {
                runMode = .free
            }
        case .track:
            break
        }
    }

    /// Takes a pending free-run or road route from the today screen once this tab is showing.
    private func applyPendingRoute() {
        guard isActive, let route = store.pendingRoute else { return }
        switch route {
        case .track:
            return
        case .freeRun, .roadWorkout:
            store.pendingRoute = nil
            if tracker.phase == .idle {
                apply(route)
            }
        }
    }

    // MARK: GPS warm-up

    /// Keeps the GPS warm while the Run tab is showing, the app is in the foreground and nothing
    /// is being recorded. Everything else stops it.
    private func syncWarmup() {
        guard tracker.phase == .idle else { return }
        if isActive && scenePhase == .active && summary == nil {
            tracker.beginWarmup()
        } else {
            tracker.endWarmup()
        }
    }

    // MARK: Status line

    private var diagAccessory: StatusAccessory? {
        guard diagnosticsEnabled else { return nil }
        return StatusAccessory(title: "diag", action: { showDiagnostics.toggle() })
    }

    private var activeCenter: String {
        if tracker.phase == .paused {
            return "paused"
        }
        let rate = Diagnostics.shared.sampleRateHz
        var text = tracker.gpsState.label
        if rate > 0 {
            text += " \u{00B7} " + String(format: "%.0f", rate) + "hz"
        }
        return text
    }

    private var statusLine: some View {
        let idle = tracker.phase == .idle
        return StatusLine(left: "milepace",
                          center: idle ? tracker.gpsState.label : activeCenter,
                          right: idle ? "" : formatDuration(tracker.elapsed),
                          recording: tracker.phase == .running,
                          searching: tracker.gpsState.isSearching,
                          accessory: diagAccessory)
    }

    // MARK: Idle

    private var modeOptions: [Choice<RunMode>] {
        return RunMode.allCases.map { Choice($0, $0.title.lowercased()) }
    }

    private var zoneOptions: [Choice<RunZoneTarget>] {
        return RunZoneTarget.allCases.map { Choice($0, $0.title.lowercased()) }
    }

    @ViewBuilder
    private var idleContent: some View {
        if diagnosticsVisible {
            DiagnosticsPanel(onClose: { showDiagnostics = false })
        } else {
            VStack(spacing: 0) {
                planBar
                ScrollView {
                    idleSetup
                }
                startArea
            }
        }
    }

    private var idleSetup: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChoiceRow(label: "mode", options: modeOptions, selection: $runMode)
            if runMode == .free {
                freeRunOptions
            } else {
                workoutOptions
            }
            metronomeSetup
            if let message = tracker.errorMessage {
                Text(message)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
                    .padding(.top, Theme.s3)
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.bottom, Theme.s3)
    }

    private var freeRunOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChoiceRow(label: "pace guard", options: zoneOptions, selection: $zoneChoice)
            ReadoutRow(key: "range /mi", value: guardRangeText)
        }
    }

    private var guardRangeText: String {
        guard let range = guardRange else { return "--" }
        return ReadoutFormat.paceRange(range)
    }

    private var workoutOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("workout")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .padding(.top, Theme.s2)
            ForEach(RoadWorkoutPresets.all) { spec in
                workoutRow(spec)
            }
            Text("warm up first, then start reps. target pace in /mi.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .padding(.top, Theme.s2)
        }
    }

    private func workoutRow(_ spec: RoadWorkoutSpec) -> some View {
        let selected = spec.name == selectedWorkout.name
        return Button {
            workoutName = spec.name
        } label: {
            ReadoutRow(key: spec.name,
                       value: ReadoutFormat.paceRange(repRange(for: spec)),
                       selected: selected,
                       leaders: false)
        }
        .buttonStyle(InstrumentButtonStyle())
    }

    private var metronomeSetup: some View {
        VStack(alignment: .leading, spacing: 0) {
            CheckRow(title: "metronome", isOn: $metronomeEnabled)
            if metronomeEnabled {
                StepperRow(title: "tempo spm",
                           value: $metronomeBPM,
                           range: ClickTrack.bpmRange,
                           step: 2)
            }
        }
        .padding(.top, Theme.s2)
    }

    @ViewBuilder
    private var startArea: some View {
        VStack(spacing: Theme.s2) {
            if tracker.authorization == .notDetermined {
                Text("milepace needs your location to measure pace and distance.")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                BracketButton(title: "allow location") {
                    tracker.requestAuthorization()
                }
            } else if tracker.isDenied {
                Text("location is off. turn on while using the app for milepace in settings.")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
                BracketButton(title: "open settings") {
                    openSystemSettings()
                }
            } else {
                BracketButton(title: "start", style: .signal, minHeight: 80) {
                    startRun()
                }
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
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

    private var cadenceText: String {
        guard let spm = tracker.cadence.currentSPM, spm.isFinite, spm > 0 else { return "--" }
        return "\(Int(spm.rounded()))"
    }

    private var cadenceValue: String {
        let click = metronome.isRunning ? "\(metronome.bpm)" : "off"
        return cadenceText + " \u{2669}" + click
    }

    /// Average cadence once there are at least two minutes of running.
    private var averageCadence: Double? {
        guard tracker.elapsed >= 120 else { return nil }
        return tracker.cadence.averageSPM(movingSeconds: tracker.elapsed)
    }

    private var activeContent: some View {
        VStack(spacing: 0) {
            workoutBanner
            paceBlock
            if diagnosticsVisible {
                DiagnosticsPanel(onClose: { showDiagnostics = false })
            } else {
                readoutScroll
            }
            controls
        }
    }

    @ViewBuilder
    private var workoutBanner: some View {
        if let workout = tracker.workout {
            banner(for: workout)
        }
    }

    private func banner(for workout: RoadWorkoutSession) -> Banner {
        let total = workout.spec.reps
        switch workout.phase {
        case .warmup:
            return Banner(title: "warm-up", subtitle: "easy pace, then start reps")
        case .rep(let number):
            let target = workout.spec.target.rawValue + " \u{00B7} " + ReadoutFormat.paceRange(repRange(for: workout.spec))
            return Banner(title: "rep \(number)/\(total)",
                          subtitle: target,
                          trailing: countdownText(for: workout),
                          trailingSub: "left")
        case .recovery(let number):
            return Banner(title: "recovery",
                          subtitle: "next rep \(number + 1)/\(total)",
                          trailing: countdownText(for: workout),
                          trailingSub: "left")
        case .cooldown:
            return Banner(title: "cool-down", subtitle: "easy, end the run when done")
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

    private var paceBlock: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            HeroReadout(label: "pace now",
                        value: formatPace(secondsPerMile: tracker.currentPace),
                        unit: "/mi",
                        size: .giant)
            PaceMeter(pace: tracker.currentPace, zone: activeRange)
        }
        .padding(.horizontal, Theme.s3)
        .padding(.top, Theme.s3)
        .padding(.bottom, Theme.s2)
    }

    private var readoutScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ReadoutRow(key: "avg", value: formatPace(secondsPerMile: tracker.averagePace))
                ReadoutRow(key: "dist", value: "\(formatMiles(tracker.distanceMeters)) mi")
                ReadoutRow(key: "time", value: formatDuration(tracker.elapsed))
                Button {
                    toggleMetronome()
                } label: {
                    ReadoutRow(key: "cadence", value: cadenceValue)
                }
                .buttonStyle(InstrumentButtonStyle())
                cadenceMatchButton
                splitsTape
            }
            .padding(.horizontal, Theme.s3)
        }
    }

    @ViewBuilder
    private var cadenceMatchButton: some View {
        if let average = averageCadence {
            BracketButton(title: "set click to cadence +5%",
                          minHeight: 40,
                          size: .micro) {
                matchMetronomeToCadence(average)
            }
            .padding(.vertical, Theme.s2)
        }
    }

    @ViewBuilder
    private var splitsTape: some View {
        if !tracker.splits.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("mile splits")
                Tape(rows: splitRows, live: true)
                    .padding(.top, Theme.s2)
            }
        }
    }

    private var splitRows: [TapeRow] {
        var rows: [TapeRow] = []
        for (index, split) in tracker.splits.enumerated() {
            rows.append(TapeRow(id: index + 1, key: "\(index + 1)", value: formatDuration(split)))
        }
        return rows
    }

    private var isPaused: Bool {
        return tracker.phase == .paused
    }

    private var controls: some View {
        VStack(spacing: Theme.s2) {
            HStack(spacing: Theme.s2) {
                workoutButton
                pauseButton
            }
            HoldBar(title: "hold to end") {
                endRun()
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
    }

    private var pauseButton: some View {
        let style: BracketStyle = isPaused ? .signal : .plain
        return BracketButton(title: isPaused ? "resume" : "pause", style: style) {
            if isPaused {
                tracker.resume()
            } else {
                tracker.pause()
            }
        }
    }

    @ViewBuilder
    private var workoutButton: some View {
        if let workout = tracker.workout {
            switch workout.phase {
            case .warmup:
                BracketButton(title: "start reps", style: .signal) {
                    tracker.startReps()
                }
            case .rep:
                BracketButton(title: "skip rep") {
                    tracker.skipPhase()
                }
            case .recovery:
                BracketButton(title: "skip rest") {
                    tracker.skipPhase()
                }
            case .cooldown:
                EmptyView()
            }
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
            metronome.setBPM(metronomeBPM)
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
        store.completeActive()
        summary = nil
        tracker.reset()
        syncWarmup()
    }

    private func discard() {
        store.discardActive()
        summary = nil
        tracker.reset()
        syncWarmup()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Shown after a run: map, numbers, splits and notes, then save or discard.
struct RunSummaryView: View {
    let summary: RunSummary
    let onSave: (String) -> Void
    let onDiscard: () -> Void

    @State private var notes: String = ""

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace",
                       center: "run summary",
                       right: ReadoutFormat.day(summary.date))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mapBlock
                    numbers
                    splitsBlock
                    SectionHeader("notes")
                    BoxedField(placeholder: "how did it feel?", text: $notes)
                        .padding(.top, Theme.s2)
                    actions
                }
                .padding(.horizontal, Theme.s3)
                .padding(.bottom, Theme.s3)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .instrumentScreen()
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var mapBlock: some View {
        if summary.route.count >= 2 {
            RunMapView(route: summary.route, averagePace: summary.averagePace)
                .padding(.top, Theme.s3)
        }
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("run")
            if let name = summary.workoutName {
                ReadoutRow(key: "workout", value: name)
            }
            ReadoutRow(key: "dist", value: "\(formatMiles(summary.distanceMeters)) mi")
            ReadoutRow(key: "time", value: formatDuration(summary.durationSeconds))
            ReadoutRow(key: "avg /mi", value: formatPace(secondsPerMile: summary.averagePace))
            if let cadence = summary.averageCadence, cadence > 0 {
                ReadoutRow(key: "cadence", value: "\(Int(cadence.rounded())) spm")
            }
        }
    }

    @ViewBuilder
    private var splitsBlock: some View {
        if !summary.splits.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("mile splits")
                Tape(rows: splitRows)
                    .padding(.top, Theme.s2)
            }
        }
    }

    private var splitRows: [TapeRow] {
        var rows: [TapeRow] = []
        for (index, split) in summary.splits.enumerated() {
            rows.append(TapeRow(id: index + 1, key: "\(index + 1)", value: formatDuration(split)))
        }
        return rows
    }

    private var actions: some View {
        VStack(spacing: Theme.s2) {
            BracketButton(title: "save run", style: .signal) {
                onSave(notes)
            }
            BracketButton(title: "discard") {
                onDiscard()
            }
        }
        .padding(.top, Theme.s4)
    }
}
