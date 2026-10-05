import Foundation

/// The test week: a one-week practice plan built in code, so the runner can try every screen before the
/// real plan starts. Pure: no clock, no storage.
enum TestWeek {
    /// `PlanFile.version` of the test plan, apart from the real plan's, so saved progress never mixes.
    static let planVersion = 1000
    static let planName = "test week"

    /// One weekday of the test week.
    private struct Slot {
        let weekday: Int
        let kind: SessionKind
        let title: String
        let miles: Double?
        let preset: String?
        let note: String
    }

    /// Monday to Saturday; Wednesday and Sunday are rest days.
    private static let template: [Slot] = [
        Slot(weekday: 1, kind: .easy, title: "1 mi easy", miles: 1.0, preset: nil,
             note: "test the run screen, voice cues and map."),
        Slot(weekday: 2, kind: .road, title: "2 \u{00D7} 2 min threshold", miles: nil,
             preset: RoadWorkoutPresets.testPresetName,
             note: "test a guided workout. jog it if you like."),
        Slot(weekday: 4, kind: .track, title: "4 \u{00D7} 200", miles: nil,
             preset: WorkoutPresets.testPresetId,
             note: "test the lap timer. walking is fine."),
        Slot(weekday: 5, kind: .easy, title: "1.5 mi easy + metronome", miles: 1.5, preset: nil,
             note: "turn on the metronome."),
        Slot(weekday: 6, kind: .timeTrial, title: "practice time trial", miles: nil,
             preset: PlanSchedule.mileTrialPresetId,
             note: "optional. test the time trial flow; jog it.")
    ]

    /// The test plan for the calendar Monday-to-Sunday week that holds `day`; sessions on days before
    /// `day` are left out. When fewer than two sessions are left and the following week also ends before
    /// `realStart`, that whole week is added as week 2. `mileSeconds` is the current mile time, the target
    /// of the practice time trial.
    static func plan(startingOn day: Date,
                     mileSeconds: Double,
                     realStart: Date? = nil,
                     calendar: Calendar = PlanCalendar.local) -> PlanFile {
        let startDay = calendar.startOfDay(for: day)
        let weekday = PlanCalendar.mondayWeekday(of: startDay, calendar: calendar)
        let monday = PlanCalendar.date(forOffset: -(weekday - 1), start: startDay, calendar: calendar)

        let remaining = template.filter { $0.weekday >= weekday }
        var weekSlots: [[Slot]] = [remaining]
        if remaining.count < 2, nextWeekEnds(before: realStart, monday: monday, calendar: calendar) {
            weekSlots.append(template)
        }

        var weeks: [PlanWeek] = []
        var sessions: [PlanSession] = []
        for (position, slots) in weekSlots.enumerated() {
            let number = position + 1
            var miles = 1.0
            var hasTrial = false
            for slot in slots {
                if slot.kind == .easy {
                    miles += slot.miles ?? 0
                }
                if slot.kind == .timeTrial {
                    hasTrial = true
                }
                sessions.append(PlanSession(week: number,
                                            weekday: slot.weekday,
                                            phase: 1,
                                            kind: slot.kind,
                                            title: slot.title,
                                            miles: slot.miles,
                                            preset: slot.preset,
                                            note: slot.note,
                                            targetSeconds: slot.kind == .timeTrial ? mileSeconds : nil))
            }
            weeks.append(PlanWeek(week: number, miles: miles, phase: 1, recovery: false, timeTrial: hasTrial, race: false))
        }
        return PlanFile(name: planName,
                        version: planVersion,
                        startDate: PlanCalendar.ymd(monday, calendar: calendar),
                        raceDate: nil,
                        weeks: weeks,
                        sessions: sessions)
    }

    /// True when the Sunday of the week after the one starting on `monday` is before `realStart`'s day.
    /// False without a `realStart`: nothing says the week would finish in time.
    private static func nextWeekEnds(before realStart: Date?, monday: Date, calendar: Calendar) -> Bool {
        guard let realStart = realStart else { return false }
        let sunday = PlanCalendar.date(forOffset: 13, start: monday, calendar: calendar)
        return PlanCalendar.dayOffset(of: sunday, start: realStart, calendar: calendar) < 0
    }

    /// The day a test week started now begins on: today by the 03:00 day boundary the plan uses.
    static func startDay(now: Date, calendar: Calendar = PlanCalendar.local) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -PlanCalendar.activityDayStartHour, to: now) ?? now
        return calendar.startOfDay(for: shifted)
    }
}

/// When a test week may start and when it ends by itself.
enum TestWeekLifecycle {
    /// The Sunday that closes the last test week: `weeks` calendar weeks from the Monday of the week
    /// holding `testStart`.
    static func lastDay(testStart: Date, weeks: Int, calendar: Calendar = PlanCalendar.local) -> Date {
        let weekday = PlanCalendar.mondayWeekday(of: testStart, calendar: calendar)
        let offset = 7 * max(weeks, 1) - weekday
        return PlanCalendar.date(forOffset: offset, start: testStart, calendar: calendar)
    }

    /// A test week is offered only while today (03:00 boundary) is before the real plan's start day.
    static func canStart(today: Date, realStart: Date, calendar: Calendar = PlanCalendar.local) -> Bool {
        return PlanCalendar.activityDay(of: today, start: realStart, calendar: calendar) < 0
    }

    /// True when the test week should end now: today has reached the real plan's start day, or the last
    /// Sunday of the test week has passed. Never while a run or track session is going; it ends after it.
    static func shouldAutoEnd(today: Date,
                              testStart: Date,
                              realStart: Date,
                              weeks: Int = 1,
                              sessionActive: Bool = false,
                              calendar: Calendar = PlanCalendar.local) -> Bool {
        if sessionActive { return false }
        if PlanCalendar.activityDay(of: today, start: realStart, calendar: calendar) >= 0 { return true }
        let last = lastDay(testStart: testStart, weeks: weeks, calendar: calendar)
        return PlanCalendar.activityDay(of: today, start: last, calendar: calendar) > 0
    }
}

/// Which saved runs and workouts a plan looks at: the real plan never sees test records, the test week
/// sees only them.
enum TestRecordFilter {
    static func runs(_ runs: [LoggedRun], testWeek: Bool) -> [LoggedRun] {
        return runs.filter { $0.isTest == testWeek }
    }

    static func workouts(_ workouts: [LoggedWorkout], testWeek: Bool) -> [LoggedWorkout] {
        return workouts.filter { $0.isTest == testWeek }
    }
}
