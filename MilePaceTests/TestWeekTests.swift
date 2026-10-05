import XCTest
@testable import MilePace

/// The test week (v1.7): its synthetic plan, when it starts and ends, which saved records a plan looks
/// at, reminder text, and the drafts that carry the test flag. Dates are Mon 2026-10-05 to Sun 2026-10-11,
/// with the real plan starting Mon 2026-10-12.
final class TestWeekTests: XCTestCase {
    private func day(_ ymd: String) throws -> Date {
        return try XCTUnwrap(PlanCalendar.parse(ymd))
    }

    private func at(_ ymd: String, hour: Int, minute: Int = 0) throws -> Date {
        let start = try day(ymd)
        return try XCTUnwrap(PlanCalendar.local.date(bySettingHour: hour, minute: minute, second: 0, of: start))
    }

    private func makePlan(from ymd: String, realStart: String? = "2026-10-12", mile: Double = 412) throws -> PlanFile {
        let real: Date? = try realStart.map { try day($0) }
        return TestWeek.plan(startingOn: try day(ymd), mileSeconds: mile, realStart: real)
    }

    // MARK: The plan

    func testMondayStartHasFiveSessionsOnMondayTuesdayThursdayFridayAndSaturday() throws {
        let plan = try makePlan(from: "2026-10-05")
        XCTAssertEqual(plan.sessions.map { $0.weekday }, [1, 2, 4, 5, 6])
        XCTAssertEqual(plan.sessions.map { $0.kind }, [.easy, .road, .track, .easy, .timeTrial])
        XCTAssertEqual(plan.sessions.map { $0.week }, [1, 1, 1, 1, 1])
        XCTAssertEqual(plan.sessions.map { $0.title },
                       ["1 mi easy", "2 \u{00D7} 2 min threshold", "4 \u{00D7} 200", "1.5 mi easy + metronome", "practice time trial"])
        XCTAssertEqual(plan.name, "test week")
        XCTAssertEqual(plan.startDate, "2026-10-05")
        XCTAssertNil(plan.raceDate)
        XCTAssertEqual(plan.weeks.count, 1)
        XCTAssertEqual(plan.weeks[0].week, 1)
        XCTAssertEqual(plan.weeks[0].phase, 1)
        XCTAssertEqual(plan.weeks[0].miles, 3.5, accuracy: 1e-9)
        XCTAssertTrue(plan.weeks[0].timeTrial)
        XCTAssertFalse(plan.weeks[0].race)
    }

    func testThursdayStartKeepsOnlyThursdayFridayAndSaturdayOfThatCalendarWeek() throws {
        let plan = try makePlan(from: "2026-10-08")
        XCTAssertEqual(plan.sessions.map { $0.weekday }, [4, 5, 6])
        XCTAssertEqual(plan.startDate, "2026-10-05")
        XCTAssertEqual(plan.weeks.count, 1)
        XCTAssertEqual(plan.weeks[0].miles, 2.5, accuracy: 1e-9)
    }

    func testTheStartDaysOwnSessionIsKept() throws {
        let plan = try makePlan(from: "2026-10-09")
        XCTAssertEqual(plan.sessions.map { $0.weekday }, [5, 6])
    }

    func testALateStartTakesTheNextWeekOnlyWhenItEndsBeforeTheRealStart() throws {
        // Saturday: one session left. The next week ends Sun 2026-10-18, before a real start on the 19th.
        let early = try makePlan(from: "2026-10-10", realStart: "2026-10-19")
        XCTAssertEqual(early.weeks.map { $0.week }, [1, 2])
        XCTAssertEqual(early.sessions.map { $0.week }, [1, 2, 2, 2, 2, 2])
        XCTAssertEqual(early.sessions.map { $0.weekday }, [6, 1, 2, 4, 5, 6])
        XCTAssertEqual(early.startDate, "2026-10-05")

        // With the real plan starting on the 12th there is no room: just what remains.
        let tight = try makePlan(from: "2026-10-10")
        XCTAssertEqual(tight.weeks.count, 1)
        XCTAssertEqual(tight.sessions.map { $0.weekday }, [6])

        // Without a real start nothing says the next week would finish in time.
        let unknown = try makePlan(from: "2026-10-10", realStart: nil)
        XCTAssertEqual(unknown.sessions.map { $0.weekday }, [6])

        // Sunday: nothing left this week.
        let sunday = try makePlan(from: "2026-10-11", realStart: "2026-10-19")
        XCTAssertEqual(sunday.sessions.map { $0.week }, [2, 2, 2, 2, 2])
    }

    func testTwoSessionsLeftDoNotPullInTheNextWeek() throws {
        let plan = try makePlan(from: "2026-10-09", realStart: "2026-10-26")
        XCTAssertEqual(plan.weeks.count, 1)
    }

    func testTheTimeTrialTargetIsTheMileTimeThatWasPassed() throws {
        let plan = try makePlan(from: "2026-10-05", mile: 399.5)
        let trials = plan.sessions.filter { $0.kind == .timeTrial }
        XCTAssertEqual(trials.count, 1)
        XCTAssertEqual(trials.first?.targetSeconds, 399.5)
        XCTAssertEqual(trials.first?.preset, PlanSchedule.mileTrialPresetId)
        XCTAssertTrue(plan.sessions.filter { $0.kind != .timeTrial }.allSatisfy { $0.targetSeconds == nil })
        XCTAssertEqual(PlanText.trialTarget(for: try XCTUnwrap(trials.first)), "target \u{2264} 6:40")
    }

    func testEveryPresetTheTestWeekNamesExists() throws {
        let plan = try makePlan(from: "2026-10-05")
        let roadNames = Set(RoadWorkoutPresets.all.map { $0.name })
        let trackIds = Set(WorkoutPresets.all.map { $0.id })
        for session in plan.sessions {
            switch session.kind {
            case .road:
                XCTAssertTrue(roadNames.contains(session.preset ?? ""), "unknown road workout \(session.preset ?? "")")
            case .track, .timeTrial:
                XCTAssertTrue(trackIds.contains(session.preset ?? ""), "unknown track preset \(session.preset ?? "")")
            case .easy, .long, .race, .other:
                XCTAssertNil(session.preset)
            }
        }
    }

    func testTheTestPresetsAreShortAndGentle() throws {
        let road = try XCTUnwrap(RoadWorkoutPresets.all.first { $0.name == "2 \u{00D7} 2 min threshold (test)" })
        XCTAssertEqual(road.reps, 2)
        XCTAssertEqual(road.length, .time(seconds: 120))
        XCTAssertEqual(road.target, .threshold)
        XCTAssertEqual(road.recoverySeconds, 60)

        let track = try XCTUnwrap(WorkoutPresets.all.first { $0.id == "4x200-test" })
        XCTAssertEqual(track.name, "4 \u{00D7} 200 (test)")
        XCTAssertEqual(track.reps, 4)
        XCTAssertEqual(track.repDistance, 200)
        XCTAssertEqual(track.restSeconds, 60)
        XCTAssertEqual(track.group, .shortReps)
        XCTAssertEqual(track.targetKind, .zone(.repetition))
    }

    func testTheVersionIsNotTheRealPlansAndSurvivesJSON() throws {
        let real = try XCTUnwrap(PlanLoader.load(bundle: Bundle(for: PlanStore.self)))
        let plan = try makePlan(from: "2026-10-05")
        XCTAssertEqual(plan.version, 1000)
        XCTAssertNotEqual(plan.version, real.version)
        let decoded = try JSONDecoder().decode(PlanFile.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(decoded, plan)
        // Progress saved for the real plan is not taken for the test plan's.
        let realProgress = try JSONEncoder().encode(PlanProgress(statuses: ["0": .done], planVersion: real.version))
        XCTAssertEqual(PlanProgress.restored(from: realProgress, planVersion: plan.version),
                       PlanProgress(planVersion: 1000))
    }

    func testTheStartDayFollowsTheThreeAmBoundary() throws {
        let early = TestWeek.startDay(now: try at("2026-10-12", hour: 1, minute: 30))
        XCTAssertEqual(PlanCalendar.ymd(early), "2026-10-11")
        let later = TestWeek.startDay(now: try at("2026-10-12", hour: 3, minute: 30))
        XCTAssertEqual(PlanCalendar.ymd(later), "2026-10-12")
    }

    // MARK: Lifecycle

    func testTheLastDayIsTheSundayOfTheLastTestWeek() throws {
        XCTAssertEqual(PlanCalendar.ymd(TestWeekLifecycle.lastDay(testStart: try day("2026-10-05"), weeks: 1)), "2026-10-11")
        XCTAssertEqual(PlanCalendar.ymd(TestWeekLifecycle.lastDay(testStart: try day("2026-10-08"), weeks: 1)), "2026-10-11")
        XCTAssertEqual(PlanCalendar.ymd(TestWeekLifecycle.lastDay(testStart: try day("2026-10-10"), weeks: 2)), "2026-10-18")
    }

    func testATestWeekIsOfferedOnlyBeforeTheRealStart() throws {
        let realStart = try day("2026-10-12")
        XCTAssertTrue(TestWeekLifecycle.canStart(today: try at("2026-10-05", hour: 9), realStart: realStart))
        XCTAssertTrue(TestWeekLifecycle.canStart(today: try at("2026-10-12", hour: 1), realStart: realStart))
        XCTAssertFalse(TestWeekLifecycle.canStart(today: try at("2026-10-12", hour: 4), realStart: realStart))
        XCTAssertFalse(TestWeekLifecycle.canStart(today: try at("2026-10-20", hour: 9), realStart: realStart))
    }

    func testItEndsOnTheRealStartDay() throws {
        let testStart = try day("2026-10-05")
        let realStart = try day("2026-10-12")
        func ends(_ ymd: String, hour: Int) throws -> Bool {
            return TestWeekLifecycle.shouldAutoEnd(today: try at(ymd, hour: hour), testStart: testStart, realStart: realStart)
        }
        XCTAssertFalse(try ends("2026-10-05", hour: 10))
        XCTAssertFalse(try ends("2026-10-08", hour: 18))
        // Sunday night and the small hours of Monday still belong to the test week.
        XCTAssertFalse(try ends("2026-10-11", hour: 23))
        XCTAssertFalse(try ends("2026-10-12", hour: 2))
        XCTAssertTrue(try ends("2026-10-12", hour: 4))
        XCTAssertTrue(try ends("2026-10-30", hour: 12))
    }

    func testItEndsAfterTheTestWeeksSundayWhenTheRealPlanStartsLater() throws {
        let realStart = try day("2026-10-19")
        func ends(start: String, _ ymd: String, hour: Int, weeks: Int = 1) throws -> Bool {
            return TestWeekLifecycle.shouldAutoEnd(today: try at(ymd, hour: hour),
                                                   testStart: try day(start),
                                                   realStart: realStart,
                                                   weeks: weeks)
        }
        XCTAssertFalse(try ends(start: "2026-10-08", "2026-10-11", hour: 12))
        XCTAssertTrue(try ends(start: "2026-10-08", "2026-10-12", hour: 4))
        // A two week test starting on a Saturday runs through the Sunday after the next.
        XCTAssertFalse(try ends(start: "2026-10-10", "2026-10-18", hour: 12, weeks: 2))
        XCTAssertTrue(try ends(start: "2026-10-10", "2026-10-19", hour: 4, weeks: 2))
    }

    func testItWaitsWhileARunOrTrackSessionIsGoing() throws {
        let testStart = try day("2026-10-05")
        let realStart = try day("2026-10-12")
        let now = try at("2026-10-13", hour: 9)
        XCTAssertTrue(TestWeekLifecycle.shouldAutoEnd(today: now, testStart: testStart, realStart: realStart))
        XCTAssertFalse(TestWeekLifecycle.shouldAutoEnd(today: now, testStart: testStart, realStart: realStart,
                                                       sessionActive: true))
    }

    // MARK: Records

    func testTheRealPlanIgnoresTestRecordsAndTheTestWeekSeesOnlyThem() throws {
        let noon = try at("2026-10-05", hour: 12)
        let runs = [LoggedRun(date: noon, meters: 1609.344, workoutName: ""),
                    LoggedRun(date: noon, meters: 3000, workoutName: "", isTest: true)]
        let workouts = [LoggedWorkout(date: noon, name: "6 \u{00D7} 400 @ R", repMeters: 2400),
                        LoggedWorkout(date: noon, name: "4 \u{00D7} 200 (test)", repMeters: 800, isTest: true)]

        let realRuns = TestRecordFilter.runs(runs, testWeek: false)
        XCTAssertEqual(realRuns.map { $0.meters }, [1609.344])
        let testRuns = TestRecordFilter.runs(runs, testWeek: true)
        XCTAssertEqual(testRuns.map { $0.meters }, [3000])
        XCTAssertEqual(TestRecordFilter.workouts(workouts, testWeek: false).map { $0.name }, ["6 \u{00D7} 400 @ R"])
        XCTAssertEqual(TestRecordFilter.workouts(workouts, testWeek: true).map { $0.name }, ["4 \u{00D7} 200 (test)"])
    }

    func testOnlyTestRecordsFinishTestWeekSessions() throws {
        let plan = try makePlan(from: "2026-10-05")
        let start = try day("2026-10-05")
        let schedule = PlanSchedule(plan: plan, progress: PlanProgress(planVersion: plan.version))
        let monday = try at("2026-10-05", hour: 12)
        let runs = [LoggedRun(date: monday, meters: 1609.344, workoutName: "", isTest: true),
                    LoggedRun(date: monday, meters: 1609.344, workoutName: "")]

        let testActivities = PlanActivities.days(runs: TestRecordFilter.runs(runs, testWeek: true),
                                                 workouts: [],
                                                 start: start)
        XCTAssertEqual(testActivities.count, 1)
        XCTAssertEqual(schedule.reconciled(activities: testActivities).statuses, [PlanProgress.key(0): .done])

        // The same Monday run without the flag finishes nothing in the test week.
        let plain = TestRecordFilter.runs(Array(runs.suffix(1)), testWeek: true)
        XCTAssertTrue(plain.isEmpty)
        let none = PlanActivities.days(runs: plain, workouts: [], start: start)
        XCTAssertEqual(schedule.reconciled(activities: none).statuses, [:])

        // And the real plan, looking at the records the same way, never sees the test run.
        let realActivities = PlanActivities.days(runs: TestRecordFilter.runs(runs, testWeek: false),
                                                 workouts: [],
                                                 start: start)
        XCTAssertEqual(realActivities.count, 1)
        XCTAssertEqual(realActivities.first?.kind, .run(miles: 1, workoutName: nil))
    }

    func testTestSessionsAreMatchedByTheTestPresets() throws {
        let plan = try makePlan(from: "2026-10-05")
        let road = plan.sessions[1]
        let track = plan.sessions[2]
        let trial = plan.sessions[4]
        XCTAssertTrue(PlanSchedule.matches(.run(miles: 0.3, workoutName: "2 \u{00D7} 2 min threshold (test)"), session: road))
        XCTAssertFalse(PlanSchedule.matches(.run(miles: 3, workoutName: nil), session: road))
        XCTAssertTrue(PlanSchedule.matches(.track(presetName: "4 \u{00D7} 200 (test)"), session: track))
        XCTAssertTrue(PlanSchedule.matches(.track(presetName: "Mile time trial"), session: trial))
        XCTAssertFalse(PlanSchedule.matches(.track(presetName: "4 \u{00D7} 200 (test)"), session: trial))
    }

    // MARK: Reminders

    private func reminders(testWeek: Bool) throws -> [ReminderSpec] {
        let plan = try makePlan(from: "2026-10-05")
        let schedule = PlanSchedule(plan: plan, progress: PlanProgress(planVersion: plan.version))
        return ReminderPlanner.build(schedule: schedule,
                                     todayOffset: 0,
                                     nowMinutes: 0,
                                     settings: ReminderSettings.standard,
                                     loggedMilesByDay: [:],
                                     zones: PaceZones.forMile(412),
                                     goalMile: 330,
                                     startDate: try day("2026-10-05"),
                                     testWeek: testWeek)
    }

    func testTestWeekRemindersSayTestAndSkipTheWeekOneStartNote() throws {
        let specs = try reminders(testWeek: true)
        XCTAssertFalse(specs.isEmpty)
        XCTAssertTrue(specs.allSatisfy { $0.title.hasPrefix("test: ") })
        XCTAssertNil(specs.first { $0.id == ReminderPlanner.startId })
        XCTAssertEqual(specs.first { $0.id == "plan.morning.0" }?.title, "test: today: 1 mi easy")
        XCTAssertEqual(specs.first { $0.id == "plan.evening.0" }?.title, "test: still on the plan: 1 mi easy")
        XCTAssertEqual(specs.first { $0.id == "plan.tt.4" }?.title, "test: time trial tomorrow")
    }

    func testRealRemindersAreUnchanged() throws {
        let specs = try reminders(testWeek: false)
        XCTAssertEqual(specs.first { $0.id == ReminderPlanner.startId }?.title, "week 1 starts today")
        XCTAssertEqual(specs.first { $0.id == "plan.morning.0" }?.title, "today: 1 mi easy")
        XCTAssertFalse(specs.contains { $0.title.hasPrefix("test: ") })
    }

    // MARK: Drafts

    private func withoutIsTest(_ data: Data) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object["isTest"])
        object.removeValue(forKey: "isTest")
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testARunDraftCarriesTheTestFlagAndOldDraftsReadAsReal() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var draft = RunDraft(start: start,
                             distanceMeters: 1609.344,
                             movingSeconds: 600,
                             splits: [600],
                             route: [],
                             cadenceSteps: 1700,
                             workoutName: "")
        XCTAssertFalse(draft.isTest)
        XCTAssertFalse(draft.makeRecord().isTest)

        draft.isTest = true
        let data = try XCTUnwrap(draft.encoded())
        XCTAssertEqual(RunDraft.decode(data), draft)
        XCTAssertTrue(draft.makeRecord().isTest)

        let old = try withoutIsTest(data)
        var expected = draft
        expected.isTest = false
        XCTAssertEqual(RunDraft.decode(old), expected)
    }

    func testARunSummaryDraftKeepsTheTestFlag() {
        var summary = RunSummary(date: Date(timeIntervalSinceReferenceDate: 800_000_000),
                                 distanceMeters: 1000,
                                 durationSeconds: 400,
                                 averagePace: 644,
                                 splits: [])
        XCTAssertFalse(RunDraft(summary: summary).isTest)
        summary.isTest = true
        XCTAssertTrue(RunDraft(summary: summary).isTest)
    }

    func testATrackDraftCarriesTheTestFlagAndOldDraftsReadAsReal() throws {
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        var workout = TrackWorkout(spec: WorkoutSpec(name: "4 \u{00D7} 200 (test)", reps: 4, repDistance: 200,
                                                     targetRepSeconds: 45, restSeconds: 60))
        workout.start(now: base)
        let plain = TrackSessionDraft(workout: workout, sessionStart: base, savedAt: base)
        XCTAssertFalse(plain.isTest)
        XCTAssertFalse(plain.makeRecord().isTest)

        let flagged = TrackSessionDraft(workout: workout, sessionStart: base, savedAt: base, isTest: true)
        XCTAssertTrue(flagged.makeRecord().isTest)
        let data = try JSONEncoder().encode(flagged)
        XCTAssertEqual(try JSONDecoder().decode(TrackSessionDraft.self, from: data), flagged)

        let old = try withoutIsTest(data)
        XCTAssertEqual(try JSONDecoder().decode(TrackSessionDraft.self, from: old), plain)
    }
}
