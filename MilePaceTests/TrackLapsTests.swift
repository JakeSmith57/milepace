import XCTest
@testable import MilePace

/// Plain-language wording on the track screens (v1.16).
final class TrackLapsTests: XCTestCase {
    func testDescribeCommonDistances() {
        XCTAssertEqual(TrackLaps.describe(meters: 200), "half a lap")
        XCTAssertEqual(TrackLaps.describe(meters: 300), "\u{00BE} of a lap")
        XCTAssertEqual(TrackLaps.describe(meters: 400), "1 lap")
        XCTAssertEqual(TrackLaps.describe(meters: 600), "1\u{00BD} laps")
        XCTAssertEqual(TrackLaps.describe(meters: 800), "2 laps")
        XCTAssertEqual(TrackLaps.describe(meters: 1000), "2\u{00BD} laps")
        XCTAssertEqual(TrackLaps.describe(meters: 1200), "3 laps")
        XCTAssertEqual(TrackLaps.describe(meters: 1609), "4 laps + 9 m")
    }

    func testDescribeOtherDistances() {
        XCTAssertEqual(TrackLaps.describe(meters: 100), "a quarter lap")
        XCTAssertEqual(TrackLaps.describe(meters: 150), "150 m")
        XCTAssertEqual(TrackLaps.describe(meters: 500), "1\u{00BC} laps")
        XCTAssertEqual(TrackLaps.describe(meters: 1500), "3\u{00BE} laps")
        XCTAssertEqual(TrackLaps.describe(meters: 450), "1 lap + 50 m")
        XCTAssertEqual(TrackLaps.describe(meters: 0), "0 m")
    }

    func testStartNotes() {
        XCTAssertEqual(TrackLaps.startNote(meters: 200),
                       "start anywhere; finish half a lap later (directly across the track)")
        XCTAssertEqual(TrackLaps.startNote(meters: 400), "start and finish at the same line")
        XCTAssertEqual(TrackLaps.startNote(meters: 1609), "start and finish at the same line")
        XCTAssertEqual(TrackLaps.startNote(meters: 300), "start anywhere; finish \u{00BE} of a lap later")
        XCTAssertTrue(TrackLaps.laneNote.contains("lane 1"))
        XCTAssertTrue(TrackLaps.laneNote.contains("7 m"))
    }

    func testTargetsAlwaysHaveUnits() {
        XCTAssertEqual(TrackLaps.timeWithUnit(55.5), "55.5 s")
        XCTAssertEqual(TrackLaps.timeWithUnit(104), "1:44.0")
        XCTAssertEqual(TrackLaps.timeWithUnit(59.96), "1:00.0")
        XCTAssertEqual(TrackLaps.unit(forSeconds: 55.5), "s")
        XCTAssertEqual(TrackLaps.unit(forSeconds: 60), "")
        XCTAssertEqual(TrackLaps.targetText(seconds: 55.5, meters: 200), "target 55.5 s per 200 m")
        XCTAssertEqual(TrackLaps.targetText(seconds: 104, meters: 400), "target 1:44.0 per 400 m")
        XCTAssertEqual(TrackLaps.lapTargetText(lap: 1, seconds: 104), "lap 1 target 1:44.0")
    }

    func testRepHeader() {
        XCTAssertEqual(TrackLaps.repHeader(rep: 2, total: 4, meters: 200), "rep 2 of 4 \u{00B7} 200 m \u{00B7} half a lap")
    }
}
