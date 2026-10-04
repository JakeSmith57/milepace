import Foundation

/// Definition of a track workout.
struct WorkoutSpec: Codable, Equatable, Hashable {
    var name: String
    var reps: Int
    /// Rep distance in meters (200, 300, 400, 600, 800, 1000, 1200, 1609).
    var repDistance: Int
    var targetRepSeconds: Double
    var restSeconds: Int
    var sets: Int = 1
    var setRestSeconds: Int = 0

    /// Total reps across all sets.
    var totalReps: Int {
        return max(1, reps) * max(1, sets)
    }

    /// Share of the rep target belonging to each tap (one entry per lap tap, sums to 1).
    /// Reps of 400 m or less are a single tap; longer reps get a tap at every 400 m and at the
    /// finish (600 m is 400 + 200). The 1609 m rep is four taps with equal targets.
    var lapFractions: [Double] {
        let distance = max(1, repDistance)
        if distance == 1609 {
            return [0.25, 0.25, 0.25, 0.25]
        }
        if distance <= 400 {
            return [1.0]
        }
        var fractions: [Double] = []
        var remaining = distance
        while remaining > 0 {
            let lap = min(400, remaining)
            fractions.append(Double(lap) / Double(distance))
            remaining -= lap
        }
        return fractions
    }

    var lapsPerRep: Int {
        return lapFractions.count
    }

    /// Target for a lap, by zero-based lap index.
    func lapTarget(lap index: Int) -> Double {
        let fractions = lapFractions
        guard index >= 0, index < fractions.count else { return targetRepSeconds }
        return targetRepSeconds * fractions[index]
    }

    /// Target pace expressed per 400 m.
    var targetPer400: Double {
        return targetRepSeconds * 400.0 / Double(max(1, repDistance))
    }
}

enum TrackState: Equatable {
    case ready
    /// Both values are one-based.
    case running(rep: Int, lap: Int)
    case resting(until: Date)
    case setRest(until: Date)
    case finished
}

enum SplitVerdict: Equatable {
    case fast
    case onPace
    case slow

    /// delta = actual - target. Within +/-1.0 s counts as on pace.
    static func verdict(delta: Double) -> SplitVerdict {
        if delta > 1.0 { return .slow }
        if delta < -1.0 { return .fast }
        return .onPace
    }
}

enum TapOutcome: Equatable {
    case ignored
    case startedRep
    case lapDone(split: Double, delta: Double, repFinished: Bool, workoutFinished: Bool)
}

/// Pure session state machine for a track workout.
struct TrackWorkout {
    struct LapResult: Equatable {
        var rep: Int
        var lap: Int
        var split: Double
        var delta: Double
    }

    let spec: WorkoutSpec
    private(set) var state: TrackState = .ready
    private(set) var lapSplits: [[Double]] = []
    private(set) var repTimes: [Double] = []
    private(set) var isRestComplete: Bool = false
    private(set) var repStart: Date?
    private(set) var lapStart: Date?

    private struct Snapshot {
        var state: TrackState
        var lapSplits: [[Double]]
        var repTimes: [Double]
        var isRestComplete: Bool
        var repStart: Date?
        var lapStart: Date?
    }

    private var history: [Snapshot] = []

    init(spec: WorkoutSpec) {
        self.spec = spec
    }

    // MARK: Derived values

    var totalReps: Int { spec.totalReps }
    var completedReps: Int { repTimes.count }
    var canUndo: Bool { !history.isEmpty }

    var isResting: Bool {
        switch state {
        case .resting, .setRest: return true
        case .ready, .running, .finished: return false
        }
    }

    var currentRep: Int? {
        if case .running(let rep, _) = state { return rep }
        return nil
    }

    var currentLap: Int? {
        if case .running(_, let lap) = state { return lap }
        return nil
    }

    /// One-based set number for a one-based rep number.
    func setNumber(forRep rep: Int) -> Int {
        return (max(1, rep) - 1) / max(1, spec.reps) + 1
    }

    /// Target for the lap currently being run.
    var currentLapTarget: Double? {
        guard let lap = currentLap else { return nil }
        return spec.lapTarget(lap: lap - 1)
    }

    var averageRepTime: Double? {
        guard !repTimes.isEmpty else { return nil }
        return repTimes.reduce(0, +) / Double(repTimes.count)
    }

    /// The most recent lap split (searching back through earlier reps if the current rep has none).
    var lastLap: LapResult? {
        var repIndex = lapSplits.count - 1
        while repIndex >= 0 {
            let laps = lapSplits[repIndex]
            if let last = laps.last {
                let lapIndex = laps.count - 1
                return LapResult(rep: repIndex + 1,
                                 lap: lapIndex + 1,
                                 split: last,
                                 delta: last - spec.lapTarget(lap: lapIndex))
            }
            repIndex -= 1
        }
        return nil
    }

    /// delta = split - target for one-based rep and lap.
    func lapDelta(rep: Int, lap: Int) -> Double? {
        guard rep >= 1, rep <= lapSplits.count else { return nil }
        let laps = lapSplits[rep - 1]
        guard lap >= 1, lap <= laps.count else { return nil }
        return laps[lap - 1] - spec.lapTarget(lap: lap - 1)
    }

    /// delta = rep time - rep target for a one-based rep.
    func repDelta(rep: Int) -> Double? {
        guard rep >= 1, rep <= repTimes.count else { return nil }
        return repTimes[rep - 1] - spec.targetRepSeconds
    }

    func repElapsed(at now: Date) -> Double {
        guard let start = repStart else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    func lapElapsed(at now: Date) -> Double {
        guard let start = lapStart else { return 0 }
        return max(0, now.timeIntervalSince(start))
    }

    /// Length of the current rest in seconds.
    var restTotal: Double {
        switch state {
        case .setRest: return Double(spec.setRestSeconds)
        default: return Double(spec.restSeconds)
        }
    }

    func restRemaining(at now: Date) -> Double {
        if isRestComplete { return 0 }
        switch state {
        case .resting(let until), .setRest(let until):
            return max(0, until.timeIntervalSince(now))
        case .ready, .running, .finished:
            return 0
        }
    }

    // MARK: Events

    /// Begins rep 1 / lap 1.
    mutating func start(now: Date) {
        guard state == .ready else { return }
        state = .running(rep: 1, lap: 1)
        repStart = now
        lapStart = now
        lapSplits = [[]]
        repTimes = []
        isRestComplete = false
        history = []
    }

    /// A tap of the big button: ends a lap while running, or starts the next rep ("GO")
    /// once the rest has completed. Taps during an unfinished rest are ignored.
    @discardableResult
    mutating func lapTap(now: Date) -> TapOutcome {
        switch state {
        case .ready, .finished:
            return .ignored

        case .running(let rep, let lap):
            guard let started = lapStart else { return .ignored }
            pushSnapshot()

            let split = max(0, now.timeIntervalSince(started))
            lapSplits[rep - 1].append(split)
            let delta = split - spec.lapTarget(lap: lap - 1)

            if lap < spec.lapsPerRep {
                state = .running(rep: rep, lap: lap + 1)
                lapStart = now
                return .lapDone(split: split, delta: delta, repFinished: false, workoutFinished: false)
            }

            let repTime = lapSplits[rep - 1].reduce(0, +)
            repTimes.append(repTime)
            isRestComplete = false
            lapStart = nil

            if rep >= spec.totalReps {
                state = .finished
                return .lapDone(split: split, delta: delta, repFinished: true, workoutFinished: true)
            }
            if rep % max(1, spec.reps) == 0 {
                state = .setRest(until: now.addingTimeInterval(Double(spec.setRestSeconds)))
            } else {
                state = .resting(until: now.addingTimeInterval(Double(spec.restSeconds)))
            }
            return .lapDone(split: split, delta: delta, repFinished: true, workoutFinished: false)

        case .resting, .setRest:
            guard isRestComplete else { return .ignored }
            pushSnapshot()
            let nextRep = repTimes.count + 1
            state = .running(rep: nextRep, lap: 1)
            repStart = now
            lapStart = now
            lapSplits.append([])
            isRestComplete = false
            return .startedRep
        }
    }

    /// Time-based check. Returns true exactly once, when a rest has just run out.
    @discardableResult
    mutating func tick(now: Date) -> Bool {
        switch state {
        case .resting(let until), .setRest(let until):
            if !isRestComplete && now >= until {
                isRestComplete = true
                return true
            }
            return false
        case .ready, .running, .finished:
            return false
        }
    }

    /// Ends the current rest early. The runner still taps GO to start the next rep.
    mutating func skipRest(now: Date) {
        guard isResting, !isRestComplete else { return }
        isRestComplete = true
    }

    /// Reverts the most recent lap tap or GO. Returns false if there is nothing to undo.
    @discardableResult
    mutating func undoLastTap() -> Bool {
        guard let snapshot = history.popLast() else { return false }
        state = snapshot.state
        lapSplits = snapshot.lapSplits
        repTimes = snapshot.repTimes
        isRestComplete = snapshot.isRestComplete
        repStart = snapshot.repStart
        lapStart = snapshot.lapStart
        return true
    }

    /// Ends the workout early, keeping only completed reps.
    mutating func finishEarly() {
        guard state != .finished else { return }
        if lapSplits.count > repTimes.count {
            lapSplits = Array(lapSplits.prefix(repTimes.count))
        }
        state = .finished
        history = []
        lapStart = nil
    }

    private mutating func pushSnapshot() {
        history.append(Snapshot(state: state,
                                lapSplits: lapSplits,
                                repTimes: repTimes,
                                isRestComplete: isRestComplete,
                                repStart: repStart,
                                lapStart: lapStart))
    }
}
