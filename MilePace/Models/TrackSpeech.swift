import Foundation

/// The words the track coach says. Pure text, so the wording is tested; `Coach` only speaks it.
enum TrackSpeech {
    /// Halfway cues are for reps of this many meters or more (GPS mode only).
    static let halfwayMinMeters = 400
    /// "100 to go." is for reps of this many meters or more (GPS mode only).
    static let hundredToGoMinMeters = 300
    /// Within this many seconds of the target counts as "On target.".
    static let onTargetBand = 0.45

    // MARK: Times

    /// "52 seconds", "1 second", "1 minute 44", "2 minutes": whole seconds, for a target.
    static func targetPhrase(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 seconds" }
        let total = Int(seconds.rounded())
        if total < 60 {
            return total == 1 ? "1 second" : "\(total) seconds"
        }
        return wholeMinutesSeconds(total)
    }

    /// "52" under a minute, "1 minute 44" from a minute up: whole seconds, no unit for the seconds part.
    static func plainTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0" }
        let total = Int(seconds.rounded())
        if total < 60 {
            return "\(total)"
        }
        return wholeMinutesSeconds(total)
    }

    private static func wholeMinutesSeconds(_ total: Int) -> String {
        let minutes = total / 60
        let secs = total % 60
        let head = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return secs == 0 ? head : head + " \(secs)"
    }

    /// "55.8", "1 minute 44.2", "2 minutes": a rep time to a tenth of a second.
    static func tenthsTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0" }
        let tenths = Int((seconds * 10).rounded())
        let minutes = tenths / 600
        let remainder = tenths % 600
        if minutes == 0 {
            return String(format: "%.1f", Double(remainder) / 10)
        }
        let head = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if remainder == 0 {
            return head
        }
        return head + " " + String(format: "%.1f", Double(remainder) / 10)
    }

    // MARK: Deltas

    /// delta = actual - target. "On target.", "Half a second fast.", "1 second slow.", "2.3 seconds fast."
    /// One decimal is used only when the amount is not a whole number of seconds.
    static func delta(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "On target." }
        let magnitude = abs(seconds)
        if magnitude < onTargetBand {
            return "On target."
        }
        let direction = seconds < 0 ? "fast" : "slow"
        if magnitude <= 0.55 {
            return "Half a second \(direction)."
        }
        let tenths = (magnitude * 10).rounded() / 10
        return secondsAmount(tenths) + " " + direction + "."
    }

    private static func secondsAmount(_ value: Double) -> String {
        let whole = value.rounded()
        if abs(value - whole) < 0.001 {
            let count = Int(whole)
            return count == 1 ? "1 second" : "\(count) seconds"
        }
        return String(format: "%.1f seconds", value)
    }

    // MARK: Cues

    /// Meters as said aloud: "200 meters", "1 mile" for the 1609.
    static func spokenMeters(_ meters: Int) -> String {
        return meters == 1609 ? "1 mile" : "\(meters) meters"
    }

    /// "Rep 2 of 4. 200 meters. Target 55 seconds." The final rep of several starts with "Last one."
    static func repIntro(rep: Int, total: Int, meters: Int, targetSeconds: Double) -> String {
        var text = ""
        if total > 1 && rep >= total {
            text += "Last one. "
        }
        if total > 1 {
            text += "Rep \(rep) of \(total). "
        }
        text += spokenMeters(meters) + ". Target " + targetPhrase(targetSeconds) + "."
        return text
    }

    /// "Halfway. 52. On pace." / "Halfway. 52. 2 seconds fast." `elapsed` against `halfTarget`, the
    /// pro-rated target at the halfway point.
    static func halfway(elapsed: Double, halfTarget: Double) -> String {
        let difference = elapsed - halfTarget
        let verdict: String
        switch SplitVerdict.verdict(delta: difference) {
        case .onPace:
            verdict = "On pace."
        case .fast, .slow:
            let whole = max(1, Int(abs(difference).rounded()))
            let unit = whole == 1 ? "second" : "seconds"
            verdict = "\(whole) \(unit) " + (difference < 0 ? "fast." : "slow.")
        }
        return "Halfway. " + plainTime(elapsed) + ". " + verdict
    }

    static let hundredToGo = "100 to go."

    /// "Rest 60 seconds." (under two minutes in seconds, otherwise minutes and seconds); empty without a rest.
    static func restPhrase(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        if seconds < 120 {
            return "Rest \(seconds) seconds."
        }
        return "Rest " + spokenMinutesSeconds(Double(seconds)) + "."
    }

    /// "55.8. Half a second slow. Rest 60 seconds." `restSeconds` nil or 0 leaves the rest out.
    static func repDone(time: Double, delta: Double, restSeconds: Int?) -> String {
        var text = tenthsTime(time) + ". " + TrackSpeech.delta(delta)
        if let rest = restSeconds, rest > 0 {
            text += " " + restPhrase(seconds: rest)
        }
        return text
    }

    /// "Last rep done. Average 55.2." (a one-rep workout says the time instead of an average).
    static func lastRepDone(average: Double) -> String {
        return "Last rep done. Average " + tenthsTime(average) + "."
    }

    /// What is said while a rest runs: "30 seconds." and "10 seconds." and "3, 2, 1."; nil for other seconds.
    static func restCountdown(seconds: Int, restTotal: Double) -> String? {
        switch seconds {
        case 30: return restTotal >= 60 ? "30 seconds." : nil
        case 10: return "10 seconds."
        case 3: return "3, 2, 1."
        default: return nil
        }
    }
}
