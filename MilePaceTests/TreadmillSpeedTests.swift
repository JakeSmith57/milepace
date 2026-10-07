import XCTest
@testable import MilePace

final class TreadmillSpeedTests: XCTestCase {
    func testPaceToMph() throws {
        XCTAssertEqual(try XCTUnwrap(TreadmillSpeed.mph(pace: 480)), 7.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(TreadmillSpeed.mph(pace: 360)), 10.0, accuracy: 1e-9)
        XCTAssertEqual(TreadmillSpeed.mphText(pace: 480), "7.5")
        XCTAssertEqual(TreadmillSpeed.mphText(pace: 360), "10.0")
        XCTAssertEqual(TreadmillSpeed.mphText(pace: 330), "10.9")
    }

    func testInvalidPaceHasNoSpeed() {
        XCTAssertNil(TreadmillSpeed.mph(pace: 0))
        XCTAssertNil(TreadmillSpeed.mph(pace: -5))
        XCTAssertNil(TreadmillSpeed.mph(pace: Double.nan))
        XCTAssertNil(TreadmillSpeed.mph(pace: Double.infinity))
        XCTAssertEqual(TreadmillSpeed.mphText(pace: 0), "--")
    }

    func testMphToPaceText() {
        XCTAssertEqual(TreadmillSpeed.paceText(mph: 7.5), "8:00")
        XCTAssertEqual(TreadmillSpeed.paceText(mph: 10.0), "6:00")
        XCTAssertEqual(TreadmillSpeed.paceText(mph: 0), "--:--")
        XCTAssertEqual(TreadmillSpeed.paceText(mph: -3), "--:--")
    }

    func testTextRoundTrips() throws {
        for pace in [360.0, 420.0, 480.0, 540.0, 600.0] {
            let text = TreadmillSpeed.mphText(pace: pace)
            let speed = try XCTUnwrap(Double(text))
            // One decimal of mph is under 7 seconds of pace at these speeds.
            let back = try XCTUnwrap(parseTime(TreadmillSpeed.paceText(mph: speed)))
            XCTAssertEqual(back, pace, accuracy: 7)
        }
    }

    func testRangeTextPutsTheFasterPaceAtTheTop() {
        // 7:52 to 8:08 per mile is 7.4 to 7.6 mph.
        XCTAssertEqual(TreadmillSpeed.rangeText(472...488), "7.4\u{2013}7.6 mph")
        // A range that rounds to one speed shows one number.
        XCTAssertEqual(TreadmillSpeed.rangeText(479...481), "7.5 mph")
    }
}

final class TreadmillWorkoutTests: XCTestCase {
    func testOnlyTimedWorkoutsRemain() {
        let all = RoadWorkoutPresets.all
        let timed = TreadmillWorkouts.timeBased(all)
        XCTAssertFalse(timed.isEmpty)
        XCTAssertLessThan(timed.count, all.count)
        for spec in timed {
            if case .distance = spec.length {
                XCTFail("distance workout kept: " + spec.name)
            }
        }
        let dropped = all.filter { !TreadmillWorkouts.isTimeBased($0) }
        XCTAssertEqual(dropped.count, all.count - timed.count)
        XCTAssertTrue(dropped.contains(where: { $0.name == "3 \u{00D7} 1 mi threshold" }))
    }

    func testIsTimeBased() {
        let timed = RoadWorkoutSpec(name: "t", reps: 2, length: .time(seconds: 300), target: .threshold, recoverySeconds: 60)
        let far = RoadWorkoutSpec(name: "d", reps: 2, length: .distance(meters: 1609), target: .threshold, recoverySeconds: 60)
        XCTAssertTrue(TreadmillWorkouts.isTimeBased(timed))
        XCTAssertFalse(TreadmillWorkouts.isTimeBased(far))
    }
}

final class TreadmillCueTests: XCTestCase {
    func testMarksEveryFiveMinutes() {
        XCTAssertNil(TreadmillCue.newMark(elapsed: 299, lastMark: 0))
        XCTAssertEqual(TreadmillCue.newMark(elapsed: 300, lastMark: 0), 5)
        XCTAssertNil(TreadmillCue.newMark(elapsed: 359, lastMark: 5))
        XCTAssertNil(TreadmillCue.newMark(elapsed: 599, lastMark: 5))
        XCTAssertEqual(TreadmillCue.newMark(elapsed: 600, lastMark: 5), 10)
    }

    func testALateTickGetsTheLatestMarkOnce() {
        XCTAssertEqual(TreadmillCue.newMark(elapsed: 905, lastMark: 5), 15)
        XCTAssertNil(TreadmillCue.newMark(elapsed: 910, lastMark: 15))
    }

    func testBadElapsedHasNoMark() {
        XCTAssertNil(TreadmillCue.newMark(elapsed: -1, lastMark: 0))
        XCTAssertNil(TreadmillCue.newMark(elapsed: Double.nan, lastMark: 0))
    }

    func testSpokenText() {
        XCTAssertEqual(TreadmillCue.spokenText(minutes: 10, cadence: nil), "10 minutes.")
        XCTAssertEqual(TreadmillCue.spokenText(minutes: 10, cadence: 171.6), "10 minutes. Cadence 172.")
        XCTAssertEqual(TreadmillCue.spokenText(minutes: 5, cadence: 0), "5 minutes.")
    }
}

final class TreadmillDraftTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func draft(treadmill: Bool) -> RunDraft {
        return RunDraft(start: start,
                        distanceMeters: 0,
                        movingSeconds: 1500,
                        splits: [],
                        route: [],
                        cadenceSteps: 4000,
                        workoutName: "",
                        isTreadmill: treadmill)
    }

    func testTreadmillFlagRoundTrips() throws {
        let original = draft(treadmill: true)
        let data = try XCTUnwrap(original.encoded())
        let decoded = try XCTUnwrap(RunDraft.decode(data))
        XCTAssertTrue(decoded.isTreadmill)
        XCTAssertEqual(decoded, original)
    }

    func testOldDraftsDecodeAsOutdoor() throws {
        // A draft written by v1.13: no isTest and no isTreadmill.
        let json = """
        {"start":800000000,"distanceMeters":3200,"movingSeconds":1500,"splits":[],"route":[],"cadenceSteps":4000,"workoutName":""}
        """
        let decoded = try XCTUnwrap(RunDraft.decode(Data(json.utf8)))
        XCTAssertFalse(decoded.isTreadmill)
        XCTAssertFalse(decoded.isTest)
        XCTAssertEqual(decoded.distanceMeters, 3200)
    }

    func testRecordAndSummaryCarryTheSurface() {
        XCTAssertTrue(draft(treadmill: true).makeRecord().isTreadmill)
        XCTAssertFalse(draft(treadmill: false).makeRecord().isTreadmill)

        var summary = RunSummary(date: start, distanceMeters: 0, durationSeconds: 1500, averagePace: 0, splits: [])
        XCTAssertFalse(RunDraft(summary: summary).isTreadmill)
        summary.isTreadmill = true
        XCTAssertTrue(RunDraft(summary: summary).isTreadmill)
    }

    func testTreadmillSummaryText() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        var run = draft(treadmill: true)
        let text = run.summaryText(calendar: utc)
        XCTAssertTrue(text.hasPrefix("unfinished treadmill run from "))
        XCTAssertTrue(text.hasSuffix(": 25:00"))
        run.distanceMeters = 2.31 * metersPerMile
        XCTAssertTrue(run.summaryText(calendar: utc).hasSuffix(": 25:00, \u{2248} 2.31 mi"))
    }
}
