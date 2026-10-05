import Foundation

/// Detail text for a plan session, shared by the today screen and the reminders so they always agree.
enum PlanText {
    /// The road workout a road session points at, if its preset is known.
    static func roadSpec(for session: PlanSession) -> RoadWorkoutSpec? {
        guard let name = session.preset else { return nil }
        return RoadWorkoutPresets.all.first(where: { $0.name == name })
    }

    /// The track workout a session points at, built from the current zones and goal mile.
    static func trackSpec(for session: PlanSession, zones: PaceZones, goalMile: Double) -> WorkoutSpec? {
        guard let id = session.preset else { return nil }
        let preset = WorkoutPresets.all.first(where: { $0.id == id })
        return preset?.spec(zones: zones, goalMile: goalMile)
    }

    /// "82.4 per rep \u{00B7} 82.4 per 400" for a track workout.
    static func trackLine(_ spec: WorkoutSpec) -> String {
        var text = formatSplit(spec.targetRepSeconds) + " per rep"
        if spec.repDistance != 400 {
            text += " \u{00B7} " + formatSplit(spec.targetPer400) + " per 400"
        }
        return text
    }

    /// What the missed card says when the session itself has no room left this week.
    static let noRoomNote = "no room this week. it'll be skipped."

    /// The missed card's main button: "do it today", or "move to wed oct 21" when the first allowed day
    /// is later. `label` is the target day's label.
    static func moveTitle(day: Int, today: Int, label: String) -> String {
        return day == today ? "do it today" : "move to " + label
    }

    /// "1 session", "3 sessions".
    static func sessionCount(_ count: Int) -> String {
        return count == 1 ? "1 session" : "\(count) sessions"
    }

    /// What the missed card says before the push is confirmed. `moved` is how many other sessions of the
    /// week move, `dropped` describes the sessions skipped to make room ("the 2 mi easy on fri"), and
    /// `targetLabel` is the day the missed session lands on when that is not today ("moving it to wed oct 21 moves ...").
    static func pushNote(moved: Int, dropped: [String], targetLabel: String? = nil) -> String {
        if moved <= 0 && dropped.isEmpty {
            if let label = targetLabel {
                return "moves to " + label + "."
            }
            return "moves to today."
        }
        var text = targetLabel.map { "moving it to " + $0 } ?? "doing it today"
        if moved > 0 {
            text += " moves " + sessionCount(moved) + " this week"
        }
        if !dropped.isEmpty {
            text += (moved > 0 ? " and skips " : " skips ") + String(dropped.count)
                + " (" + dropped.joined(separator: ", ") + ")"
        }
        return text + "."
    }

    /// "the 2 mi easy on fri": a skipped session named for the note.
    static func droppedItem(title: String, dayShort: String) -> String {
        return "the " + title + " on " + dayShort
    }

    /// "target \u{2264} 6:35" for a time trial that has a goal time; nil for everything else.
    static func trialTarget(for session: PlanSession) -> String? {
        guard session.kind == .timeTrial, let seconds = session.targetSeconds, seconds > 0 else { return nil }
        return "target \u{2264} " + formatPace(secondsPerMile: seconds)
    }

    /// "goal 5:30": the race's own goal time, or `goalMile` when the plan gives none.
    static func raceGoal(for session: PlanSession, goalMile: Double) -> String {
        let seconds = session.targetSeconds ?? goalMile
        return "goal " + formatPace(secondsPerMile: seconds)
    }

    /// The detail lines under a session title, in display order.
    /// `window` is the pace window setting: ranges narrower than twice that are widened to it.
    static func lines(for session: PlanSession,
                      zones: PaceZones,
                      goalMile: Double,
                      window: Double = PaceZones.defaultWindow) -> [String] {
        var lines: [String] = []
        switch session.kind {
        case .easy, .long:
            var line = ""
            if let miles = session.miles {
                line = PlanFormat.miles(miles) + " mi, "
            }
            line += "conversational, " + ReadoutFormat.paceRange(PaceZones.guardRange(zones.easy, window: window)) + " /mi"
            lines.append(line)
        case .road:
            if let spec = roadSpec(for: session) {
                let range = spec.target.guardedRange(zones: zones, goalMile: goalMile, window: window)
                lines.append(spec.target.rawValue + " " + ReadoutFormat.paceRange(range) + " /mi")
            }
        case .track:
            if let spec = trackSpec(for: session, zones: zones, goalMile: goalMile) {
                lines.append(trackLine(spec))
            }
        case .timeTrial:
            if let target = trialTarget(for: session) {
                lines.append(target)
            }
        case .race:
            lines.append(raceGoal(for: session, goalMile: goalMile))
        case .other:
            break
        }
        if let note = session.note, !note.isEmpty, !lines.contains(where: { sameText($0, note) }) {
            lines.append(note)
        }
        return lines
    }

    /// Whether two lines say the same thing, ignoring case, spaces and a final full stop.
    static func sameText(_ left: String, _ right: String) -> Bool {
        func normal(_ text: String) -> String {
            var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while trimmed.hasSuffix(".") {
                trimmed.removeLast()
            }
            return trimmed
        }
        return normal(left) == normal(right)
    }

    /// The detail lines as one sentence-style string: "target \u{2264} 6:35. keep the first lap easy."
    /// Empty when there is nothing to say.
    static func detail(for session: PlanSession,
                       zones: PaceZones,
                       goalMile: Double,
                       window: Double = PaceZones.defaultWindow) -> String {
        let parts = lines(for: session, zones: zones, goalMile: goalMile, window: window).map { line -> String in
            var trimmed = line
            while trimmed.hasSuffix(".") {
                trimmed.removeLast()
            }
            return trimmed
        }
        let usable = parts.filter { !$0.isEmpty }
        if usable.isEmpty {
            return ""
        }
        return usable.joined(separator: ". ") + "."
    }
}
