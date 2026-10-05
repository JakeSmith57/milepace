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

    /// What the missed card says when no day this week has room.
    static let noRoomNote = "no room this week. it'll be skipped."

    /// The missed card's main button: "do it today", or "move to wed oct 21" for a later day.
    /// `label` is the target day's label.
    static func moveTitle(day: Int, today: Int, label: String) -> String {
        return day == today ? "do it today" : "move to " + label
    }

    /// The line under the button when the missed session takes an easy session's day: "replaces thu
    /// 3 mi easy." `dayLabel` is the easy session's day label ("thu oct 22").
    static func replacesNote(dayLabel: String, title: String) -> String {
        return "replaces " + String(dayLabel.prefix(3)) + " " + title + "."
    }

    /// The detail lines under a session title, in display order.
    static func lines(for session: PlanSession, zones: PaceZones, goalMile: Double) -> [String] {
        var lines: [String] = []
        switch session.kind {
        case .easy, .long:
            var line = ""
            if let miles = session.miles {
                line = PlanFormat.miles(miles) + " mi, "
            }
            line += "conversational, " + ReadoutFormat.paceRange(zones.easy) + " /mi"
            lines.append(line)
        case .road:
            if let spec = roadSpec(for: session) {
                let range = spec.target.range(zones: zones, goalMile: goalMile)
                lines.append(spec.target.rawValue + " " + ReadoutFormat.paceRange(range) + " /mi")
            }
        case .track:
            if let spec = trackSpec(for: session, zones: zones, goalMile: goalMile) {
                lines.append(trackLine(spec))
            }
        case .timeTrial, .race:
            lines.append("goal " + formatPace(secondsPerMile: goalMile))
        case .other:
            break
        }
        if let note = session.note, !note.isEmpty {
            lines.append(note)
        }
        return lines
    }

    /// The detail lines as one sentence-style string: "goal 5:30. target \u{2264} 6:35." Empty when
    /// there is nothing to say.
    static func detail(for session: PlanSession, zones: PaceZones, goalMile: Double) -> String {
        let parts = lines(for: session, zones: zones, goalMile: goalMile).map { line -> String in
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
