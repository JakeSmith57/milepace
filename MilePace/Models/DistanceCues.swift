import Foundation

/// How often the runner hears a short pace cue.
enum CueInterval: String, CaseIterable, Identifiable {
    case off
    case quarter
    case half
    case mile

    var id: String { rawValue }

    /// Interval length in meters, or nil when cues are off.
    var meters: Double? {
        switch self {
        case .off: return nil
        case .quarter: return metersPerMile / 4
        case .half: return metersPerMile / 2
        case .mile: return metersPerMile
        }
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .quarter: return "¼ mi"
        case .half: return "½ mi"
        case .mile: return "1 mi"
        }
    }

    var spokenName: String {
        switch self {
        case .off: return ""
        case .quarter: return "Quarter"
        case .half: return "Half"
        case .mile: return "Mile"
        }
    }

    /// How many cues make up one whole mile (4, 2, 1), or nil when off.
    var cuesPerMile: Int? {
        switch self {
        case .off: return nil
        case .quarter: return 4
        case .half: return 2
        case .mile: return 1
        }
    }
}

struct DistanceCue: Equatable {
    /// 1-based boundary number.
    let index: Int
    let splitSeconds: Double
    let paceSecondsPerMile: Double
}

/// Emits a cue each time cumulative distance crosses a multiple of the interval.
struct DistanceCueTracker {
    let intervalMeters: Double

    private var anchored = false
    private var lastDistance: Double = 0
    private var lastElapsed: Double = 0
    private var lastCrossing: Double = 0
    private var nextIndex: Int = 1

    init(intervalMeters: Double) {
        self.intervalMeters = intervalMeters
    }

    /// Feed cumulative distance (meters) and moving elapsed time (seconds). Returns one cue for every
    /// boundary crossed since the previous call, with the crossing time linearly interpolated.
    /// The first call only anchors the tracker.
    @discardableResult
    mutating func update(distance: Double, elapsed: Double) -> [DistanceCue] {
        guard intervalMeters > 0, distance.isFinite, elapsed.isFinite else { return [] }

        if !anchored {
            anchored = true
            lastDistance = max(0, distance)
            lastElapsed = max(0, elapsed)
            lastCrossing = lastElapsed
            nextIndex = Int((lastDistance / intervalMeters).rounded(.down)) + 1
            return []
        }

        let currentDistance = max(distance, lastDistance)
        let currentElapsed = max(elapsed, lastElapsed)
        var cues: [DistanceCue] = []
        while currentDistance >= Double(nextIndex) * intervalMeters {
            let boundary = Double(nextIndex) * intervalMeters
            let span = currentDistance - lastDistance
            let fraction = span > 0 ? (boundary - lastDistance) / span : 1
            let crossing = lastElapsed + fraction * (currentElapsed - lastElapsed)
            let split = max(0, crossing - lastCrossing)
            let pace = split / intervalMeters * metersPerMile
            cues.append(DistanceCue(index: nextIndex, splitSeconds: split, paceSecondsPerMile: pace))
            lastCrossing = crossing
            nextIndex += 1
        }
        lastDistance = currentDistance
        lastElapsed = currentElapsed
        return cues
    }
}

/// Spoken comparison of a pace against a target range.
enum ZoneVerdict {
    /// "On target." / "4 seconds fast." / "1 second slow."
    static func phrase(pace: Double, zone: ClosedRange<Double>) -> String {
        if pace < zone.lowerBound {
            return "\(seconds(zone.lowerBound - pace)) fast."
        }
        if pace > zone.upperBound {
            return "\(seconds(pace - zone.upperBound)) slow."
        }
        return "On target."
    }

    private static func seconds(_ delta: Double) -> String {
        let whole = max(1, Int(delta.rounded()))
        return whole == 1 ? "1 second" : "\(whole) seconds"
    }
}
