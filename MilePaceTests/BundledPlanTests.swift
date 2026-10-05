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

    /// Pushes `missed` back on `base` as of `today` and checks every rule the contained push-back keeps:
    /// only the missed session and the sessions it moves leave their day, and they stay between today and
    /// that week's Sunday on open days; the race, finished sessions and later weeks stay put; no two
    /// sessions share a day and no two hard ones (the race included) are on neighbouring days; the
    /// handful of changes stays small. Returns the result for further checks.
    private func pushAndCheck(_ plan: PlanFile, base: PlanSchedule, missed: Int, today: Int) throws -> PushBackResult {
        let raceIndex = try XCTUnwrap(base.raceIndex)
        let raceDay = base.dayOffset(raceIndex)
        let label = "missed \(missed) today \(today)"
        let result = base.pushingBack(missed: missed, today: today)
        let pushed = PlanSchedule(plan: plan, progress: result.progress)
        let sunday = base.calendarWeekStart(containing: today) + 6

        // The race never moves and is never skipped.
        XCTAssertNil(pushed.status(raceIndex), label)
        XCTAssertEqual(pushed.dayOffset(raceIndex), raceDay, label)

        // The only status changes are the skips of the dropped sessions; finished sessions keep their day.
        for index in plan.sessions.indices {
            if result.dropped.contains(index) {
                XCTAssertEqual(pushed.status(index), .skipped, label)
            } else {
                XCTAssertEqual(pushed.status(index), base.status(index), label)
            }
            if base.status(index) == .done {
                XCTAssertEqual(pushed.dayOffset(index), base.dayOffset(index), label)
            }
        }

        // Only the missed session and the moved ones changed day. They are on open days from today to this
        // week's Sunday, before the race; everything else (later weeks included) is where it was.
        let movedSet = Set(result.moved)
        for index in plan.sessions.indices {
            let placed = index == missed ? !result.dropped.contains(index) : movedSet.contains(index)
            if placed {
                let day = pushed.dayOffset(index)
                XCTAssertGreaterThanOrEqual(day, today, label)
                XCTAssertLessThanOrEqual(day, sunday, label)
                XCTAssertLessThan(day, raceDay, label)
                XCTAssertNotEqual(pushed.weekdayNumber(ofDay: day), 3, label)
                XCTAssertNotEqual(pushed.weekdayNumber(ofDay: day), 7, label)
            } else {
                XCTAssertEqual(pushed.dayOffset(index), base.dayOffset(index), label)
            }
        }
        for index in result.moved {
            XCTAssertGreaterThan(pushed.dayOffset(index), base.dayOffset(index), label)
        }

        // No two sessions that are still to do (or done) share a day, and no two hard ones are neighbours.
        var days: [Int] = []
        var hardDays: [Int] = []
        for index in plan.sessions.indices where pushed.status(index) != .skipped {
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

        // A week has five sessions, so a push touches a handful at most (the largest in the plan is 5).
        XCTAssertLessThanOrEqual(result.moved.count + result.dropped.count, 6, label)
        return result
    }

    func testPushBackOnTheRealPlanStaysInsideTheWeekAndKeepsItsRules() throws {
        let plan = try bundledPlan()
        let base = PlanSchedule(plan: plan, progress: PlanProgress())
        var cleanCount = 0
        var droppedCount = 0
        for missed in plan.sessions.indices where plan.sessions[missed].kind != .race {
            for delay in [1, 2] {
                let result = try pushAndCheck(plan, base: base, missed: missed, today: base.dayOffset(missed) + delay)
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

    func testPushBackOnTheRealPlanLeavesFinishedSessionsWhereTheyAre() throws {
        let plan = try bundledPlan()
        // Every fifth session is already done.
        var progress = PlanProgress()
        for index in plan.sessions.indices where index % 5 == 3 && plan.sessions[index].kind != .race {
            progress.statuses[PlanProgress.key(index)] = .done
        }
        let base = PlanSchedule(plan: plan, progress: progress)
        for missed in plan.sessions.indices where plan.sessions[missed].kind != .race && base.status(missed) == nil {
            for delay in [1, 2] {
                _ = try pushAndCheck(plan, base: base, missed: missed, today: base.dayOffset(missed) + delay)
            }
        }
    }

    func testPushBackExamplesOnTheRealPlan() throws {
        let plan = try bundledPlan()
        let base = PlanSchedule(plan: plan, progress: PlanProgress())
        let raceIndex = try XCTUnwrap(base.raceIndex)

        // Week 3's Saturday long run: on the Sunday after (closed) the week has no day left for it, so it
        // is skipped and nothing else changes. On the Monday it takes that day, and Monday holds nothing.
        let long3 = try sessionIndex(plan, week: 3, weekday: 6)
        let sunday3 = base.pushingBack(missed: long3, today: base.dayOffset(long3) + 1)
        XCTAssertEqual(sunday3.dropped, [long3])
        XCTAssertEqual(sunday3.moved, [])
        XCTAssertEqual(sunday3.progress.statuses, [PlanProgress.key(long3): .skipped])
        XCTAssertEqual(sunday3.progress.dayOverrides, [:])
        let monday3 = base.pushingBack(missed: long3, today: base.dayOffset(long3) + 2)
        XCTAssertEqual(PlanSchedule(plan: plan, progress: monday3.progress).dayOffset(long3),
                       base.dayOffset(long3) + 2)
        XCTAssertEqual(monday3.moved, [])
        XCTAssertEqual(monday3.dropped, [])

        // Week 8's long run on Monday of week 9 takes that Monday and pushes the first three sessions of
        // week 9 later; the fourth (Saturday) keeps its day.
        let long8 = try sessionIndex(plan, week: 8, weekday: 6)
        let first9 = try sessionIndex(plan, week: 9, weekday: 1)
        let second9 = try sessionIndex(plan, week: 9, weekday: 2)
        let third9 = try sessionIndex(plan, week: 9, weekday: 4)
        let result8 = base.pushingBack(missed: long8, today: base.dayOffset(long8) + 2)
        let pushed8 = PlanSchedule(plan: plan, progress: result8.progress)
        XCTAssertEqual(pushed8.dayOffset(long8), base.dayOffset(first9))
        XCTAssertEqual(result8.moved, [first9, second9, third9])
        XCTAssertEqual(result8.dropped, [])

        // Week 13 is full. The Tuesday road session is done on Thursday (Wednesday is closed, so that is the
        // first open day, whether today is Wednesday or Thursday). The Friday track session cannot sit
        // next to it and moves to Saturday, so the Thursday easy run and the Saturday long run have no day
        // left and are skipped. Nothing in week 14 or later moves.
        let road13 = try sessionIndex(plan, week: 13, weekday: 2)
        let easy13 = try sessionIndex(plan, week: 13, weekday: 4)
        let track13 = try sessionIndex(plan, week: 13, weekday: 5)
        let long13 = try sessionIndex(plan, week: 13, weekday: 6)
        for delay in [1, 2] {
            let result = base.pushingBack(missed: road13, today: base.dayOffset(road13) + delay)
            let pushed = PlanSchedule(plan: plan, progress: result.progress)
            XCTAssertEqual(pushed.dayOffset(road13), base.dayOffset(road13) + 2)
            XCTAssertEqual(pushed.dayOffset(track13), base.dayOffset(track13) + 1)
            XCTAssertEqual(result.moved, [track13])
            XCTAssertEqual(result.dropped, [easy13, long13])
            XCTAssertEqual(Set(result.progress.dayOverrides.keys),
                           [PlanProgress.key(road13), PlanProgress.key(track13)])
        }

        // Race week: Friday's track session done on Saturday skips Saturday's easy run, and on Sunday
        // (closed) it is skipped itself. The race stays on Monday either way.
        let track36 = try sessionIndex(plan, week: 36, weekday: 5)
        let easy36 = try sessionIndex(plan, week: 36, weekday: 6)
        let saturday36 = base.pushingBack(missed: track36, today: base.dayOffset(track36) + 1)
        let pushed36 = PlanSchedule(plan: plan, progress: saturday36.progress)
        XCTAssertEqual(pushed36.dayOffset(track36), base.dayOffset(easy36))
        XCTAssertEqual(saturday36.dropped, [easy36])
        XCTAssertEqual(saturday36.moved, [])
        XCTAssertEqual(pushed36.dayOffset(raceIndex), base.dayOffset(raceIndex))
        let sunday36 = base.pushingBack(missed: track36, today: base.dayOffset(track36) + 2)
        XCTAssertEqual(sunday36.dropped, [track36])
        XCTAssertEqual(sunday36.moved, [])
        XCTAssertEqual(PlanSchedule(plan: plan, progress: sunday36.progress).dayOffset(raceIndex),
                       base.dayOffset(raceIndex))
    }

    func testRaceDateAgreesWithTheStartAndTheRaceSession() throws {
        let plan = try bundledPlan()
        XCTAssertNil(PlanLaunch.raceDateMismatch(plan: plan, startYMD: plan.startDate))
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
