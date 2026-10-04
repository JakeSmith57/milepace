import XCTest
@testable import MilePace

final class PaceCalculatorTests: XCTestCase {
    /// Meters per degree of latitude for the haversine radius used by PaceCalculator.
    private let metersPerDegree = 2.0 * Double.pi * 6_371_000.0 / 360.0
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func sample(second: Double, meters: Double, accuracy: Double = 5) -> PaceSample {
        return PaceSample(timestamp: t0.addingTimeInterval(second),
                          latitude: 40.0 + meters / metersPerDegree,
                          longitude: -75.0,
                          horizontalAccuracy: accuracy,
                          speed: 4)
    }

    func testSteadyPaceAtFourMetersPerSecond() throws {
        var calc = PaceCalculator()
        calc.start(at: t0)
        for second in 0...60 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        XCTAssertEqual(calc.totalDistance, 240, accuracy: 0.5)
        let current = try XCTUnwrap(calc.currentPace)
        XCTAssertEqual(current, 402.336, accuracy: 1.0)
        let average = try XCTUnwrap(calc.averagePace(at: t0.addingTimeInterval(60)))
        XCTAssertEqual(average, 402.336, accuracy: 1.0)
    }

    func testCurrentPaceNeedsEnoughDistance() {
        var calc = PaceCalculator()
        calc.start(at: t0)
        for second in 0...3 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        XCTAssertNil(calc.currentPace)
    }

    func testInaccurateSamplesAreIgnored() {
        var calc = PaceCalculator()
        calc.start(at: t0)
        for second in 0...10 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        // Poor accuracy and far away: must not count.
        calc.add(sample(second: 11, meters: 500, accuracy: 50))
        // Invalid (negative) accuracy: must not count.
        calc.add(sample(second: 11, meters: 500, accuracy: -1))
        calc.add(sample(second: 12, meters: 48))
        XCTAssertEqual(calc.totalDistance, 48, accuracy: 0.05)
    }

    func testTeleportIsRejected() {
        var calc = PaceCalculator()
        calc.start(at: t0)
        for second in 0...10 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        // One kilometer in one second is far above 9 m/s.
        calc.add(sample(second: 11, meters: 1040))
        XCTAssertEqual(calc.totalDistance, 40, accuracy: 0.05)
        calc.add(sample(second: 12, meters: 48))
        XCTAssertEqual(calc.totalDistance, 48, accuracy: 0.05)
    }

    func testNonIncreasingTimestampsAreIgnored() {
        var calc = PaceCalculator()
        calc.start(at: t0)
        calc.add(sample(second: 0, meters: 0))
        calc.add(sample(second: 5, meters: 20))
        calc.add(sample(second: 5, meters: 30))
        calc.add(sample(second: 4, meters: 30))
        XCTAssertEqual(calc.totalDistance, 20, accuracy: 0.05)
    }

    func testPauseIsExcluded() {
        var calc = PaceCalculator()
        calc.start(at: t0)
        for second in 0...10 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        calc.pause(at: t0.addingTimeInterval(10))
        XCTAssertTrue(calc.isPaused)

        // Samples while paused are ignored.
        for second in 11...19 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        XCTAssertEqual(calc.totalDistance, 40, accuracy: 0.05)
        XCTAssertEqual(calc.elapsed(at: t0.addingTimeInterval(15)), 10, accuracy: 0.001)

        calc.resume(at: t0.addingTimeInterval(20))
        XCTAssertFalse(calc.isPaused)
        for second in 20...30 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        // First post-resume sample only anchors; 10 s of paused time is excluded from elapsed.
        XCTAssertEqual(calc.totalDistance, 40 + 40, accuracy: 0.1)
        XCTAssertEqual(calc.elapsed(at: t0.addingTimeInterval(30)), 20, accuracy: 0.001)
    }

    func testMileSplitEmittedAtOneMile() throws {
        var calc = PaceCalculator()
        calc.start(at: t0)
        var emitted: [Double] = []
        for second in 0...410 {
            emitted += calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        XCTAssertEqual(calc.splits.count, 1)
        XCTAssertEqual(emitted.count, 1)
        let split = try XCTUnwrap(calc.splits.first)
        XCTAssertEqual(split, 402.336, accuracy: 0.05)
        XCTAssertGreaterThan(calc.totalDistance, metersPerMile)
    }

    func testSecondMileSplit() {
        var calc = PaceCalculator()
        calc.start(at: t0)
        for second in 0...820 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        XCTAssertEqual(calc.splits.count, 2)
        if calc.splits.count == 2 {
            XCTAssertEqual(calc.splits[1], 402.336, accuracy: 0.05)
        }
    }

    func testHaversineDistance() {
        let a = sample(second: 0, meters: 0)
        let b = sample(second: 1, meters: 100)
        XCTAssertEqual(PaceCalculator.distance(from: a, to: b), 100, accuracy: 0.01)
    }
}
