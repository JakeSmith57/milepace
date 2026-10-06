import XCTest
@testable import MilePace

/// The progress export (v1.10): section order, session statuses, rep deltas, which sessions are listed,
/// test data left out, and the file name. Everything runs in a fixed UTC calendar; the plan starts on
/// Monday 2026-10-12 and today is Saturday 2026-10-17 (day 5).
final class ProgressExportTests: XCTestCase {
    private var calendar: Calendar {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return utc
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        return try XCTUnwrap(calendar.date(from: parts))
    }

    private func makePlan() -> PlanFile {
        let sessions = [
            PlanSession(week: 1, weekday: 1, phase: 1, kind: .easy, title: "3 mi easy",
                        miles: 3, preset: nil, note: nil),
            PlanSession(week: 1, weekday: 2, phase: 1, kind: .track, title: "6 x 400",
                        miles: nil, preset: nil, note: nil),
            PlanSession(week: 1, weekday: 4, phase: 1, kind: .easy, title: "2 mi easy",
                        miles: 2, preset: nil, note: nil),
            PlanSession(week: 1, weekday: 5, phase: 1, kind: .easy, title: "1 mi easy",
                        miles: 1, preset: nil, note: nil),
            PlanSession(week: 1, weekday: 6, phase: 1, kind: .timeTrial, title: "mile time trial",
                        miles: nil, preset: "mile-tt", note: nil, targetSeconds: 395),
            PlanSession(week: 2, weekday: 1, phase: 1, kind: .easy, title: "4 mi easy",
                        miles: 4, preset: nil, note: nil),
            PlanSession(week: 2, weekday: 6, phase: 1, kind: .race, title: "race",
                        miles: nil, preset: "mile-tt", note: nil, targetSeconds: 330),
            PlanSession(week: 3, weekday: 1, phase: 2, kind: .easy, title: "week three session",
                        miles: 5, preset: nil, note: nil)
        ]
        let weeks = [
            PlanWeek(week: 1, miles: 9, phase: 1, recovery: false, timeTrial: true, race: false),
            PlanWeek(week: 2, miles: 10, phase: 1, recovery: false, timeTrial: false, race: true),
            PlanWeek(week: 3, miles: 12, phase: 2, recovery: false, timeTrial: false, race: false)
        ]
        return PlanFile(name: "export plan", version: 7, startDate: "2026-10-12", raceDate: "2026-10-24",
                        weeks: weeks, sessions: sessions)
    }

    private func makeProgress(timeTrialDone: Bool = false) -> PlanProgress {
        var statuses: [String: SessionStatus] = ["0": .done, "1": .done, "3": .skipped]
        if timeTrialDone {
            statuses["4"] = .done
        }
        return PlanProgress(statuses: statuses,
                            dayOverrides: ["5": 8],
                            planVersion: 7,
                            autoDone: ["1"])
    }

    private func makeSpec() -> WorkoutSpec {
        return WorkoutSpec(name: "3 x 800", reps: 3, repDistance: 800, targetRepSeconds: 176, restSeconds: 90)
    }

    private func makeInput(timeTrialDone: Bool = false,
                           testWeekActive: Bool = false,
                           extraWorkouts: [ExportWorkout] = []) throws -> ExportInput {
        let plan = makePlan()
        let progress = makeProgress(timeTrialDone: timeTrialDone)
        let schedule = PlanSchedule(plan: plan, progress: progress, startWeekday: 1)
        let runs = [
            ExportRun(date: try date(2026, 10, 12, hour: 7),
                      distanceMeters: 3 * metersPerMile,
                      durationSeconds: 1800,
                      averagePace: 600,
                      splits: [600, 600, 600],
                      averageCadence: 168,
                      workoutName: "",
                      notes: "felt good | easy",
                      hasRoute: true),
            ExportRun(date: try date(2026, 10, 13),
                      distanceMeters: metersPerMile,
                      durationSeconds: 0,
                      averagePace: 0,
                      splits: [],
                      averageCadence: 0,
                      workoutName: "",
                      notes: "",
                      hasRoute: false),
            ExportRun(date: try date(2026, 10, 14),
                      distanceMeters: 9999,
                      durationSeconds: 100,
                      averagePace: 500,
                      splits: [],
                      averageCadence: 0,
                      workoutName: "",
                      notes: "TESTRUN",
                      hasRoute: false,
                      isTest: true)
        ]
        var workouts = [
            ExportWorkout(date: try date(2026, 10, 13, hour: 18),
                          name: "3 x 800",
                          spec: makeSpec(),
                          repTimes: [175, 177.5, 176],
                          lapSplits: [[87, 88], [88, 89.5], [88, 88]]),
            ExportWorkout(date: try date(2026, 10, 14, hour: 18),
                          name: "TESTWORKOUT",
                          spec: makeSpec(),
                          repTimes: [170],
                          lapSplits: [[170]],
                          isTest: true)
        ]
        workouts.append(contentsOf: extraWorkouts)
        let settings = ExportSettings(mileTime: 412,
                                      goalMile: 330,
                                      paceWindow: 8,
                                      metronomeBPM: 166,
                                      metronomeEnabled: true,
                                      voiceEnabled: false,
                                      cueInterval: "\u{00BD} mi")
        return ExportInput(generatedAt: try date(2026, 10, 17, hour: 14),
                           appVersion: "1.10",
                           plan: plan,
                           startYMD: "2026-10-12",
                           progress: progress,
                           schedule: schedule,
                           todayOffset: 5,
                           settings: settings,
                           zones: PaceZones.forMile(412),
                           runs: runs,
                           workouts: workouts,
                           testWeekActive: testWeekActive)
    }

    private func build(_ input: ExportInput) -> String {
        return ProgressExport.markdown(input, calendar: calendar)
    }

    // MARK: Structure

    func testSectionHeadersAppearInOrder() throws {
        let text = build(try makeInput())
        let headers = ["# MilePace progress export",
                       "## Settings",
                       "## Sessions",
                       "## Weekly mileage",
                       "## Runs",
                       "## Track workouts",
                       "## Time trials and races"]
        var previous = text.startIndex
        for header in headers {
            let range = try XCTUnwrap(text.range(of: header), header)
            XCTAssertGreaterThanOrEqual(range.lowerBound, previous, header)
            previous = range.lowerBound
        }
        let totals = try XCTUnwrap(text.range(of: "Totals:"))
        XCTAssertGreaterThan(totals.lowerBound, previous)
    }

    func testHeaderAndSettings() throws {
        let text = build(try makeInput())
        XCTAssertTrue(text.contains("- generated: 2026-10-17 (Sat) 14:00"))
        XCTAssertTrue(text.contains("- app version: 1.10"))
        XCTAssertTrue(text.contains("- plan: export plan (version 7)"))
        XCTAssertTrue(text.contains("- plan start: 2026-10-12 (Mon)"))
        XCTAssertTrue(text.contains("- race date: 2026-10-24"))
        XCTAssertTrue(text.contains("- today: 2026-10-17 (Sat), plan week 1 of 3, phase 1"))
        XCTAssertFalse(text.contains("test week active"))
        XCTAssertTrue(text.contains("- current mile: 6:52"))
        XCTAssertTrue(text.contains("- goal mile: 5:30"))
        XCTAssertTrue(text.contains("- metronome: 166 spm, on"))
        XCTAssertTrue(text.contains("- voice: off"))
        XCTAssertTrue(text.contains("- pace window: \u{00B1}8 s/mi"))
    }

    func testTestWeekLine() throws {
        let text = build(try makeInput(testWeekActive: true))
        XCTAssertTrue(text.contains("- test week active (test data excluded)"))
    }

    // MARK: Sessions

    func testSessionStatuses() throws {
        let text = build(try makeInput())
        XCTAssertTrue(text.contains("| 2026-10-12 (Mon) | 1 | easy | 3 mi easy | 3 | \u{2014} | done |"))
        XCTAssertTrue(text.contains("| 2026-10-13 (Tue) | 1 | track | 6 x 400 | \u{2014} | \u{2014} | done (auto) |"))
        XCTAssertTrue(text.contains("| 2026-10-15 (Thu) | 1 | easy | 2 mi easy | 2 | \u{2014} | missed |"))
        XCTAssertTrue(text.contains("| 2026-10-16 (Fri) | 1 | easy | 1 mi easy | 1 | \u{2014} | skipped |"))
        XCTAssertTrue(text.contains("| 2026-10-17 (Sat) | 1 | timeTrial | mile time trial | \u{2014} | 6:35 | today |"))
        XCTAssertTrue(text.contains("| 2026-10-24 (Sat) | 2 | race | race | \u{2014} | 5:30 | planned |"))
    }

    func testSessionsStopAfterTheWeekFollowingToday() throws {
        let text = build(try makeInput())
        XCTAssertTrue(text.contains("4 mi easy"))
        XCTAssertFalse(text.contains("week three session"))
    }

    func testMovedSessionUsesItsOverrideDayAndIsListed() throws {
        let text = build(try makeInput())
        XCTAssertTrue(text.contains("| 2026-10-20 (Tue) | 2 | easy | 4 mi easy | 4 |"))
        XCTAssertTrue(text.contains("- day override: 4 mi easy (week 2) is on 2026-10-20 (Tue), planned 2026-10-19 (Mon)"))
    }

    func testStatusTextForSessionsWithoutProgress() throws {
        let schedule = PlanSchedule(plan: makePlan(), progress: PlanProgress(planVersion: 7), startWeekday: 1)
        XCTAssertEqual(ProgressExport.statusText(0, day: 0, schedule: schedule, today: 5), "missed")
        XCTAssertEqual(ProgressExport.statusText(4, day: 5, schedule: schedule, today: 5), "today")
        XCTAssertEqual(ProgressExport.statusText(6, day: 12, schedule: schedule, today: 5), "planned")
    }

    // MARK: Weekly mileage

    func testWeeklyMileageUsesRunsAndEstimatedTrackMiles() throws {
        let text = build(try makeInput())
        // 3.00 + 1.00 mi of runs, and 3 x 800 m = 1.49 mi plus 2.0 for the warm-up and cool-down.
        XCTAssertTrue(text.contains("| 1 | 1 | 9.0 | 7.5 | 2/5 |"))
        XCTAssertFalse(text.contains("| 2 | 1 | 10.0 |"))
    }

    // MARK: Runs and workouts

    func testRunsAreListedNewestFirstAndTestRunsAreLeftOut() throws {
        let text = build(try makeInput())
        XCTAssertFalse(text.contains("TESTRUN"))
        XCTAssertFalse(text.contains("TESTWORKOUT"))
        let manual = try XCTUnwrap(text.range(of: "| 2026-10-13 (Tue) | 1.00 | \u{2014} | --:-- | \u{2014} | free | manual |"))
        let first = try XCTUnwrap(text.range(of: "| 2026-10-12 (Mon) | 3.00 | 30:00 | 10:00 | 168 spm | free | 10:00, 10:00, 10:00 | felt good / easy |"))
        XCTAssertLessThan(manual.lowerBound, first.lowerBound)
        XCTAssertTrue(text.contains("Totals: 2 runs, 4.00 mi; 1 track workouts; since 2026-10-12 (Mon)."))
    }

    func testRepDeltasUseARealMinusSign() throws {
        let text = build(try makeInput())
        XCTAssertTrue(text.contains("- workout: 3 \u{00D7} 800 m @ 2:56.0, rest 90 s"))
        XCTAssertTrue(text.contains("2:55.0 (\u{2212}1.0)"))
        XCTAssertTrue(text.contains("2:57.5 (+1.5)"))
        XCTAssertTrue(text.contains("- average rep: 2:56.2 vs target 2:56.0 (+0.2)"))
        XCTAssertTrue(text.contains("- laps, rep 2: 1:28.0, 1:29.5"))
    }

    func testSpecInWordsWithSets() {
        let spec = WorkoutSpec(name: "sets", reps: 4, repDistance: 400, targetRepSeconds: 88,
                               restSeconds: 60, sets: 2, setRestSeconds: 180)
        XCTAssertEqual(ProgressExport.specText(spec), "2 sets of 4 \u{00D7} 400 m @ 1:28.0, rest 60 s, set rest 180 s")
    }

    // MARK: Time trials

    func testNoTimeTrialsYet() throws {
        let text = build(try makeInput())
        XCTAssertTrue(text.contains("## Time trials and races\n\nnone yet."))
    }

    func testFinishedTimeTrialShowsTheSameDayWorkoutAgainstTheTarget() throws {
        let spec = WorkoutSpec(name: "mile time trial", reps: 1, repDistance: 1609, targetRepSeconds: 395, restSeconds: 0)
        let trial = ExportWorkout(date: try date(2026, 10, 17, hour: 9),
                                  name: "mile time trial",
                                  spec: spec,
                                  repTimes: [391.2],
                                  lapSplits: [[97, 98, 98, 98.2]])
        let text = build(try makeInput(timeTrialDone: true, extraWorkouts: [trial]))
        XCTAssertTrue(text.contains("track workout mile time trial, result 6:31.2 vs target 6:35 (\u{2212}3.8)"))
        XCTAssertFalse(text.contains("## Time trials and races\n\nnone yet."))
    }

    // MARK: File name

    func testFileName() throws {
        XCTAssertEqual(ProgressExport.fileName(for: try date(2026, 10, 6), calendar: calendar),
                       "milepace-progress-2026-10-06.md")
    }

    func testCellsHaveNoPipesOrLineBreaks() {
        XCTAssertEqual(ProgressExport.cell("a | b\nc"), "a / b c")
        XCTAssertEqual(ProgressExport.cell("  "), "\u{2014}")
    }

    func testNoPlanStillProducesEveryHeader() throws {
        let base = try makeInput()
        let input = ExportInput(generatedAt: base.generatedAt,
                                appVersion: "1.10",
                                plan: nil,
                                startYMD: "2026-10-12",
                                progress: PlanProgress(),
                                schedule: nil,
                                todayOffset: 5,
                                settings: base.settings,
                                zones: base.zones,
                                runs: [],
                                workouts: [])
        let text = build(input)
        XCTAssertTrue(text.contains("no plan loaded."))
        XCTAssertTrue(text.contains("## Runs\n\nnone yet."))
        XCTAssertTrue(text.contains("Totals: 0 runs, 0.00 mi; 0 track workouts; since no activity yet."))
    }
}
