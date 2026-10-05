import SwiftUI
import SwiftData
import UIKit

@MainActor
struct TrackSessionView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime

    @State private var workout: TrackWorkout
    @State private var now: Date = Date()
    @State private var lastCountdownSecond: Int = -1
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
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            PlanStore.shared.trackInProgress = false
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
                   tag: isTest ? "test" : "")
    }

    private var banner: Banner {
        let total = workout.totalReps
        let spec = workout.spec
        switch workout.state {
        case .ready:
            return Banner(title: "ready",
                          subtitle: startBlocked ? "could not save your last workout. tap start to try again." : "\(total) reps",
                          trailing: formatSplit(spec.targetRepSeconds),
                          trailingSub: "target per rep")
        case .running(let rep, let lap):
            var title = "rep \(rep)/\(total)"
            if spec.lapsPerRep > 1 {
                title += " \u{00B7} lap \(lap)"
            }
            var subtitle = "target " + formatSplit(workout.currentLapTarget ?? spec.targetRepSeconds)
            if spec.sets > 1 {
                subtitle += " \u{00B7} set \(workout.setNumber(forRep: rep))/\(spec.sets)"
            }
            return Banner(title: title,
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
            HeroReadout(label: "target per rep",
                        value: formatSplit(workout.spec.targetRepSeconds),
                        size: .hero)
        } else if let last = workout.lastLap {
            HeroReadout(label: workout.spec.lapsPerRep > 1 ? "last lap" : "last rep",
                        value: formatSplit(last.split),
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
            signalBlock(word: "start") {
                startWorkout()
            }
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

    private func startWorkout() {
        guard saveFinishedDraftBeforeStarting() else {
            startBlocked = true
            return
        }
        startBlocked = false
        isTest = PlanStore.shared.isTestWeek
        workout.start(now: Date())
        sessionStart = Date()
        Coach.shared.lapHaptic()
        persist()
    }

    private func tapLap() {
        let outcome = workout.lapTap(now: Date())
        switch outcome {
        case .ignored:
            break
        case .tooSoon:
            Coach.shared.tooSoonHaptic()
            tooSoonUntil = Date().addingTimeInterval(1)
        case .startedRep:
            Coach.shared.lapHaptic()
            persist()
        case .lapDone(_, let delta, _, _):
            Coach.shared.lapHaptic()
            Coach.shared.announceLap(delta: delta)
            persist()
        }
    }

    private func undoLastTap() {
        if workout.undoLastTap() {
            persist()
        }
    }

    private func handleTick(_ date: Date) {
        now = date
        if workout.tick(now: date) {
            RestAlert.cancel()
            Coach.shared.restEndHaptic()
            Coach.shared.announceGo()
        }
        if workout.isResting && !workout.isRestComplete {
            let seconds = Int(workout.restRemaining(at: date).rounded(.up))
            if seconds == 10 && lastCountdownSecond != 10 {
                Coach.shared.announceRestCountdown(seconds: 10)
            }
            lastCountdownSecond = seconds
        } else {
            lastCountdownSecond = -1
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
        TrackSessionStore.save(TrackSessionDraft(workout: workout, sessionStart: began, savedAt: Date(), isTest: isTest))
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
                                        lapSplits: workout.lapSplits)
                        .padding(.top, Theme.s2)
                    resultsUndo
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

    private func discardWorkout() {
        saved = true
        TrackSessionStore.clear()
        RestAlert.cancel()
        Coach.shared.stopSpeaking()
        PlanStore.shared.discardActive()
        onClose()
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
            onClose()
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
        onClose()
    }

    private func keepPaces() {
        paceOffer = nil
        onClose()
    }
}
