import XCTest
@testable import MilePace

final class TrainingPlanTests: XCTestCase {
    /// Two weeks, five sessions. Day offsets from the start: 1, 3, 5, 8, 12.
    private static let miniJSON = """
    {
      "name": "mini",
      "startDate": "2026-10-12",
      "weeks": [
        { "week": 1, "miles": 5, "phase": 1, "recovery": false, "timeTrial": false, "race": false },
        { "week": 2, "miles": 6, "phase": 1, "recovery": true, "timeTrial": false, "race": true }
      ],
      "sessions": [
        { "week": 1, "weekday": 2, "phase": 1, "kind": "easy", "miles": 2, "title": "2 mi easy" },
        { "week": 1, "weekday": 4, "phase": 1, "kind": "track", "preset": "6x400-r", "title": "6 x 400 @ R", "note": "full rest" },
        { "week": 1, "weekday": 6, "phase": 1, "kind": "long", "miles": 3, "title": "3 mi long" },
        { "week": 2, "weekday": 2, "phase": 1, "kind": "mystery", "title": "mystery" },
        { "week": 2, "weekday": 6, "phase": 1, "kind": "race", "preset": "mile-tt", "title": "race" }
      ]
    }
    """

    private func miniPlan() throws -> PlanFile {
        return try JSONDecoder().decode(PlanFile.self, from: Data(TrainingPlanTests.miniJSON.utf8))
    }

    private func schedule(_ progress: PlanProgress = PlanProgress()) throws -> PlanSchedule {
        return PlanSchedule(plan: try miniPlan(), progress: progress)
    }

    // MARK: Decoding

    func testDecoding() throws {
        let plan = try miniPlan()
        XCTAssertEqual(plan.name, "mini")
        XCTAssertEqual(plan.startDate, "2026-10-12")
        XCTAssertEqual(plan.weeks.count, 2)
        XCTAssertEqual(plan.sessions.count, 5)
        XCTAssertTrue(plan.weeks[1].recovery)
        XCTAssertTrue(plan.weeks[1].race)
        XCTAssertEqual(plan.sessions[0].kind, .easy)
        XCTAssertEqual(plan.sessions[0].miles, 2)
        XCTAssertNil(plan.sessions[0].preset)
        XCTAssertEqual(plan.sessions[1].kind, .track)
        XCTAssertEqual(plan.sessions[1].preset, "6x400-r")
        XCTAssertEqual(plan.sessions[1].note, "full rest")
        XCTAssertEqual(plan.sessions[4].kind, .race)
    }

    func testUnknownKindDecodesAsOther() throws {
        let plan = try miniPlan()
        XCTAssertEqual(plan.sessions[3].kind, .other)
    }

    func testProgressRoundTrips() throws {
        var progress = PlanProgress()
        progress.shifts.append(PlanShift(fromIndex: 2, days: 3))
        progress.statuses[PlanProgress.key(1)] = .done
        progress.statuses[PlanProgress.key(4)] = .skipped
        let data = try JSONEncoder().encode(progress)
        let decoded = try JSONDecoder().decode(PlanProgress.self, from: data)
        XCTAssertEqual(decoded, progress)
    }

    // MARK: Day offsets and shifts

    func testDayOffsetsWithoutShifts() throws {
        let plan = try schedule()
        XCTAssertEqual((0..<5).map { plan.dayOffset($0) }, [1, 3, 5, 8, 12])
    }

    func testPushingBackShiftsThatSessionAndLaterOnes() throws {
        let plan = try schedule()
        // Session 1 was due on day 3; today is day 5, so it moves back 2 days.
        let pushed = try schedule(plan.pushingBack(missed: 1, today: 5))
        XCTAssertEqual((0..<5).map { pushed.dayOffset($0) }, [1, 5, 7, 10, 14])
        XCTAssertEqual(pushed.raceDayOffset, 14)
    }

    func testStackedShiftsAddUp() throws {
        let first = try schedule().pushingBack(missed: 1, today: 5)
        let once = try schedule(first)
        // Session 2 is now due on day 7; today is day 9, so another 2 days.
        let second = once.pushingBack(missed: 2, today: 9)
        let twice = try schedule(second)
        XCTAssertEqual(second.shifts.count, 2)
        XCTAssertEqual((0..<5).map { twice.dayOffset($0) }, [1, 5, 9, 12, 16])
    }

    func testPushingBackIgnoresNonPositiveShift() throws {
        let plan = try schedule()
        XCTAssertEqual(plan.pushingBack(missed: 1, today: 3), PlanProgress())
        XCTAssertEqual(plan.pushingBack(missed: 99, today: 9), PlanProgress())
    }

    // MARK: Missed, today, next

    func testFirstMissedIgnoresStatusedAndFutureSessions() throws {
        let plan = try schedule()
        XCTAssertNil(plan.firstMissed(today: 0))
        XCTAssertNil(plan.firstMissed(today: 1))
        XCTAssertEqual(plan.firstMissed(today: 4), 0)

        let afterDone = try schedule(plan.markingDone(0))
        XCTAssertEqual(afterDone.firstMissed(today: 4), 1)

        let afterSkip = try schedule(afterDone.skipping(1))
        XCTAssertNil(afterSkip.firstMissed(today: 4))
        XCTAssertEqual(afterSkip.firstMissed(today: 6), 2)
    }

    func testTodays() throws {
        let plan = try schedule()
        XCTAssertEqual(plan.todays(today: 3), [1])
        XCTAssertEqual(plan.todays(today: 2), [])
        let done = try schedule(plan.markingDone(1))
        XCTAssertEqual(done.todays(today: 3), [])
        XCTAssertEqual(done.indices(onDay: 3), [1])
    }

    func testNextAfter() throws {
        let plan = try schedule()
        XCTAssertEqual(plan.next(after: 0), 0)
        XCTAssertEqual(plan.next(after: 3), 2)
        XCTAssertEqual(plan.next(after: 5), 3)
        XCTAssertNil(plan.next(after: 12))

        let skipped = try schedule(plan.skipping(2))
        XCTAssertEqual(skipped.next(after: 3), 3)
    }

    // MARK: Reconcile

    func testReconciledMarksOnlyDaysWithActivity() throws {
        let plan = try schedule()
        let result = try schedule(plan.reconciled(activityDays: [1, 2, 5]))
        XCTAssertEqual(result.status(0), .done)
        XCTAssertNil(result.status(1))
        XCTAssertEqual(result.status(2), .done)
        XCTAssertNil(result.status(3))
    }

    func testReconciledNeverTouchesRestDays() throws {
        let plan = try schedule()
        XCTAssertEqual(plan.reconciled(activityDays: [0, 2, 4, 6, 7]), PlanProgress())
        XCTAssertEqual(plan.reconciled(activityDays: []), PlanProgress())
    }

    func testReconciledKeepsSkippedSessions() throws {
        let skipped = try schedule(try schedule().skipping(2))
        let result = try schedule(skipped.reconciled(activityDays: [5]))
        XCTAssertEqual(result.status(2), .skipped)
    }

    // MARK: Current week

    func testCurrentWeek() throws {
        let plan = try schedule()
        XCTAssertEqual(plan.currentWeek(today: -3), 0)
        XCTAssertEqual(plan.currentWeek(today: 0), 1)
        XCTAssertEqual(plan.currentWeek(today: 1), 1)
        XCTAssertEqual(plan.currentWeek(today: 4), 1)
        XCTAssertEqual(plan.currentWeek(today: 6), 2)
        XCTAssertEqual(plan.currentWeek(today: 12), 2)
        XCTAssertEqual(plan.currentWeek(today: 13), 2)
        XCTAssertEqual(plan.currentWeek(today: 400), 2)
    }

    func testCurrentWeekStaysOnTodaysSessionWhenDone() throws {
        let plan = try schedule(try schedule().markingDone(2))
        XCTAssertEqual(plan.currentWeek(today: 5), 1)
    }

    func testStripStartAndWeekStart() throws {
        let plan = try schedule()
        XCTAssertEqual(plan.stripStart(today: -5), 0)
        XCTAssertEqual(plan.stripStart(today: 3), 0)
        XCTAssertEqual(plan.stripStart(today: 8), 7)
        XCTAssertEqual(plan.stripStart(today: 100), 7)
        XCTAssertEqual(plan.startOffset(ofWeek: 1), 0)
        XCTAssertEqual(plan.startOffset(ofWeek: 2), 7)

        let pushed = try schedule(plan.pushingBack(missed: 1, today: 5))
        XCTAssertEqual(pushed.startOffset(ofWeek: 1), 0)
        XCTAssertEqual(pushed.startOffset(ofWeek: 2), 9)
    }

    // MARK: Strip cells and preset tags

    func testStripCells() throws {
        let plan = try schedule()
        XCTAssertEqual(plan.stripCell(day: 0, today: 3), StripCell(state: .rest, label: "\u{00B7}"))
        XCTAssertEqual(plan.stripCell(day: 3, today: 3), StripCell(state: .today, label: "trk"))
        XCTAssertEqual(plan.stripCell(day: 5, today: 3), StripCell(state: .planned, label: "lg3"))
        XCTAssertEqual(plan.stripCell(day: 1, today: 3), StripCell(state: .missed, label: "!"))
        XCTAssertEqual(plan.stripCell(day: 2, today: 2).state, .today)

        let marked = try schedule(plan.markingDone(0))
        XCTAssertEqual(marked.stripCell(day: 1, today: 3), StripCell(state: .done, label: "x"))
        let skipped = try schedule(plan.skipping(0))
        XCTAssertEqual(skipped.stripCell(day: 1, today: 3), StripCell(state: .skipped, label: "\u{2013}"))
    }

    func testNearestDayForPreset() throws {
        let plan = try schedule()
        XCTAssertEqual(plan.nearestDay(forPreset: "6x400-r", today: 0, within: 14), 3)
        XCTAssertNil(plan.nearestDay(forPreset: "6x400-r", today: 0, within: 2))
        XCTAssertNil(plan.nearestDay(forPreset: "6x400-r", today: 4, within: 14))
        XCTAssertNil(plan.nearestDay(forPreset: "nope", today: 0, within: 14))
        XCTAssertEqual(plan.nearestDay(forPreset: "mile-tt", today: 0, within: 14), 12)
        let done = try schedule(plan.markingDone(1))
        XCTAssertNil(done.nearestDay(forPreset: "6x400-r", today: 0, within: 14))
    }

    // MARK: Routes

    func testRoutes() throws {
        let plan = try miniPlan()
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[0]), .freeRun(zone: .easy))
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[1]), .track(presetId: "6x400-r"))
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[2]), .freeRun(zone: .easy))
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[3]), .freeRun(zone: .off))
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[4]), .track(presetId: "mile-tt"))

        let road = PlanSession(week: 1, weekday: 1, phase: 1, kind: .road, title: "t",
                               miles: nil, preset: "3 \u{00D7} 5 min threshold", note: nil)
        XCTAssertEqual(PlanRoute.route(for: road), .roadWorkout(name: "3 \u{00D7} 5 min threshold"))
        let bare = PlanSession(week: 1, weekday: 1, phase: 1, kind: .road, title: "t",
                               miles: nil, preset: nil, note: nil)
        XCTAssertEqual(PlanRoute.route(for: bare), .freeRun(zone: .threshold))
    }

    func testShortLabels() throws {
        let plan = try miniPlan()
        XCTAssertEqual(plan.sessions[0].shortLabel, "e2")
        XCTAssertEqual(plan.sessions[1].shortLabel, "trk")
        XCTAssertEqual(plan.sessions[2].shortLabel, "lg3")
        XCTAssertEqual(plan.sessions[4].shortLabel, "race")
        XCTAssertEqual(PlanFormat.miles(1.5), "1.5")
        XCTAssertEqual(PlanFormat.miles(2), "2")
        XCTAssertEqual(PlanFormat.miles(nil), "")
        XCTAssertEqual(PlanFormat.daysText(1), "1 day")
        XCTAssertEqual(PlanFormat.daysText(8), "8 days")
    }

    // MARK: Calendar

    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone.current
        return calendar
    }

    func testCalendarRoundTripAcrossDaylightSavingChange() throws {
        let calendar = newYork()
        let start = try XCTUnwrap(PlanCalendar.parse("2026-10-12", calendar: calendar))
        // US clocks go back on 2026-11-01, so offset 20 is the 25-hour day and 27 is 2026-11-08.
        let date = PlanCalendar.date(forOffset: 27, start: start, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 11)
        XCTAssertEqual(parts.day, 8)
        XCTAssertEqual(parts.hour, 0)
        XCTAssertEqual(PlanCalendar.dayOffset(of: date, start: start, calendar: calendar), 27)

        let lateEvening = date.addingTimeInterval(23.5 * 3600)
        XCTAssertEqual(PlanCalendar.dayOffset(of: lateEvening, start: start, calendar: calendar), 27)

        for offset in 0...40 {
            let day = PlanCalendar.date(forOffset: offset, start: start, calendar: calendar)
            XCTAssertEqual(PlanCalendar.dayOffset(of: day, start: start, calendar: calendar), offset)
        }
    }

    func testParseAndFormatDates() throws {
        let calendar = newYork()
        let date = try XCTUnwrap(PlanCalendar.parse("2026-10-12", calendar: calendar))
        XCTAssertEqual(PlanCalendar.ymd(date, calendar: calendar), "2026-10-12")
        XCTAssertNil(PlanCalendar.parse("2026-13-40", calendar: calendar))
        XCTAssertNil(PlanCalendar.parse("garbage", calendar: calendar))
        XCTAssertNil(PlanCalendar.parse("2026-10", calendar: calendar))
    }
}
