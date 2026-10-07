import XCTest
@testable import MilePace

/// The v1.14 export additions: effort and foot pain on runs and workouts, the "## Mile progress" and
/// "## Foot" sections. No plan is loaded, so these cover the parts that do not depend on one.
final class ProgressExportFeelTests: XCTestCase {
    private var calendar: Calendar {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return utc
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = month
        parts.day = day
        parts.hour = hour
        return try XCTUnwrap(calendar.date(from: parts))
    }

    private func run(_ date: Date, miles: Double = 3, effort: Int = 0, foot: Int = -1, test: Bool = false) -> ExportRun {
        return ExportRun(date: date,
                         distanceMeters: miles * metersPerMile,
                         durationSeconds: miles * 600,
                         averagePace: 600,
                         splits: [],
                         averageCadence: 0,
                         workoutName: "",
                         notes: "",
                         hasRoute: false,
                         isTest: test,
                         effort: effort,
                         footPain: foot)
    }

    private func build(runs: [ExportRun] = [],
                       workouts: [ExportWorkout] = [],
                       gps: [DistanceBest] = []) throws -> String {
        let settings = ExportSettings(mileTime: 412,
                                      goalMile: 330,
                                      paceWindow: 8,
                                      metronomeBPM: 166,
                                      metronomeEnabled: false,
                                      voiceEnabled: true,
                                      cueInterval: "1 mi")
        let input = ExportInput(generatedAt: try date(10, 20),
                                appVersion: "1.14",
                                plan: nil,
                                startYMD: "2026-10-12",
                                progress: PlanProgress(),
                                schedule: nil,
                                todayOffset: 8,
                                settings: settings,
                                zones: PaceZones.forMile(412),
                                runs: runs,
                                workouts: workouts,
                                gpsBests: gps)
        return ProgressExport.markdown(input, calendar: calendar)
    }

    private func mileTrial(_ date: Date, time: Double, effort: Int = 0, foot: Int = -1, test: Bool = false) -> ExportWorkout {
        let spec = WorkoutSpec(name: "Mile time trial", reps: 1, repDistance: 1609, targetRepSeconds: 395, restSeconds: 0)
        return ExportWorkout(date: date,
                             name: "Mile time trial",
                             spec: spec,
                             repTimes: [time],
                             lapSplits: [[time]],
                             isTest: test,
                             effort: effort,
                             footPain: foot)
    }

    // MARK: Effort and foot on runs and workouts

    func testNoFeelColumnWhenNothingIsSet() throws {
        let text = try build(runs: [run(try date(10, 18))])
        XCTAssertTrue(text.contains("| date | miles | time | avg /mi | cadence | workout | mile splits | notes |"))
        XCTAssertFalse(text.contains("| feel |"))
    }

    func testFeelColumnAppearsOnceAnyRunHasOne() throws {
        let text = try build(runs: [run(try date(10, 18), effort: 7, foot: 0), run(try date(10, 17))])
        XCTAssertTrue(text.contains("| mile splits | feel | notes |"))
        XCTAssertTrue(text.contains("| rpe 7, foot 0 |"))
        // The run without a rating has an empty cell.
        XCTAssertTrue(text.contains("| 2026-10-17 (Sat) | 3.00 | 30:00 | 10:00 | \u{2014} | free | manual | \u{2014} | \u{2014} |"))
    }

    func testWorkoutFeelLine() throws {
        let text = try build(workouts: [mileTrial(try date(10, 17), time: 391.2, effort: 9, foot: 2)])
        XCTAssertTrue(text.contains("- feel: rpe 9, foot 2"))
        let plain = try build(workouts: [mileTrial(try date(10, 17), time: 391.2)])
        XCTAssertFalse(plain.contains("- feel:"))
    }

    // MARK: Foot section

    func testFootSectionWithNothingLogged() throws {
        let text = try build(runs: [run(try date(10, 18), effort: 5, foot: 0)])
        XCTAssertTrue(text.contains("## Foot\n\nno foot pain logged"))
    }

    func testFootSectionListsEveryEntryFromOneUpNewestFirst() throws {
        let runs = [run(try date(10, 15), miles: 4, foot: 2),
                    run(try date(10, 18), miles: 3, foot: 5),
                    run(try date(10, 19), miles: 2, foot: 0),
                    run(try date(10, 16), miles: 9, foot: 8, test: true)]
        let workouts = [mileTrial(try date(10, 17), time: 395, foot: 1)]
        let text = try build(runs: runs, workouts: workouts)
        let newest = try XCTUnwrap(text.range(of: "- 2026-10-18 (Sun): foot 5, run 3.00 mi"))
        let middle = try XCTUnwrap(text.range(of: "- 2026-10-17 (Sat): foot 1, workout Mile time trial"))
        let oldest = try XCTUnwrap(text.range(of: "- 2026-10-15 (Thu): foot 2, run 4.00 mi"))
        XCTAssertLessThan(newest.lowerBound, middle.lowerBound)
        XCTAssertLessThan(middle.lowerBound, oldest.lowerBound)
        XCTAssertFalse(text.contains("foot 0, run"))
        XCTAssertFalse(text.contains("foot 8"))
        XCTAssertFalse(text.contains("no foot pain logged"))
    }

    // MARK: Mile progress

    func testMileProgressWithoutATrackMileUsesTheSetting() throws {
        let text = try build()
        XCTAssertTrue(text.contains("## Mile progress"))
        XCTAssertTrue(text.contains("- latest mile: 6:52 (the mile time setting; no track mile yet)"))
        XCTAssertTrue(text.contains("- goal mile: 5:30"))
        XCTAssertTrue(text.contains("- to go: 1:22"))
        XCTAssertTrue(text.contains("| 400 m | \u{2014} | \u{2014} |"))
        XCTAssertTrue(text.contains("| 5 km | \u{2014} | \u{2014} |"))
        XCTAssertTrue(text.contains("Time trials and races against the plan target:\n\nnone yet."))
    }

    func testMileProgressWithATimeTrialAndGPSBests() throws {
        let gps = [DistanceBest(distance: 800, seconds: 170, date: try date(10, 14)),
                   DistanceBest(distance: 5000, seconds: 1500, date: try date(10, 12))]
        let text = try build(workouts: [mileTrial(try date(10, 17), time: 391.2)], gps: gps)
        XCTAssertTrue(text.contains("- latest mile: 6:31 (track, 2026-10-17 (Sat))"))
        XCTAssertTrue(text.contains("- to go: 1:01"))
        XCTAssertTrue(text.contains("| 1 mi | 6:31 | 2026-10-17 (Sat) |"))
        XCTAssertTrue(text.contains("| 800 m | 2:50.0 | 2026-10-14 (Wed) |"))
        XCTAssertTrue(text.contains("| 5 km | 25:00 | 2026-10-12 (Mon) |"))
        XCTAssertTrue(text.contains("- 2026-10-17 (Sat) time trial: 6:31, no plan target that day"))
    }

    func testTestWorkoutsNeverCountForMileProgress() throws {
        let text = try build(workouts: [mileTrial(try date(10, 17), time: 300, test: true)])
        XCTAssertTrue(text.contains("no track mile yet"))
        XCTAssertFalse(text.contains("(track, "))
    }

    // MARK: Order

    func testNewSectionsComeBeforeTheTotals() throws {
        let text = try build(runs: [run(try date(10, 18))])
        let trials = try XCTUnwrap(text.range(of: "## Time trials and races"))
        let mile = try XCTUnwrap(text.range(of: "## Mile progress"))
        let foot = try XCTUnwrap(text.range(of: "## Foot"))
        let totals = try XCTUnwrap(text.range(of: "Totals:"))
        XCTAssertLessThan(trials.lowerBound, mile.lowerBound)
        XCTAssertLessThan(mile.lowerBound, foot.lowerBound)
        XCTAssertLessThan(foot.lowerBound, totals.lowerBound)
    }
}
