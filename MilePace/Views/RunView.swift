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
    @AppStorage(SettingsKey.runViewMode) private var viewMode: RunViewMode = .data
    @AppStorage(SettingsKey.paceWindow) private var paceWindow: Double = AppSettings.defaultPaceWindow

    /// The finished run shown in the summary sheet. It is already saved in `savedRecord`.
    @State private var summary: RunSummary?
    @State private var savedRecord: RunRecord?
    /// The plan session the run marked done, so discarding the run can reopen it.
    @State private var completedPlanIndex: Int?
    @State private var summaryBusy: Bool = false
    @State private var showDiagnostics: Bool = false
    /// A run found on disk that was never finished (the app was killed or crashed during it).
    @State private var pendingDraft: RunDraft?
    @State private var confirmDraftDiscard: Bool = false
    /// The run that just ended could not be saved and waits in the draft card instead.
    @State private var draftSaveFailed: Bool = false

    init(isActive: Bool) {
        self.isActive = isActive
    }

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    /// The pace-guard range, widened to at least the pace window either side of its middle.
    private var guardRange: ClosedRange<Double>? {
        return zoneChoice.guardedRange(in: zones, window: paceWindow)
    }

    private var metronome: Metronome {
        return Metronome.shared
    }

    private var selectedWorkout: RoadWorkoutSpec {
        let presets = RoadWorkoutPresets.all
        return presets.first(where: { $0.name == workoutName }) ?? presets[0]
    }

    private func repRange(for spec: RoadWorkoutSpec) -> ClosedRange<Double> {
        return spec.target.guardedRange(zones: zones, goalMile: goalMile, window: paceWindow)
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
                           isBusy: summaryBusy,
                           onSave: { notes in save(item, notes: notes) },
                           onDiscard: { discard() })
        }
        .onAppear {
            store.runInProgress = tracker.phase != .idle
            reloadDraft()
            syncWarmup()
            applyPendingRoute()
        }
        .onChange(of: tracker.phase) { old, phase in
            // A day change at 03:00 must not forget the session while a run is going.
            store.runInProgress = phase != .idle
            followRunWithMetronome(from: old, to: phase)
        }
        .onChange(of: isActive) { _, active in
            syncWarmup()
            if active {
                applyPendingRoute()
            } else if tracker.phase == .idle {
                // Left the run tab without starting: forget the session the route opened.
                store.discardActive()
            }
        }
        .onChange(of: PlanStore.shared.pendingRoute) { _, _ in
            applyPendingRoute()
        }
        .onChange(of: PlanStore.shared.isTestWeek) { _, _ in
            // Ending the test week removes its unfinished run, so the card for it must go too.
            reloadDraft()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && tracker.phase != .idle {
                tracker.checkpoint()
            }
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

    /// "[ map ]" in the data view, "[ data ]" in the map view. Only while a run is active.
    private var viewAccessory: StatusAccessory? {
        guard tracker.phase != .idle else { return nil }
        let showingMap = viewMode == .map
        return StatusAccessory(title: showingMap ? "data" : "map",
                               action: { viewMode = viewMode.other })
    }

    /// "[ wake ]" once the idle GPS warm-up has timed out.
    private var wakeAccessory: StatusAccessory? {
        guard tracker.phase == .idle, tracker.warmupTimedOut else { return nil }
        return StatusAccessory(title: "wake", action: { tracker.wakeWarmup() })
    }

    private var accessoryList: [StatusAccessory] {
        var list: [StatusAccessory] = []
        if let wake = wakeAccessory {
            list.append(wake)
        }
        if let diag = diagAccessory {
            list.append(diag)
        }
        if let view = viewAccessory {
            list.append(view)
        }
        return list
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

    private var idleCenter: String {
        return tracker.warmupTimedOut ? "gps paused" : tracker.gpsState.label
    }

    private var statusLine: some View {
        let idle = tracker.phase == .idle
        return StatusLine(left: "milepace",
                          center: idle ? idleCenter : activeCenter,
                          right: idle ? "" : formatDuration(tracker.elapsed),
                          recording: tracker.phase == .running,
                          searching: tracker.gpsState.isSearching,
                          accessories: accessoryList,
                          tag: store.isTestWeek ? "test" : "")
    }

    // MARK: Idle

    private var modeOptions: [Choice<RunMode>] {
        return RunMode.allCases.map { Choice($0, $0.title.lowercased()) }
    }

    private var zoneOptions: [Choice<RunZoneTarget>] {
        return RunZoneTarget.allCases.map { Choice($0, $0.title.lowercased()) }
    }

    /// Picking another mode by hand ends the plan session hand-off; plan routes set `runMode`
    /// directly and do not pass through here.
    private var modeSelection: Binding<RunMode> {
        return Binding(get: { runMode },
                       set: { newMode in
                           if newMode != runMode {
                               store.discardActive()
                           }
                           runMode = newMode
                       })
    }

    /// The setup list scrolls; the diagnostics panel, when open, sits between it and the start
    /// button instead of covering them.
    private var idleContent: some View {
        VStack(spacing: 0) {
            planBar
            preciseLocationWarning
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    draftBlock
                    idleSetup
                }
            }
            if diagnosticsVisible {
                DiagnosticsPanel(onClose: { showDiagnostics = false })
                    .frame(height: 240)
            }
            startArea
        }
    }

    private var idleSetup: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChoiceRow(label: "mode", options: modeOptions, selection: modeSelection)
            if runMode == .free {
                freeRunOptions
            } else {
                workoutOptions
            }
            paceWindowRow
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

    private var paceWindowSeconds: Binding<Int> {
        return Binding(get: { Int(paceWindow.rounded()) },
                       set: { paceWindow = Double($0) })
    }

    /// The same setting as in Set: how far off target before a speed up or slow down cue.
    private var paceWindowRow: some View {
        let range = Int(AppSettings.paceWindowRange.lowerBound)...Int(AppSettings.paceWindowRange.upperBound)
        return StepperRow(title: "target window",
                          value: paceWindowSeconds,
                          range: range,
                          format: { "\u{00B1}\($0) s" })
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
            if spec.name != workoutName {
                store.discardActive()
            }
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

    /// Approximate location records no distance or pace, so say so before the run starts.
    @ViewBuilder
    private var preciseLocationWarning: some View {
        if tracker.isAuthorized && tracker.accuracyReduced {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text("precise location is off. distance and pace won't record.")
                    .font(Theme.mono(.micro))
                    .fixedSize(horizontal: false, vertical: true)
                BracketButton(title: "open settings", style: .outlineOnInverted, minHeight: 48) {
                    openSystemSettings()
                }
            }
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.s3)
            .background(Theme.fg)
            .padding(.horizontal, Theme.s3)
            .padding(.top, Theme.s2)
        }
    }

    /// "unfinished run from 6:42 am: 2.41 mi, 18:52" with a way to keep or drop it.
    @ViewBuilder
    private var draftBlock: some View {
        if let draft = pendingDraft, summary == nil {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text(draft.summaryText())
                    .font(Theme.mono(.body))
                    .fixedSize(horizontal: false, vertical: true)
                if draftSaveFailed {
                    Text("the run could not be saved. save it from here.")
                        .font(Theme.mono(.micro))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Theme.s2) {
                    BracketButton(title: "save it", style: .outlineOnInverted, minHeight: 48) {
                        saveDraft(draft)
                    }
                    BracketButton(title: confirmDraftDiscard ? "yes, discard" : "discard",
                                  style: .outlineOnInverted,
                                  minHeight: 48) {
                        discardDraft()
                    }
                }
            }
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.s3)
            .background(Theme.fg)
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2)
        }
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
        // The note glyph only appears while the click is really playing.
        if metronome.isRunning {
            return cadenceText + " \u{2669}\(metronome.bpm)"
        }
        if metronome.isSuspended {
            return cadenceText + " \u{2669}paused"
        }
        return cadenceText + " click off"
    }

    /// Average cadence once there are at least two minutes of running.
    private var averageCadence: Double? {
        guard tracker.elapsed >= 120 else { return nil }
        return tracker.cadence.averageSPM(movingSeconds: tracker.elapsed)
    }

    private var activeContent: some View {
        VStack(spacing: 0) {
            workoutBanner
            if viewMode == .map {
                mapContent
            } else {
                dataContent
            }
            controls
        }
    }

    /// The data view: big pace, meter and the readout list.
    private var dataContent: some View {
        VStack(spacing: 0) {
            paceBlock
            if diagnosticsVisible {
                DiagnosticsPanel(onClose: { showDiagnostics = false })
            } else {
                readoutScroll
            }
        }
    }

    /// The map view: the live map (the diagnostics panel overlays it) over a compact readout strip.
    private var mapContent: some View {
        VStack(spacing: 0) {
            ZStack {
                LiveRunMapView(route: tracker.liveRoute, lastCoordinate: tracker.lastCoordinate)
                if diagnosticsVisible {
                    DiagnosticsPanel(onClose: { showDiagnostics = false })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            LiveRunReadout(pace: tracker.currentPace,
                           averagePace: tracker.averagePace,
                           zone: activeRange,
                           distanceMeters: tracker.distanceMeters,
                           elapsed: tracker.elapsed,
                           cadence: tracker.cadence.currentSPM)
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
            // A pause or resume starts the pace guards from scratch.
            Coach.shared.resetZoneGuard()
            Coach.shared.resetRepGuard()
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
        // A run that was never finished is kept before a new one starts, so the new run's draft
        // cannot replace it.
        // If that save fails the draft stays the only copy and the new run does not start over it.
        if let draft = pendingDraft, !saveDraft(draft) {
            return
        }
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
            // No mile announcement over a rep or a recovery.
            let suppressed = tracker.workout?.isInRepOrRecovery ?? false
            Coach.shared.announceMile(mile, split: split, average: average, suppressed: suppressed)
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

    /// Stopping saves the run at once, then shows it. Nothing the runner does on the summary sheet can
    /// lose it: save only adds notes, and discard asks twice.
    private func endRun() {
        metronome.stop()
        Coach.shared.stopSpeaking()
        let result = tracker.stop()
        tracker.onMile = nil
        tracker.onTick = nil
        tracker.onDistanceCue = nil
        tracker.onWorkoutEvent = nil

        let record = RunRecord(date: result.date,
                               distanceMeters: result.distanceMeters,
                               durationSeconds: result.durationSeconds,
                               averagePace: result.averagePace,
                               splits: result.splits,
                               notes: "",
                               route: result.route,
                               averageCadence: result.averageCadence ?? 0,
                               workoutName: result.workoutName ?? "",
                               isTest: result.isTest)
        modelContext.insert(record)
        do {
            try modelContext.save()
            RunDraftStore.clear()
        } catch {
            // Not saved. The record is taken back out so the draft is the only copy (never both), the
            // draft is refreshed to the whole run, and the recovery card is the one way to save it.
            Diagnostics.shared.log(.state, "run save failed: \(error.localizedDescription)")
            modelContext.delete(record)
            modelContext.rollback()
            RunDraftStore.save(RunDraft(summary: result))
            draftSaveFailed = true
            tracker.reset()
            reloadDraft()
            syncWarmup()
            return
        }
        completedPlanIndex = store.completeActive(.run(miles: result.distanceMeters / metersPerMile,
                                                       workoutName: result.workoutName))
        savedRecord = record
        summaryBusy = false
        summary = result
    }

    /// The click follows the run: a pause silences it, a resume brings it back. Driven by the run's phase
    /// so every way of pausing is covered. Ending the run stops it in `endRun()`.
    private func followRunWithMetronome(from old: RunPhase, to phase: RunPhase) {
        switch phase {
        case .paused:
            metronome.suspend()
        case .running:
            if old == .paused {
                metronome.resumeFromSuspend()
            }
        case .idle:
            break
        }
    }

    private func toggleMetronome() {
        if metronome.isRunning {
            metronome.stop()
        } else if isPaused {
            // Never start audio while paused: a second tap clears the hold, the first one sets it.
            if metronome.isSuspended {
                metronome.stop()
            } else {
                metronome.setBPM(metronomeBPM)
                metronome.setVolume(Float(min(max(metronomeVolume, 0.1), 1.0)))
                metronome.suspendedStart()
            }
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

    // MARK: Summary sheet

    /// "[ save run ]": the run is already stored; this adds the notes and the pedometer's cadence for
    /// the whole run, then closes the sheet.
    private func save(_ item: RunSummary, notes: String) {
        guard !summaryBusy, let record = savedRecord else { return }
        summaryBusy = true
        let cadence = tracker.cadence
        Task { @MainActor in
            if let plan = item.cadencePlan,
               let refined = await cadence.refinedAverageSPM(plan: plan, movingSeconds: item.durationSeconds) {
                record.averageCadence = refined
            }
            record.notes = notes
            try? modelContext.save()
            RunDraftStore.clear()
            closeSummary()
        }
    }

    /// "[ yes, discard ]": removes the saved run, and reopens the plan session it had marked done.
    private func discard() {
        guard !summaryBusy else { return }
        if let record = savedRecord {
            modelContext.delete(record)
            try? modelContext.save()
        }
        if let index = completedPlanIndex {
            store.reopen(index)
        } else {
            store.discardActive()
        }
        RunDraftStore.clear()
        closeSummary()
    }

    private func closeSummary() {
        summary = nil
        savedRecord = nil
        completedPlanIndex = nil
        summaryBusy = false
        tracker.reset()
        reloadDraft()
        syncWarmup()
    }

    // MARK: Unfinished run

    private func reloadDraft() {
        guard tracker.phase == .idle, summary == nil else { return }
        let draft = RunDraftStore.load()
        if draft != pendingDraft {
            pendingDraft = draft
        }
        if draft == nil {
            confirmDraftDiscard = false
            draftSaveFailed = false
        }
    }

    /// "[ save it ]": the run on disk becomes a saved run. False when the save failed and the draft stays.
    @discardableResult
    private func saveDraft(_ draft: RunDraft) -> Bool {
        let record = draft.makeRecord()
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            // Keep the draft as the only copy: a record left in the context would be saved by the next
            // successful save and the draft would then offer it a second time.
            modelContext.delete(record)
            modelContext.rollback()
            draftSaveFailed = true
            return false
        }
        RunDraftStore.clear()
        pendingDraft = nil
        confirmDraftDiscard = false
        draftSaveFailed = false
        return true
    }

    private func discardDraft() {
        if confirmDraftDiscard {
            RunDraftStore.clear()
            pendingDraft = nil
            confirmDraftDiscard = false
            draftSaveFailed = false
        } else {
            confirmDraftDiscard = true
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Shown after a run: map, numbers, splits and notes. The run is already saved; "save run" keeps the
/// notes and "discard" (asked twice) deletes it.
struct RunSummaryView: View {
    let summary: RunSummary
    let isBusy: Bool
    let onSave: (String) -> Void
    let onDiscard: () -> Void

    @State private var notes: String = ""
    @State private var confirmDiscard: Bool = false

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
            BracketButton(title: "save run", style: .signal, isEnabled: !isBusy) {
                onSave(notes)
            }
            BracketButton(title: confirmDiscard ? "yes, discard" : "discard",
                          style: confirmDiscard ? .inverted : .plain,
                          isEnabled: !isBusy) {
                if confirmDiscard {
                    onDiscard()
                } else {
                    confirmDiscard = true
                }
            }
        }
        .padding(.top, Theme.s4)
    }
}
