import SwiftUI
import SwiftData
import UIKit
import CoreLocation

@MainActor
struct RunView: View {
    /// True while the run screen is showing. All screens stay alive, so this drives GPS warm-up.
    let isActive: Bool

    @Environment(LocationTracker.self) private var tracker
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query private var savedRoutes: [SavedRoute]

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile
    @AppStorage(SettingsKey.runZone) private var zoneChoice: RunZoneTarget = .off
    @AppStorage(SettingsKey.runMode) private var runMode: RunMode = .free
    @AppStorage(SettingsKey.runSurface) private var runSurface: RunSurface = .outdoor
    @AppStorage(SettingsKey.roadWorkoutName) private var workoutName: String = ""
    @AppStorage(SettingsKey.metronomeEnabled) private var metronomeEnabled: Bool = false
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled: Bool = true
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
    /// The run's fastest mile when it beats every earlier mile and the mile time setting; worked out after
    /// the summary opens, so it can appear a moment later.
    @State private var newBestMile: Double?
    @State private var showDiagnostics: Bool = false
    /// A run found on disk that was never finished (the app was killed or crashed during it).
    @State private var pendingDraft: RunDraft?
    @State private var confirmDraftDiscard: Bool = false
    /// The run that just ended could not be saved and waits in the draft card instead.
    @State private var draftSaveFailed: Bool = false
    /// The treadmill distance typed on the unfinished-run card.
    @State private var draftMilesText: String = ""
    /// The route this run follows, loaded when it starts (outdoor runs with a route selected).
    @State private var followed: FollowedRoute? = nil

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

    /// The treadmill is the setup's surface, so only timed workouts are offered on it.
    private var onTreadmill: Bool {
        return runSurface == .treadmill
    }

    private var workoutPresets: [RoadWorkoutSpec] {
        let all = RoadWorkoutPresets.all
        return onTreadmill ? TreadmillWorkouts.timeBased(all) : all
    }

    private var selectedWorkout: RoadWorkoutSpec {
        let presets = RoadWorkoutPresets.all
        return presets.first(where: { $0.name == workoutName }) ?? presets[0]
    }

    /// The workout the setup would start, or nil for a free run. A saved distance workout does not
    /// carry over to the treadmill.
    private var chosenWorkout: RoadWorkoutSpec? {
        guard runMode == .workout else { return nil }
        let spec = selectedWorkout
        if onTreadmill && !TreadmillWorkouts.isTimeBased(spec) { return nil }
        return spec
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

    /// Today's unfinished plan session when it belongs on this screen (easy, long or road).
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
                           newBestMile: newBestMile,
                           onSave: { notes, treadmillMeters, effort, footPain in
                               save(item, notes: notes, treadmillMeters: treadmillMeters, effort: effort, footPain: footPain)
                           },
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
                reloadDraft()
                applyPendingRoute()
            } else if tracker.phase == .idle {
                // Left the run screen without starting: forget the session the route opened.
                store.discardActive()
            }
        }
        .onChange(of: runSurface) { _, _ in
            if onTreadmill && runMode == .workout && chosenWorkout == nil {
                runMode = .free
            }
            syncWarmup()
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

    /// Sets the idle run screen up for a plan route. Track routes belong to the track screen.
    private func apply(_ route: PlanRoute) {
        switch route {
        case .freeRun(let zone):
            runMode = .free
            zoneChoice = zone
        case .roadWorkout(let name):
            if let spec = RoadWorkoutPresets.all.first(where: { $0.name == name }),
               !onTreadmill || TreadmillWorkouts.isTimeBased(spec) {
                runMode = .workout
                workoutName = name
            } else {
                runMode = .free
            }
        case .track:
            break
        }
    }

    /// Takes a pending free-run or road route from the today screen once this screen is showing.
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

    /// Keeps the GPS warm while the run screen is showing, the app is in the foreground and nothing
    /// is being recorded. Everything else stops it.
    private func syncWarmup() {
        guard tracker.phase == .idle else { return }
        // A treadmill run never uses the GPS.
        if isActive && scenePhase == .active && summary == nil && !onTreadmill {
            tracker.beginWarmup()
        } else {
            tracker.endWarmup()
        }
    }

    // MARK: Status line

    /// "[ today ]" back to the home screen, only while leaving is allowed: nothing recording and no
    /// summary sheet up.
    private var todayAccessory: StatusAccessory? {
        guard tracker.phase == .idle, summary == nil else { return nil }
        return StatusAccessory(title: "today", action: { store.goHome() })
    }

    private var diagAccessory: StatusAccessory? {
        guard diagnosticsEnabled else { return nil }
        return StatusAccessory(title: "diag", action: { showDiagnostics.toggle() })
    }

    /// "[ map ]" in the data view, "[ data ]" in the map view. Only while a run is active.
    private var viewAccessory: StatusAccessory? {
        guard tracker.phase != .idle, !tracker.isTreadmill else { return nil }
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
            return tracker.autoPaused ? "auto-paused" : "paused"
        }
        if tracker.isTreadmill {
            return "treadmill"
        }
        let rate = Diagnostics.shared.sampleRateHz
        var text = tracker.gpsState.label
        if rate > 0 {
            text += " \u{00B7} " + String(format: "%.0f", rate) + "hz"
        }
        return text
    }

    private var idleCenter: String {
        if onTreadmill {
            return "treadmill"
        }
        return tracker.warmupTimedOut ? "gps paused" : tracker.gpsState.label
    }

    private var statusLine: some View {
        let idle = tracker.phase == .idle
        return StatusLine(left: "milepace",
                          center: idle ? idleCenter : activeCenter,
                          right: idle ? "" : formatDuration(tracker.elapsed),
                          recording: tracker.phase == .running,
                          searching: tracker.gpsState.isSearching,
                          accessory: todayAccessory,
                          accessories: accessoryList,
                          tag: store.isTestWeek ? "test" : "")
    }

    // MARK: Idle

    private var modeOptions: [Choice<RunMode>] {
        return RunMode.allCases.map { Choice($0, $0.title.lowercased()) }
    }

    private var surfaceOptions: [Choice<RunSurface>] {
        return RunSurface.allCases.map { Choice($0, $0.title.lowercased()) }
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
            ChoiceRow(label: "surface", options: surfaceOptions, selection: $runSurface)
            ChoiceRow(label: "mode", options: modeOptions, selection: modeSelection)
            if runMode == .free {
                freeRunOptions
            } else {
                workoutOptions
            }
            routeRow
            treadmillNote
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

    /// "route: none >" opens the routes screen; with a route chosen it shows the name. Outdoor only.
    @ViewBuilder
    private var routeRow: some View {
        if !onTreadmill {
            Button {
                store.open(.routes)
            } label: {
                ReadoutRow(key: "route", value: selectedRouteName + " >", leaders: false)
            }
            .buttonStyle(InstrumentButtonStyle())
        }
    }

    /// The chosen route's name, or "none".
    private var selectedRouteName: String {
        guard let id = store.selectedRouteId else { return "none" }
        if let name = RouteCatalogLoader.bundled?.name(forId: id) {
            return name
        }
        return savedRoutes.first(where: { $0.id == id })?.name ?? id
    }

    private var freeRunOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChoiceRow(label: "pace guard", options: zoneOptions, selection: $zoneChoice)
            if onTreadmill {
                ReadoutRow(key: "range mph", value: guardSpeedText)
            } else {
                ReadoutRow(key: "range /mi", value: guardRangeText)
            }
        }
    }

    private var guardSpeedText: String {
        guard let range = guardRange else { return "--" }
        return TreadmillSpeed.rangeText(range)
    }

    /// Said once on the treadmill setup, and what a distance workout does there.
    @ViewBuilder
    private var treadmillNote: some View {
        if onTreadmill {
            Text(TreadmillSpeed.inclineNote)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .padding(.top, Theme.s2)
            if !tracker.isAuthorized {
                Text("allow location so cues keep working with the screen locked. gps isn't used on the treadmill.")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, Theme.s1)
            }
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
            ForEach(workoutPresets) { spec in
                workoutRow(spec)
            }
            Text(onTreadmill ? "warm up first, then start reps. target speed in mph." : "warm up first, then start reps. target pace in /mi.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .padding(.top, Theme.s2)
            if onTreadmill {
                Text(TreadmillWorkouts.distanceNote)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, Theme.s1)
            }
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
                       value: onTreadmill ? TreadmillSpeed.rangeText(repRange(for: spec)) : ReadoutFormat.paceRange(repRange(for: spec)),
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
        if !onTreadmill && tracker.isAuthorized && tracker.accuracyReduced {
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
                treadmillDraftField(draft)
                HStack(spacing: Theme.s2) {
                    BracketButton(title: "save it",
                                  style: .outlineOnInverted,
                                  minHeight: 48,
                                  isEnabled: !draft.isTreadmill || draftTreadmillMeters(draft) != nil) {
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

    /// A recovered treadmill run asks for the distance, prefilled by the pedometer's guess when it had one.
    @ViewBuilder
    private func treadmillDraftField(_ draft: RunDraft) -> some View {
        if draft.isTreadmill {
            TreadmillDraftField(text: $draftMilesText,
                                placeholder: draft.distanceMeters > 0 ? formatMiles(draft.distanceMeters) : "0.00")
        }
    }

    /// The distance for a recovered treadmill run: what was typed, else the pedometer's guess, else none.
    private func draftTreadmillMeters(_ draft: RunDraft) -> Double? {
        if let miles = InputParsing.addedMiles(draftMilesText) {
            return miles * metersPerMile
        }
        return draft.distanceMeters > 0 ? draft.distanceMeters : nil
    }

    @ViewBuilder
    private var startArea: some View {
        VStack(spacing: Theme.s2) {
            if !onTreadmill && tracker.authorization == .notDetermined {
                Text("milepace needs your location to measure pace and distance.")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                BracketButton(title: "allow location") {
                    tracker.requestAuthorization()
                }
            } else if !onTreadmill && tracker.isDenied {
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
            if tracker.isTreadmill {
                treadmillContent
            } else if viewMode == .map {
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

    /// The treadmill view: the clock, the target as a treadmill speed, the pedometer's distance guess and cadence.
    private var treadmillContent: some View {
        VStack(spacing: 0) {
            TreadmillTimeHero(elapsed: tracker.elapsed)
            if diagnosticsVisible {
                DiagnosticsPanel(onClose: { showDiagnostics = false })
            } else {
                treadmillScroll
            }
        }
    }

    private var treadmillScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                treadmillTargetRow
                TreadmillPedometerRow(meters: tracker.cadence.estimatedDistance)
                Button {
                    toggleMetronome()
                } label: {
                    ReadoutRow(key: "cadence", value: cadenceValue)
                }
                .buttonStyle(InstrumentButtonStyle())
                cadenceMatchButton
            }
            .padding(.horizontal, Theme.s3)
        }
    }

    /// Rep speed during a rep, easy speed in the other workout phases, the pace guard's zone on a free
    /// run; nothing when there is no target.
    @ViewBuilder
    private var treadmillTargetRow: some View {
        if let workout = tracker.workout {
            if workout.isInRep {
                ReadoutRow(key: "rep speed", value: TreadmillSpeed.rangeText(repRange(for: workout.spec)))
            } else {
                ReadoutRow(key: "easy speed", value: TreadmillSpeed.rangeText(zones.easy))
            }
        } else if let range = guardRange {
            ReadoutRow(key: "target speed", value: TreadmillSpeed.rangeText(range))
        }
    }

    /// The map view: the live map (the diagnostics panel overlays it) over a compact readout strip.
    private var mapContent: some View {
        VStack(spacing: 0) {
            ZStack {
                LiveRunMapView(route: tracker.liveRoute,
                               lastCoordinate: tracker.lastCoordinate,
                               plannedRoute: followed?.points ?? [])
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
            let range = repRange(for: workout.spec)
            let targetText = tracker.isTreadmill ? TreadmillSpeed.rangeText(range) : ReadoutFormat.paceRange(range)
            let target = workout.spec.target.rawValue + " \u{00B7} " + targetText
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
                followRow
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
    private var followRow: some View {
        if let route = followed {
            RouteFollowRow(followed: route, liveRoute: tracker.liveRoute)
                .id(route.id)
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
            audioToggles
            HStack(spacing: Theme.s2) {
                workoutButton
                pauseArea
            }
            HoldBar(title: "hold 3s to end",
                    duration: 3.0,
                    onPressBegan: { Coach.shared.announceEndHold() }) {
                endRun()
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s2)
    }

    /// Whether the click is audible now, or held back by a pause and back on resume.
    private var clickIsOn: Bool {
        return metronome.isRunning || metronome.isSuspended
    }

    /// "[ voice on ]" and "[ click on ]": each mutes or restores its own sound, mid-run, independently.
    private var audioToggles: some View {
        HStack(spacing: Theme.s2) {
            voiceToggleButton
            clickToggleButton
        }
    }

    private var voiceToggleButton: some View {
        BracketButton(title: MidRunAudioLabels.voiceTitle(on: voiceEnabled),
                      minHeight: 44,
                      size: .micro) {
            toggleVoice()
        }
        .accessibilityLabel(MidRunAudioLabels.voiceAccessibility(on: voiceEnabled))
    }

    private var clickToggleButton: some View {
        BracketButton(title: MidRunAudioLabels.clickTitle(on: clickIsOn),
                      minHeight: 44,
                      size: .micro) {
            toggleMetronome()
        }
        .accessibilityLabel(MidRunAudioLabels.clickAccessibility(on: clickIsOn))
    }

    /// The pause button, with "auto-paused" over it when the run paused itself.
    private var pauseArea: some View {
        VStack(spacing: Theme.s1) {
            if tracker.autoPaused {
                Text("auto-paused")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
            }
            pauseButton
        }
    }

    private var pauseButton: some View {
        let style: BracketStyle = isPaused ? .signal : .plain
        return BracketButton(title: isPaused ? "resume" : "pause", style: style) {
            // A pause or resume starts the pace guards from scratch.
            Coach.shared.resetZoneGuard()
            Coach.shared.resetRepGuard()
            if isPaused {
                tracker.resume()
                Coach.shared.announcePause(paused: false)
            } else {
                tracker.pause()
                Coach.shared.announcePause(paused: true)
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
                HoldBracketButton(title: "hold: skip rep") {
                    tracker.skipPhase()
                }
            case .recovery:
                HoldBracketButton(title: "hold: skip rest") {
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
        loadFollowedRoute()
        let freeRange = guardRange
        let interval = AppSettings.cueInterval
        let spec: RoadWorkoutSpec? = chosenWorkout
        let surface = runSurface
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
        tracker.onTreadmillMinute = { minutes, spm in
            Coach.shared.announceTreadmillMinutes(minutes, cadence: spm)
        }
        tracker.start(surface: surface)

        guard tracker.phase != .idle else { return }
        metronome.setBPM(metronomeBPM)
        metronome.setVolume(Float(min(max(metronomeVolume, 0.1), 1.0)))
        if metronomeEnabled {
            metronome.start()
        }
    }

    /// Reads the chosen route's saved path for an outdoor run; nothing on the treadmill or without a route.
    private func loadFollowedRoute() {
        guard !onTreadmill,
              let id = store.selectedRouteId,
              let saved = savedRoutes.first(where: { $0.id == id }),
              !saved.pointsData.isEmpty else {
            followed = nil
            return
        }
        followed = FollowedRoute(id: id, points: saved.points, meters: saved.distanceMeters)
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
        tracker.onTreadmillMinute = nil

        let record = RunRecord(date: result.date,
                               distanceMeters: result.distanceMeters,
                               durationSeconds: result.durationSeconds,
                               averagePace: result.averagePace,
                               splits: result.splits,
                               notes: "",
                               route: result.route,
                               averageCadence: result.averageCadence ?? 0,
                               workoutName: result.workoutName ?? "",
                               isTest: result.isTest,
                               isTreadmill: result.isTreadmill,
                               routeId: result.isTreadmill ? "" : (followed?.id ?? ""))
        let history = mileHistory(for: result)
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
            followed = nil
            store.selectedRouteId = nil
            tracker.reset()
            reloadDraft()
            syncWarmup()
            return
        }
        // A treadmill run has no distance yet; it marks its plan session when the runner saves it.
        if !result.isTreadmill {
            completedPlanIndex = store.completeActive(.run(miles: result.distanceMeters / metersPerMile,
                                                           workoutName: result.workoutName))
        }
        savedRecord = record
        summaryBusy = false
        newBestMile = nil
        summary = result
        checkNewBestMile(result, history: history)
    }

    // MARK: New best mile

    /// What the new-best check compares a run against: the routes of earlier outdoor runs (decoded later,
    /// off the main thread) and the best single-mile track result so far.
    private struct MileHistory {
        let routes: [Data]
        let trackMile: Double?
    }

    /// Read before the new run is inserted, so it is never compared with itself. Empty for runs that cannot
    /// set a GPS best (treadmill, test week).
    private func mileHistory(for result: RunSummary) -> MileHistory {
        guard !result.isTreadmill, !result.isTest else {
            return MileHistory(routes: [], trackMile: nil)
        }
        let runs = (try? modelContext.fetch(FetchDescriptor<RunRecord>())) ?? []
        let routes = runs.filter { !$0.isTest && !$0.isTreadmill && !$0.routeData.isEmpty }.map { $0.routeData }
        let workouts = (try? modelContext.fetch(FetchDescriptor<WorkoutRecord>())) ?? []
        var trackMile: Double? = nil
        for workout in workouts where !workout.isTest {
            guard let spec = workout.spec else { continue }
            let bests = MileProgress.trackBests(date: workout.date, repDistance: spec.repDistance, repTimes: workout.repTimes)
            for best in bests where best.distance == MileProgress.mileMeters {
                trackMile = min(trackMile ?? best.seconds, best.seconds)
            }
        }
        return MileHistory(routes: routes, trackMile: trackMile)
    }

    /// Sets `newBestMile` when this run's fastest mile beats every earlier mile (GPS and track) and the mile
    /// time setting. Never changes a setting: only a track time trial offers new paces.
    private func checkNewBestMile(_ result: RunSummary, history: MileHistory) {
        guard !result.isTreadmill, !result.isTest,
              let mile = MileProgress.fastestMile(route: result.route) else { return }
        let mileTime = AppSettings.mileTime
        let routes = history.routes
        let trackMile = history.trackMile
        let runID = result.id
        Task { @MainActor in
            let previous = await Task.detached(priority: .utility) { () -> Double? in
                var best: Double? = trackMile
                for blob in routes {
                    guard let route = try? JSONDecoder().decode([RoutePoint].self, from: blob),
                          let time = MileProgress.fastestMile(route: route) else { continue }
                    best = min(best ?? time, time)
                }
                return best
            }.value
            guard summary?.id == runID else { return }
            newBestMile = MileProgress.newBestMile(current: mile, previousBest: previous, mileTime: mileTime)
        }
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

    /// Mutes or restores the spoken cues. The switch is the same setting as in Set; turning it off cuts
    /// off what is being said. The click is not touched.
    private func toggleVoice() {
        voiceEnabled.toggle()
        if !voiceEnabled {
            Coach.shared.stopSpeaking()
        }
    }

    private func toggleMetronome() {
        defer {
            // The next run starts the way this one was left.
            metronomeEnabled = metronome.isRunning || metronome.isSuspended
        }
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
    private func save(_ item: RunSummary, notes: String, treadmillMeters: Double?, effort: Int, footPain: Int) {
        guard !summaryBusy, let record = savedRecord else { return }
        if item.isTreadmill {
            // The typed distance is the run's distance; only now does the plan session get marked.
            guard let meters = treadmillMeters, meters > 0 else { return }
            record.distanceMeters = meters
            record.averagePace = item.durationSeconds > 0 ? item.durationSeconds / meters * metersPerMile : 0
            completedPlanIndex = store.completeActive(.run(miles: meters / metersPerMile,
                                                           workoutName: item.workoutName))
        }
        summaryBusy = true
        let cadence = tracker.cadence
        Task { @MainActor in
            if let plan = item.cadencePlan,
               let refined = await cadence.refinedAverageSPM(plan: plan, movingSeconds: item.durationSeconds) {
                record.averageCadence = refined
            }
            record.notes = notes
            record.effort = effort
            record.footPain = footPain
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
        if let route = followed {
            RouteResolver.shared.markUsed(id: route.id)
        }
        followed = nil
        store.selectedRouteId = nil
        summary = nil
        savedRecord = nil
        newBestMile = nil
        completedPlanIndex = nil
        summaryBusy = false
        tracker.reset()
        reloadDraft()
        syncWarmup()
        // Finished with this run, saved or discarded: back to the home screen.
        store.goHome()
    }

    // MARK: Unfinished run

    private func reloadDraft() {
        guard tracker.phase == .idle, summary == nil else { return }
        let draft = RunDraftStore.load()
        if draft != pendingDraft {
            pendingDraft = draft
        }
        if draft == nil {
            draftMilesText = ""
            confirmDraftDiscard = false
            draftSaveFailed = false
        }
    }

    /// "[ save it ]": the run on disk becomes a saved run. False when the save failed and the draft stays.
    @discardableResult
    private func saveDraft(_ draft: RunDraft) -> Bool {
        let record = draft.makeRecord()
        if draft.isTreadmill, let meters = draftTreadmillMeters(draft) {
            record.distanceMeters = meters
            record.averagePace = draft.movingSeconds > 0 ? draft.movingSeconds / meters * metersPerMile : 0
        }
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
        draftMilesText = ""
        confirmDraftDiscard = false
        draftSaveFailed = false
        return true
    }

    private func discardDraft() {
        if confirmDraftDiscard {
            RunDraftStore.clear()
            pendingDraft = nil
            draftMilesText = ""
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
    /// This run's fastest mile when it is a new best, in seconds.
    let newBestMile: Double?
    /// Called with the notes, for a treadmill run the typed distance in meters, the effort (0 = not set) and
    /// the foot pain (-1 = not set).
    let onSave: (String, Double?, Int, Int) -> Void
    let onDiscard: () -> Void

    @State private var notes: String = ""
    @State private var effort: Int = 0
    @State private var footPain: Int = -1
    @State private var confirmDiscard: Bool = false
    /// The treadmill distance in miles as typed; prefilled with the pedometer's guess.
    @State private var milesText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace",
                       center: "run summary",
                       right: ReadoutFormat.day(summary.date))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mapBlock
                    numbers
                    treadmillBlock
                    splitsBlock
                    SectionHeader("effort and foot")
                    EffortFootRows(effort: $effort, footPain: $footPain)
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
        .onAppear {
            if summary.isTreadmill && milesText.isEmpty && summary.distanceMeters > 0 {
                milesText = String(format: "%.2f", summary.distanceMeters / metersPerMile)
            }
        }
    }

    /// The treadmill distance in meters, when this is a treadmill run and a distance above 0 is typed.
    private var treadmillMeters: Double? {
        guard summary.isTreadmill, let miles = InputParsing.addedMiles(milesText) else { return nil }
        return miles * metersPerMile
    }

    private var canSave: Bool {
        return !isBusy && (!summary.isTreadmill || treadmillMeters != nil)
    }

    /// Average pace for the typed distance.
    private var treadmillPace: Double? {
        guard let meters = treadmillMeters, summary.durationSeconds > 0 else { return nil }
        return summary.durationSeconds / meters * metersPerMile
    }

    @ViewBuilder
    private var treadmillBlock: some View {
        if summary.isTreadmill {
            TreadmillDistanceEntry(text: $milesText,
                                   averagePaceText: formatPace(secondsPerMile: treadmillPace),
                                   needsValue: treadmillMeters == nil)
                .padding(.top, Theme.s1)
        }
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
            if !summary.isTreadmill {
                ReadoutRow(key: "dist", value: "\(formatMiles(summary.distanceMeters)) mi")
            }
            ReadoutRow(key: "time", value: formatDuration(summary.durationSeconds))
            if !summary.isTreadmill {
                ReadoutRow(key: "avg /mi", value: formatPace(secondsPerMile: summary.averagePace))
            }
            if let cadence = summary.averageCadence, cadence > 0 {
                ReadoutRow(key: "cadence", value: "\(Int(cadence.rounded())) spm")
            }
            if let best = newBestMile {
                Text("new best mile in a run: " + formatDuration(best))
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
                    .padding(.top, Theme.s2)
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
            BracketButton(title: "save run", style: .signal, isEnabled: canSave) {
                onSave(notes, treadmillMeters, effort, footPain)
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
