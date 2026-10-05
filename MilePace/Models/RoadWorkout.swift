import Foundation

/// How long a rep lasts: a fixed time or a fixed distance.
enum RepLength: Codable, Equatable, Hashable {
    case time(seconds: Int)
    case distance(meters: Double)
}

/// Which pace range a rep is coached against.
enum RepTarget: String, Codable, CaseIterable, Hashable {
    case threshold
    case interval
    case goal

    /// Seconds-per-mile range. Goal is the goal mile pace plus or minus 3 seconds.
    func range(zones: PaceZones, goalMile: Double) -> ClosedRange<Double> {
        switch self {
        case .threshold: return zones.threshold
        case .interval: return zones.interval
        case .goal: return (goalMile - 3)...(goalMile + 3)
        }
    }

    /// `range(zones:goalMile:)` widened to at least `window` seconds either side of its middle, for cues,
    /// the pace meter and the on-target checks. The goal range becomes the goal pace plus or minus `window`.
    func guardedRange(zones: PaceZones, goalMile: Double, window: Double) -> ClosedRange<Double> {
        return PaceZones.guardRange(range(zones: zones, goalMile: goalMile), window: window)
    }

    var spokenName: String {
        switch self {
        case .threshold: return "threshold"
        case .interval: return "interval pace"
        case .goal: return "goal pace"
        }
    }
}

struct RoadWorkoutSpec: Codable, Equatable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var reps: Int
    var length: RepLength
    var target: RepTarget
    var recoverySeconds: Int

    /// "6 minutes", "1 mile", "1.5 miles" for speech.
    var spokenLength: String {
        switch length {
        case .time(let seconds):
            if seconds % 60 == 0 {
                let minutes = seconds / 60
                return minutes == 1 ? "1 minute" : "\(minutes) minutes"
            }
            return spokenMinutesSeconds(Double(seconds))
        case .distance(let meters):
            let miles = (meters / metersPerMile * 10).rounded() / 10
            if miles == miles.rounded() {
                let whole = Int(miles)
                return whole == 1 ? "1 mile" : "\(whole) miles"
            }
            return "\(miles) miles"
        }
    }
}

enum RoadWorkoutPresets {
    private static func timed(reps: Int, minutes: Int, recovery: Int, suffix: String = "") -> RoadWorkoutSpec {
        let name: String
        if reps == 1 {
            name = "\(minutes) min tempo"
        } else {
            name = "\(reps) × \(minutes) min threshold\(suffix)"
        }
        return RoadWorkoutSpec(name: name,
                               reps: reps,
                               length: .time(seconds: minutes * 60),
                               target: .threshold,
                               recoverySeconds: recovery)
    }

    private static func distance(reps: Int, miles: Double, label: String, recovery: Int) -> RoadWorkoutSpec {
        return RoadWorkoutSpec(name: "\(reps) × \(label) mi threshold",
                               reps: reps,
                               length: .distance(meters: miles * metersPerMile),
                               target: .threshold,
                               recoverySeconds: recovery)
    }

    static let all: [RoadWorkoutSpec] = [
        timed(reps: 3, minutes: 5, recovery: 120),
        timed(reps: 4, minutes: 5, recovery: 120),
        timed(reps: 4, minutes: 6, recovery: 120),
        timed(reps: 3, minutes: 8, recovery: 120),
        timed(reps: 2, minutes: 10, recovery: 120),
        timed(reps: 3, minutes: 10, recovery: 120),
        timed(reps: 2, minutes: 12, recovery: 120),
        timed(reps: 2, minutes: 15, recovery: 180),
        timed(reps: 4, minutes: 5, recovery: 60, suffix: " (1:00 rest)"),
        timed(reps: 1, minutes: 15, recovery: 0),
        timed(reps: 1, minutes: 20, recovery: 0),
        timed(reps: 1, minutes: 25, recovery: 0),
        distance(reps: 3, miles: 1, label: "1", recovery: 60),
        distance(reps: 3, miles: 1.5, label: "1.5", recovery: 120)
    ]
}

/// Pure state machine for a guided road workout. `elapsed` is moving time in seconds and
/// `distance` is cumulative meters; the caller feeds both on every tick and after GPS samples.
struct RoadWorkoutSession {
    enum Phase: Equatable {
        case warmup
        case rep(Int)
        case recovery(Int)
        case cooldown
    }

    enum Event: Equatable {
        case repStarted(Int, total: Int)
        case halfway(Int)
        case repEnded(Int, avgPace: Double?)
        case recoveryCountdown(Int)
        case workoutComplete
    }

    let spec: RoadWorkoutSpec
    private(set) var phase: Phase = .warmup

    private var phaseStartElapsed: Double = 0
    private var phaseStartDistance: Double = 0
    private var lastElapsed: Double = 0
    private var lastDistance: Double = 0
    private var halfwayFired = false
    private var tenFired = false
    private var threeFired = false

    init(spec: RoadWorkoutSpec) {
        self.spec = spec
    }

    // MARK: Queries

    var isInRep: Bool {
        switch phase {
        case .rep: return true
        case .warmup, .recovery, .cooldown: return false
        }
    }

    var isInRepOrRecovery: Bool {
        switch phase {
        case .rep, .recovery: return true
        case .warmup, .cooldown: return false
        }
    }

    var phaseTitle: String {
        switch phase {
        case .warmup: return "Warm-up"
        case .rep(let number): return "Rep \(number) of \(spec.reps)"
        case .recovery: return "Recovery"
        case .cooldown: return "Cool-down"
        }
    }

    /// Time or distance left in the current rep or recovery. Both nil during warm-up and cool-down.
    func remaining(elapsed: Double, distance: Double) -> (seconds: Double?, meters: Double?) {
        switch phase {
        case .warmup, .cooldown:
            return (nil, nil)
        case .rep:
            switch spec.length {
            case .time(let seconds):
                return (max(0, Double(seconds) - (elapsed - phaseStartElapsed)), nil)
            case .distance(let meters):
                return (nil, max(0, meters - (distance - phaseStartDistance)))
            }
        case .recovery:
            return (max(0, Double(spec.recoverySeconds) - (elapsed - phaseStartElapsed)), nil)
        }
    }

    // MARK: Transitions

    /// Warm-up to rep 1. Does nothing in any other phase.
    @discardableResult
    mutating func startReps(elapsed: Double, distance: Double) -> [Event] {
        guard phase == .warmup else { return [] }
        beginRep(1, elapsed: elapsed, distance: distance)
        notePosition(elapsed: elapsed, distance: distance)
        return [.repStarted(1, total: spec.reps)]
    }

    /// Ends the current rep or recovery right now.
    @discardableResult
    mutating func skip(elapsed: Double, distance: Double) -> [Event] {
        var events: [Event] = []
        switch phase {
        case .warmup, .cooldown:
            break
        case .rep(let number):
            finishRep(number, endElapsed: max(elapsed, phaseStartElapsed),
                      endDistance: max(distance, phaseStartDistance), events: &events)
        case .recovery(let number):
            beginRep(number + 1, elapsed: max(elapsed, phaseStartElapsed),
                     distance: max(distance, phaseStartDistance))
            events.append(.repStarted(number + 1, total: spec.reps))
        }
        notePosition(elapsed: elapsed, distance: distance)
        return events
    }

    /// Advances the workout. Safe to call repeatedly with the same values: each event fires once.
    @discardableResult
    mutating func update(elapsed: Double, distance: Double) -> [Event] {
        let now = max(elapsed, lastElapsed)
        let travelled = max(distance, lastDistance)
        var events: [Event] = []
        var transitioned = true
        var passes = 0
        while transitioned && passes < 100 {
            transitioned = false
            passes += 1
            switch phase {
            case .warmup, .cooldown:
                break
            case .rep(let number):
                transitioned = stepRep(number, now: now, travelled: travelled, events: &events)
            case .recovery(let number):
                transitioned = stepRecovery(number, now: now, travelled: travelled, events: &events)
            }
        }
        notePosition(elapsed: now, distance: travelled)
        return events
    }

    // MARK: Internals

    private mutating func notePosition(elapsed: Double, distance: Double) {
        if elapsed >= lastElapsed {
            lastElapsed = elapsed
        }
        if distance >= lastDistance {
            lastDistance = distance
        }
    }

    private mutating func beginRep(_ number: Int, elapsed: Double, distance: Double) {
        phase = .rep(number)
        phaseStartElapsed = elapsed
        phaseStartDistance = distance
        halfwayFired = false
    }

    private mutating func beginRecovery(_ number: Int, elapsed: Double, distance: Double) {
        phase = .recovery(number)
        phaseStartElapsed = elapsed
        phaseStartDistance = distance
        tenFired = false
        threeFired = false
    }

    /// Distance at a moment between the previous update and this one.
    private func distanceAt(time target: Double, now: Double, travelled: Double) -> Double {
        guard now > lastElapsed, target < now else { return travelled }
        if target <= lastElapsed { return lastDistance }
        let fraction = (target - lastElapsed) / (now - lastElapsed)
        return lastDistance + fraction * (travelled - lastDistance)
    }

    /// Time at which cumulative distance reached `target`, between the previous update and this one.
    private func timeAt(distance target: Double, now: Double, travelled: Double) -> Double {
        guard travelled > lastDistance, now >= lastElapsed else { return now }
        let raw = (target - lastDistance) / (travelled - lastDistance)
        let fraction = min(1, max(0, raw))
        return max(phaseStartElapsed, lastElapsed + fraction * (now - lastElapsed))
    }

    private func averagePace(endElapsed: Double, endDistance: Double) -> Double? {
        let seconds = endElapsed - phaseStartElapsed
        let meters = endDistance - phaseStartDistance
        guard seconds > 0, meters >= 5 else { return nil }
        return seconds / meters * metersPerMile
    }

    private mutating func finishRep(_ number: Int, endElapsed: Double, endDistance: Double, events: inout [Event]) {
        events.append(.repEnded(number, avgPace: averagePace(endElapsed: endElapsed, endDistance: endDistance)))
        if number >= spec.reps {
            phase = .cooldown
            events.append(.workoutComplete)
        } else if spec.recoverySeconds > 0 {
            beginRecovery(number, elapsed: endElapsed, distance: endDistance)
        } else {
            beginRep(number + 1, elapsed: endElapsed, distance: endDistance)
            events.append(.repStarted(number + 1, total: spec.reps))
        }
    }

    /// Returns true when the phase changed.
    private mutating func stepRep(_ number: Int, now: Double, travelled: Double, events: inout [Event]) -> Bool {
        switch spec.length {
        case .time(let seconds):
            let length = Double(seconds)
            let spent = now - phaseStartElapsed
            if !halfwayFired && spent >= length / 2 {
                halfwayFired = true
                events.append(.halfway(number))
            }
            if spent >= length {
                let endElapsed = phaseStartElapsed + length
                let endDistance = distanceAt(time: endElapsed, now: now, travelled: travelled)
                finishRep(number, endElapsed: endElapsed, endDistance: endDistance, events: &events)
                return true
            }
        case .distance(let meters):
            let covered = travelled - phaseStartDistance
            if !halfwayFired && covered >= meters / 2 {
                halfwayFired = true
                events.append(.halfway(number))
            }
            if covered >= meters {
                let endDistance = phaseStartDistance + meters
                let endElapsed = timeAt(distance: endDistance, now: now, travelled: travelled)
                finishRep(number, endElapsed: endElapsed, endDistance: endDistance, events: &events)
                return true
            }
        }
        return false
    }

    /// Returns true when the phase changed.
    private mutating func stepRecovery(_ number: Int, now: Double, travelled: Double, events: inout [Event]) -> Bool {
        let length = Double(spec.recoverySeconds)
        let spent = now - phaseStartElapsed
        let left = length - spent
        if spec.recoverySeconds > 10 && !tenFired && left <= 10 {
            tenFired = true
            events.append(.recoveryCountdown(10))
        }
        if spec.recoverySeconds > 3 && !threeFired && left <= 3 {
            threeFired = true
            events.append(.recoveryCountdown(3))
        }
        if spent >= length {
            let endElapsed = phaseStartElapsed + length
            let endDistance = distanceAt(time: endElapsed, now: now, travelled: travelled)
            beginRep(number + 1, elapsed: endElapsed, distance: endDistance)
            events.append(.repStarted(number + 1, total: spec.reps))
            return true
        }
        return false
    }
}
