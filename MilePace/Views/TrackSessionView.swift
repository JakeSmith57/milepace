import SwiftUI
import SwiftData
import UIKit

@MainActor
struct TrackSessionView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime

    @State private var workout: TrackWorkout
    @State private var now: Date = Date()
    @State private var lastCountdownSecond: Int = -1
    @State private var confirmEnd: Bool = false
    @State private var sessionStart: Date?
    @State private var paceOffer: PaceOffer?

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(spec: WorkoutSpec, onClose: @escaping () -> Void) {
        _workout = State(initialValue: TrackWorkout(spec: spec))
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
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(item: $paceOffer) { offer in
            PaceUpdateSheet(offer: offer,
                            currentSeconds: mileTime,
                            onUpdate: { applyPaceOffer(offer) },
                            onKeep: { keepPaces() })
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
                   accessory: StatusAccessory(title: "end", action: { confirmEnd = true }))
    }

    private var banner: Banner {
        let total = workout.totalReps
        let spec = workout.spec
        switch workout.state {
        case .ready:
            return Banner(title: "ready",
                          subtitle: "\(total) reps",
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
                          minHeight: 36,
                          fullWidth: false,
                          size: .micro,
                          isEnabled: workout.canUndo) {
                workout.undoLastTap()
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
            signalBlock(word: lapWord(lap: lap)) {
                tapLap()
            }
        case .resting, .setRest:
            restArea
        case .finished:
            EmptyView()
        }
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
                }
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.bottom, Theme.s2)
    }

    // MARK: Actions

    private func startWorkout() {
        workout.start(now: Date())
        sessionStart = Date()
        Coach.shared.lapHaptic()
    }

    private func tapLap() {
        let outcome = workout.lapTap(now: Date())
        switch outcome {
        case .ignored:
            break
        case .startedRep:
            Coach.shared.lapHaptic()
        case .lapDone(_, let delta, _, _):
            Coach.shared.lapHaptic()
            Coach.shared.announceLap(delta: delta)
        }
    }

    private func handleTick(_ date: Date) {
        now = date
        if workout.tick(now: date) {
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

    // MARK: Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "results", right: "")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(workout.spec.name)
                    WorkoutResultsTable(spec: workout.spec,
                                        repTimes: workout.repTimes,
                                        lapSplits: workout.lapSplits)
                        .padding(.top, Theme.s2)
                    BracketButton(title: "save workout",
                                  style: .signal,
                                  minHeight: 72,
                                  isEnabled: !workout.repTimes.isEmpty) {
                        saveWorkout()
                    }
                    .padding(.top, Theme.s4)
                    BracketButton(title: "discard") {
                        PlanStore.shared.discardActive()
                        onClose()
                    }
                    .padding(.top, Theme.s2)
                    .padding(.bottom, Theme.s3)
                }
                .padding(.horizontal, Theme.s3)
            }
        }
    }

    private func saveWorkout() {
        let record = WorkoutRecord(date: sessionStart ?? Date(),
                                   name: workout.spec.name,
                                   spec: workout.spec,
                                   repTimes: workout.repTimes,
                                   lapSplits: workout.lapSplits)
        modelContext.insert(record)
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
