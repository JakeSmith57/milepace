import XCTest
@testable import MilePace

/// Checks the real `plan.json` in the app bundle against the presets in the app.
final class BundledPlanTests: XCTestCase {
    private func bundledPlan() throws -> PlanFile {
        let plan = PlanLoader.load(bundle: Bundle(for: PlanStore.self))
        return try XCTUnwrap(plan, "plan.json is missing from the app bundle or does not parse")
    }

    func testHas37WeeksAndTheRaceInWeek37() throws {
        let plan = try bundledPlan()
        XCTAssertEqual(plan.weeks.count, 37)
        for (index, week) in plan.weeks.enumerated() {
            XCTAssertEqual(week.week, index + 1)
        }
        XCTAssertEqual(plan.version, 2)
        XCTAssertEqual(plan.startDate, "2026-10-12")
        XCTAssertEqual(plan.raceDate, "2027-06-21")
    }

    func testPhasesComeFromTheWeeks() throws {
        let plan = try bundledPlan()
        XCTAssertEqual(Set(plan.weeks.map { $0.phase }), [1, 2, 3, 4])
        func weeks(inPhase phase: Int) -> ClosedRange<Int>? {
            let numbers = plan.weeks.filter { $0.phase == phase }.map { $0.week }
            guard let first = numbers.min(), let last = numbers.max() else { return nil }
            return first...last
        }
        XCTAssertEqual(weeks(inPhase: 1), 1...14)
        XCTAssertEqual(weeks(inPhase: 2), 15...24)
        XCTAssertEqual(weeks(inPhase: 3), 25...33)
        XCTAssertEqual(weeks(inPhase: 4), 34...37)
    }

    func testSessionsAreSortedByWeekAndWeekday() throws {
        let plan = try bundledPlan()
        XCTAssertFalse(plan.sessions.isEmpty)
        for index in 1..<plan.sessions.count {
            let before = plan.sessions[index - 1]
            let after = plan.sessions[index]
            let ordered = before.week < after.week || (before.week == after.week && before.weekday < after.weekday)
            XCTAssertTrue(ordered, "session \(index) is out of order")
        }
        for session in plan.sessions {
            XCTAssertTrue((1...7).contains(session.weekday))
            XCTAssertTrue((1...plan.weeks.count).contains(session.week))
        }
    }

    func testRoadPresetsExist() throws {
        let plan = try bundledPlan()
        let names = Set(RoadWorkoutPresets.all.map { $0.name })
        for session in plan.sessions where session.kind == .road {
            let name = session.preset ?? ""
            XCTAssertTrue(names.contains(name), "unknown road workout: \(name)")
        }
    }

    func testTrackPresetsExistExceptSharpener() throws {
        let plan = try bundledPlan()
        let ids = Set(WorkoutPresets.all.map { $0.id })
        for session in plan.sessions where session.isTrackSession {
            let id = session.preset ?? ""
            if id == "sharpener" { continue }
            XCTAssertTrue(ids.contains(id), "unknown track preset: \(id)")
        }
    }

    func testExactlyOneRaceOnMondayOfWeek37() throws {
        let plan = try bundledPlan()
        let races = plan.sessions.filter { $0.kind == .race }
        XCTAssertEqual(races.count, 1)
        XCTAssertEqual(races.first?.week, 37)
        XCTAssertEqual(races.first?.weekday, 1)
        XCTAssertEqual(races.first?.targetSeconds, 330)
    }

    func testRaceDateMatchesTheRaceSession() throws {
        let plan = try bundledPlan()
        let start = try XCTUnwrap(PlanCalendar.parse(plan.startDate))
        let race = try XCTUnwrap(PlanCalendar.parse(try XCTUnwrap(plan.raceDate)))
        let schedule = PlanSchedule(plan: plan, progress: PlanProgress())
        XCTAssertEqual(PlanCalendar.dayOffset(of: race, start: start), schedule.raceDayOffset)
        XCTAssertEqual(schedule.raceDayOffset, 252)
    }

    func testTimeTrialsAndRaceHaveTargets() throws {
        let plan = try bundledPlan()
        let timed = plan.sessions.filter { $0.kind == .timeTrial || $0.kind == .race }
        XCTAssertEqual(timed.count, 4)
        for session in timed {
            XCTAssertNotNil(session.targetSeconds, "\(session.title) has no targetSeconds")
        }
        let trials = plan.sessions.filter { $0.kind == .timeTrial }
        XCTAssertEqual(trials.map { $0.targetSeconds }, [395, 365, 345])
        XCTAssertEqual(trials.map { $0.week }, [14, 24, 33])
        for session in plan.sessions where session.kind != .timeTrial && session.kind != .race {
            XCTAssertNil(session.targetSeconds)
        }
    }

    func testNoSessionOnWednesdayOrSunday() throws {
        let plan = try bundledPlan()
        for session in plan.sessions {
            XCTAssertNotEqual(session.weekday, 3, "\(session.title) is on a Wednesday")
            XCTAssertNotEqual(session.weekday, 7, "\(session.title) is on a Sunday")
        }
    }

    private func sessionIndex(_ plan: PlanFile, week: Int, weekday: Int) throws -> Int {
        return try XCTUnwrap(plan.sessions.firstIndex(where: { $0.week == week && $0.weekday == weekday }))
    }

    func testPushBackOnTheRealPlanKeepsItsRules() throws {
        let plan = try bundledPlan()
        let base = PlanSchedule(plan: plan, progress: PlanProgress())
        let raceIndex = try XCTUnwrap(base.raceIndex)
        let raceDay = base.dayOffset(raceIndex)
        var cleanCount = 0
        var droppedCount = 0
        for missed in plan.sessions.indices {
            if plan.sessions[missed].kind == .race { continue }
            for delay in [1, 2] {
                let today = base.dayOffset(missed) + delay
                let label = "missed \(missed) today \(today)"
                let result = base.pushingBack(missed: missed, today: today)
                let pushed = PlanSchedule(plan: plan, progress: result.progress)

                // The race never moves and is never skipped.
                XCTAssertNil(pushed.status(raceIndex), label)
                XCTAssertEqual(pushed.dayOffset(raceIndex), raceDay, label)

                // The only statuses written are the dropped sessions' skips.
                XCTAssertEqual(result.progress.statuses.count, result.dropped.count, label)
                for index in result.dropped {
                    XCTAssertEqual(pushed.status(index), .skipped, label)
                }

                // Every session that was given a day lands on an allowed one, after today and before
                // the day before the race.
                for (key, day) in result.progress.dayOverrides {
                    XCTAssertGreaterThanOrEqual(day, today, label)
                    XCTAssertLessThan(day, raceDay - 1, label)
                    let weekday = pushed.weekdayNumber(ofDay: day)
                    XCTAssertNotEqual(weekday, 3, label)
                    XCTAssertNotEqual(weekday, 7, label)
                    XCTAssertNil(result.progress.statuses[key], label)
                }
                for index in result.moved {
                    XCTAssertGreaterThan(pushed.dayOffset(index), base.dayOffset(index), label)
                }

                // The missed session itself takes today, or the next day when today is closed.
                if !result.dropped.contains(missed) {
                    XCTAssertNil(pushed.status(missed), label)
                    XCTAssertGreaterThanOrEqual(pushed.dayOffset(missed), today, label)
                    XCTAssertLessThanOrEqual(pushed.dayOffset(missed), today + 1, label)
                }

                // Of the sessions still to do, no two hard ones are on neighbouring days and no two share a day.
                var days: [Int] = []
                var hardDays: [Int] = []
                for index in plan.sessions.indices where pushed.status(index) == nil {
                    days.append(pushed.dayOffset(index))
                    if PlanSchedule.isHard(plan.sessions[index].kind) {
                        hardDays.append(pushed.dayOffset(index))
                    }
                }
                XCTAssertEqual(Set(days).count, days.count, label)
                hardDays.sort()
                for pair in zip(hardDays, hardDays.dropFirst()) {
                    XCTAssertGreaterThan(pair.1 - pair.0, 1, label)
                }

                if result.dropped.isEmpty {
                    cleanCount += 1
                } else {
                    droppedCount += 1
                }
            }
        }
        XCTAssertGreaterThan(cleanCount, 10)
        XCTAssertGreaterThan(droppedCount, 10)
    }

    func testPushBackExamplesOnTheRealPlan() throws {
        let plan = try bundledPlan()
        let base = PlanSchedule(plan: plan, progress: PlanProgress())
        let raceIndex = try XCTUnwrap(base.raceIndex)

        // Week 3's Saturday long run, done on the Sunday after (closed) or Monday: it takes Monday, and
        // Monday holds nothing, so nothing else moves.
        let long3 = try sessionIndex(plan, week: 3, weekday: 6)
        for delay in [1, 2] {
            let result = base.pushingBack(missed: long3, today: base.dayOffset(long3) + delay)
            XCTAssertEqual(PlanSchedule(plan: plan, progress: result.progress).dayOffset(long3),
                           base.dayOffset(long3) + 2)
            XCTAssertEqual(result.moved, [])
            XCTAssertEqual(result.dropped, [])
        }

        // Week 8's long run on Monday of week 9 pushes that week's first three sessions later, and the
        // fourth keeps its day.
        let long8 = try sessionIndex(plan, week: 8, weekday: 6)
        let first9 = try sessionIndex(plan, week: 9, weekday: 1)
        let second9 = try sessionIndex(plan, week: 9, weekday: 2)
        let third9 = try sessionIndex(plan, week: 9, weekday: 4)
        let result8 = base.pushingBack(missed: long8, today: base.dayOffset(long8) + 2)
        let pushed8 = PlanSchedule(plan: plan, progress: result8.progress)
        XCTAssertEqual(pushed8.dayOffset(long8), base.dayOffset(first9))
        XCTAssertEqual(result8.moved, [first9, second9, third9])
        XCTAssertEqual(result8.dropped, [])

        // Weeks 13 to 36 use every open day, so a missed session there pushes everything behind it
        // later and the last easy run before the race (week 36 Saturday) is dropped.
        let road13 = try sessionIndex(plan, week: 13, weekday: 2)
        let easy36 = try sessionIndex(plan, week: 36, weekday: 6)
        for delay in [1, 2] {
            let result = base.pushingBack(missed: road13, today: base.dayOffset(road13) + delay)
            XCTAssertEqual(result.dropped, [easy36])
            XCTAssertGreaterThan(result.moved.count, 50)
        }

        // Race week: Friday's track session goes to Saturday and Saturday's easy run is dropped. The race
        // stays on Monday.
        let track36 = try sessionIndex(plan, week: 36, weekday: 5)
        let result36 = base.pushingBack(missed: track36, today: base.dayOffset(track36) + 1)
        let pushed36 = PlanSchedule(plan: plan, progress: result36.progress)
        XCTAssertEqual(pushed36.dayOffset(track36), base.dayOffset(easy36))
        XCTAssertEqual(result36.dropped, [easy36])
        XCTAssertEqual(result36.moved, [])
        XCTAssertEqual(pushed36.dayOffset(raceIndex), base.dayOffset(raceIndex))
    }

    func testScheduleStartsOnPlanStartDate() throws {
        let plan = try bundledPlan()
        XCTAssertNotNil(PlanCalendar.parse(plan.startDate))
        let schedule = PlanSchedule(plan: plan, progress: PlanProgress())
        XCTAssertEqual(schedule.dayOffset(0), 1)
        XCTAssertEqual(schedule.currentWeek(today: -1), 0)
        XCTAssertEqual(schedule.currentWeek(today: schedule.raceDayOffset + 1), 37)
    }
}
