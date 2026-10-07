import Foundation

/// Pace and treadmill speed are the same thing in two units: mph = 3600 / seconds per mile.
enum TreadmillSpeed {
    /// Miles per hour for a pace in seconds per mile; nil when the pace is not a positive number.
    static func mph(pace: Double) -> Double? {
        guard pace.isFinite, pace > 0 else { return nil }
        return 3600 / pace
    }

    /// "7.5" for a pace of 8:00 per mile, one decimal; "--" when there is no speed.
    static func mphText(pace: Double) -> String {
        guard let speed = mph(pace: pace) else { return "--" }
        return String(format: "%.1f", speed)
    }

    /// "8:00" for 7.5 mph (a pace per mile); "--:--" when the speed is not a positive number.
    static func paceText(mph: Double) -> String {
        guard mph.isFinite, mph > 0 else { return "--:--" }
        return formatPace(secondsPerMile: 3600 / mph)
    }

    /// "7.2\u{2013}7.8 mph" for a pace range in seconds per mile (the faster pace is the higher speed);
    /// one number when both ends round to the same speed.
    static func rangeText(_ paceRange: ClosedRange<Double>) -> String {
        let low = mphText(pace: paceRange.upperBound)
        let high = mphText(pace: paceRange.lowerBound)
        if low == high {
            return low + " mph"
        }
        return low + "\u{2013}" + high + " mph"
    }

    /// Shown once on the treadmill setup.
    static let inclineNote = "set 1% incline to match outdoor effort."
}

/// Which guided road workouts a treadmill can do: only timed ones, since distance reps need GPS.
enum TreadmillWorkouts {
    static func isTimeBased(_ spec: RoadWorkoutSpec) -> Bool {
        switch spec.length {
        case .time: return true
        case .distance: return false
        }
    }

    static func timeBased(_ specs: [RoadWorkoutSpec]) -> [RoadWorkoutSpec] {
        return specs.filter { isTimeBased($0) }
    }

    /// Shown under the workout list on the treadmill.
    static let distanceNote = "distance reps need gps; use a timed workout or the track."
}

/// The spoken "10 minutes" marks of a treadmill run.
enum TreadmillCue {
    static let intervalMinutes = 5

    /// The newest whole mark (5, 10, 15 ... minutes) reached by `elapsed` seconds that is later than
    /// `lastMark`, or nil. A late tick that skipped a mark still gets the latest one, once.
    static func newMark(elapsed: Double, lastMark: Int) -> Int? {
        guard elapsed.isFinite, elapsed >= 0 else { return nil }
        let minutes = Int(elapsed / 60)
        let mark = minutes / intervalMinutes * intervalMinutes
        guard mark >= intervalMinutes, mark > lastMark else { return nil }
        return mark
    }

    /// "10 minutes." with " Cadence 172." when the cadence is known.
    static func spokenText(minutes: Int, cadence: Double?) -> String {
        var text = "\(minutes) minutes."
        if let spm = cadence, spm.isFinite, spm > 0 {
            text += " Cadence \(Int(spm.rounded()))."
        }
        return text
    }
}
