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
        XCTAssertEqual(progress.autoDone, [])
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

    // MARK: Push back (contained in the current week)

    func testSwapPlanDayOffsets() throws {
        let plan = try swapSchedule()
        XCTAssertEqual((0..<17).map { plan.dayOffset($0) },
                       [0, 1, 3, 4, 5, 7, 8, 10, 12, 14, 15, 17, 19, 21, 24, 25, 26])
        XCTAssertEqual(plan.raceDayOffset, 26)
    }

    func testAMissedSessionTakesTodayAndTheRestOfTheWeekIsPlacedAgain() throws {
        let plan = try swapSchedule()
        // The long run (Monday day 0) was missed; today is Tuesday day 1. It takes today. The easy run that
        // was on Tuesday moves to Thursday (Wednesday is closed), Thursday's easy run to Friday and Friday's
        // track session to Saturday. Saturday's easy run has no day left (Sunday is closed) and is skipped.
        let result = plan.pushingBack(missed: 0, today: 1)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(result.moved, [1, 2, 3])
        XCTAssertEqual(result.dropped, [4])
        XCTAssertEqual((0..<5).map { pushed.dayOffset($0) }, [1, 3, 4, 5, 5])
        XCTAssertEqual(result.progress.dayOverrides,
                       [PlanProgress.key(0): 1, PlanProgress.key(1): 3, PlanProgress.key(2): 4, PlanProgress.key(3): 5])
        XCTAssertEqual(result.progress.statuses, [PlanProgress.key(4): .skipped])
        XCTAssertEqual(pushed.todays(today: 1), [0])
        // Every later week is where the plan put it.
        XCTAssertEqual((5..<17).map { pushed.dayOffset($0) }, (5..<17).map { plan.dayOffset($0) })
    }

    func testSessionsKeepTheirDayWhenTheyStillFit() throws {
        let plan = try swapSchedule()
        // The week 2 track session (Monday day 7) was missed; today is Tuesday day 8. The long run moves to
        // Thursday and the easy run to Friday; the road session keeps its Saturday.
        let result = plan.pushingBack(missed: 5, today: 8)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual((5..<9).map { pushed.dayOffset($0) }, [8, 10, 11, 12])
        XCTAssertEqual(result.moved, [6, 7])
        XCTAssertEqual(result.dropped, [])
        XCTAssertEqual(result.progress.dayOverrides,
                       [PlanProgress.key(5): 8, PlanProgress.key(6): 10, PlanProgress.key(7): 11])
        XCTAssertEqual(result.progress.statuses, [:])
    }

    func testAMissedSessionOnAClosedDayTakesTheNextOpenOneAndEarlierSessionsStay() throws {
        let plan = try swapSchedule()
        // Same track session, but today is Wednesday day 9: it takes Thursday and the easy run behind it
        // moves to Friday. The long run on Tuesday (day 8) is before today and is not touched.
        let result = plan.pushingBack(missed: 5, today: 9)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(5), 10)
        XCTAssertEqual(pushed.dayOffset(6), 8)
        XCTAssertNil(pushed.status(6))
        XCTAssertEqual(pushed.dayOffset(7), 11)
        XCTAssertEqual(pushed.dayOffset(8), 12)
        XCTAssertEqual(result.moved, [7])
        XCTAssertEqual(result.dropped, [])
        XCTAssertEqual(result.progress.dayOverrides, [PlanProgress.key(5): 10, PlanProgress.key(7): 11])
    }

    func testNothingOutsideTheCurrentCalendarWeekMoves() throws {
        let plan = try swapSchedule()
        // (missed, today); (4, 7) is Saturday's easy run done on the Monday of the next week.
        for (missed, today) in [(0, 1), (4, 7), (5, 8), (8, 14), (9, 16), (12, 21), (13, 24)] {
            let result = plan.pushingBack(missed: missed, today: today)
            let pushed = try swapSchedule(result.progress)
            let monday = plan.calendarWeekStart(containing: today)
            for index in 0..<17 {
                let label = "missed \(missed) today \(today) session \(index)"
                if index == missed || result.moved.contains(index) {
                    XCTAssertGreaterThanOrEqual(pushed.dayOffset(index), today, label)
                    XCTAssertLessThanOrEqual(pushed.dayOffset(index), monday + 6, label)
                } else {
                    XCTAssertEqual(pushed.dayOffset(index), plan.dayOffset(index), label)
                }
            }
            // Only the missed session and the moved ones carry an override.
            let touched = Set(([missed] + result.moved).map { PlanProgress.key($0) })
            XCTAssertTrue(Set(result.progress.dayOverrides.keys).isSubset(of: touched), "missed \(missed) today \(today)")
        }
    }

    func testSessionsNeverLandOnWednesdaysOrSundays() throws {
        let plan = try swapSchedule()
        for missed in 0..<16 {
            for delay in [1, 2] {
                let pushed = try swapSchedule(plan.pushingBack(missed: missed, today: plan.dayOffset(missed) + delay).progress)
                for index in 0..<17 {
                    let weekday = pushed.weekdayNumber(ofDay: pushed.dayOffset(index))
                    XCTAssertNotEqual(weekday, 3, "missed \(missed) delay \(delay) session \(index)")
                    XCTAssertNotEqual(weekday, 7, "missed \(missed) delay \(delay) session \(index)")
                }
            }
        }
        // Wednesday day 2 is closed, so the missed session takes Thursday.
        let thursday = try swapSchedule(plan.pushingBack(missed: 0, today: 2).progress)
        XCTAssertEqual(thursday.dayOffset(0), 3)
    }

    func testEasyAndLongSessionsCanBePushedToo() throws {
        let plan = try swapSchedule()
        let result = plan.pushingBack(missed: 1, today: 2)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(1), 3)
        XCTAssertEqual(pushed.dayOffset(2), 4)
        XCTAssertEqual(pushed.dayOffset(3), 5)
        XCTAssertEqual(result.moved, [2, 3])
    }

    func testHardSessionsNeverEndUpOnNeighbouringDays() throws {
        let plan = try swapSchedule(try swapSchedule().skipping(9))
        // The road session (Saturday day 12) was missed and Sunday is closed, so it takes Monday day 14.
        // Tuesday's track session (day 15) is next to it, so it moves to Thursday day 17; the easy run
        // that was there moves to Friday and the Saturday easy run stays.
        let result = plan.pushingBack(missed: 8, today: 14)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(8), 14)
        XCTAssertEqual(pushed.dayOffset(10), 17)
        XCTAssertEqual(pushed.dayOffset(11), 18)
        XCTAssertEqual(pushed.dayOffset(12), 19)
        XCTAssertEqual(result.moved, [10, 11])
        XCTAssertEqual(result.dropped, [])
        XCTAssertEqual(result.progress.statuses, [PlanProgress.key(9): .skipped])
    }

    func testEasyRunsMayFollowAHardSession() throws {
        let plan = try swapSchedule()
        // Same miss, but Monday's easy run (day 14) is still there: it moves to Tuesday behind the road
        // session, the track session goes to Thursday and the easy run behind it to Friday.
        let result = plan.pushingBack(missed: 8, today: 14)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual((8..<13).map { pushed.dayOffset($0) }, [14, 15, 17, 18, 19])
        XCTAssertEqual(result.moved, [9, 10, 11])
        XCTAssertEqual(result.dropped, [])
    }

    func testNoTwoSessionsShareADayAndHardOnesStayApartAfterAnyPush() throws {
        let plan = try swapSchedule()
        for missed in 0..<16 {
            for delay in [1, 2] {
                let label = "missed \(missed) delay \(delay)"
                let pushed = try swapSchedule(plan.pushingBack(missed: missed, today: plan.dayOffset(missed) + delay).progress)
                let open = (0..<17).filter { pushed.status($0) == nil }
                let days = open.map { pushed.dayOffset($0) }
                XCTAssertEqual(Set(days).count, days.count, label)
                // The race counts as a hard session here.
                let hardDays = open
                    .filter { PlanSchedule.isHard(pushed.plan.sessions[$0].kind) }
                    .map { pushed.dayOffset($0) }
                    .sorted()
                for pair in zip(hardDays, hardDays.dropFirst()) {
                    XCTAssertGreaterThan(pair.1 - pair.0, 1, label)
                }
            }
        }
    }

    func testTheRaceCountsAsAHardSessionAndTheDaysAroundItAreNotUsed() throws {
        XCTAssertTrue(PlanSchedule.isHard(.race))
        XCTAssertTrue(PlanSchedule.isHard(.timeTrial))
        XCTAssertFalse(PlanSchedule.isHard(.long))
        let plan = try swapSchedule()
        // The long run (Thursday day 24) was missed; today is Friday day 25, the day before the race. It
        // takes today; the easy run that was there has no day left before the race and is skipped.
        let result = plan.pushingBack(missed: 14, today: 25)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(14), 25)
        XCTAssertEqual(result.moved, [])
        XCTAssertEqual(result.dropped, [15])
        XCTAssertEqual(pushed.status(15), .skipped)
        XCTAssertEqual(pushed.dayOffset(16), 26)
        XCTAssertNil(pushed.status(16))
        // On the race day itself, or later, nothing is left to place.
        let late = plan.pushingBack(missed: 15, today: 26)
        XCTAssertEqual(late.dropped, [15])
        XCTAssertEqual(late.moved, [])
        XCTAssertEqual(late.progress.dayOverrides, [:])
    }

    func testFinishedSessionsAreNeverTouched() throws {
        // Tuesday's easy run (day 1) is already done: the long run cannot take that day and goes to Thursday,
        // and the sessions behind it each move one day. Saturday's easy run is skipped.
        let plan = try swapSchedule(try swapSchedule().markingDone(1))
        let result = plan.pushingBack(missed: 0, today: 1)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(0), 3)
        XCTAssertEqual(pushed.dayOffset(2), 4)
        XCTAssertEqual(pushed.dayOffset(3), 5)
        XCTAssertEqual(pushed.status(1), .done)
        XCTAssertEqual(pushed.dayOffset(1), 1)
        XCTAssertEqual(result.moved, [2, 3])
        XCTAssertEqual(result.dropped, [4])
        XCTAssertEqual(result.progress.statuses, [PlanProgress.key(1): .done, PlanProgress.key(4): .skipped])
    }

    func testAHardSessionAvoidsTheDaysNextToAFinishedHardSession() throws {
        // The track session on day 15 is done. The missed road session may not take day 14 or 16 beside it,
        // so it takes Thursday day 17; the easy runs behind it follow and the last one is skipped.
        let plan = try swapSchedule(try swapSchedule().markingDone(10))
        let result = plan.pushingBack(missed: 8, today: 14)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(8), 17)
        XCTAssertEqual(pushed.dayOffset(9), 18)
        XCTAssertEqual(pushed.dayOffset(11), 19)
        XCTAssertEqual(pushed.dayOffset(10), 15)
        XCTAssertEqual(pushed.status(10), .done)
        XCTAssertEqual(result.moved, [9, 11])
        XCTAssertEqual(result.dropped, [12])
    }

    func testPriorityDecidesWhatIsSkippedAndTheLaterOfTwoEqualsGoesFirst() throws {
        XCTAssertGreaterThan(PlanSchedule.priority(.timeTrial), PlanSchedule.priority(.track))
        XCTAssertEqual(PlanSchedule.priority(.timeTrial), PlanSchedule.priority(.race))
        XCTAssertGreaterThan(PlanSchedule.priority(.track), PlanSchedule.priority(.road))
        XCTAssertGreaterThan(PlanSchedule.priority(.road), PlanSchedule.priority(.long))
        XCTAssertGreaterThan(PlanSchedule.priority(.long), PlanSchedule.priority(.easy))
        let plan = try swapSchedule()
        // Monday's easy run (day 21) is done on Thursday day 24. The long run that was there moves to
        // Friday; the easy run on Friday would have to reach the race day, and it is the later of the two
        // easy runs, so it is the one skipped.
        let result = plan.pushingBack(missed: 13, today: 24)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(pushed.dayOffset(13), 24)
        XCTAssertEqual(pushed.dayOffset(14), 25)
        XCTAssertEqual(result.moved, [14])
        XCTAssertEqual(result.dropped, [15])
        XCTAssertEqual(pushed.status(15), .skipped)
        XCTAssertNil(pushed.status(13))
        XCTAssertNil(pushed.status(14))
        XCTAssertEqual(pushed.dayOffset(16), 26)
    }

    func testAMissedEasyRunIsSkippedBeforeTheRoadSessionIsMoved() throws {
        let plan = try swapSchedule()
        // The easy run (Thursday day 10) was missed and today is Saturday day 12, where the road session
        // is. Only one of them fits (Sunday is closed): the easy run goes.
        let result = plan.pushingBack(missed: 7, today: 12)
        XCTAssertEqual(result.dropped, [7])
        XCTAssertEqual(result.moved, [])
        XCTAssertEqual(result.progress.statuses, [PlanProgress.key(7): .skipped])
        XCTAssertEqual(result.progress.dayOverrides, [:])
    }

    func testALongRunIsSkippedBeforeATrackSession() throws {
        // Week 1's easy runs are done on Tuesday, Thursday and Saturday. The long run (Monday) was missed
        // and today is Tuesday: Tuesday is taken, Wednesday is closed, Thursday is taken, so it could
        // only take Friday, which holds the track session. The track session outranks it and keeps Friday.
        var plan = try swapSchedule()
        for index in [1, 2, 4] {
            plan = try swapSchedule(plan.markingDone(index))
        }
        let result = plan.pushingBack(missed: 0, today: 1)
        let pushed = try swapSchedule(result.progress)
        XCTAssertEqual(result.dropped, [0])
        XCTAssertEqual(result.moved, [])
        XCTAssertEqual(pushed.status(0), .skipped)
        XCTAssertNil(pushed.status(3))
        XCTAssertEqual(pushed.dayOffset(3), 4)
        XCTAssertEqual(result.progress.dayOverrides, [:])
    }

    func testTheMissedSessionAloneIsSkippedWhenItFindsNoDayAndTheWeekStaysAsItIs() throws {
        let plan = try swapSchedule()
        // Saturday's easy run (day 5) was missed and today is Sunday day 6, which is closed.
        let sunday = plan.pushingBack(missed: 4, today: 6)
        XCTAssertEqual(sunday.dropped, [4])
        XCTAssertEqual(sunday.moved, [])
        XCTAssertEqual(sunday.progress.statuses, [PlanProgress.key(4): .skipped])
        XCTAssertEqual(sunday.progress.dayOverrides, [:])

        // The road session (Saturday day 12) is done. The week 2 track session (Monday day 7) was missed and
        // today is Friday day 11, next to the finished road session, with Saturday taken and Sunday closed.
        // The easy run that sits on Friday must not be dropped just because the track session has no room.
        var progress = try swapSchedule().markingDone(8)
        progress.dayOverrides[PlanProgress.key(7)] = 11
        let crowded = try swapSchedule(progress)
        let result = crowded.pushingBack(missed: 5, today: 11)
        XCTAssertEqual(result.dropped, [5])
        XCTAssertEqual(result.moved, [])
        XCTAssertEqual(result.progress.statuses, [PlanProgress.key(8): .done, PlanProgress.key(5): .skipped])
        XCTAssertEqual(result.progress.dayOverrides, [PlanProgress.key(7): 11])
    }

    func testTheRaceNeverMoves() throws {
        let plan = try swapSchedule()
        for (missed, today) in [(0, 1), (5, 11), (8, 14), (13, 24), (14, 25), (15, 26)] {
            let pushed = try swapSchedule(plan.pushingBack(missed: missed, today: today).progress)
            XCTAssertEqual(pushed.dayOffset(16), 26, "missed \(missed) today \(today)")
            XCTAssertNil(pushed.status(16), "missed \(missed) today \(today)")
        }
    }

    func testPushingBackLeavesTheRaceAndUnmissedSessionsAlone() throws {
        let plan = try swapSchedule()
        let unchanged = PushBackResult(progress: plan.progress, moved: [], dropped: [])
        // The race never moves.
        XCTAssertEqual(plan.pushingBack(missed: 16, today: 27), unchanged)
        // Not missed yet, or not a session.
        XCTAssertEqual(plan.pushingBack(missed: 0, today: 0), unchanged)
        XCTAssertEqual(plan.pushingBack(missed: 99, today: 9), unchanged)
        // Already finished.
        let done = try swapSchedule(plan.markingDone(0))
        XCTAssertEqual(done.pushingBack(missed: 0, today: 1).progress, done.progress)
    }

    func testAMovedSessionCanBePushedAgain() throws {
        let plan = try swapSchedule()
        let first = plan.pushingBack(missed: 0, today: 1)
        // Day 1 passes without the run; it is missed again. On Thursday day 3 it takes today again, the
        // easy run behind it moves to Friday, the other easy run (day 4) is skipped to make room for the
        // track session, which takes Saturday.
        let again = try swapSchedule(first.progress)
        XCTAssertEqual(again.firstMissed(today: 2), 0)
        let second = again.pushingBack(missed: 0, today: 3)
        let pushed = try swapSchedule(second.progress)
        XCTAssertEqual(second.moved, [1])
        XCTAssertEqual(second.dropped, [2])
        XCTAssertEqual(pushed.dayOffset(0), 3)
        XCTAssertEqual(pushed.dayOffset(1), 4)
        XCTAssertEqual(pushed.status(2), .skipped)
        XCTAssertEqual(pushed.dayOffset(3), 5)
        XCTAssertEqual(pushed.status(4), .skipped)
        XCTAssertEqual(pushed.dayOffset(16), 26)
    }

    func testPushTexts() {
        XCTAssertEqual(PlanText.moveTitle(day: 5, today: 5, label: "sat oct 17"), "do it today")
        XCTAssertEqual(PlanText.moveTitle(day: 9, today: 7, label: "wed oct 21"), "move to wed oct 21")
        XCTAssertEqual(PlanText.noRoomNote, "no room this week. it'll be skipped.")
        XCTAssertEqual(PlanText.sessionCount(1), "1 session")
        XCTAssertEqual(PlanText.sessionCount(3), "3 sessions")
        XCTAssertEqual(PlanText.droppedItem(title: "2 mi easy", dayShort: "fri"), "the 2 mi easy on fri")
        XCTAssertEqual(PlanText.pushNote(moved: 0, dropped: []), "moves to today.")
        XCTAssertEqual(PlanText.pushNote(moved: 0, dropped: [], targetLabel: "thu oct 15"), "moves to thu oct 15.")
        XCTAssertEqual(PlanText.pushNote(moved: 3, dropped: []), "doing it today moves 3 sessions this week.")
        XCTAssertEqual(PlanText.pushNote(moved: 1, dropped: ["the 2 mi easy on fri"]),
                       "doing it today moves 1 session this week and skips 1 (the 2 mi easy on fri).")
        XCTAssertEqual(PlanText.pushNote(moved: 0, dropped: ["the 2 mi easy on fri", "the 3 mi easy on sat"]),
                       "doing it today skips 2 (the 2 mi easy on fri, the 3 mi easy on sat).")
        XCTAssertEqual(PlanText.pushNote(moved: 2, dropped: [], targetLabel: "thu oct 15"),
                       "moving it to thu oct 15 moves 2 sessions this week.")
    }

    // MARK: Missed, today, next

    func testFirstMissedIgnoresStatusedAndFutureSessions() throws {
        let plan = try schedule()
        XCTAssertNil(plan.firstMissed(today: 0))
        XCTAssertNil(plan.firstMissed(today: 1))
        // Session 0 (easy, day 1) is on offer for two days like any other session; then session 1
        // (track, day 3) is the oldest one left.
        XCTAssertEqual(plan.firstMissed(today: 2), 0)
        XCTAssertEqual(plan.firstMissed(today: 3), 0)
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

    func testMissedEasySessionsAreOfferedForTwoDaysThenSkipped() throws {
        let plan = try schedule()
        // Session 0 is a 2 mi easy run on day 1.
        XCTAssertEqual(plan.firstMissed(today: 3), 0)
        XCTAssertNil(try schedule(plan.skippingOld(today: 3)).status(0))
        XCTAssertEqual(try schedule(plan.skippingOld(today: 4)).status(0), .skipped)
        let reconciled = try schedule(plan.reconciled(activities: [], today: 4))
        XCTAssertEqual(reconciled.status(0), .skipped)
        XCTAssertNil(reconciled.status(1))
        // A matching run still counts on the day itself and afterwards.
        let run = ActivityDay(day: 1, kind: .run(miles: 2, workoutName: nil))
        XCTAssertEqual(try schedule(plan.reconciled(activities: [run], today: 4)).status(0), .done)
        // Wednesday day 2 is closed, so the easy run takes Thursday and the track session behind it moves
        // to Friday; the long run keeps Saturday.
        let pushed = try schedule(plan.pushingBack(missed: 0, today: 2).progress)
        XCTAssertEqual((0..<5).map { pushed.dayOffset($0) }, [3, 4, 5, 8, 12])
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

    func testASmallRunDoesNotCompleteALongRun() throws {
        // The swap plan's long run on day 24 is 6 mi: it needs 3 mi. The mini plan's long run is 3 mi.
        let long = try swapSchedule().plan.sessions[14]
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 0.8, workoutName: nil), session: long))
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 2.9, workoutName: nil), session: long))
        XCTAssertTrue(PlanSchedule.matches(.run(miles: 3.0, workoutName: nil), session: long))
        // A track workout is not a long run either, and a guided road workout is not an easy run.
        XCTAssertFalse(PlanSchedule.matches(.track(presetName: "6 \u{00D7} 400 @ R"), session: long))
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 6, workoutName: "20 min tempo"), session: long))
        let easy = try swapSchedule().plan.sessions[1]
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 1.4, workoutName: nil), session: easy))
        XCTAssertTrue(PlanSchedule.matches(.run(miles: 1.5, workoutName: nil), session: easy))
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

    // MARK: Done marks earned by activities

    func testReconcileRecordsWhichDoneMarksCameFromActivities() throws {
        // Session 1 was marked done by hand; sessions 0 and 2 are earned by runs.
        let plan = try schedule(try schedule().markingDone(1))
        let result = plan.reconciled(activities: [runActivity(1, miles: 2), runActivity(5, miles: 3)])
        let reconciled = try schedule(result)
        XCTAssertEqual((0..<3).map { reconciled.status($0) }, [.done, .done, .done])
        XCTAssertEqual(result.autoDone, [PlanProgress.key(0), PlanProgress.key(2)])
    }

    func testDoneMarksAreManualUnlessAnActivityEarnedThem() throws {
        let plan = try schedule()
        let auto = plan.markingDone(0, auto: true)
        XCTAssertEqual(auto.statuses, [PlanProgress.key(0): .done])
        XCTAssertEqual(auto.autoDone, [PlanProgress.key(0)])
        // Tapping done by hand on it makes it the runner's own mark.
        let manual = try schedule(auto).markingDone(0)
        XCTAssertEqual(manual.autoDone, [])
        XCTAssertEqual(manual.statuses, [PlanProgress.key(0): .done])
        // A plain done is manual from the start; skipping or reopening drops the automatic mark.
        XCTAssertEqual(plan.markingDone(1).autoDone, [])
        XCTAssertEqual(try schedule(auto).skipping(0).autoDone, [])
        XCTAssertEqual(try schedule(auto).reopening(0).autoDone, [])
        XCTAssertEqual(try schedule(auto).reopening(0).statuses, [:])
    }

    func testDeletingARunTakesBackOnlyTheMarksItEarned() throws {
        let plan = try schedule(try schedule().markingDone(1))
        let earned = try schedule(plan.reconciled(activities: [runActivity(1, miles: 2), runActivity(5, miles: 3)]))
        // The 3 mi run on day 5 is deleted and the 2 mi run stays: session 2 is open again, session 0 is
        // earned again by the run that is left, and the manual done on session 1 is untouched.
        let after = earned.reconciledAfterRemoval(activities: [runActivity(1, miles: 2)], today: 5)
        let result = try schedule(after)
        XCTAssertEqual(result.status(0), .done)
        XCTAssertEqual(result.status(1), .done)
        XCTAssertNil(result.status(2))
        XCTAssertEqual(after.autoDone, [PlanProgress.key(0)])
    }

    func testDeletingEveryRunLeavesManualMarksAndReopensTheRest() throws {
        let plan = try schedule(try schedule().markingDone(1))
        let earned = try schedule(plan.reconciled(activities: [runActivity(1, miles: 2)]))
        XCTAssertEqual(earned.status(0), .done)
        // Day 3: the easy run of day 1 is still within its two days on offer, so it is open again.
        let after = try schedule(earned.reconciledAfterRemoval(activities: [], today: 3))
        XCTAssertNil(after.status(0))
        XCTAssertEqual(after.status(1), .done)
        XCTAssertEqual(after.progress.autoDone, [])
        XCTAssertEqual(after.firstMissed(today: 3), 0)
        // Later than that it is skipped like any session missed more than two days ago.
        let late = try schedule(earned.reconciledAfterRemoval(activities: [], today: 6))
        XCTAssertEqual(late.status(0), .skipped)
        XCTAssertEqual(late.status(1), .done)
    }

    func testClearingAutoDoneLeavesSkipsAndOverridesAlone() throws {
        var progress = PlanProgress()
        progress.statuses[PlanProgress.key(0)] = .done
        progress.statuses[PlanProgress.key(2)] = .skipped
        progress.dayOverrides[PlanProgress.key(3)] = 9
        // Key 2 is listed but is not done any more (it was skipped later): it stays skipped.
        progress.autoDone = [PlanProgress.key(0), PlanProgress.key(2)]
        let cleared = try schedule(progress).clearingAutoDone()
        XCTAssertEqual(cleared.statuses, [PlanProgress.key(2): .skipped])
        XCTAssertEqual(cleared.dayOverrides, [PlanProgress.key(3): 9])
        XCTAssertEqual(cleared.autoDone, [])
    }

    func testAutoDoneRoundTripsAndOldProgressDecodesWithoutIt() throws {
        var progress = PlanProgress()
        progress.statuses[PlanProgress.key(2)] = .done
        progress.autoDone = [PlanProgress.key(2)]
        let data = try JSONEncoder().encode(progress)
        XCTAssertEqual(try JSONDecoder().decode(PlanProgress.self, from: data), progress)
        let old = try JSONDecoder().decode(PlanProgress.self,
                                           from: Data("{ \"statuses\": { \"2\": \"done\" }, \"planVersion\": 2 }".utf8))
        XCTAssertEqual(old.autoDone, [])
        XCTAssertEqual(old.statuses, [PlanProgress.key(2): .done])
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

    func testFreeRunsOfOneDayAreAddedUpAndGuidedOnesStandAlone() throws {
        let calendar = newYork()
        let start = try XCTUnwrap(PlanCalendar.parse("2026-10-12", calendar: calendar))
        func noon(_ day: Int, hour: Int = 12) -> Date {
            return PlanCalendar.date(forOffset: day, start: start, calendar: calendar)
                .addingTimeInterval(Double(hour) * 3600)
        }
        let runs = [LoggedRun(date: noon(1, hour: 7), meters: 1 * metersPerMile, workoutName: ""),
                    LoggedRun(date: noon(1, hour: 18), meters: 0.8 * metersPerMile, workoutName: ""),
                    LoggedRun(date: noon(1, hour: 19), meters: 3 * metersPerMile, workoutName: "20 min tempo"),
                    LoggedRun(date: noon(2), meters: 2 * metersPerMile, workoutName: "")]
        let days = PlanActivities.days(runs: runs, workouts: [], start: start, calendar: calendar)
        XCTAssertEqual(days.count, 3)
        var freeMilesOnDayOne: [Double] = []
        for activity in days where activity.day == 1 {
            if case .run(let miles, let name) = activity.kind, name == nil {
                freeMilesOnDayOne.append(miles)
            }
        }
        XCTAssertEqual(freeMilesOnDayOne.count, 1)
        XCTAssertEqual(freeMilesOnDayOne.first ?? 0, 1.8, accuracy: 0.0001)
        var guidedNames: [String] = []
        for activity in days {
            if case .run(_, let name) = activity.kind, let guided = name {
                guidedNames.append(guided)
            }
        }
        XCTAssertEqual(guidedNames, ["20 min tempo"])

        // Two short runs together make the 2 mi easy session of day 1 (it needs 1.0 mi).
        let plan = try schedule()
        let split = [LoggedRun(date: noon(1, hour: 7), meters: 0.6 * metersPerMile, workoutName: ""),
                     LoggedRun(date: noon(1, hour: 18), meters: 0.6 * metersPerMile, workoutName: "")]
        let split1 = PlanActivities.days(runs: split, workouts: [], start: start, calendar: calendar)
        XCTAssertEqual(try schedule(plan.reconciled(activities: split1)).status(0), .done)
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

    func testMinutesIntoTheDayRunPastMidnightUntilTheNextActivityDay() throws {
        let calendar = newYork()
        let start = try XCTUnwrap(PlanCalendar.parse("2026-10-12", calendar: calendar))
        func date(_ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            var parts = DateComponents()
            parts.year = 2026
            parts.month = 10
            parts.day = day
            parts.hour = hour
            parts.minute = minute
            return try XCTUnwrap(calendar.date(from: parts))
        }
        // 00:30 on the 13th still belongs to the 12th (day 0): 24 h 30 min into it.
        let late = try date(13, 0, 30)
        XCTAssertEqual(PlanCalendar.activityDay(of: late, start: start, calendar: calendar), 0)
        XCTAssertEqual(PlanCalendar.minutesIntoDay(now: late, offset: 0, start: start, calendar: calendar), 1470)
        // 03:00 starts day 1, which is 3 h into itself.
        let morning = try date(13, 3, 0)
        XCTAssertEqual(PlanCalendar.activityDay(of: morning, start: start, calendar: calendar), 1)
        XCTAssertEqual(PlanCalendar.minutesIntoDay(now: morning, offset: 1, start: start, calendar: calendar), 180)
        // Never negative.
        XCTAssertEqual(PlanCalendar.minutesIntoDay(now: late, offset: 2, start: start, calendar: calendar), 0)
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
