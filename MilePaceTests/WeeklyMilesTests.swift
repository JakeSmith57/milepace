import XCTest
@testable import MilePace

final class WeeklyMilesTests: XCTestCase {
    private func newYork() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? TimeZone.current
        return calendar
    }

    private func date(_ calendar: Calendar, month: Int, day: Int, hour: Int = 12, minute: Int = 0) throws -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return try XCTUnwrap(calendar.date(from: parts))
    }

    func testSumAddsSevenDays() {
        let miles: [Int: Double] = [-1: 9, 0: 1, 3: 2.5, 6: 1, 7: 4]
        XCTAssertEqual(WeeklyMiles.sum(milesByDay: miles, firstDay: 0), 4.5, accuracy: 1e-9)
        XCTAssertEqual(WeeklyMiles.sum(milesByDay: miles, firstDay: 7), 4, accuracy: 1e-9)
        XCTAssertEqual(WeeklyMiles.sum(milesByDay: [:], firstDay: 0), 0, accuracy: 1e-9)
    }

    func testMondayOnOrBefore() throws {
        let calendar = newYork()
        let monday = try date(calendar, month: 10, day: 12, hour: 0)
        // Wednesday noon and Sunday late evening both belong to the week of Monday Oct 12.
        XCTAssertEqual(WeeklyMiles.monday(onOrBefore: try date(calendar, month: 10, day: 14), calendar: calendar), monday)
        XCTAssertEqual(WeeklyMiles.monday(onOrBefore: try date(calendar, month: 10, day: 18, hour: 23, minute: 30), calendar: calendar), monday)
        XCTAssertEqual(WeeklyMiles.monday(onOrBefore: monday, calendar: calendar), monday)
    }

    func testBucketsAreCalendarWeeksOldestFirst() throws {
        let calendar = newYork()
        let now = try date(calendar, month: 10, day: 14)
        let runs = [LoggedRun(date: try date(calendar, month: 10, day: 13), meters: 3 * metersPerMile, workoutName: ""),
                    LoggedRun(date: try date(calendar, month: 10, day: 5), meters: 4 * metersPerMile, workoutName: "")]
        let workouts = [LoggedWorkout(date: try date(calendar, month: 10, day: 14), name: "6 \u{00D7} 400 @ R", repMeters: 2400)]
        let buckets = WeeklyMiles.buckets(runs: runs, workouts: workouts, weeks: 3, now: now, calendar: calendar)
        XCTAssertEqual(buckets.map { $0.label }, ["9/28", "10/5", "10/12"])
        XCTAssertEqual(buckets[0].miles, 0, accuracy: 1e-9)
        XCTAssertEqual(buckets[1].miles, 4, accuracy: 1e-6)
        XCTAssertEqual(buckets[2].miles, 3 + 2400 / metersPerMile + 2.0, accuracy: 1e-6)
        XCTAssertEqual(WeeklyMiles.buckets(runs: runs, workouts: workouts, weeks: 0, now: now, calendar: calendar), [])
    }

    func testTheLogAndThePlanAddUpTheSameMiles() throws {
        let calendar = newYork()
        let now = try date(calendar, month: 10, day: 16)
        let monday = WeeklyMiles.monday(onOrBefore: now, calendar: calendar)
        let runs = [LoggedRun(date: try date(calendar, month: 10, day: 12, hour: 7), meters: 2 * metersPerMile, workoutName: ""),
                    LoggedRun(date: try date(calendar, month: 10, day: 15, hour: 18), meters: 3.5 * metersPerMile, workoutName: "20 min tempo")]
        let workouts = [LoggedWorkout(date: try date(calendar, month: 10, day: 13), name: "x", repMeters: 1600)]
        let byDay = PlanActivities.milesByDay(runs: runs, workouts: workouts, start: monday, calendar: calendar)
        let planSum = WeeklyMiles.sum(milesByDay: byDay, firstDay: 0)
        let buckets = WeeklyMiles.buckets(runs: runs, workouts: workouts, weeks: 4, now: now, calendar: calendar)
        XCTAssertEqual(buckets.last?.miles ?? -1, planSum, accuracy: 1e-9)
        XCTAssertEqual(planSum, 2 + 3.5 + 1600 / metersPerMile + 2.0, accuracy: 1e-6)
    }

    func testAnEarlyMorningRunBelongsToTheDayBefore() throws {
        let calendar = newYork()
        let now = try date(calendar, month: 10, day: 14)
        // 00:30 on Monday Oct 12 counts for Sunday Oct 11, which is the previous week.
        let runs = [LoggedRun(date: try date(calendar, month: 10, day: 12, hour: 0, minute: 30),
                              meters: 5 * metersPerMile, workoutName: "")]
        let buckets = WeeklyMiles.buckets(runs: runs, workouts: [], weeks: 2, now: now, calendar: calendar)
        XCTAssertEqual(buckets.map { $0.label }, ["10/5", "10/12"])
        XCTAssertEqual(buckets[0].miles, 5, accuracy: 1e-6)
        XCTAssertEqual(buckets[1].miles, 0, accuracy: 1e-6)
    }
}
