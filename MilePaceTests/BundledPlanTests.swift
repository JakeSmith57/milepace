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
        var movedCount = 0
        var droppedCount = 0
        for missed in plan.sessions.indices {
            let kind = plan.sessions[missed].kind
            if kind == .easy || kind == .race { continue }
            for delay in [1, 2] {
                let today = base.dayOffset(missed) + delay
                let result = base.pushingBack(missed: missed, today: today)
                let pushed = PlanSchedule(plan: plan, progress: result.progress)
                XCTAssertNil(pushed.status(raceIndex))
                XCTAssertEqual(pushed.dayOffset(raceIndex), raceDay)

                if !result.dropped.isEmpty {
                    XCTAssertEqual(result.dropped, [missed])
                    XCTAssertNil(result.replaced)
                    XCTAssertEqual(pushed.status(missed), .skipped)
                    XCTAssertEqual(result.progress.statuses.count, 1)
                    XCTAssertEqual(result.progress.dayOverrides, [:])
                    droppedCount += 1
                    continue
                }

                // The session lands on an allowed day this calendar week, nothing but the easy
                // session it replaced changes, and hard sessions stay apart.
                let day = pushed.dayOffset(missed)
                XCTAssertGreaterThanOrEqual(day, today)
                XCTAssertLessThanOrEqual(day, base.calendarWeekStart(containing: today) + 6)
                XCTAssertLessThan(day, raceDay - 1)
                let weekday = pushed.weekdayNumber(ofDay: day)
                XCTAssertNotEqual(weekday, 3)
                XCTAssertNotEqual(weekday, 7)
                XCTAssertNil(pushed.status(missed))
                XCTAssertEqual(result.progress.dayOverrides, [PlanProgress.key(missed): day])
                if let replaced = result.replaced {
                    XCTAssertEqual(plan.sessions[replaced].kind, .easy)
                    XCTAssertEqual(base.dayOffset(replaced), day)
                    XCTAssertEqual(pushed.status(replaced), .skipped)
                    XCTAssertEqual(result.progress.statuses.count, 1)
                } else {
                    XCTAssertTrue(base.indices(onDay: day).isEmpty)
                    XCTAssertEqual(result.progress.statuses.count, 0)
                }
                if PlanSchedule.isHard(kind) {
                    for other in plan.sessions.indices where other != missed {
                        guard PlanSchedule.isHard(plan.sessions[other].kind) else { continue }
                        XCTAssertGreaterThan(abs(pushed.dayOffset(other) - day), 1)
                    }
                }
                movedCount += 1
            }
        }
        XCTAssertGreaterThan(movedCount, 10)
        XCTAssertGreaterThan(droppedCount, 10)
    }

    func testPushBackExamplesOnTheRealPlan() throws {
        let plan = try bundledPlan()
        let base = PlanSchedule(plan: plan, progress: PlanProgress())
        func landing(_ missed: Int, _ today: Int) -> (day: Int, result: PushBackResult) {
            let result = base.pushingBack(missed: missed, today: today)
            return (PlanSchedule(plan: plan, progress: result.progress).dayOffset(missed), result)
        }

        // Week 3's Saturday long run, done on Monday of week 4, which holds nothing.
        let long3 = try sessionIndex(plan, week: 3, weekday: 6)
        let monday = base.dayOffset(long3) + 2
        let early = landing(long3, monday)
        XCTAssertEqual(early.day, monday)
        XCTAssertNil(early.result.replaced)
        // On the Sunday after, no day is left this week.
        let sunday = base.pushingBack(missed: long3, today: base.dayOffset(long3) + 1)
        XCTAssertEqual(sunday.dropped, [long3])

        // Week 8's long run on Monday of week 9 replaces that day's easy run.
        let long8 = try sessionIndex(plan, week: 8, weekday: 6)
        let easy9 = try sessionIndex(plan, week: 9, weekday: 1)
        let swapped = landing(long8, base.dayOffset(long8) + 2)
        XCTAssertEqual(swapped.day, base.dayOffset(easy9))
        XCTAssertEqual(swapped.result.replaced, easy9)

        // Week 13's Tuesday road session: Thursday's easy run sits next to Friday's track session, so
        // there is no room this week.
        let road13 = try sessionIndex(plan, week: 13, weekday: 2)
        for delay in [1, 2] {
            XCTAssertEqual(base.pushingBack(missed: road13, today: base.dayOffset(road13) + delay).dropped,
                           [road13])
        }

        // Race week: Friday's track session goes to Saturday and replaces its easy run. The race
        // stays on Monday.
        let track36 = try sessionIndex(plan, week: 36, weekday: 5)
        let easy36 = try sessionIndex(plan, week: 36, weekday: 6)
        let last = landing(track36, base.dayOffset(track36) + 1)
        XCTAssertEqual(last.day, base.dayOffset(easy36))
        XCTAssertEqual(last.result.replaced, easy36)
        let raceIndex = try XCTUnwrap(base.raceIndex)
        XCTAssertEqual(PlanSchedule(plan: plan, progress: last.result.progress).dayOffset(raceIndex),
                       base.dayOffset(raceIndex))
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
