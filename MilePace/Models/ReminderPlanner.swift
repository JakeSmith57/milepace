import Foundation

/// What the runner turned on in Set.
struct ReminderSettings: Equatable {
    var enabled: Bool
    var morning: Bool
    var evening: Bool
    var timeTrial: Bool
    var weekly: Bool
    /// Minutes since local midnight.
    var morningMinutes: Int
    var eveningMinutes: Int

    static let defaultMorningMinutes: Int = 480
    static let defaultEveningMinutes: Int = 1020

    static let standard = ReminderSettings(enabled: true,
                                           morning: true,
                                           evening: true,
                                           timeTrial: true,
                                           weekly: true,
                                           morningMinutes: ReminderSettings.defaultMorningMinutes,
                                           eveningMinutes: ReminderSettings.defaultEveningMinutes)
}

/// One local notification to schedule, before it is turned into a `UNNotificationRequest`.
struct ReminderSpec: Equatable {
    let id: String
    /// Days from the plan start.
    let dayOffset: Int
    /// Minutes since local midnight.
    let minutes: Int
    let title: String
    let body: String
    let category: String?
    let sessionIndex: Int?
}

/// Decides which reminders should exist. Pure: no clock, no notification center.
enum ReminderPlanner {
    static let idPrefix = "plan."
    static let morningPrefix = "plan.morning."
    static let eveningPrefix = "plan.evening."
    static let timeTrialPrefix = "plan.tt."
    static let weeklyPrefix = "plan.week."
    static let startId = "plan.start"
    /// Id of the one-off notification from "send a test".
    static let testId = "test.reminder"

    static let sessionCategory = "PLAN_SESSION"
    static let markDoneAction = "MARK_DONE"
    static let skipAction = "SKIP"

    /// Minutes after midnight for the Sunday summary (18:00).
    static let weeklyMinutes: Int = 1080
    static let eveningBody = "log it, or open the app to skip or move it."
    static let startBody = "three short easy runs this week. see a doctor about your foot before week 5."

    /// True for the reminders that may show a banner while the app is open.
    static func showsInForeground(_ identifier: String) -> Bool {
        return identifier.hasPrefix(timeTrialPrefix)
            || identifier.hasPrefix(weeklyPrefix)
            || identifier.hasPrefix("test.")
    }

    static func build(schedule: PlanSchedule,
                      todayOffset: Int,
                      nowMinutes: Int,
                      settings: ReminderSettings,
                      loggedMilesByDay: [Int: Double],
                      zones: PaceZones,
                      goalMile: Double,
                      startDate: Date,
                      windowDays: Int = 14,
                      cap: Int = 60) -> [ReminderSpec] {
        guard settings.enabled, windowDays > 0, cap > 0 else { return [] }
        let window = todayOffset...(todayOffset + windowDays - 1)

        var specs: [ReminderSpec] = []
        specs.append(contentsOf: startSpecs(window: window, settings: settings))
        specs.append(contentsOf: sessionSpecs(schedule: schedule, window: window, settings: settings,
                                              zones: zones, goalMile: goalMile))
        specs.append(contentsOf: timeTrialSpecs(schedule: schedule, window: window, settings: settings,
                                                goalMile: goalMile))
        specs.append(contentsOf: weeklySpecs(schedule: schedule, window: window, settings: settings,
                                             loggedMilesByDay: loggedMilesByDay, startDate: startDate))

        var kept = specs.filter { spec in
            if spec.dayOffset == todayOffset {
                return spec.minutes > nowMinutes
            }
            return spec.dayOffset > todayOffset
        }
        kept.sort { left, right in
            if left.dayOffset != right.dayOffset { return left.dayOffset < right.dayOffset }
            if left.minutes != right.minutes { return left.minutes < right.minutes }
            return left.id < right.id
        }
        kept = unique(kept)
        kept = appendingMissed(to: kept, schedule: schedule, todayOffset: todayOffset, startDate: startDate)
        return Array(kept.prefix(cap))
    }

    // MARK: Pieces

    private static func startSpecs(window: ClosedRange<Int>, settings: ReminderSettings) -> [ReminderSpec] {
        guard settings.morning, window.contains(0), window.lowerBound <= 0 else { return [] }
        let spec = ReminderSpec(id: startId,
                                dayOffset: 0,
                                minutes: clamped(settings.morningMinutes),
                                title: "week 1 starts today",
                                body: startBody,
                                category: nil,
                                sessionIndex: nil)
        return [spec]
    }

    private static func sessionSpecs(schedule: PlanSchedule,
                                     window: ClosedRange<Int>,
                                     settings: ReminderSettings,
                                     zones: PaceZones,
                                     goalMile: Double) -> [ReminderSpec] {
        var specs: [ReminderSpec] = []
        for day in window {
            guard let index = schedule.todays(today: day).first else { continue }
            let session = schedule.plan.sessions[index]
            if settings.morning {
                let detail = PlanText.detail(for: session, zones: zones, goalMile: goalMile)
                specs.append(ReminderSpec(id: morningPrefix + String(day),
                                          dayOffset: day,
                                          minutes: clamped(settings.morningMinutes),
                                          title: "today: " + session.title,
                                          body: detail.isEmpty ? "open the app for details." : detail,
                                          category: sessionCategory,
                                          sessionIndex: index))
            }
            if settings.evening {
                specs.append(ReminderSpec(id: eveningPrefix + String(day),
                                          dayOffset: day,
                                          minutes: clamped(settings.eveningMinutes),
                                          title: "still on the plan: " + session.title,
                                          body: eveningBody,
                                          category: sessionCategory,
                                          sessionIndex: index))
            }
        }
        return specs
    }

    private static func isTimeTrialOrRace(_ kind: SessionKind) -> Bool {
        switch kind {
        case .timeTrial, .race: return true
        case .easy, .long, .road, .track, .other: return false
        }
    }

    private static func timeTrialSpecs(schedule: PlanSchedule,
                                       window: ClosedRange<Int>,
                                       settings: ReminderSettings,
                                       goalMile: Double) -> [ReminderSpec] {
        guard settings.timeTrial else { return [] }
        var specs: [ReminderSpec] = []
        for index in schedule.plan.sessions.indices {
            let session = schedule.plan.sessions[index]
            guard isTimeTrialOrRace(session.kind), schedule.status(index) == nil else { continue }
            let day = schedule.dayOffset(index) - 1
            guard window.contains(day) else { continue }
            let isRace = session.kind == .race
            var body = "keep today short and easy."
            if isRace {
                body = "goal " + formatPace(secondsPerMile: goalMile) + ". lay out your shoes."
            } else if let note = session.note, !note.isEmpty {
                body += " " + note + "."
            }
            specs.append(ReminderSpec(id: timeTrialPrefix + String(day),
                                      dayOffset: day,
                                      minutes: clamped(settings.eveningMinutes + 60),
                                      title: isRace ? "race tomorrow" : "time trial tomorrow",
                                      body: body,
                                      category: nil,
                                      sessionIndex: nil))
        }
        return specs
    }

    /// The Sunday summary: always on the calendar Sunday at 18:00. It counts the Monday-to-Sunday
    /// week that ends on that Sunday, against the plan week most of that week's sessions belong to.
    private static func weeklySpecs(schedule: PlanSchedule,
                                    window: ClosedRange<Int>,
                                    settings: ReminderSettings,
                                    loggedMilesByDay: [Int: Double],
                                    startDate: Date) -> [ReminderSpec] {
        guard settings.weekly else { return [] }
        var specs: [ReminderSpec] = []
        for sunday in window where schedule.weekdayNumber(ofDay: sunday) == 7 {
            let summary = schedule.weekMiles(containing: sunday, milesByDay: loggedMilesByDay)
            guard let planWeek = summary.planWeek,
                  let next = schedule.plan.weeks.first(where: { $0.week == planWeek.week + 1 }) else { continue }
            let loggedText = String(format: "%.1f", summary.logged)
            let plannedText = PlanFormat.miles(planWeek.miles)
            let title = "week \(planWeek.week): \(loggedText) / \(plannedText) mi"
            specs.append(ReminderSpec(id: weeklyPrefix + String(sunday),
                                      dayOffset: sunday,
                                      minutes: weeklyMinutes,
                                      title: title,
                                      body: weeklyBody(next: next, schedule: schedule, startDate: startDate),
                                      category: nil,
                                      sessionIndex: nil))
        }
        return specs
    }

    private static func weeklyBody(next: PlanWeek, schedule: PlanSchedule, startDate: Date) -> String {
        var body = "next week: " + PlanFormat.miles(next.miles) + " mi"
        if next.recovery {
            body += ", recovery week"
        }
        if next.timeTrial {
            body += ", " + dayTag("time trial", kind: .timeTrial, week: next.week, schedule: schedule, startDate: startDate)
        }
        if next.race {
            body += ", " + dayTag("race", kind: .race, week: next.week, schedule: schedule, startDate: startDate)
        }
        return body + "."
    }

    /// "time trial sat"; just the label when the week has no session of that kind.
    private static func dayTag(_ label: String,
                               kind: SessionKind,
                               week: Int,
                               schedule: PlanSchedule,
                               startDate: Date) -> String {
        for index in schedule.plan.sessions.indices {
            let session = schedule.plan.sessions[index]
            if session.week == week && session.kind == kind {
                let date = PlanCalendar.date(forOffset: schedule.dayOffset(index), start: startDate)
                return label + " " + String(PlanFormat.weekdayName(date).prefix(3))
            }
        }
        return label
    }

    /// Adds " also missed: tue oct 20 2 mi easy." to the first morning reminder when a session was missed.
    private static func appendingMissed(to specs: [ReminderSpec],
                                        schedule: PlanSchedule,
                                        todayOffset: Int,
                                        startDate: Date) -> [ReminderSpec] {
        guard let missed = schedule.firstMissed(today: todayOffset),
              let position = specs.firstIndex(where: { $0.id.hasPrefix(morningPrefix) }) else {
            return specs
        }
        let session = schedule.plan.sessions[missed]
        let when = PlanFormat.dayLabel(offset: schedule.dayOffset(missed), start: startDate)
        let extra = " also missed: " + when + " " + session.title + "."
        let old = specs[position]
        var result = specs
        result[position] = ReminderSpec(id: old.id,
                                        dayOffset: old.dayOffset,
                                        minutes: old.minutes,
                                        title: old.title,
                                        body: old.body + extra,
                                        category: old.category,
                                        sessionIndex: old.sessionIndex)
        return result
    }

    /// Whether a "mark done" or "skip" tapped on a notification made for `day` should still act: the
    /// session must still be scheduled for that day and have no status.
    static func actionApplies(schedule: PlanSchedule, sessionIndex: Int, day: Int) -> Bool {
        guard schedule.plan.sessions.indices.contains(sessionIndex) else { return false }
        return schedule.dayOffset(sessionIndex) == day && schedule.status(sessionIndex) == nil
    }

    /// The plan day a `plan.` notification id stands for: "plan.morning.12" is 12, "plan.start" is
    /// 0; nil for anything else.
    static func dayOffset(ofIdentifier identifier: String) -> Int? {
        guard identifier.hasPrefix(idPrefix) else { return nil }
        if identifier == startId { return 0 }
        guard let dot = identifier.lastIndex(of: ".") else { return nil }
        return Int(identifier[identifier.index(after: dot)...])
    }

    private static func unique(_ specs: [ReminderSpec]) -> [ReminderSpec] {
        var seen = Set<String>()
        var result: [ReminderSpec] = []
        for spec in specs where !seen.contains(spec.id) {
            seen.insert(spec.id)
            result.append(spec)
        }
        return result
    }

    private static func clamped(_ minutes: Int) -> Int {
        return min(max(minutes, 0), 1439)
    }
}

/// Clock text and minute conversion for the reminder times.
enum ReminderFormat {
    /// "8:00 am", "5:00 pm", "12:00 am".
    static func clock(_ minutes: Int) -> String {
        let total = min(max(minutes, 0), 1439)
        let hour24 = total / 60
        let minute = total % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        let suffix = hour24 < 12 ? "am" : "pm"
        return String(format: "%d:%02d", hour12, minute) + " " + suffix
    }

    /// Today at `minutes` past midnight, for a time picker.
    static func date(minutes: Int, calendar: Calendar = PlanCalendar.local) -> Date {
        let total = min(max(minutes, 0), 1439)
        let start = calendar.startOfDay(for: Date())
        return calendar.date(bySettingHour: total / 60, minute: total % 60, second: 0, of: start) ?? start
    }

    /// Minutes past midnight of a picked time.
    static func minutes(of date: Date, calendar: Calendar = PlanCalendar.local) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
