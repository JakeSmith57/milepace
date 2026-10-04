import XCTest
@testable import MilePace

final class DistanceCuesTests: XCTestCase {
    func testIntervalMetersAndTitles() throws {
        XCTAssertNil(CueInterval.off.meters)
        XCTAssertEqual(try XCTUnwrap(CueInterval.quarter.meters), metersPerMile / 4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(CueInterval.half.meters), metersPerMile / 2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(CueInterval.mile.meters), metersPerMile, accuracy: 1e-9)
        XCTAssertEqual(CueInterval.allCases.count, 4)
        XCTAssertEqual(CueInterval.quarter.cuesPerMile, 4)
        XCTAssertEqual(CueInterval.mile.spokenName, "Mile")
    }

    func testQuarterMileCuesAtFourMetersPerSecond() throws {
        let interval = try XCTUnwrap(CueInterval.quarter.meters)
        var tracker = DistanceCueTracker(intervalMeters: interval)
        XCTAssertTrue(tracker.update(distance: 0, elapsed: 0).isEmpty)

        var cues: [DistanceCue] = []
        for second in 1...310 {
            cues += tracker.update(distance: 4.0 * Double(second), elapsed: Double(second))
        }
        // 4 m/s covers 3 quarter miles (1207.008 m) in 301.752 s.
        XCTAssertEqual(cues.map { $0.index }, [1, 2, 3])
        for cue in cues {
            XCTAssertEqual(cue.splitSeconds, 100.584, accuracy: 0.01)
            XCTAssertEqual(cue.paceSecondsPerMile, 402.336, accuracy: 0.05)
        }
    }

    func testMultipleBoundariesInOneUpdate() throws {
        let interval = try XCTUnwrap(CueInterval.quarter.meters)
        var tracker = DistanceCueTracker(intervalMeters: interval)
        tracker.update(distance: 0, elapsed: 0)
        let cues = tracker.update(distance: 1000, elapsed: 250)
        XCTAssertEqual(cues.map { $0.index }, [1, 2])
        XCTAssertEqual(cues[0].splitSeconds, 100.584, accuracy: 0.001)
        XCTAssertEqual(cues[1].splitSeconds, 100.584, accuracy: 0.001)
        // Nothing new until the third boundary at 1207.008 m.
        XCTAssertTrue(tracker.update(distance: 1100, elapsed: 275).isEmpty)
    }

    func testNoCueBeforeFirstBoundaryAndAnchorOnly() {
        var tracker = DistanceCueTracker(intervalMeters: metersPerMile)
        XCTAssertTrue(tracker.update(distance: 0, elapsed: 0).isEmpty)
        XCTAssertTrue(tracker.update(distance: 800, elapsed: 200).isEmpty)
    }

    func testZoneVerdictPhrases() {
        let zone: ClosedRange<Double> = 400...410
        XCTAssertEqual(ZoneVerdict.phrase(pace: 405, zone: zone), "On target.")
        XCTAssertEqual(ZoneVerdict.phrase(pace: 396, zone: zone), "4 seconds fast.")
        XCTAssertEqual(ZoneVerdict.phrase(pace: 416, zone: zone), "6 seconds slow.")
        XCTAssertEqual(ZoneVerdict.phrase(pace: 399.9, zone: zone), "1 second fast.")
    }
}
