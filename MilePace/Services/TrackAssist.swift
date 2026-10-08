import Foundation

/// What the session screen has to do after `TrackAssist.tick`.
enum TrackAssistEvent: Equatable {
    /// The countdown into rep 1 ran out: start the workout.
    case startRep1
    /// GPS says the current lap ended at this moment.
    case autoLap(Date)
}

/// The steps of the optional calibration lap on the ready screen.
enum TrackCalibrationStep: Equatable {
    case idle
    /// The runner was told to jog to the start line and tap there.
    case armed
    /// Running the lap; `startRaw` is the GPS counter at the start tap.
    case measuring(startRaw: Double)
    case done(measured: Double, factor: Double)
    case failed
}

/// Everything the track session does beyond the plain tap state machine: GPS auto-lap, the spoken cues
/// around a rep, the countdown into rep 1 and the calibration lap. One per session screen.
@Observable
@MainActor
final class TrackAssist {
    let gps = TrackGPS()
    private(set) var calibration: TrackCalibration?
    private(set) var calibrationStep: TrackCalibrationStep = .idle
    /// Rep numbers (one-based) that GPS ended; the results mark them "gps".
    private(set) var autoEndedReps: [Int]
    /// When the spoken countdown into rep 1 ends; nil when none runs.
    private(set) var countdownEnd: Date?
    /// Whether GPS auto-lap is switched on for this session (setting on and not a treadmill).
    private(set) var gpsEnabled: Bool = false

    @ObservationIgnored private var halfwaySpoken = false
    @ObservationIgnored private var hundredSpoken = false
    @ObservationIgnored private var weakSpoken = false
    @ObservationIgnored private var countdownThreeSpoken = false
    /// The rep number whose "Rep n of N" line was already said.
    @ObservationIgnored private var introSpokenRep = 0
    @ObservationIgnored private var restMarksSpoken: Set<Int> = []

    init(autoEnded: [Int] = []) {
        autoEndedReps = autoEnded
        calibration = TrackCalibrationStore.load()
        if let saved = calibration {
            gps.setFactor(saved.factor)
        }
    }

    // MARK: Session

    /// Reads the settings and starts the GPS when auto-lap is on. A resumed session (`resumed`) keeps its
    /// reps but has no rep distance until the next rep starts.
    func begin(resumed: Bool) {
        gpsEnabled = AppSettings.trackAutoLap && AppSettings.runSurface == .outdoor
        guard gpsEnabled else { return }
        let wasUpdating = gps.updating
        gps.start()
        if resumed {
            gps.setLive(true)
            if !wasUpdating {
                gps.invalidate()
            }
        }
    }

    func end() {
        gps.stop()
        cancelCountdown()
        calibrationStep = .idle
    }

    /// The first rep starts: from here the GPS may keep running in the background.
    func workoutStarted() {
        cancelCountdown()
        calibrationStep = .idle
        gps.setLive(true)
        repStarted()
    }

    /// A rep (lap 1) starts.
    func repStarted() {
        halfwaySpoken = false
        hundredSpoken = false
        weakSpoken = false
        restMarksSpoken = []
        if gpsEnabled {
            gps.beginRep()
        }
    }

    /// The runner tapped at a line while a rep went on (not the end of the rep): the meter reads the lap end.
    func lapTapped(spec: WorkoutSpec, lapJustEnded lap: Int) {
        guard gpsEnabled, let boundary = TrackAutoLap.boundary(spec, lap: lap) else { return }
        gps.snap(toMeters: boundary)
    }

    /// A tap was taken back: the GPS rep distance no longer fits the state.
    func undone(completedReps: Int) {
        autoEndedReps = autoEndedReps.filter { $0 <= completedReps }
        gps.invalidate()
        halfwaySpoken = true
        hundredSpoken = true
    }

    func noteAutoEnded(rep: Int) {
        if !autoEndedReps.contains(rep) {
            autoEndedReps.append(rep)
        }
    }

    // MARK: Countdown into rep 1

    var isCountingDown: Bool {
        return countdownEnd != nil
    }

    func countdownRemaining(now: Date) -> Double {
        guard let end = countdownEnd else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    func beginCountdown(now: Date, spec: WorkoutSpec, seconds: Double = 10) {
        countdownEnd = now.addingTimeInterval(seconds)
        countdownThreeSpoken = false
        speakIntro(rep: 1, spec: spec)
    }

    func cancelCountdown() {
        countdownEnd = nil
    }

    // MARK: Cues

    /// "Rep 2 of 4. 200 meters. Target 55 seconds." Once per rep.
    func speakIntro(rep: Int, spec: WorkoutSpec) {
        guard introSpokenRep != rep else { return }
        introSpokenRep = rep
        let text = TrackSpeech.repIntro(rep: rep,
                                        total: spec.totalReps,
                                        meters: spec.repDistance,
                                        targetSeconds: spec.targetRepSeconds)
        Coach.shared.announceRepIntro(text)
    }

    /// Speaks the lines of a rest that is running: 30, 10 and 3 seconds, and the next rep's introduction
    /// from 10 seconds on.
    private func restCues(workout: TrackWorkout, now: Date) {
        guard workout.isResting, !workout.isRestComplete else { return }
        let seconds = Int(workout.restRemaining(at: now).rounded(.up))
        if seconds <= 10 {
            speakIntro(rep: workout.completedReps + 1, spec: workout.spec)
        }
        guard [30, 10, 3].contains(seconds), !restMarksSpoken.contains(seconds) else { return }
        restMarksSpoken.insert(seconds)
        Coach.shared.announceRestCountdown(seconds: seconds, restTotal: workout.restTotal)
    }

    /// The rest just ran out. `autoStarted` is true when the rep begins by itself.
    func restEnded(workout: TrackWorkout, autoStarted: Bool) {
        speakIntro(rep: workout.completedReps + 1, spec: workout.spec)
        if autoStarted {
            Coach.shared.announceAutoGo()
        } else {
            Coach.shared.announceGo()
        }
    }

    // MARK: Tick

    /// Called ten times a second. Speaks the cues that are due and returns what the screen must do.
    func tick(workout: TrackWorkout, now: Date) -> TrackAssistEvent? {
        if let end = countdownEnd, workout.state == .ready {
            let remaining = end.timeIntervalSince(now)
            if remaining <= 3 && !countdownThreeSpoken {
                countdownThreeSpoken = true
                Coach.shared.announceRestCountdown(seconds: 3)
            }
            if remaining <= 0 {
                countdownEnd = nil
                return .startRep1
            }
            return nil
        }
        restCues(workout: workout, now: now)
        guard gpsEnabled, case .running(_, let lap) = workout.state else {
            gps.discardPending()
            return nil
        }
        return runningCues(workout: workout, lap: lap, now: now)
    }

    private func runningCues(workout: TrackWorkout, lap: Int, now: Date) -> TrackAssistEvent? {
        guard let meters = gps.repMeters, let lapStart = workout.lapStart else {
            gps.discardPending()
            return nil
        }
        let spec = workout.spec
        speakProgress(meters: meters, workout: workout, now: now)
        guard let boundary = TrackAutoLap.boundary(spec, lap: lap) else { return nil }
        switch gps.poll(boundary: boundary, lapStart: lapStart, lapTarget: spec.lapTarget(lap: lap - 1)) {
        case .cross(let date):
            return .autoLap(date)
        case .weakGPS:
            if !weakSpoken {
                weakSpoken = true
                Coach.shared.announceGPSWeak()
            }
            return nil
        case .wait:
            return nil
        }
    }

    /// "Halfway. 52. On pace." and "100 to go." from the GPS rep distance.
    private func speakProgress(meters: Double, workout: TrackWorkout, now: Date) {
        let spec = workout.spec
        let distance = Double(spec.repDistance)
        let half = distance / 2
        if !halfwaySpoken, spec.repDistance >= TrackSpeech.halfwayMinMeters, meters >= half {
            halfwaySpoken = true
            let onLapEnd = TrackAutoLap.lapBoundaries(spec).contains { abs($0 - half) < 1 }
            if !onLapEnd {
                let text = TrackSpeech.halfway(elapsed: workout.repElapsed(at: now), halfTarget: spec.targetRepSeconds / 2)
                Coach.shared.announceTrackFeedback(text, reason: "halfway")
            }
        }
        if !hundredSpoken, spec.repDistance >= TrackSpeech.hundredToGoMinMeters, meters >= distance - 100 {
            hundredSpoken = true
            Coach.shared.announceTrackFeedback(TrackSpeech.hundredToGo, reason: "100 to go")
        }
    }

    // MARK: Calibration

    func beginCalibration() {
        calibrationStep = .armed
    }

    func cancelCalibration() {
        calibrationStep = .idle
    }

    func markCalibrationStart() {
        calibrationStep = .measuring(startRaw: gps.rawTotal)
    }

    /// Meters measured so far in a calibration lap (uncalibrated GPS distance).
    var calibrationMeasured: Double {
        if case .measuring(let startRaw) = calibrationStep {
            return max(0, gps.rawTotal - startRaw)
        }
        return 0
    }

    func markCalibrationFinish(now: Date) {
        guard case .measuring(let startRaw) = calibrationStep else { return }
        let measured = max(0, gps.rawTotal - startRaw)
        guard let factor = TrackAutoLap.calibrationFactor(measured: measured) else {
            calibrationStep = .failed
            return
        }
        let saved = TrackCalibration(factor: factor, date: now)
        TrackCalibrationStore.save(saved)
        calibration = saved
        gps.setFactor(factor)
        calibrationStep = .done(measured: measured, factor: factor)
    }
}
