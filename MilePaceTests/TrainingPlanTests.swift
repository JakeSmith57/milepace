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

    /// Four Monday-to-Sunday weeks that start on a Monday (day 0). Day offsets from the start:
    /// week 1: long 0, easy 1, easy 3, track 4, easy 5.
    /// week 2: track 7, long 8, easy 10, road 12.
    /// week 3: easy 14, track 15, easy 17, easy 19.
    /// week 4: easy 21, long 24, easy 25, race 26 (so the day before the race is Friday 25).
    private static let swapJSON = """
    {
      "name": "swap",
      "startDate": "2026-10-12",
      "weeks": [
        { "week": 1, "miles": 5, "phase": 1, "recovery": false, "timeTrial": false, "race": false },
        { "week": 2, "miles": 5, "phase": 1, "recovery": false, "timeTrial": false, "race": false },
        { "week": 3, "miles": 5, "phase": 1, "recovery": false, "timeTrial": false, "race": false },
        { "week": 4, "miles": 5, "phase": 1, "recovery": false, "timeTrial": false, "race": true }
      ],
      "sessions": [
        { "week": 1, "weekday": 1, "phase": 1, "kind": "long", "miles": 4, "title": "4 mi long" },
        { "week": 1, "weekday": 2, "phase": 1, "kind": "easy", "miles": 3, "title": "3 mi easy" },
        { "week": 1, "weekday": 4, "phase": 1, "kind": "easy", "miles": 3, "title": "3 mi easy" },
        { "week": 1, "weekday": 5, "phase": 1, "kind": "track", "preset": "6x400-r", "title": "6 x 400 @ R" },
        { "week": 1, "weekday": 6, "phase": 1, "kind": "easy", "miles": 2, "title": "2 mi easy" },
        { "week": 2, "weekday": 1, "phase": 1, "kind": "track", "preset": "6x400-r", "title": "6 x 400 @ R" },
        { "week": 2, "weekday": 2, "phase": 1, "kind": "long", "miles": 5, "title": "5 mi long" },
        { "week": 2, "weekday": 4, "phase": 1, "kind": "easy", "miles": 3, "title": "3 mi easy" },
        { "week": 2, "weekday": 6, "phase": 1, "kind": "road", "preset": "x", "title": "road" },
        { "week": 3, "weekday": 1, "phase": 1, "kind": "easy", "miles": 2, "title": "2 mi easy" },
        { "week": 3, "weekday": 2, "phase": 1, "kind": "track", "preset": "6x400-r", "title": "6 x 400 @ R" },
        { "week": 3, "weekday": 4, "phase": 1, "kind": "easy", "miles": 3, "title": "3 mi easy" },
        { "week": 3, "weekday": 6, "phase": 1, "kind": "easy", "miles": 2, "title": "2 mi easy" },
        { "week": 4, "weekday": 1, "phase": 1, "kind": "easy", "miles": 2, "title": "2 mi easy" },
        { "week": 4, "weekday": 4, "phase": 1, "kind": "long", "miles": 6, "title": "6 mi long" },
        { "week": 4, "weekday": 5, "phase": 1, "kind": "easy", "miles": 2, "title": "2 mi easy" },
        { "week": 4, "weekday": 6, "phase": 1, "kind": "race", "preset": "mile-tt", "title": "race" }
      ]
    }
    """

    private func swapSchedule(_ progress: PlanProgress = PlanProgress()) throws -> PlanSchedule {
        let plan = try JSONDecoder().decode(PlanFile.self, from: Data(TrainingPlanTests.swapJSON.utf8))
        return PlanSchedule(plan: plan, progress: progress)
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

    func testDayOverridesReplaceTheBaseDay() throws {
        var progress = PlanProgress()
        progress.dayOverrides[PlanProgress.key(2)] = 9
        let plan = try schedule(progress)
        XCTAssertEqual((0..<5).map { plan.dayOffset($0) }, [1, 3, 9, 8, 12])
        XCTAssertEqual(plan.baseOffset(2), 5)
    }

    func testOldShiftsAreDecodedAndIgnored() throws {
        let old = """
        { "shifts": [ { "fromIndex": 1, "days": 3 } ], "statuses": { "0": "done" } }
        """
        let progress = try JSONDecoder().decode(PlanProgress.self, from: Data(old.utf8))
        XCTAssertEqual(progress.shifts.count, 1)
        XCTAssertEqual(progress.statuses[PlanProgress.key(0)], .done)
        XCTAssertEqual(progress.dayOverrides, [:])
        XCTAssertEqual(progress.planVersion, 1)
        let plan = try schedule(progress)
        XCTAssertEqual((0..<5).map { plan.dayOffset($0) }, [1, 3, 5, 8, 12])
    }

    func testProgressRestoreDiscardsAnotherPlanVersion() throws {
        var saved = PlanProgress(planVersion: 1)
        saved.statuses[PlanProgress.key(3)] = .done
        let data = try JSONEncoder().encode(saved)
        XCTAssertEqual(PlanProgress.restored(from: data, planVersion: 1), saved)
        XCTAssertEqual(PlanProgress.restored(from: data, planVersion: 2), PlanProgress(planVersion: 2))
        XCTAssertEqual(PlanProgress.restored(from: nil, planVersion: 2), PlanProgress(planVersion: 2))
        XCTAssertEqual(PlanProgress.restored(from: Data("nope".utf8), planVersion: 1), PlanProgress())
    }

    // MARK: Push back (swap)

    func testSwapPlanDayOffsets() throws {
        let plan = try swapSchedule()
        XCTAssertEqual((0..<17).map { plan.dayOffset($0) },
                       [0, 1, 3, 4, 5, 7, 8, 10, 12, 14, 15, 17, 19, 21, 24, 25, 26])
        XCTAssertEqual(plan.raceDayOffset, 26)
    }

    func testAKeySessionSwapsTodaysEasySession() throws {
        let plan = try swapSchedule()
        // The long run (day 0) was missed; today is Tuesday day 1 and holds a 3 mi easy run.
        let result = plan.pushingBack(missed: 0, today: 1)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(0), 1)
        XCTAssertEqual(result.replaced, 1)
        XCTAssertEqual(result.dropped, [])
        XCTAssertEqual(pushed.status(1), .skipped)
        // Nothing else moved or changed.
        XCTAssertEqual(result.progress.dayOverrides, [PlanProgress.key(0): 1])
        XCTAssertEqual(result.progress.statuses, [PlanProgress.key(1): .skipped])
        XCTAssertEqual((1..<17).map { pushed.dayOffset($0) },
                       [1, 3, 4, 5, 7, 8, 10, 12, 14, 15, 17, 19, 21, 24, 25, 26])
        XCTAssertEqual(pushed.todays(today: 1), [0])
    }

    func testAnEmptyDayTakesTheMissedSessionWithoutReplacingAnything() throws {
        // The road session (day 12) is skipped, so Friday day 11 holds nothing and has no hard
        // neighbour left for the missed track session (day 7).
        let plan = try swapSchedule(try swapSchedule().skipping(8))
        let result = plan.pushingBack(missed: 5, today: 11)
        XCTAssertEqual(try swapSchedule(result.progress).dayOffset(5), 11)
        XCTAssertNil(result.replaced)
        XCTAssertEqual(result.dropped, [])
        XCTAssertEqual(result.progress.statuses, [PlanProgress.key(8): .skipped])
    }

    func testWhenTodayHoldsAWorkoutItLandsOnTheNextEasyDayThisWeek() throws {
        let plan = try swapSchedule()
        // The track session (Monday day 7) was missed. Today, Tuesday day 8, holds a long run, Wednesday
        // is closed, so it replaces Thursday's 3 mi easy run on day 10.
        let result = plan.pushingBack(missed: 5, today: 8)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(5), 10)
        XCTAssertEqual(result.replaced, 7)
        XCTAssertEqual(pushed.status(7), .skipped)
        XCTAssertNil(pushed.status(6))
        XCTAssertEqual(pushed.dayOffset(6), 8)
        XCTAssertEqual(result.progress.dayOverrides, [PlanProgress.key(5): 10])
    }

    func testWednesdaysAreSkipped() throws {
        let plan = try swapSchedule()
        // Wednesday day 2 holds nothing, but sessions never go there: the long run lands on Thursday.
        let result = plan.pushingBack(missed: 0, today: 2)
        XCTAssertEqual(try swapSchedule(result.progress).dayOffset(0), 3)
        XCTAssertEqual(result.replaced, 2)
    }

    func testLongRunsIgnoreTheHardSessionRule() throws {
        let plan = try swapSchedule()
        // Thursday day 3 is the day before the track session (day 4); a long run may still go there.
        let result = plan.pushingBack(missed: 0, today: 3)
        XCTAssertEqual(try swapSchedule(result.progress).dayOffset(0), 3)
        XCTAssertEqual(result.replaced, 2)
    }

    func testHardSessionsStayOffNeighbouringDays() throws {
        let plan = try swapSchedule()
        // The road session (Saturday day 12) was missed; today is Monday day 14. Monday is next to
        // Tuesday's track session and Tuesday holds it, Wednesday is closed, so it goes to Thursday.
        let result = plan.pushingBack(missed: 8, today: 14)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(8), 17)
        XCTAssertEqual(result.replaced, 11)
        XCTAssertNil(pushed.status(9))

        // With Tuesday's track session skipped nothing is in the way of Monday any more.
        let freed = try swapSchedule(plan.skipping(10))
        let early = freed.pushingBack(missed: 8, today: 14)
        XCTAssertEqual(try swapSchedule(early.progress).dayOffset(8), 14)
        XCTAssertEqual(early.replaced, 9)
    }

    func testNoRoomSkipsTheMissedSession() throws {
        let plan = try swapSchedule()
        // The track session (day 7) was missed; today is Friday day 11. Friday is next to Saturday's
        // road session, Saturday holds it, and Sunday is closed.
        let result = plan.pushingBack(missed: 5, today: 11)
        XCTAssertEqual(result.dropped, [5])
        XCTAssertNil(result.replaced)
        XCTAssertEqual(result.progress.statuses, [PlanProgress.key(5): .skipped])
        XCTAssertEqual(result.progress.dayOverrides, [:])
        XCTAssertNil(try swapSchedule(result.progress).status(8))
    }

    func testItNeverCrossesIntoTheNextCalendarWeek() throws {
        let plan = try swapSchedule()
        // The road session (Saturday day 12) was missed and today is Sunday day 13. Monday day 14 holds
        // an easy run, but that is next week.
        let result = plan.pushingBack(missed: 8, today: 13)
        XCTAssertEqual(result.dropped, [8])
        XCTAssertNil(result.replaced)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.status(8), .skipped)
        XCTAssertNil(pushed.status(9))
        XCTAssertEqual(pushed.dayOffset(9), 14)
    }

    func testTheRaceAndTheDayBeforeItAreNeverUsed() throws {
        let plan = try swapSchedule()
        // The long run (Thursday day 24) was missed; today is Friday day 25, the day before the race.
        // Friday's easy run, the race on Saturday and Sunday are all off limits.
        let result = plan.pushingBack(missed: 14, today: 25)
        XCTAssertEqual(result.dropped, [14])
        XCTAssertNil(result.replaced)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.status(14), .skipped)
        XCTAssertNil(pushed.status(15))
        XCTAssertNil(pushed.status(16))
        XCTAssertEqual(pushed.dayOffset(16), 26)
        XCTAssertEqual(result.progress.dayOverrides, [:])
    }

    func testFinishedSessionsAreNeverTouched() throws {
        // Today's easy run (day 1) is already done, so the long run goes to Thursday instead.
        let plan = try swapSchedule(try swapSchedule().markingDone(1))
        let result = plan.pushingBack(missed: 0, today: 1)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(0), 3)
        XCTAssertEqual(result.replaced, 2)
        XCTAssertEqual(pushed.status(1), .done)
        XCTAssertEqual(pushed.dayOffset(1), 1)
    }

    func testPushingBackLeavesEasyRaceAndUnmissedSessionsAlone() throws {
        let plan = try swapSchedule()
        let unchanged = PushBackResult(progress: plan.progress, replaced: nil, dropped: [])
        // An easy session is never moved.
        XCTAssertEqual(plan.pushingBack(missed: 1, today: 2), unchanged)
        // The race never moves.
        XCTAssertEqual(plan.pushingBack(missed: 16, today: 27), unchanged)
        // Not missed yet, or not a session.
        XCTAssertEqual(plan.pushingBack(missed: 0, today: 0), unchanged)
        XCTAssertEqual(plan.pushingBack(missed: 99, today: 9), unchanged)
        // Already finished.
        let done = try swapSchedule(plan.markingDone(0))
        XCTAssertEqual(done.pushingBack(missed: 0, today: 1).progress, done.progress)
    }

    func testAMovedSessionCanBePushedAgainWithinTheWeek() throws {
        let plan = try swapSchedule()
        let first = plan.pushingBack(missed: 0, today: 1)
        // Day 1 passes without the run; on Thursday it is missed again and takes the easy run there.
        let again = try swapSchedule(first.progress)
        XCTAssertEqual(again.firstMissed(today: 2), 0)
        let second = again.pushingBack(missed: 0, today: 3)
        XCTAssertEqual(try swapSchedule(second.progress).dayOffset(0), 3)
        XCTAssertEqual(second.replaced, 2)
    }

    func testPushTexts() {
        XCTAssertEqual(PlanText.moveTitle(day: 5, today: 5, label: "sat oct 17"), "do it today")
        XCTAssertEqual(PlanText.moveTitle(day: 9, today: 7, label: "wed oct 21"), "move to wed oct 21")
        XCTAssertEqual(PlanText.replacesNote(dayLabel: "thu oct 22", title: "3 mi easy"), "replaces thu 3 mi easy.")
        XCTAssertEqual(PlanText.noRoomNote, "no room this week. it'll be skipped.")
    }

    // MARK: Missed, today, next

    func testFirstMissedIgnoresStatusedAndFutureSessions() throws {
        let plan = try schedule()
        XCTAssertNil(plan.firstMissed(today: 0))
        XCTAssertNil(plan.firstMissed(today: 1))
        // Session 0 (day 1) is an easy run and is never offered. Session 1 (track, day 3) is.
        XCTAssertNil(plan.firstMissed(today: 2))
        XCTAssertNil(plan.firstMissed(today: 3))
        XCTAssertEqual(plan.firstMissed(today: 4), 1)
        XCTAssertEqual(plan.firstMissed(today: 5), 1)

        let afterDone = try schedule(plan.markingDone(1))
        XCTAssertNil(afterDone.firstMissed(today: 4))
        XCTAssertEqual(afterDone.firstMissed(today: 6), 2)

        let afterSkip = try schedule(afterDone.skipping(2))
        XCTAssertNil(afterSkip.firstMissed(today: 6))
    }

    func testFirstMissedOnlyLooksAtTheLastTwoDays() throws {
        let plan = try schedule()
        // Sessions are on days 1, 3, 5, 8 and 12.
        XCTAssertEqual(plan.firstMissed(today: 7), 2)
        XCTAssertEqual(plan.firstMissed(today: 9), 3)
        XCTAssertEqual(plan.firstMissed(today: 10), 3)
        XCTAssertNil(plan.firstMissed(today: 11))
    }

    func testMissedEasySessionsAreNeverOfferedAndSkippedTheNextDay() throws {
        let plan = try schedule()
        // Session 0 is a 2 mi easy run on day 1.
        XCTAssertNil(plan.firstMissed(today: 2))
        XCTAssertNil(try schedule(plan.skippingOld(today: 1)).status(0))
        XCTAssertEqual(try schedule(plan.skippingOld(today: 2)).status(0), .skipped)
        let reconciled = try schedule(plan.reconciled(activities: [], today: 2))
        XCTAssertEqual(reconciled.status(0), .skipped)
        XCTAssertNil(reconciled.status(1))
        // A matching run still counts on the day itself and afterwards.
        let run = ActivityDay(day: 1, kind: .run(miles: 2, workoutName: nil))
        XCTAssertEqual(try schedule(plan.reconciled(activities: [run], today: 2)).status(0), .done)
        // Pushing back an easy session does nothing.
        XCTAssertEqual(plan.pushingBack(missed: 0, today: 2).progress, plan.progress)
    }

    func testKeySessionsStayOnOfferForTwoDays() throws {
        let plan = try schedule()
        // Session 1 (track) is on day 3.
        XCTAssertNil(try schedule(plan.skippingOld(today: 5)).status(1))
        XCTAssertEqual(try schedule(plan.skippingOld(today: 6)).status(1), .skipped)
    }

    func testOldMissesAreSkippedOnReconcile() throws {
        let plan = try schedule()
        let skipped = try schedule(plan.skippingOld(today: 5))
        XCTAssertEqual(skipped.status(0), .skipped)
        XCTAssertNil(skipped.status(1))
        XCTAssertNil(skipped.status(2))

        let reconciled = try schedule(plan.reconciled(activities: [], today: 9))
        XCTAssertEqual((0..<5).map { reconciled.status($0) },
                       [.skipped, .skipped, .skipped, nil, nil])
        XCTAssertNil(try schedule(plan.reconciled(activities: [], today: 0)).status(0))
    }

    func testReconcileMatchesActivitiesBeforeSkippingOldSessions() throws {
        let plan = try schedule()
        let run = ActivityDay(day: 1, kind: .run(miles: 2, workoutName: nil))
        let result = try schedule(plan.reconciled(activities: [run], today: 9))
        XCTAssertEqual(result.status(0), .done)
        XCTAssertEqual(result.status(1), .skipped)
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

    private func runActivity(_ day: Int, miles: Double, name: String? = nil) -> ActivityDay {
        return ActivityDay(day: day, kind: .run(miles: miles, workoutName: name))
    }

    private func trackActivity(_ day: Int, preset: String = "6 \u{00D7} 400 @ R") -> ActivityDay {
        return ActivityDay(day: day, kind: .track(presetName: preset))
    }

    func testReconciledMarksOnlySessionsThatMatchAnActivityOnTheirDay() throws {
        let plan = try schedule()
        let result = try schedule(plan.reconciled(activities: [runActivity(1, miles: 2), runActivity(2, miles: 5), runActivity(5, miles: 3)]))
        XCTAssertEqual(result.status(0), .done)
        XCTAssertNil(result.status(1))
        XCTAssertEqual(result.status(2), .done)
        XCTAssertNil(result.status(3))
    }

    func testReconciledNeverTouchesRestDays() throws {
        let plan = try schedule()
        let restDays = [0, 2, 4, 6, 7].map { runActivity($0, miles: 6) }
        XCTAssertEqual(plan.reconciled(activities: restDays), PlanProgress())
        XCTAssertEqual(plan.reconciled(activities: []), PlanProgress())
    }

    func testReconciledKeepsSkippedSessions() throws {
        let skipped = try schedule(try schedule().skipping(2))
        let result = try schedule(skipped.reconciled(activities: [runActivity(5, miles: 3)]))
        XCTAssertEqual(result.status(2), .skipped)
    }

    func testEasyAndLongRunsNeedHalfTheMiles() throws {
        let plan = try schedule()
        // Session 0 is 2 mi easy, session 2 is 3 mi long.
        XCTAssertNil(try schedule(plan.reconciled(activities: [runActivity(1, miles: 0.9)])).status(0))
        XCTAssertEqual(try schedule(plan.reconciled(activities: [runActivity(1, miles: 1.0)])).status(0), .done)
        XCTAssertNil(try schedule(plan.reconciled(activities: [runActivity(5, miles: 1.4)])).status(2))
        XCTAssertEqual(try schedule(plan.reconciled(activities: [runActivity(5, miles: 1.5)])).status(2), .done)
        // A guided workout run is not an easy run.
        XCTAssertNil(try schedule(plan.reconciled(activities: [runActivity(1, miles: 4, name: "20 min tempo")])).status(0))
    }

    func testRoadSessionsNeedTheirWorkoutName() throws {
        let road = PlanSession(week: 1, weekday: 2, phase: 1, kind: .road, title: "t",
                               miles: nil, preset: "3 \u{00D7} 5 min threshold", note: nil)
        XCTAssertTrue(PlanSchedule.matches(.run(miles: 3, workoutName: "3 \u{00D7} 5 min threshold"), session: road))
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 3, workoutName: "20 min tempo"), session: road))
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 3, workoutName: nil), session: road))
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 3, workoutName: ""), session: road))
        XCTAssertFalse(PlanSchedule.matches(.track(presetName: "3 \u{00D7} 5 min threshold"), session: road))
    }

    func testTrackSessionsNeedATrackWorkout() throws {
        let plan = try schedule()
        // Session 1 is a track session on day 3.
        XCTAssertNil(try schedule(plan.reconciled(activities: [runActivity(3, miles: 6)])).status(1))
        XCTAssertEqual(try schedule(plan.reconciled(activities: [trackActivity(3, preset: "anything")])).status(1), .done)
        // Race day accepts any track workout; a time trial needs the mile time trial.
        let race = PlanSession(week: 2, weekday: 6, phase: 1, kind: .race, title: "r",
                               miles: nil, preset: "mile-tt", note: nil)
        let trial = PlanSession(week: 2, weekday: 6, phase: 1, kind: .timeTrial, title: "t",
                                miles: nil, preset: "mile-tt", note: nil)
        XCTAssertTrue(PlanSchedule.matches(.track(presetName: "Custom workout"), session: race))
        XCTAssertFalse(PlanSchedule.matches(.track(presetName: "Custom workout"), session: trial))
        XCTAssertTrue(PlanSchedule.matches(.track(presetName: "Mile time trial"), session: trial))
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 1, workoutName: nil), session: trial))
    }

    func testOneActivityCannotSatisfyTwoSessions() throws {
        // Put the long run on the same day as the easy run.
        var progress = PlanProgress()
        progress.dayOverrides[PlanProgress.key(2)] = 1
        let plan = try schedule(progress)
        let one = try schedule(plan.reconciled(activities: [runActivity(1, miles: 3)]))
        XCTAssertEqual(one.status(0), .done)
        XCTAssertNil(one.status(2))
        let two = try schedule(plan.reconciled(activities: [runActivity(1, miles: 3), runActivity(1, miles: 2)]))
        XCTAssertEqual(two.status(0), .done)
        XCTAssertEqual(two.status(2), .done)
    }

    func testActivitiesStartingBeforeThreeInTheMorningCountForThePreviousDay() throws {
        let calendar = newYork()
        let start = try XCTUnwrap(PlanCalendar.parse("2026-10-12", calendar: calendar))
        func at(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            var parts = DateComponents()
            parts.year = 2026
            parts.month = 10
            parts.day = day
            parts.hour = hour
            parts.minute = minute
            return try XCTUnwrap(calendar.date(from: parts))
        }
        XCTAssertEqual(PlanCalendar.activityDay(of: try at(13, 0, 30), start: start, calendar: calendar), 0)
        XCTAssertEqual(PlanCalendar.activityDay(of: try at(13, 2, 59), start: start, calendar: calendar), 0)
        XCTAssertEqual(PlanCalendar.activityDay(of: try at(13, 3, 0), start: start, calendar: calendar), 1)
        XCTAssertEqual(PlanCalendar.activityDay(of: try at(13, 23, 59), start: start, calendar: calendar), 1)

        let runs = [LoggedRun(date: try at(13, 0, 30), meters: 3000, workoutName: "")]
        let days = PlanActivities.days(runs: runs, workouts: [], start: start, calendar: calendar)
        XCTAssertEqual(days.map { $0.day }, [0])
    }

    // MARK: Weekly miles

    func testWeekMilesUseTheCalendarWeekAndEstimateTrackWorkouts() throws {
        let calendar = newYork()
        let start = try XCTUnwrap(PlanCalendar.parse("2026-10-12", calendar: calendar))
        func noon(_ day: Int) -> Date {
            let date = PlanCalendar.date(forOffset: day, start: start, calendar: calendar)
            return date.addingTimeInterval(12 * 3600)
        }
        let runs = [LoggedRun(date: noon(1), meters: 3 * metersPerMile, workoutName: ""),
                    LoggedRun(date: noon(8), meters: 4 * metersPerMile, workoutName: "")]
        // 6 x 400 m = 2400 m of reps, plus 2 mi of warm-up and cool-down.
        let workouts = [LoggedWorkout(date: noon(3), name: "6 \u{00D7} 400 @ R", repMeters: 2400)]
        let miles = PlanActivities.milesByDay(runs: runs, workouts: workouts, start: start, calendar: calendar)
        XCTAssertEqual(miles[1] ?? 0, 3.0, accuracy: 0.001)
        XCTAssertEqual(miles[3] ?? 0, 2400 / 1609.344 + 2.0, accuracy: 0.001)

        let plan = try schedule()
        let first = plan.weekMiles(containing: 4, milesByDay: miles)
        XCTAssertEqual(first.planWeek?.week, 1)
        XCTAssertEqual(first.planWeek?.miles, 5)
        XCTAssertEqual(first.logged, 3.0 + 2400 / 1609.344 + 2.0, accuracy: 0.001)
        let second = plan.weekMiles(containing: 12, milesByDay: miles)
        XCTAssertEqual(second.planWeek?.week, 2)
        XCTAssertEqual(second.logged, 4.0, accuracy: 0.001)
    }

    func testPlannedMilesComeFromThePlanWeekMostSessionsBelongTo() throws {
        // Slip week 1's three sessions into the calendar week of days 7...13 (days 7, 9 and 11).
        var progress = PlanProgress()
        progress.dayOverrides[PlanProgress.key(0)] = 7
        progress.dayOverrides[PlanProgress.key(1)] = 9
        progress.dayOverrides[PlanProgress.key(2)] = 11
        let plan = try schedule(progress)
        // That week now holds three week-1 sessions and two week-2 sessions (days 8 and 12).
        XCTAssertEqual(plan.plannedWeek(inCalendarWeekStarting: 7)?.week, 1)
        XCTAssertNil(plan.plannedWeek(inCalendarWeekStarting: 0))
        XCTAssertNil(plan.plannedWeek(inCalendarWeekStarting: 21))
        XCTAssertEqual(plan.calendarWeekStart(containing: 12), 7)
        XCTAssertEqual(plan.calendarWeekStart(containing: 7), 7)
        XCTAssertEqual(plan.calendarWeekStart(containing: 6), 0)
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

        // Weeks are Monday-to-Sunday around each week's first session.
        var progress = PlanProgress()
        progress.dayOverrides[PlanProgress.key(3)] = 10
        let moved = try schedule(progress)
        XCTAssertEqual(moved.startOffset(ofWeek: 1), 0)
        XCTAssertEqual(moved.startOffset(ofWeek: 2), 7)
        progress.dayOverrides[PlanProgress.key(3)] = 15
        XCTAssertEqual(try schedule(progress).startOffset(ofWeek: 2), 14)
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
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[1]), .track(presetId: "6x400-r", targetSeconds: nil))
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[2]), .freeRun(zone: .easy))
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[3]), .freeRun(zone: .off))
        XCTAssertEqual(PlanRoute.route(for: plan.sessions[4]), .track(presetId: "mile-tt", targetSeconds: nil))

        let road = PlanSession(week: 1, weekday: 1, phase: 1, kind: .road, title: "t",
                               miles: nil, preset: "3 \u{00D7} 5 min threshold", note: nil)
        XCTAssertEqual(PlanRoute.route(for: road), .roadWorkout(name: "3 \u{00D7} 5 min threshold"))
        let bare = PlanSession(week: 1, weekday: 1, phase: 1, kind: .road, title: "t",
                               miles: nil, preset: nil, note: nil)
        XCTAssertEqual(PlanRoute.route(for: bare), .freeRun(zone: .threshold))
    }

    func testRoutesCarryTheSessionsTargetTime() throws {
        let trial = PlanSession(week: 1, weekday: 6, phase: 1, kind: .timeTrial, title: "t",
                                miles: nil, preset: "mile-tt", note: nil, targetSeconds: 395)
        XCTAssertEqual(PlanRoute.route(for: trial), .track(presetId: "mile-tt", targetSeconds: 395))
    }

    func testDecodesVersionRaceDateAndTargetSeconds() throws {
        let plain = try miniPlan()
        XCTAssertEqual(plain.version, 1)
        XCTAssertNil(plain.raceDate)
        XCTAssertNil(plain.sessions[4].targetSeconds)

        let json = """
        {
          "name": "v2",
          "version": 2,
          "startDate": "2026-10-12",
          "raceDate": "2027-06-21",
          "weeks": [],
          "sessions": [
            { "week": 1, "weekday": 6, "phase": 1, "kind": "timeTrial", "preset": "mile-tt", "title": "tt", "targetSeconds": 395 }
          ]
        }
        """
        let plan = try JSONDecoder().decode(PlanFile.self, from: Data(json.utf8))
        XCTAssertEqual(plan.version, 2)
        XCTAssertEqual(plan.raceDate, "2027-06-21")
        XCTAssertEqual(plan.sessions[0].targetSeconds, 395)
        let again = try JSONDecoder().decode(PlanFile.self, from: try JSONEncoder().encode(plan))
        XCTAssertEqual(again, plan)
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

    func testMondayWeekdayNumbers() throws {
        let calendar = newYork()
        let monday = try XCTUnwrap(PlanCalendar.parse("2026-10-12", calendar: calendar))
        XCTAssertEqual(PlanCalendar.mondayWeekday(of: monday, calendar: calendar), 1)
        let wednesday = PlanCalendar.date(forOffset: 2, start: monday, calendar: calendar)
        XCTAssertEqual(PlanCalendar.mondayWeekday(of: wednesday, calendar: calendar), 3)
        let sunday = PlanCalendar.date(forOffset: 6, start: monday, calendar: calendar)
        XCTAssertEqual(PlanCalendar.mondayWeekday(of: sunday, calendar: calendar), 7)

        // A plan that starts on a Wednesday has its Monday two days later.
        let plan = PlanSchedule(plan: try miniPlan(), progress: PlanProgress(), startWeekday: 3)
        XCTAssertEqual(plan.weekdayNumber(ofDay: 0), 3)
        XCTAssertEqual(plan.weekdayNumber(ofDay: 5), 1)
        XCTAssertEqual(plan.weekdayNumber(ofDay: -1), 2)
        XCTAssertEqual(plan.calendarWeekStart(containing: 7), 5)
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
