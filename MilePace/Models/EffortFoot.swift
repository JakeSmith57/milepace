import Foundation

// MARK: - Foot check

/// A run or workout with its foot pain rating, for the Today warning.
struct FootEntry: Equatable {
    let date: Date
    /// 0 to 10; -1 when not set.
    let value: Int
    var isTest: Bool = false
}

enum FootCheck {
    /// Pain at or above this shows the warning.
    static let warnAt = 4
    /// How far back a run or workout still counts, in days.
    static let days = 3

    /// The most recent rated entry in the last 3 days when its pain is 4 or more; nil otherwise. Entries
    /// without a rating are skipped, so an unrated run after a sore one does not clear the warning, and a later
    /// rating of 0 to 3 does. Test entries and future dates are ignored.
    static func warning(entries: [FootEntry], now: Date) -> (value: Int, date: Date)? {
        let earliest = now.addingTimeInterval(-Double(days) * 86400)
        let recent = entries.filter { entry in
            !entry.isTest && entry.value >= 0 && entry.date >= earliest && entry.date <= now
        }
        guard let latest = recent.max(by: { $0.date < $1.date }), latest.value >= warnAt else { return nil }
        return (latest.value, latest.date)
    }

    /// "take the next day easy or off. ..." under the foot row once the pain is 4 or more.
    static let advice = "take the next day easy or off. if it still hurts after 2 days or gets worse, get it checked."

    /// The Today card text: "foot pain 5 on tue oct 20. go easy today; skip if it still hurts."
    static func cardText(value: Int, day: String) -> String {
        return "foot pain \(value) on \(day). go easy today; skip if it still hurts."
    }
}

// MARK: - Effort and foot text

/// How effort and foot pain read in the log and in the export.
enum FeelText {
    /// " \u{00B7} rpe 7 \u{00B7} foot 3" for a log row: rpe when set (1 to 10), foot only from 1 up; empty when neither.
    static func logSuffix(effort: Int, footPain: Int) -> String {
        var text = ""
        if effort >= 1 {
            text += " \u{00B7} rpe \(effort)"
        }
        if footPain >= 1 {
            text += " \u{00B7} foot \(footPain)"
        }
        return text
    }

    /// "rpe 7, foot 0" for the export: each part only when set (foot 0 is a real answer); nil when neither is.
    static func exportText(effort: Int, footPain: Int) -> String? {
        var parts: [String] = []
        if effort >= 1 {
            parts.append("rpe \(effort)")
        }
        if footPain >= 0 {
            parts.append("foot \(footPain)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
