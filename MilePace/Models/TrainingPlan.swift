import Foundation

// MARK: - Plan file

struct PlanFile: Codable, Equatable {
    let name: String
    /// Bumped whenever the plan changes shape; stored progress from another version is discarded.
    /// Files without a version are version 1.
    let version: Int
    let startDate: String
    /// "yyyy-MM-dd" of the race, when the file names one.
    let raceDate: String?
    let weeks: [PlanWeek]
    let sessions: [PlanSession]

    enum CodingKeys: String, CodingKey {
        case name
        case version
        case startDate
        case raceDate
        case weeks
        case sessions
    }

    init(name: String,
         version: Int = 1,
         startDate: String,
         raceDate: String? = nil,
         weeks: [PlanWeek],
         sessions: [PlanSession]) {
        self.name = name
        self.version = version
        self.startDate = startDate
        self.raceDate = raceDate
        self.weeks = weeks
        self.sessions = sessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        startDate = try container.decode(String.self, forKey: .startDate)
        raceDate = try container.decodeIfPresent(String.self, forKey: .raceDate)
        weeks = try container.decode([PlanWeek].self, forKey: .weeks)
        sessions = try container.decode([PlanSession].self, forKey: .sessions)
    }
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
    /// Goal time in seconds for time trials and the race; nil for every other session.
    var targetSeconds: Double? = nil

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

/// "From session `fromIndex` on, everything moves `days` later." Only the v1.5 model used this; the
/// shifts are still decoded so old saved progress parses, but nothing reads them any more.
struct PlanShift: Codable, Equatable {
    let fromIndex: Int
    let days: Int
}

struct PlanProgress: Codable, Equatable {
    /// Decoded from v1.5 progress and ignored.
    var shifts: [PlanShift] = []
    /// Keyed by the session index as a string, so the JSON stays a plain object.
    var statuses: [String: SessionStatus] = [:]
    /// Session index (as a string) to an absolute day offset from the plan start. A session with no
    /// entry is on its planned day.
    var dayOverrides: [String: Int] = [:]
    /// `PlanFile.version` this progress belongs to.
    var planVersion: Int = 1
    /// Session indices (as strings) whose `.done` came from a saved activity (a reconcile match or the
    /// run that was started for the session), not from the runner's own tap. Those marks are taken back
    /// when the activity is deleted; a manual done or skip is never listed here.
    var autoDone: Set<String> = []

    enum CodingKeys: String, CodingKey {
        case shifts
        case statuses
        case dayOverrides
        case planVersion
        case autoDone
    }

    init(shifts: [PlanShift] = [],
         statuses: [String: SessionStatus] = [:],
         dayOverrides: [String: Int] = [:],
         planVersion: Int = 1,
         autoDone: Set<String> = []) {
        self.shifts = shifts
        self.statuses = statuses
        self.dayOverrides = dayOverrides
        self.planVersion = planVersion
        self.autoDone = autoDone
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        shifts = try container.decodeIfPresent([PlanShift].self, forKey: .shifts) ?? []
        statuses = try container.decodeIfPresent([String: SessionStatus].self, forKey: .statuses) ?? [:]
        dayOverrides = try container.decodeIfPresent([String: Int].self, forKey: .dayOverrides) ?? [:]
        planVersion = try container.decodeIfPresent(Int.self, forKey: .planVersion) ?? 1
        autoDone = try container.decodeIfPresent(Set<String>.self, forKey: .autoDone) ?? []
    }

    static func key(_ index: Int) -> String {
        return String(index)
    }

    /// Progress saved by an earlier run of the app, or a fresh one for `planVersion` when there is
    /// nothing saved, it does not parse, or it belongs to a different plan version.
    static func restored(from data: Data?, planVersion: Int) -> PlanProgress {
        let fresh = PlanProgress(planVersion: planVersion)
        guard let data = data,
              let decoded = try? JSONDecoder().decode(PlanProgress.self, from: data),
              decoded.planVersion == planVersion else {
            return fresh
        }
        return decoded
    }
}

// MARK: - Routing

/// Where "start" on the today screen sends the runner.
enum PlanRoute: Equatable {
    case freeRun(zone: RunZoneTarget)
    case roadWorkout(name: String)
    case track(presetId: String?, targetSeconds: Double?)

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
            return .track(presetId: session.preset, targetSeconds: session.targetSeconds)
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

/// What `PlanSchedule.pushingBack` decided.
struct PushBackResult: Equatable {
    /// Progress with the missed session and the rest of the week moved, and the dropped sessions skipped.
    var progress: PlanProgress
    /// Sessions other than the missed one that moved to a later day this week.
    var moved: [Int]
    /// Sessions skipped because the rest of the week had no room for them (the missed one included).
    var dropped: [Int]
}

/// The calendar Monday-to-Sunday week around a day: the plan week most of its sessions belong to
/// and the miles logged in it.
struct PlanWeekMiles: Equatable {
    let planWeek: PlanWeek?
    let logged: Double
}

/// The plan plus the runner's progress. Days are offsets from the plan start (start = 0).
struct PlanSchedule {
    /// Preset id of the mile time trial, which time trials and the race point at.
    static let mileTrialPresetId = "mile-tt"
    /// A missed session stays on offer for this many days; older ones are skipped.
    static let missedWindowDays = 2

    let plan: PlanFile
    let progress: PlanProgress
    /// Weekday of day offset 0 on the calendar, Monday = 1 ... Sunday = 7. The bundled plan starts on
    /// a Monday, so its weekday numbers match the calendar.
    var startWeekday: Int = 1

    /// Days from plan start for session `index` before any push back.
    func baseOffset(_ index: Int) -> Int {
        guard plan.sessions.indices.contains(index) else { return 0 }
        let session = plan.sessions[index]
        return (session.week - 1) * 7 + (session.weekday - 1)
    }

    /// Days from plan start for session `index`: its override when it was pushed back, else its plan day.
    func dayOffset(_ index: Int) -> Int {
        guard plan.sessions.indices.contains(index) else { return 0 }
        return progress.dayOverrides[PlanProgress.key(index)] ?? baseOffset(index)
    }

    /// Calendar weekday of day offset `day`, Monday = 1 ... Sunday = 7.
    func weekdayNumber(ofDay day: Int) -> Int {
        let start = min(max(startWeekday, 1), 7)
        let shifted = (start - 1 + day) % 7
        return (shifted + 7) % 7 + 1
    }

    /// The Monday on or before `day`.
    func calendarWeekStart(containing day: Int) -> Int {
        return day - (weekdayNumber(ofDay: day) - 1)
    }

    func indices(onDay day: Int) -> [Int] {
        return plan.sessions.indices.filter { dayOffset($0) == day }
    }

    func status(_ index: Int) -> SessionStatus? {
        return progress.statuses[PlanProgress.key(index)]
    }

    /// Oldest session from the last `missedWindowDays` days before `today` with no status.
    func firstMissed(today: Int) -> Int? {
        let oldest = today - PlanSchedule.missedWindowDays
        for index in plan.sessions.indices {
            let day = dayOffset(index)
            if day < today && day >= oldest && status(index) == nil {
                return index
            }
        }
        return nil
    }

    /// Sessions scheduled for `today` with no status.
    func todays(today: Int) -> [Int] {
        return plan.sessions.indices.filter { dayOffset($0) == today && status($0) == nil }
    }

    /// First session strictly after `today` with no status.
    func next(after today: Int) -> Int? {
        return plan.sessions.indices.first(where: { dayOffset($0) > today && status($0) == nil })
    }

    /// Index of the race session, if the plan has one.
    var raceIndex: Int? {
        return plan.sessions.lastIndex(where: { $0.kind == .race })
    }

    /// Day offset of the race session (the last session when the file has no race).
    var raceDayOffset: Int {
        if let race = raceIndex {
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

    /// First day offset of the Monday-to-Sunday strip that holds `today` (the race day at the latest).
    func stripStart(today: Int) -> Int {
        if today < 0 { return 0 }
        return calendarWeekStart(containing: min(today, raceDayOffset))
    }

    /// Monday of the calendar week holding the first session of plan week `week`.
    func startOffset(ofWeek week: Int) -> Int {
        if let index = plan.sessions.firstIndex(where: { $0.week == week }) {
            return calendarWeekStart(containing: dayOffset(index))
        }
        return (week - 1) * 7
    }

    /// The plan week that most of the sessions scheduled in the calendar week starting on `monday`
    /// belong to (the earlier week on a tie); nil when no session is scheduled in it.
    func plannedWeek(inCalendarWeekStarting monday: Int) -> PlanWeek? {
        var counts: [Int: Int] = [:]
        for index in plan.sessions.indices {
            let day = dayOffset(index)
            if day >= monday && day <= monday + 6 {
                counts[plan.sessions[index].week, default: 0] += 1
            }
        }
        var best: Int? = nil
        var bestCount = 0
        for (week, count) in counts {
            if count > bestCount || (count == bestCount && week < (best ?? Int.max)) {
                best = week
                bestCount = count
            }
        }
        guard let chosen = best else { return nil }
        return plan.weeks.first(where: { $0.week == chosen })
    }

    /// The calendar week holding `day`: its planned week and the miles in `milesByDay` over its seven days.
    func weekMiles(containing day: Int, milesByDay: [Int: Double]) -> PlanWeekMiles {
        let monday = calendarWeekStart(containing: day)
        return PlanWeekMiles(planWeek: plannedWeek(inCalendarWeekStarting: monday),
                             logged: WeeklyMiles.sum(milesByDay: milesByDay, firstDay: monday))
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

    // MARK: Push back

    /// Road, track, time trial and race sessions are the hard ones: two of them never sit on neighbouring
    /// days. Easy and long runs may follow a hard session.
    static func isHard(_ kind: SessionKind) -> Bool {
        switch kind {
        case .road, .track, .timeTrial, .race: return true
        case .easy, .long, .other: return false
        }
    }

    /// How much a session matters when a crowded week has to lose some: higher is kept first.
    static func priority(_ kind: SessionKind) -> Int {
        switch kind {
        case .timeTrial, .race: return 4
        case .track: return 3
        case .road: return 2
        case .long: return 1
        case .easy: return 0
        case .other: return -1
        }
    }

    private func setDay(_ index: Int, _ day: Int, in target: inout PlanProgress) {
        let key = PlanProgress.key(index)
        if day == baseOffset(index) {
            target.dayOverrides.removeValue(forKey: key)
        } else {
            target.dayOverrides[key] = day
        }
    }

    /// The days that hold a finished session, and those among them that hold a hard one.
    private func finishedDays() -> (all: Set<Int>, hard: Set<Int>) {
        var all = Set<Int>()
        var hard = Set<Int>()
        for index in plan.sessions.indices where status(index) == SessionStatus.done {
            let day = dayOffset(index)
            all.insert(day)
            if PlanSchedule.isHard(plan.sessions[index].kind) {
                hard.insert(day)
            }
        }
        return (all: all, hard: hard)
    }

    /// Places `order` (the missed session first, then the others in plan order) on the open days from
    /// `today` through `lastDay`. Each session wants its own day, or the day after the one before it,
    /// whichever is later, and takes the first open day from there: not a Wednesday or Sunday, not a day
    /// in `occupied`, not at or after `limit`, and for a hard session not next to a hard day in `fixedHard`
    /// or one placed already. Nil when some session finds no day.
    private func placing(_ order: [Int],
                         missed: Int,
                         today: Int,
                         lastDay: Int,
                         limit: Int,
                         occupied: Set<Int>,
                         fixedHard: Set<Int>) -> [Int: Int]? {
        var placed: [Int: Int] = [:]
        var taken = occupied
        var hardDays = fixedHard
        var previous = today - 1
        for index in order {
            let hard = PlanSchedule.isHard(plan.sessions[index].kind)
            let own = index == missed ? today : dayOffset(index)
            var day = max(own, previous + 1)
            var found: Int? = nil
            while day <= lastDay && day < limit {
                let weekday = weekdayNumber(ofDay: day)
                var open = weekday != 3 && weekday != 7 && !taken.contains(day)
                if open && hard && (hardDays.contains(day - 1) || hardDays.contains(day + 1)) {
                    open = false
                }
                if open {
                    found = day
                    break
                }
                day += 1
            }
            guard let chosen = found else { return nil }
            placed[index] = chosen
            taken.insert(chosen)
            if hard {
                hardDays.insert(chosen)
            }
            previous = chosen
        }
        return placed
    }

    /// "Do it today" for the missed session `missed`, contained in the calendar Monday-to-Sunday week
    /// that holds `today`. The missed session takes today, or the first open day after it this week. The
    /// unfinished sessions scheduled from today through that Sunday are placed again in plan order, each
    /// keeping its day when it still fits. When they do not all fit, the lowest priority ones are
    /// skipped until they do (time trial and race, then track, road, long, easy; the later of two equals
    /// goes first) and returned in `dropped`. Sessions in later weeks, finished sessions and the race never
    /// move, and no day at or after the race is used.
    func pushingBack(missed: Int, today: Int) -> PushBackResult {
        let unchanged = PushBackResult(progress: progress, moved: [], dropped: [])
        guard plan.sessions.indices.contains(missed),
              status(missed) == nil,
              today > dayOffset(missed),
              plan.sessions[missed].kind != .race else {
            return unchanged
        }

        let lastDay = calendarWeekStart(containing: today) + 6
        var limit = Int.max
        var occupied = finishedDays().all
        var fixedHard = finishedDays().hard
        if let race = raceIndex {
            limit = dayOffset(race)
            occupied.insert(limit)
            fixedHard.insert(limit)
        }
        let others = plan.sessions.indices.filter { index in
            index != missed
                && status(index) == nil
                && plan.sessions[index].kind != .race
                && dayOffset(index) >= today
                && dayOffset(index) <= lastDay
        }
        var order = [missed] + others
        var dropped: [Int] = []
        var placed: [Int: Int] = [:]
        // The missed session is placed first, so what the others do never changes whether it fits. When
        // it finds no day this week it alone is skipped and the rest of the week stays as it is.
        if placing([missed], missed: missed, today: today, lastDay: lastDay,
                   limit: limit, occupied: occupied, fixedHard: fixedHard) == nil {
            order = []
            dropped = [missed]
        }
        while !order.isEmpty {
            if let result = placing(order, missed: missed, today: today, lastDay: lastDay,
                                    limit: limit, occupied: occupied, fixedHard: fixedHard) {
                placed = result
                break
            }
            // Something does not fit: the least important session of the week goes.
            var victim = order[0]
            for index in order {
                let low = PlanSchedule.priority(plan.sessions[index].kind)
                let current = PlanSchedule.priority(plan.sessions[victim].kind)
                if low < current || (low == current && index > victim) {
                    victim = index
                }
            }
            order.removeAll(where: { $0 == victim })
            dropped.append(victim)
        }

        var updated = progress
        var moved: [Int] = []
        for index in order {
            guard let day = placed[index] else { continue }
            if index != missed && day != dayOffset(index) {
                moved.append(index)
            }
            setDay(index, day, in: &updated)
        }
        for index in dropped {
            updated.statuses[PlanProgress.key(index)] = .skipped
        }
        return PushBackResult(progress: updated, moved: moved.sorted(), dropped: dropped.sorted())
    }

    // MARK: Status changes

    func skipping(_ index: Int) -> PlanProgress {
        guard plan.sessions.indices.contains(index) else { return progress }
        var updated = progress
        updated.statuses[PlanProgress.key(index)] = .skipped
        updated.autoDone.remove(PlanProgress.key(index))
        return updated
    }

    /// Marks `index` done. `auto` is for a done that comes from a saved activity; the runner's own tap
    /// (the default) is manual and is never taken back when an activity is deleted.
    func markingDone(_ index: Int, auto: Bool = false) -> PlanProgress {
        guard plan.sessions.indices.contains(index) else { return progress }
        var updated = progress
        updated.statuses[PlanProgress.key(index)] = .done
        if auto {
            updated.autoDone.insert(PlanProgress.key(index))
        } else {
            updated.autoDone.remove(PlanProgress.key(index))
        }
        return updated
    }

    /// Takes a finished session back to unfinished (a run that was marked done was then discarded).
    func reopening(_ index: Int) -> PlanProgress {
        guard plan.sessions.indices.contains(index), status(index) == SessionStatus.done else { return progress }
        var updated = progress
        updated.statuses.removeValue(forKey: PlanProgress.key(index))
        updated.autoDone.remove(PlanProgress.key(index))
        return updated
    }

    /// Takes back every done mark that came from a saved activity (`autoDone`), after a run or workout
    /// was deleted. Manual done and skipped statuses stay. Reconciling again then puts back the marks
    /// that another activity still earns.
    func clearingAutoDone() -> PlanProgress {
        var updated = progress
        for key in progress.autoDone where updated.statuses[key] == SessionStatus.done {
            updated.statuses.removeValue(forKey: key)
        }
        updated.autoDone = []
        return updated
    }

    /// Skips every session with no status whose day is more than `missedWindowDays` before `today`.
    func skippingOld(today: Int) -> PlanProgress {
        var updated = progress
        let oldest = today - PlanSchedule.missedWindowDays
        for index in plan.sessions.indices where status(index) == nil {
            if dayOffset(index) < oldest {
                updated.statuses[PlanProgress.key(index)] = .skipped
            }
        }
        return updated
    }

    // MARK: Matching activities

    /// The track preset a time trial points at (the mile time trial when it names none) and the name
    /// a saved workout of that preset carries.
    private static func trialPresetName(for session: PlanSession) -> String? {
        let id = session.preset ?? PlanSchedule.mileTrialPresetId
        return WorkoutPresets.all.first(where: { $0.id == id })?.name
    }

    /// Whether a saved activity of `kind` is what `session` asks for.
    static func matches(_ kind: ActivityDay.Kind, session: PlanSession) -> Bool {
        switch kind {
        case .run(let miles, let workoutName):
            let named = (workoutName ?? "").isEmpty ? nil : workoutName
            switch session.kind {
            case .easy, .long:
                if named != nil { return false }
                return miles >= 0.5 * (session.miles ?? 0)
            case .road:
                guard let preset = session.preset else { return true }
                return named == preset
            case .other:
                return true
            case .track, .timeTrial, .race:
                return false
            }
        case .track(let presetName):
            switch session.kind {
            case .track, .race:
                return true
            case .timeTrial:
                guard let expected = trialPresetName(for: session) else { return true }
                return presetName == expected
            case .easy, .long, .road, .other:
                return false
            }
        }
    }

    /// Marks done every session with no status that has a matching activity on its scheduled day.
    /// An activity satisfies at most one session.
    func reconciled(activities: [ActivityDay]) -> PlanProgress {
        var updated = progress
        var used = Set<Int>()
        for index in plan.sessions.indices {
            guard status(index) == nil else { continue }
            let day = dayOffset(index)
            let session = plan.sessions[index]
            for position in activities.indices {
                guard !used.contains(position), activities[position].day == day else { continue }
                guard PlanSchedule.matches(activities[position].kind, session: session) else { continue }
                used.insert(position)
                updated.statuses[PlanProgress.key(index)] = .done
                updated.autoDone.insert(PlanProgress.key(index))
                break
            }
        }
        return updated
    }

    /// Matches activities first, then skips sessions missed more than two days ago.
    func reconciled(activities: [ActivityDay], today: Int) -> PlanProgress {
        let matched = PlanSchedule(plan: plan,
                                   progress: reconciled(activities: activities),
                                   startWeekday: startWeekday)
        return matched.skippingOld(today: today)
    }

    /// Like `reconciled(activities:today:)`, but first takes back the done marks that earlier activities
    /// earned (`clearingAutoDone`), so a deleted run or workout no longer counts. Manual statuses stay.
    func reconciledAfterRemoval(activities: [ActivityDay], today: Int) -> PlanProgress {
        let cleared = PlanSchedule(plan: plan, progress: clearingAutoDone(), startWeekday: startWeekday)
        return cleared.reconciled(activities: activities, today: today)
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
    /// Gregorian in the time zone the phone is in right now (it follows travel, unlike a time zone
    /// captured at launch).
    static var local: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.autoupdatingCurrent
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

    /// Hours after midnight at which a day starts for activities: a run that starts at 00:30 counts
    /// for the day before.
    static let activityDayStartHour = 3

    /// Day offset of an activity that started at `date`.
    static func activityDay(of date: Date, start: Date, calendar: Calendar = PlanCalendar.local) -> Int {
        let shifted = calendar.date(byAdding: .hour, value: -activityDayStartHour, to: date) ?? date
        return dayOffset(of: shifted, start: start, calendar: calendar)
    }

    /// Minutes from the start of plan day `offset` (midnight) to `now`. Today changes at 03:00, so between
    /// midnight and 03:00 this is over 1440 for the day that is still "today": its reminders are all past.
    static func minutesIntoDay(now: Date, offset: Int, start: Date, calendar: Calendar = PlanCalendar.local) -> Int {
        let dayStart = date(forOffset: offset, start: start, calendar: calendar)
        return max(0, Int(now.timeIntervalSince(dayStart) / 60))
    }

    /// Weekday of `date`, Monday = 1 ... Sunday = 7.
    static func mondayWeekday(of date: Date, calendar: Calendar = PlanCalendar.local) -> Int {
        let sundayFirst = calendar.component(.weekday, from: date)
        return (sundayFirst + 5) % 7 + 1
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
