import XCTest
@testable import MilePace

final class RunDraftTests: XCTestCase {
    private func utc() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return calendar
    }

    private func draft(start: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)) -> RunDraft {
        let route = [RoutePoint(lat: 40.0, lon: -73.0, t: 0, d: 0, segmentStart: true),
                     RoutePoint(lat: 40.001, lon: -73.0, t: 60, d: 111)]
        return RunDraft(start: start,
                        distanceMeters: 2.41 * metersPerMile,
                        movingSeconds: 1132,
                        splits: [470.5, 468.0],
                        route: route,
                        cadenceSteps: 3000,
                        workoutName: "")
    }

    func testRoundTripsThroughJSON() throws {
        let original = draft()
        let data = try XCTUnwrap(original.encoded())
        XCTAssertEqual(RunDraft.decode(data), original)
        XCTAssertNil(RunDraft.decode(Data("nope".utf8)))
    }

    func testAveragePaceAndCadence() {
        let run = draft()
        XCTAssertEqual(run.averagePace, 1132 / (2.41 * metersPerMile) * metersPerMile, accuracy: 1e-6)
        // 3000 steps over 1132 seconds.
        XCTAssertEqual(run.averageCadence, 3000.0 / 1132 * 60, accuracy: 1e-6)

        var short = run
        short.distanceMeters = 5
        XCTAssertEqual(short.averagePace, 0)
        var brief = run
        brief.movingSeconds = 30
        XCTAssertEqual(brief.averageCadence, 0)
    }

    func testSummaryText() throws {
        let calendar = utc()
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 14
        parts.hour = 6
        parts.minute = 42
        let start = try XCTUnwrap(calendar.date(from: parts))
        XCTAssertEqual(draft(start: start).summaryText(calendar: calendar),
                       "unfinished run from 6:42 am: 2.41 mi, 18:52")
    }

    func testMakeRecordKeepsEverything() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var run = draft(start: start)
        run.workoutName = "20 min tempo"
        let record = run.makeRecord()
        XCTAssertEqual(record.date, start)
        XCTAssertEqual(record.distanceMeters, 2.41 * metersPerMile, accuracy: 1e-9)
        XCTAssertEqual(record.durationSeconds, 1132, accuracy: 1e-9)
        XCTAssertEqual(record.averagePace, run.averagePace, accuracy: 1e-9)
        XCTAssertEqual(record.splits, [470.5, 468.0])
        XCTAssertEqual(record.notes, "")
        XCTAssertEqual(record.route, run.route)
        XCTAssertEqual(record.averageCadence, run.averageCadence, accuracy: 1e-9)
        XCTAssertEqual(record.workoutName, "20 min tempo")
    }
}

final class CadenceMathTests: XCTestCase {
    func testAverageOverMovingTime() {
        // 3000 steps in 20 minutes is 150 steps per minute.
        XCTAssertEqual(CadenceMath.averageSPM(totalSteps: 3000, pausedSteps: 0, movingSeconds: 1200) ?? 0, 150, accuracy: 1e-9)
    }

    func testPausedStepsAreLeftOut() {
        // 400 of the 3400 steps were taken while paused.
        XCTAssertEqual(CadenceMath.averageSPM(totalSteps: 3400, pausedSteps: 400, movingSeconds: 1200) ?? 0, 150, accuracy: 1e-9)
        XCTAssertEqual(CadenceMath.averageSPM(totalSteps: 3000, pausedSteps: -50, movingSeconds: 1200) ?? 0, 150, accuracy: 1e-9)
    }

    func testNilWithTooLittleData() {
        XCTAssertNil(CadenceMath.averageSPM(totalSteps: 100, pausedSteps: 0, movingSeconds: 59))
        XCTAssertNil(CadenceMath.averageSPM(totalSteps: 100, pausedSteps: 100, movingSeconds: 600))
        XCTAssertNil(CadenceMath.averageSPM(totalSteps: 100, pausedSteps: 200, movingSeconds: 600))
        XCTAssertNil(CadenceMath.averageSPM(totalSteps: 0, pausedSteps: 0, movingSeconds: 600))
        XCTAssertNil(CadenceMath.averageSPM(totalSteps: 100, pausedSteps: 0, movingSeconds: .nan))
        XCTAssertNil(CadenceMath.averageSPM(totalSteps: 100, pausedSteps: 0, movingSeconds: .infinity))
    }

    func testADraftFromAFinishedRunKeepsTheWholeRun() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let summary = RunSummary(date: start,
                                 distanceMeters: 3000,
                                 durationSeconds: 1200,
                                 averagePace: 644,
                                 splits: [640, 648],
                                 workoutName: "20 min tempo",
                                 averageCadence: 174,
                                 route: [RoutePoint(lat: 40.7, lon: -73.9, t: 0, d: 0, segmentStart: true),
                                         RoutePoint(lat: 40.71, lon: -73.9, t: 600, d: 1500)])
        let run = RunDraft(summary: summary)
        XCTAssertEqual(run.start, start)
        XCTAssertEqual(run.distanceMeters, 3000)
        XCTAssertEqual(run.movingSeconds, 1200)
        XCTAssertEqual(run.splits, [640, 648])
        XCTAssertEqual(run.route, summary.route)
        XCTAssertEqual(run.workoutName, "20 min tempo")
        // 174 steps a minute for 20 minutes.
        XCTAssertEqual(run.cadenceSteps, 3480)
        XCTAssertEqual(run.averageCadence, 174, accuracy: 1e-9)

        // No pedometer data, no workout.
        let bare = RunDraft(summary: RunSummary(date: start, distanceMeters: 100, durationSeconds: 50,
                                                averagePace: 0, splits: []))
        XCTAssertEqual(bare.cadenceSteps, 0)
        XCTAssertEqual(bare.workoutName, "")
    }
}
