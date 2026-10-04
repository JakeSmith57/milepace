import Foundation

// MARK: - Plan file

struct PlanFile: Codable, Equatable {
    let name: String
    let startDate: String
    let weeks: [PlanWeek]
    let sessions: [PlanSession]
}

struct PlanWeek: Codable, Equatable {
    let week: Int
    let miles: Double
    let phase: Int
    let recovery: Bool
    let timeTrial: Bool
    let race: Bool
}

/// What kind of session this is. Unknown values in the file decode as `.other`.
enum SessionKind: String, Codable, Equatable, Hashable {
    case easy
    case long
    case road
    case track
    case timeTrial
    case race
    case other

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = SessionKind(rawValue: raw) ?? .other
    }
}

struct PlanSession: Codable, Equatable {
    let week: Int
    /// 1 = first day of the plan week (Monday when the plan starts on a Monday) ... 7.
    let weekday: Int
    let phase: Int
    let kind: SessionKind
    let title: String
    let miles: Double?
    /// A `RoadWorkoutSpec.name` for road sessions, a `WorkoutPreset.id` for track sessions.
    let preset: String?
    let note: String?

    /// True for sessions that belong on the track tab.
    var isTrackSession: Bool {
        switch kind {
        case .track, .timeTrial, .race: return true
        case .easy, .long, .road, .other: return false
        }
    }

    /// True for sessions that belong on the run tab.
    var isRunTabSession: Bool {
        switch kind {
        case .easy, .long, .road, .other: return true
        case .track, .timeTrial, .race: return false
        }
    }

    /// Short label for the week strip: "e2", "lg3", "trk", "rd", "tt", "race".
    var shortLabel: String {
        switch kind {
        case .easy: return "e" + PlanFormat.miles(miles)
        case .long: return "lg" + PlanFormat.miles(miles)
        case .road: return "rd"
        case .track: return "trk"
        case .timeTrial: return "tt"
        case .race: return "race"
        case .other: return "run"
        }
    }
}

// MARK: - Progress

enum SessionStatus: String, Codable, Equatable {
    case done
    case skipped
}

/// "From session `fromIndex` on, everything moves `days` later."
struct PlanShift: Codable, Equatable {
    let fromIndex: Int
    let days: Int
}

struct PlanProgress: Codable, Equatable {
    var shifts: [PlanShift] = []
    /// Keyed by the session index as a string, so the JSON stays a plain object.
    var statuses: [String: SessionStatus] = [:]

    static func key(_ index: Int) -> String {
        return String(index)
    }
}

// MARK: - Routing

/// Where "start" on the today screen sends the runner.
enum PlanRoute: Equatable {
    case freeRun(zone: RunZoneTarget)
    case roadWorkout(name: String)
    case track(presetId: String?)

    static func route(for session: PlanSession) -> PlanRoute {
        switch session.kind {
        case .easy, .long:
            return .freeRun(zone: .easy)
        case .road:
            if let name = session.preset {
                return .roadWorkout(name: name)
            }
            return .freeRun(zone: .threshold)
        case .track, .timeTrial, .race:
            return .track(presetId: session.preset)
        case .other:
            return .freeRun(zone: .off)
        }
    }
}

// MARK: - Week strip model

enum StripState: Equatable {
    case rest
    case planned
    case today
    case done
    case skipped
    case missed
}

struct StripCell: Equatable {
    let state: StripState
    let label: String
}

// MARK: - Schedule

/// The plan plus the runner's progress. Days are offsets from the plan start (start = 0).
struct PlanSchedule {
    let plan: PlanFile
    let progress: PlanProgress

    /// Days from plan start for session `index`, including every shift that applies to it.
    func dayOffset(_ index: Int) -> Int {
        guard plan.sessions.indices.contains(index) else { return 0 }
        let session = plan.sessions[index]
        var offset = (session.week - 1) * 7 + (session.weekday - 1)
        for shift in progress.shifts where shift.fromIndex <= index {
            offset += shift.days
        }
        return offset
    }

    func indices(onDay day: Int) -> [Int] {
        return plan.sessions.indices.filter { dayOffset($0) == day }
    }

    func status(_ index: Int) -> SessionStatus? {
        return progress.statuses[PlanProgress.key(index)]
    }

    /// Oldest session before `today` with no status.
    func firstMissed(today: Int) -> Int? {
        return plan.sessions.indices.first(where: { dayOffset($0) < today && status($0) == nil })
    }

    /// Sessions scheduled for `today` with no status.
    func todays(today: Int) -> [Int] {
        return plan.sessions.indices.filter { dayOffset($0) == today && status($0) == nil }
    }

    /// First session strictly after `today` with no status.
    func next(after today: Int) -> Int? {
        return plan.sessions.indices.first(where: { dayOffset($0) > today && status($0) == nil })
    }

    /// Day offset of the race session (the last session when the file has no race).
    var raceDayOffset: Int {
        if let race = plan.sessions.lastIndex(where: { $0.kind == .race }) {
            return dayOffset(race)
        }
        if let last = plan.sessions.indices.last {
            return dayOffset(last)
        }
        return 0
    }

    /// Plan week to show for `today`: 0 before the start, the last week after the race, otherwise the
    /// week of today's session (or the next one).
    func currentWeek(today: Int) -> Int {
        let total = plan.weeks.count
        if today < 0 { return 0 }
        if today > raceDayOffset { return total }
        if let index = indices(onDay: today).first ?? next(after: today) {
            return plan.sessions[index].week
        }
        return total
    }

    /// First day offset of the seven-day strip that holds `today`.
    func stripStart(today: Int) -> Int {
        if today < 0 { return 0 }
        let capped = min(today, raceDayOffset)
        return (capped / 7) * 7
    }

    /// Day offset on which plan week `week` starts, following any shifts.
    func startOffset(ofWeek week: Int) -> Int {
        if let index = plan.sessions.firstIndex(where: { $0.week == week }) {
            return dayOffset(index) - (plan.sessions[index].weekday - 1)
        }
        return (week - 1) * 7
    }

    /// Nearest unfinished track session using preset `id` from `today` through `today + days`.
    func nearestDay(forPreset id: String, today: Int, within days: Int) -> Int? {
        var best: Int? = nil
        for index in plan.sessions.indices {
            let session = plan.sessions[index]
            guard session.isTrackSession, session.preset == id, status(index) == nil else { continue }
            let day = dayOffset(index)
            guard day >= today, day <= today + days else { continue }
            if let current = best, current <= day { continue }
            best = day
        }
        return best
    }

    /// What one cell of the week strip shows.
    func stripCell(day: Int, today: Int) -> StripCell {
        let ids = indices(onDay: day)
        guard let first = ids.first else {
            return StripCell(state: day == today ? .today : .rest, label: "\u{00B7}")
        }
        let statuses = ids.map { status($0) }
        if !statuses.contains(where: { $0 == nil }) {
            if statuses.contains(where: { $0 == SessionStatus.done }) {
                return StripCell(state: .done, label: "x")
            }
            return StripCell(state: .skipped, label: "\u{2013}")
        }
        let label = plan.sessions[first].shortLabel
        if day == today {
            return StripCell(state: .today, label: label)
        }
        if day < today {
            return StripCell(state: .missed, label: "!")
        }
        return StripCell(state: .planned, label: label)
    }

    /// Progress after choosing "do it today" for a missed session: that session and every later one
    /// move back by the days between its scheduled day and today.
    func pushingBack(missed: Int, today: Int) -> PlanProgress {
        guard plan.sessions.indices.contains(missed) else { return progress }
        let days = today - dayOffset(missed)
        guard days > 0 else { return progress }
        var updated = progress
        updated.shifts.append(PlanShift(fromIndex: missed, days: days))
        return updated
    }

    func skipping(_ index: Int) -> PlanProgress {
        guard plan.sessions.indices.contains(index) else { return progress }
        var updated = progress
        updated.statuses[PlanProgress.key(index)] = .skipped
        return updated
    }

    func markingDone(_ index: Int) -> PlanProgress {
        guard plan.sessions.indices.contains(index) else { return progress }
        var updated = progress
        updated.statuses[PlanProgress.key(index)] = .done
        return updated
    }

    /// Marks done every session with no status whose scheduled day has a logged activity.
    func reconciled(activityDays: Set<Int>) -> PlanProgress {
        var updated = progress
        for index in plan.sessions.indices {
            guard status(index) == nil else { continue }
            if activityDays.contains(dayOffset(index)) {
                updated.statuses[PlanProgress.key(index)] = .done
            }
        }
        return updated
    }
}

// MARK: - Loading

enum PlanLoader {
    static func decode(_ data: Data) -> PlanFile? {
        return try? JSONDecoder().decode(PlanFile.self, from: data)
    }

    /// Reads `plan.json` from the bundle; nil when it is missing or does not parse.
    static func load(bundle: Bundle) -> PlanFile? {
        guard let url = bundle.url(forResource: "plan", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decode(data)
    }
}

// MARK: - Calendar

/// Date and day-offset conversion: Gregorian, start of day, local time zone. Day counts always go
/// through `Calendar.dateComponents` between start-of-day values, so DST changes cannot shift them.
enum PlanCalendar {
    static var local: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }

    static func dayOffset(of date: Date, start: Date, calendar: Calendar = PlanCalendar.local) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    static func date(forOffset offset: Int, start: Date, calendar: Calendar = PlanCalendar.local) -> Date {
        let from = calendar.startOfDay(for: start)
        return calendar.date(byAdding: .day, value: offset, to: from) ?? from
    }

    /// "2026-10-12" as the start of that day; nil for anything that is not a real date.
    static func parse(_ ymd: String, calendar: Calendar = PlanCalendar.local) -> Date? {
        let parts = ymd.split(separator: "-").map { Int($0) }
        guard parts.count == 3,
              let year = parts[0],
              let month = parts[1],
              let day = parts[2] else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// "2026-10-12".
    static func ymd(_ date: Date, calendar: Calendar = PlanCalendar.local) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - Text

/// Small text helpers for the plan screens.
enum PlanFormat {
    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    private static let shortDateFormatter: DateFormatter = PlanFormat.makeFormatter("MMM d")
    private static let weekdayFormatter: DateFormatter = PlanFormat.makeFormatter("EEEE")
    private static let letterFormatter: DateFormatter = PlanFormat.makeFormatter("EEEEE")

    /// "2", "1.5"; empty for nil.
    static func miles(_ value: Double?) -> String {
        guard let value = value, value.isFinite else { return "" }
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    /// "oct 26".
    static func shortDate(_ date: Date) -> String {
        return shortDateFormatter.string(from: date).lowercased()
    }

    static func shortDate(offset: Int, start: Date) -> String {
        return shortDate(PlanCalendar.date(forOffset: offset, start: start))
    }

    /// "tue oct 20".
    static func dayLabel(offset: Int, start: Date) -> String {
        return ReadoutFormat.day(PlanCalendar.date(forOffset: offset, start: start))
    }

    /// "saturday".
    static func weekdayName(_ date: Date) -> String {
        return weekdayFormatter.string(from: date).lowercased()
    }

    /// "s".
    static func weekdayLetter(_ date: Date) -> String {
        return letterFormatter.string(from: date).lowercased()
    }

    /// "1 day", "8 days".
    static func daysText(_ days: Int) -> String {
        return days == 1 ? "1 day" : "\(days) days"
    }
}
