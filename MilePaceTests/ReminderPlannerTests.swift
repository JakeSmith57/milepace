import XCTest
@testable import MilePace

final class ReminderPlannerTests: XCTestCase {
    /// Three weeks, six sessions. Day offsets from the start (a Monday): 1, 3, 5, 8, 12, 19.
    /// Sundays (day 6 and 13) close weeks 1 and 2; the time trial is on day 12, the race on day 19.
    private static let miniJSON = """
    {
      "name": "mini",
      "startDate": "2026-10-12",
      "weeks": [
        { "week": 1, "miles": 5, "phase": 1, "recovery": false, "timeTrial": false, "race": false },
        { "week": 2, "miles": 6, "phase": 1, "recovery": true, "timeTrial": true, "race": false },
        { "week": 3, "miles": 3, "phase": 1, "recovery": false, "timeTrial": false, "race": true }
      ],
      "sessions": [
        { "week": 1, "weekday": 2, "phase": 1, "kind": "easy", "miles": 2, "title": "2 mi easy" },
        { "week": 1, "weekday": 4, "phase": 1, "kind": "track", "preset": "6x400-r", "title": "6 x 400 @ R" },
        { "week": 1, "weekday": 6, "phase": 1, "kind": "long", "miles": 3, "title": "3 mi long" },
        { "week": 2, "weekday": 2, "phase": 1, "kind": "easy", "miles": 2, "title": "2 mi easy" },
        { "week": 2, "weekday": 6, "phase": 1, "kind": "timeTrial", "preset": "mile-tt", "title": "mile time trial", "note": "target \\u2264 6:35" },
        { "week": 3, "weekday": 6, "phase": 1, "kind": "race", "preset": "mile-tt", "title": "goal race", "note": "race day" }
      ]
    }
    """

    private func miniPlan() throws -> PlanFile {
        return try JSONDecoder().decode(PlanFile.self, from: Data(ReminderPlannerTests.miniJSON.utf8))
    }

    private func startDate() throws -> Date {
        return try XCTUnwrap(PlanCalendar.parse("2026-10-12"))
    }

    private func build(progress: PlanProgress = PlanProgress(),
                       today: Int = 0,
                       now: Int = 0,
                       settings: ReminderSettings = ReminderSettings.standard,
                       logged: [Int: Double] = [:],
                       window: Int = 14,
                       cap: Int = 60) throws -> [ReminderSpec] {
        let schedule = PlanSchedule(plan: try miniPlan(), progress: progress)
        return ReminderPlanner.build(schedule: schedule,
                                     todayOffset: today,
                                     nowMinutes: now,
                                     settings: settings,
                                     loggedMilesByDay: logged,
                                     zones: PaceZones.forMile(412),
                                     goalMile: 330,
                                     startDate: try startDate(),
                                     windowDays: window,
                                     cap: cap)
    }

    private func days(_ specs: [ReminderSpec], prefix: String) -> [Int] {
        return specs.filter { $0.id.hasPrefix(prefix) }.map { $0.dayOffset }
    }

    private func spec(_ specs: [ReminderSpec], id: String) -> ReminderSpec? {
        return specs.first(where: { $0.id == id })
    }

    // MARK: Morning and evening

    func testMorningAndEveningForEachSessionDayAndNoneOnRestDays() throws {
        let specs = try build()
        XCTAssertEqual(days(specs, prefix: "plan.morning."), [1, 3, 5, 8, 12])
        XCTAssertEqual(days(specs, prefix: "plan.evening."), [1, 3, 5, 8, 12])

        let morning = try XCTUnwrap(spec(specs, id: "plan.morning.1"))
        XCTAssertEqual(morning.minutes, 480)
        XCTAssertEqual(morning.title, "today: 2 mi easy")
        XCTAssertEqual(morning.body, "2 mi, conversational, 9:35\u{2013}10:30 /mi.")
        XCTAssertEqual(morning.category, "PLAN_SESSION")
        XCTAssertEqual(morning.sessionIndex, 0)

        let evening = try XCTUnwrap(spec(specs, id: "plan.evening.1"))
        XCTAssertEqual(evening.minutes, 1020)
        XCTAssertEqual(evening.title, "still on the plan: 2 mi easy")
        XCTAssertEqual(evening.body, "log it, or open the app to skip or move it.")
        XCTAssertEqual(evening.category, "PLAN_SESSION")
        XCTAssertEqual(evening.sessionIndex, 0)
    }

    func testPlanStartReminderOnlyBeforeTheStart() throws {
        let before = try build(today: -2)
        let start = try XCTUnwrap(spec(before, id: "plan.start"))
        XCTAssertEqual(start.dayOffset, 0)
        XCTAssertEqual(start.minutes, 480)
        XCTAssertEqual(start.title, "week 1 starts today")
        XCTAssertNil(start.category)

        let after = try build(today: 1)
        XCTAssertNil(spec(after, id: "plan.start"))
    }

    func testDoneAndSkippedSessionsGetNoReminders() throws {
        var progress = PlanProgress()
        progress.statuses[PlanProgress.key(0)] = .done
        progress.statuses[PlanProgress.key(2)] = .skipped
        let specs = try build(progress: progress)
        XCTAssertEqual(days(specs, prefix: "plan.morning."), [3, 8, 12])
        XCTAssertEqual(days(specs, prefix: "plan.evening."), [3, 8, 12])
    }

    func testSameDayRemindersBeforeNowAreDropped() throws {
        let midday = try build(today: 1, now: 600)
        XCTAssertNil(spec(midday, id: "plan.morning.1"))
        XCTAssertNotNil(spec(midday, id: "plan.evening.1"))
        XCTAssertEqual(midday.first?.id, "plan.evening.1")

        let night = try build(today: 1, now: 1020)
        XCTAssertNil(spec(night, id: "plan.morning.1"))
        XCTAssertNil(spec(night, id: "plan.evening.1"))
        XCTAssertNotNil(spec(night, id: "plan.morning.3"))
    }

    // MARK: Time trial, race and weekly

    func testTimeTrialReminderTheDayBefore() throws {
        let specs = try build()
        let tt = try XCTUnwrap(spec(specs, id: "plan.tt.11"))
        XCTAssertEqual(tt.dayOffset, 11)
        XCTAssertEqual(tt.minutes, 1080)
        XCTAssertEqual(tt.title, "time trial tomorrow")
        XCTAssertEqual(tt.body, "keep today short and easy. target \u{2264} 6:35.")
        XCTAssertNil(tt.category)
        XCTAssertNil(tt.sessionIndex)

        var late = ReminderSettings.standard
        late.eveningMinutes = 1200
        let moved = try build(settings: late)
        XCTAssertEqual(spec(moved, id: "plan.tt.11")?.minutes, 1260)

        var off = ReminderSettings.standard
        off.timeTrial = false
        let without = try build(settings: off)
        XCTAssertNil(spec(without, id: "plan.tt.11"))
    }

    func testRaceReminderTheDayBefore() throws {
        let specs = try build(today: 10)
        let race = try XCTUnwrap(spec(specs, id: "plan.tt.18"))
        XCTAssertEqual(race.title, "race tomorrow")
        XCTAssertEqual(race.body, "goal 5:30. lay out your shoes.")
        XCTAssertEqual(race.minutes, 1080)
    }

    func testWeeklySummaryUsesLoggedAndPlannedMiles() throws {
        let logged: [Int: Double] = [1: 1.0, 3: 1.5, 8: 9.0]
        let specs = try build(logged: logged)
        XCTAssertEqual(days(specs, prefix: "plan.week."), [6, 13])

        let first = try XCTUnwrap(spec(specs, id: "plan.week.6"))
        XCTAssertEqual(first.minutes, 1080)
        XCTAssertEqual(first.title, "week 1: 2.5 / 5 mi")
        XCTAssertEqual(first.body, "next week: 6 mi, recovery week, time trial sat.")

        let second = try XCTUnwrap(spec(specs, id: "plan.week.13"))
        XCTAssertEqual(second.title, "week 2: 9.0 / 6 mi")
        XCTAssertEqual(second.body, "next week: 3 mi, race sat.")

        var off = ReminderSettings.standard
        off.weekly = false
        let without = try build(settings: off)
        XCTAssertEqual(days(without, prefix: "plan.week."), [])
    }

    // MARK: Missed sessions

    func testMissedKeySessionIsAppendedToTheNextMorning() throws {
        // Session 1 (the track session, thu oct 15, day 3) is within two days of day 4.
        let specs = try build(today: 4)
        let next = try XCTUnwrap(spec(specs, id: "plan.morning.5"))
        XCTAssertTrue(next.body.hasSuffix(" also missed: thu oct 15 6 x 400 @ R."))
        let later = try XCTUnwrap(spec(specs, id: "plan.morning.8"))
        XCTAssertFalse(later.body.contains("also missed"))
    }

    func testMissedEasySessionsAreNeverMentioned() throws {
        // Session 0 is a 2 mi easy run on day 1; it is never offered, so no morning mentions it.
        for today in [2, 3] {
            let specs = try build(today: today)
            for reminder in specs where reminder.id.hasPrefix("plan.morning.") {
                XCTAssertFalse(reminder.body.contains("also missed"), "day \(today): \(reminder.id)")
            }
        }
    }

    func testMissedSessionsOlderThanTwoDaysAreNotMentioned() throws {
        let specs = try build(today: 7)
        let next = try XCTUnwrap(spec(specs, id: "plan.morning.8"))
        // The track session (day 3) is too old; the long run (day 5, sat oct 17) is still on offer.
        XCTAssertTrue(next.body.hasSuffix(" also missed: sat oct 17 3 mi long."))
        XCTAssertFalse(next.body.contains("6 x 400"))

        let tooLate = try build(today: 8)
        let morning = try XCTUnwrap(spec(tooLate, id: "plan.morning.8"))
        XCTAssertFalse(morning.body.contains("also missed"))
    }

    // MARK: Limits

    func testDisabledReturnsNothing() throws {
        var settings = ReminderSettings.standard
        settings.enabled = false
        let specs = try build(settings: settings)
        XCTAssertTrue(specs.isEmpty)
    }

    func testEverySwitchOffReturnsNothing() throws {
        var settings = ReminderSettings.standard
        settings.morning = false
        settings.evening = false
        settings.timeTrial = false
        settings.weekly = false
        let specs = try build(settings: settings)
        XCTAssertTrue(specs.isEmpty)
    }

    func testCapKeepsTheEarliest() throws {
        let all = try build()
        let capped = try build(cap: 3)
        XCTAssertEqual(capped.count, 3)
        XCTAssertEqual(capped, Array(all.prefix(3)))
        XCTAssertEqual(capped.map { $0.id }, ["plan.start", "plan.morning.1", "plan.evening.1"])
    }

    func testResultsAreSortedByDayThenMinutes() throws {
        let specs = try build()
        for pair in zip(specs, specs.dropFirst()) {
            let ordered = pair.0.dayOffset < pair.1.dayOffset
                || (pair.0.dayOffset == pair.1.dayOffset && pair.0.minutes <= pair.1.minutes)
            XCTAssertTrue(ordered)
        }
        XCTAssertEqual(Set(specs.map { $0.id }).count, specs.count)
    }

    func testWindowStopsAfterTheLastDay() throws {
        let specs = try build(window: 3)
        XCTAssertTrue(specs.allSatisfy { $0.dayOffset <= 2 })
        XCTAssertEqual(days(specs, prefix: "plan.morning."), [1])
    }

    // MARK: Push back

    func testPushBackMovesTheReminderDays() throws {
        var progress = PlanProgress()
        progress.dayOverrides[PlanProgress.key(1)] = 5
        progress.dayOverrides[PlanProgress.key(2)] = 7
        progress.dayOverrides[PlanProgress.key(3)] = 10
        progress.dayOverrides[PlanProgress.key(4)] = 14
        let specs = try build(progress: progress)
        XCTAssertEqual(days(specs, prefix: "plan.morning."), [1, 5, 7, 10])
        XCTAssertNotNil(spec(specs, id: "plan.tt.13"))
        XCTAssertNil(spec(specs, id: "plan.tt.11"))
        // The Sunday summaries stay on the calendar Sundays, days 6 and 13.
        XCTAssertEqual(days(specs, prefix: "plan.week."), [6, 13])
    }

    func testSundaySummaryCountsTheCalendarWeekAndUsesTheMajorityPlanWeek() throws {
        // Week 1's long run slips to day 7 and week 2's first session to day 10, so the calendar week
        // of days 7...13 holds session 2 (week 1), session 3 (week 2) and the time trial (week 2).
        var progress = PlanProgress()
        progress.dayOverrides[PlanProgress.key(2)] = 7
        progress.dayOverrides[PlanProgress.key(3)] = 10
        let specs = try build(progress: progress, logged: [6: 1.0, 7: 3.0, 10: 2.0])
        let first = try XCTUnwrap(spec(specs, id: "plan.week.6"))
        XCTAssertEqual(first.title, "week 1: 1.0 / 5 mi")
        let second = try XCTUnwrap(spec(specs, id: "plan.week.13"))
        XCTAssertEqual(second.title, "week 2: 5.0 / 6 mi")
        XCTAssertEqual(second.minutes, 1080)
    }

    // MARK: Actions

    func testActionsApplyOnlyWhileTheSessionIsStillOnThatDay() throws {
        let plan = PlanSchedule(plan: try miniPlan(), progress: PlanProgress())
        XCTAssertTrue(ReminderPlanner.actionApplies(schedule: plan, sessionIndex: 0, day: 1))
        XCTAssertFalse(ReminderPlanner.actionApplies(schedule: plan, sessionIndex: 0, day: 2))
        XCTAssertFalse(ReminderPlanner.actionApplies(schedule: plan, sessionIndex: 99, day: 1))
        XCTAssertFalse(ReminderPlanner.actionApplies(schedule: plan, sessionIndex: -1, day: 1))

        let done = PlanSchedule(plan: try miniPlan(), progress: plan.markingDone(0))
        XCTAssertFalse(ReminderPlanner.actionApplies(schedule: done, sessionIndex: 0, day: 1))
        let skipped = PlanSchedule(plan: try miniPlan(), progress: plan.skipping(0))
        XCTAssertFalse(ReminderPlanner.actionApplies(schedule: skipped, sessionIndex: 0, day: 1))

        // Pushed to day 5: a notification made for day 1 is stale, one made for day 5 is not.
        var moved = PlanProgress()
        moved.dayOverrides[PlanProgress.key(0)] = 5
        let pushed = PlanSchedule(plan: try miniPlan(), progress: moved)
        XCTAssertFalse(ReminderPlanner.actionApplies(schedule: pushed, sessionIndex: 0, day: 1))
        XCTAssertTrue(ReminderPlanner.actionApplies(schedule: pushed, sessionIndex: 0, day: 5))
    }

    func testNotificationIdsTellTheirDay() {
        XCTAssertEqual(ReminderPlanner.dayOffset(ofIdentifier: "plan.morning.12"), 12)
        XCTAssertEqual(ReminderPlanner.dayOffset(ofIdentifier: "plan.evening.0"), 0)
        XCTAssertEqual(ReminderPlanner.dayOffset(ofIdentifier: "plan.tt.251"), 251)
        XCTAssertEqual(ReminderPlanner.dayOffset(ofIdentifier: "plan.week.6"), 6)
        XCTAssertEqual(ReminderPlanner.dayOffset(ofIdentifier: "plan.start"), 0)
        XCTAssertNil(ReminderPlanner.dayOffset(ofIdentifier: "test.reminder"))
        XCTAssertNil(ReminderPlanner.dayOffset(ofIdentifier: "plan.morning.x"))
    }

    func testSessionRemindersCarryTheirDay() throws {
        let specs = try build()
        let morning = try XCTUnwrap(spec(specs, id: "plan.morning.3"))
        XCTAssertEqual(morning.dayOffset, 3)
        XCTAssertEqual(morning.sessionIndex, 1)
    }

    // MARK: Shared text and helpers

    func testForegroundPolicy() {
        XCTAssertTrue(ReminderPlanner.showsInForeground("plan.tt.11"))
        XCTAssertTrue(ReminderPlanner.showsInForeground("plan.week.6"))
        XCTAssertTrue(ReminderPlanner.showsInForeground("test.reminder"))
        XCTAssertFalse(ReminderPlanner.showsInForeground("plan.morning.1"))
        XCTAssertFalse(ReminderPlanner.showsInForeground("plan.evening.1"))
        XCTAssertFalse(ReminderPlanner.showsInForeground("plan.start"))
    }

    func testPlanTextDetail() throws {
        let plan = try miniPlan()
        let zones = PaceZones.forMile(412)
        XCTAssertEqual(PlanText.lines(for: plan.sessions[0], zones: zones, goalMile: 330),
                       ["2 mi, conversational, 9:35\u{2013}10:30 /mi"])
        XCTAssertEqual(PlanText.detail(for: plan.sessions[4], zones: zones, goalMile: 330),
                       "goal 5:30. target \u{2264} 6:35.")
        XCTAssertEqual(PlanText.lines(for: plan.sessions[5], zones: zones, goalMile: 330),
                       ["goal 5:30", "race day"])
    }

    func testClockText() {
        XCTAssertEqual(ReminderFormat.clock(480), "8:00 am")
        XCTAssertEqual(ReminderFormat.clock(1020), "5:00 pm")
        XCTAssertEqual(ReminderFormat.clock(0), "12:00 am")
        XCTAssertEqual(ReminderFormat.clock(720), "12:00 pm")
        XCTAssertEqual(ReminderFormat.clock(1439), "11:59 pm")
    }

    func testMinutesRoundTripThroughADate() {
        for minutes in [0, 480, 1020, 1439] {
            let date = ReminderFormat.date(minutes: minutes)
            XCTAssertEqual(ReminderFormat.minutes(of: date), minutes)
        }
    }
}
