import SwiftUI
import SwiftData
import UIKit

@MainActor
struct TrackSessionView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled: Bool = true

    @State private var workout: TrackWorkout
    @State private var now: Date = Date()
    /// GPS auto-lap, the spoken cues around a rep and the countdown into rep 1.
    @State private var assist: TrackAssist
    @State private var confirmEnd: Bool = false
    @State private var sessionStart: Date?
    @State private var paceOffer: PaceOffer?
    /// While in the future, the lap button says "too soon".
    @State private var tooSoonUntil: Date?
    @State private var confirmDiscard: Bool = false
    /// Set by the first save tap so a second one cannot insert the workout twice.
    @State private var saving: Bool = false
    /// Set once the workout is saved or discarded. The finished draft was cleared then; nothing may write it
    /// again (going to the background while the pace offer is up would, and the draft would offer a second copy).
    @State private var saved: Bool = false
    @State private var saveFailed: Bool = false
    /// Effort (0 = not set) and foot pain (-1 = not set) chosen on the results screen, saved with the workout.
    @State private var effort: Int = 0
    @State private var footPain: Int = -1
    /// Set when an unsaved finished workout from earlier could not be saved before this one started.
    @State private var startBlocked: Bool = false
    /// Whether this session belongs to the test week. A resumed session keeps what it was saved with; a
    /// new one takes the state when its first rep starts.
    @State private var isTest: Bool

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    /// `restored` carries a session that was running when the app was closed; it picks up where it was.
    init(spec: WorkoutSpec, restored: TrackSessionDraft? = nil, onClose: @escaping () -> Void) {
        _workout = State(initialValue: restored?.workout ?? TrackWorkout(spec: spec))
        _sessionStart = State(initialValue: restored?.sessionStart)
        _isTest = State(initialValue: restored?.isTest ?? PlanStore.shared.isTestWeek)
        _assist = State(initialValue: TrackAssist(autoEnded: restored?.autoEnded ?? []))
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if workout.state == .finished {
                resultsView
            } else {
                sessionBody
            }
        }
        .instrumentScreen()
        .onReceive(ticker) { date in
            handleTick(date)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            PlanStore.shared.trackInProgress = true
            if workout.state != .finished {
                assist.begin(resumed: workout.state != .ready)
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            PlanStore.shared.trackInProgress = false
            assist.end()
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .sheet(item: $paceOffer) { offer in
            PaceUpdateSheet(offer: offer,
                            currentSeconds: mileTime,
                            onUpdate: { applyPaceOffer(offer) },
                            onKeep: { keepPaces() },
                            practice: isTest)
        }
    }

    // MARK: Session

    private var sessionBody: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                statusLine
                banner
                upperArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                lowerArea
                    .frame(height: max(200, proxy.size.height * 0.35))
            }
        }
    }

    private var isRunning: Bool {
        switch workout.state {
        case .running, .resting, .setRest: return true
        case .ready, .finished: return false
        }
    }

    private var sessionClock: String {
        guard let began = sessionStart else { return "" }
        return formatDuration(now.timeIntervalSince(began))
    }

    private var statusLine: some View {
        StatusLine(left: "milepace",
                   center: workout.spec.name,
                   right: sessionClock,
                   recording: isRunning,
                   accessory: StatusAccessory(title: "end", action: { confirmEnd = true }),
                   accessories: [voiceAccessory],
                   tag: isTest ? "test" : "")
    }

    /// "[ voice on ]" / "[ voice off ]": mutes the countdown and lap feedback, same setting as in Set.
    private var voiceAccessory: StatusAccessory {
        return StatusAccessory(title: MidRunAudioLabels.voiceTitle(on: voiceEnabled), action: {
            voiceEnabled.toggle()
            if !voiceEnabled {
                Coach.shared.stopSpeaking()
            }
        })
    }

    private var banner: Banner {
        let total = workout.totalReps
        let spec = workout.spec
        switch workout.state {
        case .ready:
            return Banner(title: "ready",
                          subtitle: startBlocked ? "could not save your last workout. tap start to try again." : "\(total) reps",
                          trailing: TrackLaps.timeWithUnit(spec.targetRepSeconds),
                          trailingSub: "target per \(spec.repDistance) m")
        case .running(let rep, let lap):
            var subtitle: String
            if spec.lapsPerRep > 1 {
                subtitle = TrackLaps.lapTargetText(lap: lap, seconds: workout.currentLapTarget ?? spec.targetRepSeconds)
            } else {
                subtitle = TrackLaps.targetText(seconds: spec.targetRepSeconds, meters: spec.repDistance)
            }
            if spec.sets > 1 {
                subtitle += " \u{00B7} set \(workout.setNumber(forRep: rep))/\(spec.sets)"
            }
            return Banner(title: TrackLaps.repHeader(rep: rep, total: total, meters: spec.repDistance),
                          subtitle: subtitle,
                          trailing: formatSplit(workout.repElapsed(at: now)),
                          trailingSub: "this rep")
        case .resting, .setRest:
            return Banner(title: "resting",
                          subtitle: "next rep \(workout.completedReps + 1)/\(total)")
        case .finished:
            return Banner(title: "finished")
        }
    }

    // MARK: Upper area

    @ViewBuilder
    private var upperArea: some View {
        if confirmEnd {
            endConfirm
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s2) {
                    heroBlock
                    deltaBlock
                    assistBlock
                    Tape(rows: repRows, live: isRunning, maxRows: 3)
                    undoRow
                }
                .padding(.horizontal, Theme.s3)
                .padding(.top, Theme.s3)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    @ViewBuilder
    private var heroBlock: some View {
        if workout.state == .ready {
            HeroReadout(label: "target time for \(workout.spec.repDistance) m",
                        value: formatSplit(workout.spec.targetRepSeconds),
                        unit: TrackLaps.unit(forSeconds: workout.spec.targetRepSeconds),
                        size: .hero)
        } else if let last = workout.lastLap {
            HeroReadout(label: workout.spec.lapsPerRep > 1 ? "last lap" : "last rep",
                        value: formatSplit(last.split),
                        unit: TrackLaps.unit(forSeconds: last.split),
                        size: .hero)
        } else {
            HeroReadout(label: workout.spec.lapsPerRep > 1 ? "last lap" : "last rep",
                        value: "--",
                        size: .hero)
        }
    }

    @ViewBuilder
    private var deltaBlock: some View {
        if workout.state != .ready {
            if let last = workout.lastLap {
                DeltaChip(delta: last.delta)
            } else {
                Color.clear.frame(height: 60)
            }
        }
    }

    /// Under the delta: how the rep starts and ends while ready, the GPS distance during a rep.
    @ViewBuilder
    private var assistBlock: some View {
        switch workout.state {
        case .ready:
            TrackReadyPanel(assist: assist, now: now)
        case .running:
            TrackLiveGPSLine(assist: assist, repDistance: workout.spec.repDistance, now: now)
        case .resting, .setRest, .finished:
            EmptyView()
        }
    }

    private var repRows: [TapeRow] {
        var rows: [TapeRow] = []
        for (index, time) in workout.repTimes.enumerated() {
            let note = workout.repDelta(rep: index + 1).map { ReadoutFormat.signedDelta($0) } ?? ""
            rows.append(TapeRow(id: index + 1, key: "\(index + 1)", value: formatSplit(time), note: note))
        }
        return rows
    }

    private var undoRow: some View {
        HStack {
            BracketButton(title: "undo last tap",
                          minHeight: 44,
                          fullWidth: false,
                          size: .micro,
                          isEnabled: workout.canUndo) {
                undoLastTap()
            }
            Spacer(minLength: 0)
        }
    }

    private var endConfirm: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text("end workout?")
                .font(Theme.mono(.title))
                .foregroundStyle(Theme.fg)
            Text("completed reps are kept. you can save them on the next screen.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
            BracketButton(title: "end workout", style: .inverted) {
                workout.finishEarly()
                assist.end()
                confirmEnd = false
                Coach.shared.stopSpeaking()
                RestAlert.cancel()
                persist()
            }
            BracketButton(title: "keep going") {
                confirmEnd = false
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.s3)
        .padding(.top, Theme.s3)
    }

    // MARK: Lower area

    @ViewBuilder
    private var lowerArea: some View {
        switch workout.state {
        case .ready:
            readyArea
        case .running(_, let lap):
            signalBlock(word: isTooSoon ? "too soon" : lapWord(lap: lap)) {
                tapLap()
            }
        case .resting, .setRest:
            restArea
        case .finished:
            EmptyView()
        }
    }

    @ViewBuilder
    private var readyArea: some View {
        if assist.isCountingDown {
            TrackCountdownArea(remaining: assist.countdownRemaining(now: now),
                               onStartNow: { startNowTapped() },
                               onCancel: { assist.cancelCountdown() })
        } else {
            signalBlock(word: "start") {
                startTapped()
            }
        }
    }

    private var isTooSoon: Bool {
        guard let until = tooSoonUntil else { return false }
        return now < until
    }

    private func lapWord(lap: Int) -> String {
        let laps = workout.spec.lapsPerRep
        return (laps > 1 && lap >= laps) ? "finish" : "lap"
    }

    /// The loud thing on this screen: one big signal-filled tap target.
    private func signalBlock(word: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(word)
                .font(Theme.mono(.giant))
                .foregroundStyle(Theme.onSignal)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.signal)
        }
        .buttonStyle(InstrumentButtonStyle())
        .padding(.horizontal, Theme.s3)
        .padding(.bottom, Theme.s2)
    }

    private var restArea: some View {
        let remaining = workout.restRemaining(at: now)
        let countdown = workout.isRestComplete ? "0:00" : formatDuration(remaining.rounded(.up))
        return VStack(spacing: Theme.s2) {
            Text(countdown)
                .font(Theme.mono(.giant))
                .foregroundStyle(Theme.bg)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.fg)
            if workout.isRestComplete {
                BracketButton(title: "go", style: .signal, minHeight: 72) {
                    tapLap()
                }
            } else {
                BracketButton(title: "skip rest") {
                    workout.skipRest(now: Date())
                    persist()
                }
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.bottom, Theme.s2)
    }

    // MARK: Actions

    /// The big [ start ] button: with auto-start a spoken 10 second countdown first, otherwise at once.
    private func startTapped() {
        if AppSettings.trackAutoStart {
            assist.beginCountdown(now: Date(), spec: workout.spec)
        } else {
            startWorkout()
        }
    }

    /// [ start now ] during the countdown.
    private func startNowTapped() {
        if startWorkout() {
            Coach.shared.announceAutoGo()
        }
    }

    /// Begins rep 1. Returns false when the earlier unsaved workout could not be saved first.
    @discardableResult
    private func startWorkout() -> Bool {
        assist.cancelCountdown()
        guard saveFinishedDraftBeforeStarting() else {
            startBlocked = true
            return false
        }
        startBlocked = false
        isTest = PlanStore.shared.isTestWeek
        workout.start(now: Date())
        sessionStart = Date()
        assist.workoutStarted()
        assist.speakIntro(rep: 1, spec: workout.spec)
        Coach.shared.lapHaptic()
        persist()
        return true
    }

    /// A tap of the big button, or (with `auto`) the moment GPS says the lap ended.
    private func tapLap(at date: Date = Date(), auto: Bool = false) {
        let endedLap = workout.currentLap
        let outcome = workout.lapTap(now: date)
        switch outcome {
        case .ignored:
            break
        case .tooSoon:
            if !auto {
                Coach.shared.tooSoonHaptic()
                tooSoonUntil = Date().addingTimeInterval(1)
            }
        case .startedRep:
            assist.repStarted()
            if let rep = workout.currentRep {
                assist.speakIntro(rep: rep, spec: workout.spec)
            }
            Coach.shared.lapHaptic()
            persist()
        case .lapDone(_, let delta, let repFinished, let workoutFinished):
            Coach.shared.lapHaptic()
            if repFinished {
                repFinishedFeedback(auto: auto, workoutFinished: workoutFinished)
            } else {
                Coach.shared.announceLap(delta: delta)
                if !auto, let lap = endedLap {
                    assist.lapTapped(spec: workout.spec, lapJustEnded: lap)
                }
            }
            persist()
        }
    }

    /// Marks a GPS-ended rep and says its time, how it compared and the rest.
    private func repFinishedFeedback(auto: Bool, workoutFinished: Bool) {
        let rep = workout.completedReps
        if auto {
            assist.noteAutoEnded(rep: rep)
        }
        guard let time = workout.repTimes.last else { return }
        if workoutFinished {
            assist.end()
            Coach.shared.announceTrackFeedback(TrackSpeech.lastRepDone(average: workout.averageRepTime ?? time),
                                               reason: "last rep")
        } else {
            let delta = workout.repDelta(rep: rep) ?? 0
            Coach.shared.announceTrackFeedback(TrackSpeech.repDone(time: time,
                                                                   delta: delta,
                                                                   restSeconds: Int(workout.restTotal)),
                                               reason: "rep \(rep) done")
        }
    }

    private func undoLastTap() {
        if workout.undoLastTap() {
            if workout.state != .finished {
                // Taking back the last tap of a finished workout brings the session back to life.
                assist.begin(resumed: true)
            }
            assist.undone(completedReps: workout.completedReps)
            persist()
        }
    }

    private func handleTick(_ date: Date) {
        now = date
        if workout.tick(now: date) {
            RestAlert.cancel()
            Coach.shared.restEndHaptic()
            restEnded(at: date)
        }
        if let event = assist.tick(workout: workout, now: date) {
            handleAssist(event, at: date)
        }
    }

    /// The rest ran out: the next rep starts by itself with auto-start, otherwise the runner taps go.
    private func restEnded(at date: Date) {
        let auto = AppSettings.trackAutoStart
        assist.restEnded(workout: workout, autoStarted: auto)
        if auto {
            tapLap(at: date)
        }
    }

    private func handleAssist(_ event: TrackAssistEvent, at date: Date) {
        switch event {
        case .startRep1:
            if startWorkout() {
                Coach.shared.announceAutoGo()
            }
        case .autoLap(let crossing):
            tapLap(at: min(crossing, date), auto: true)
        }
    }

    // MARK: Saved state and the rest alert

    /// Writes the session so a killed app can pick it up again. Nothing is written before the first rep.
    private func persist() {
        guard TrackSessionStore.shouldPersist(started: sessionStart != nil,
                                              state: workout.state,
                                              saved: saved,
                                              saving: saving),
              let began = sessionStart else {
            return
        }
        TrackSessionStore.save(TrackSessionDraft(workout: workout,
                                                       sessionStart: began,
                                                       savedAt: Date(),
                                                       isTest: isTest,
                                                       autoEnded: assist.autoEndedReps))
    }

    /// A finished workout left in the draft (never saved, never discarded) is saved as a workout record
    /// before a new session starts, so the new session's draft cannot replace it. Returns false when
    /// that save failed and the draft is still the only copy.
    private func saveFinishedDraftBeforeStarting() -> Bool {
        guard let old = TrackSessionStore.load(), old.isFinished else { return true }
        guard old.hasResults else {
            TrackSessionStore.clear()
            return true
        }
        let record = old.makeRecord()
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(record)
            modelContext.rollback()
            return false
        }
        TrackSessionStore.clear()
        return true
    }

    /// Going to the background saves the session and, during a rest, schedules a notification for the
    /// moment the rest ends; coming back cancels it.
    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            persist()
            if workout.isResting && !workout.isRestComplete {
                RestAlert.schedule(inSeconds: workout.restRemaining(at: Date()),
                                   nextRep: workout.completedReps + 1,
                                   totalReps: workout.totalReps)
            }
        case .active:
            RestAlert.cancel()
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    // MARK: Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "results", right: "", tag: isTest ? "test" : "")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(workout.spec.name)
                    WorkoutResultsTable(spec: workout.spec,
                                        repTimes: workout.repTimes,
                                        lapSplits: workout.lapSplits,
                                        autoEnded: assist.autoEndedReps)
                        .padding(.top, Theme.s2)
                    resultsUndo
                    SectionHeader("effort and foot")
                    EffortFootRows(effort: $effort, footPain: $footPain)
                    saveButton
                    discardButton
                }
                .padding(.horizontal, Theme.s3)
            }
        }
    }

    /// Takes the last lap tap back, which returns to the running state of the final lap.
    @ViewBuilder
    private var resultsUndo: some View {
        if workout.canUndo {
            HStack {
                BracketButton(title: "undo last tap",
                              minHeight: 44,
                              fullWidth: false,
                              size: .micro) {
                    undoLastTap()
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Theme.s3)
        }
    }

    private var saveButton: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            BracketButton(title: "save workout",
                          style: .signal,
                          minHeight: 72,
                          isEnabled: !workout.repTimes.isEmpty && !saving) {
                saveWorkout()
            }
            if saveFailed {
                Text("could not save. try again.")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
            }
        }
        .padding(.top, Theme.s4)
    }

    /// The first tap arms it, the second throws the workout away.
    private var discardButton: some View {
        let style: BracketStyle = confirmDiscard ? .inverted : .plain
        return BracketButton(title: confirmDiscard ? "yes, discard" : "discard", style: style) {
            if confirmDiscard {
                discardWorkout()
            } else {
                confirmDiscard = true
            }
        }
        .padding(.top, Theme.s2)
        .padding(.bottom, Theme.s3)
    }

    /// The session is over (saved or discarded): tells the owner to close it. `trackInProgress` is cleared
    /// first, because the owner may ask for the home screen before this view has disappeared, and a
    /// recording session blocks that.
    private func finish() {
        PlanStore.shared.trackInProgress = false
        onClose()
    }

    private func discardWorkout() {
        saved = true
        TrackSessionStore.clear()
        RestAlert.cancel()
        Coach.shared.stopSpeaking()
        PlanStore.shared.discardActive()
        finish()
    }

    private func saveWorkout() {
        guard !saving else { return }
        saving = true
        let record = WorkoutRecord(date: sessionStart ?? Date(),
                                   name: workout.spec.name,
                                   spec: workout.spec,
                                   repTimes: workout.repTimes,
                                   lapSplits: workout.lapSplits,
                                   isTest: isTest)
        record.effort = effort
        record.footPain = footPain
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(record)
            modelContext.rollback()
            saving = false
            saveFailed = true
            return
        }
        saveFailed = false
        saved = true
        TrackSessionStore.clear()
        RestAlert.cancel()
        Coach.shared.stopSpeaking()
        PlanStore.shared.completeActive(.track(presetName: workout.spec.name))
        if let offer = timeTrialOffer() {
            paceOffer = offer
        } else {
            finish()
        }
    }

    /// A saved mile time trial can retune the training paces, when the time is a believable mile.
    private func timeTrialOffer() -> PaceOffer? {
        let spec = workout.spec
        guard spec.repDistance == 1609, spec.totalReps == 1, let time = workout.repTimes.first else {
            return nil
        }
        let seconds = time.rounded()
        guard AppSettings.validMileRange.contains(seconds) else { return nil }
        guard abs(seconds - mileTime.rounded()) >= 1 else { return nil }
        return PaceOffer(seconds: seconds)
    }

    private func applyPaceOffer(_ offer: PaceOffer) {
        mileTime = offer.seconds
        paceOffer = nil
        finish()
    }

    private func keepPaces() {
        paceOffer = nil
        finish()
    }
}
