import Foundation

/// Plain-language wording for the track screens: distances in laps of a 400 m track, targets with units,
/// and where to start. Pure, so it is tested.
enum TrackLaps {
    static let lapMeters = 400

    /// "half a lap", "3/4 of a lap", "1 lap", "1 1/2 laps", "4 laps + 9 m" for a rep distance in meters.
    static func describe(meters: Int) -> String {
        guard meters > 0 else { return "0 m" }
        let whole = meters / lapMeters
        let rest = meters % lapMeters
        if whole == 0 {
            switch rest {
            case 100: return "a quarter lap"
            case 200: return "half a lap"
            case 300: return "\u{00BE} of a lap"
            default: return "\(meters) m"
            }
        }
        if rest == 0 {
            return whole == 1 ? "1 lap" : "\(whole) laps"
        }
        switch rest {
        case 100: return "\(whole)\u{00BC} laps"
        case 200: return "\(whole)\u{00BD} laps"
        case 300: return "\(whole)\u{00BE} laps"
        default: return (whole == 1 ? "1 lap" : "\(whole) laps") + " + \(rest) m"
        }
    }

    /// Where to start and finish a rep of this distance.
    static func startNote(meters: Int) -> String {
        if meters >= lapMeters {
            return "start and finish at the same line"
        }
        if meters == 200 {
            return "start anywhere; finish half a lap later (directly across the track)"
        }
        return "start anywhere; finish \(describe(meters: meters)) later"
    }

    static let laneNote = "run in lane 1 (inside); lane 2 adds ~7 m per lap."

    /// "55.5 s" under a minute, "1:44.0" from a minute up. Never a bare number.
    static func timeWithUnit(_ seconds: Double) -> String {
        let text = formatSplit(seconds)
        return seconds.isFinite && seconds < 59.95 ? text + " s" : text
    }

    /// "s" for a time under a minute (shown as 55.5 s), "" from a minute up (1:44.0).
    static func unit(forSeconds seconds: Double) -> String {
        return seconds.isFinite && seconds < 59.95 ? "s" : ""
    }

    /// "target 55.5 s per 200 m".
    static func targetText(seconds: Double, meters: Int) -> String {
        return "target " + timeWithUnit(seconds) + " per \(meters) m"
    }

    /// "lap 1 target 1:44.0" (one-based lap).
    static func lapTargetText(lap: Int, seconds: Double) -> String {
        return "lap \(lap) target " + timeWithUnit(seconds)
    }

    /// "rep 2 of 4 \u{00B7} 200 m \u{00B7} half a lap".
    static func repHeader(rep: Int, total: Int, meters: Int) -> String {
        return "rep \(rep) of \(total) \u{00B7} \(meters) m \u{00B7} " + describe(meters: meters)
    }
}
