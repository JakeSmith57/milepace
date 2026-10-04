import XCTest
@testable import MilePace

final class DopplerPaceTests: XCTestCase {
    /// Meters per degree of latitude for the haversine radius used by PaceCalculator.
    private let metersPerDegree = 2.0 * Double.pi * 6_371_000.0 / 360.0
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func sample(second: Double,
                        meters: Double,
                        accuracy: Double = 5,
                        speed: Double = -1,
                        speedAccuracy: Double = -1) -> PaceSample {
        return PaceSample(timestamp: t0.addingTimeInterval(second),
                          latitude: 40.0 + meters / metersPerDegree,
                          longitude: -75.0,
                          horizontalAccuracy: accuracy,
                          speed: speed,
                          speedAccuracy: speedAccuracy)
    }

    private func started() -> PaceCalculator {
        var calc = PaceCalculator()
        calc.start(at: t0)
        return calc
    }

    // MARK: Doppler pace

    func testDopplerPaceShowsOnTheFirstSample() throws {
        var calc = started()
        calc.add(sample(second: 0, meters: 0, speed: 3.5, speedAccuracy: 0.3))
        let pace = try XCTUnwrap(calc.currentPace)
        XCTAssertEqual(pace, 459.8, accuracy: 0.1)
        XCTAssertNil(calc.windowPace)

        calc.add(sample(second: 1, meters: 3.5, speed: 3.5, speedAccuracy: 0.3))
        calc.add(sample(second: 2, meters: 7.0, speed: 3.5, speedAccuracy: 0.3))
        let later = try XCTUnwrap(calc.currentPace)
        XCTAssertEqual(later, 459.8, accuracy: 0.1)
        XCTAssertEqual(try XCTUnwrap(calc.dopplerPace), 459.8, accuracy: 0.1)
    }

    func testDopplerStepReachesMostOfTheChangeInFourSeconds() throws {
        var calc = started()
        var meters = 0.0
        for second in 0...10 {
            meters = 3.5 * Double(second)
            calc.add(sample(second: Double(second), meters: meters, speed: 3.5, speedAccuracy: 0.3))
        }
        let before = try XCTUnwrap(calc.currentPace)
        XCTAssertEqual(before, 459.8, accuracy: 0.1)

        // Speed steps to 4.0 m/s (pace 402.3). Four seconds of new samples: seconds 11 to 14.
        for second in 11...14 {
            meters += 4.0
            calc.add(sample(second: Double(second), meters: meters, speed: 4.0, speedAccuracy: 0.3))
        }
        let after = try XCTUnwrap(calc.currentPace)
        let target = metersPerMile / 4.0
        let fraction = (before - after) / (before - target)
        XCTAssertGreaterThanOrEqual(fraction, 0.63)
        XCTAssertLessThan(fraction, 1.0)
    }

    func testStandingStillGivesNoPace() {
        var calc = started()
        for second in 0...5 {
            calc.add(sample(second: Double(second), meters: 0, speed: 0.2, speedAccuracy: 0.3))
        }
        XCTAssertNil(calc.dopplerPace)
        XCTAssertNil(calc.currentPace)
    }

    func testPoorSpeedAccuracyFallsBackToWindowPace() throws {
        var calc = started()
        for second in 0...30 {
            // The reported speed is wrong on purpose, but its accuracy is too poor to be trusted.
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second), speed: 3.5, speedAccuracy: 3.0))
        }
        XCTAssertNil(calc.dopplerPace)
        let pace = try XCTUnwrap(calc.currentPace)
        XCTAssertEqual(pace, 402.336, accuracy: 1.0)
        XCTAssertEqual(try XCTUnwrap(calc.windowPace), pace, accuracy: 0.0001)
    }

    func testUnknownSpeedBehavesLikeV11() throws {
        var withSpeed = started()
        var withoutSpeed = started()
        for second in 0...60 {
            let meters = 4.0 * Double(second)
            // v1.1 style: speed given, speed accuracy unknown.
            withSpeed.add(sample(second: Double(second), meters: meters, speed: 4, speedAccuracy: -1))
            // Speed unknown, speed accuracy given.
            withoutSpeed.add(sample(second: Double(second), meters: meters, speed: -1, speedAccuracy: 0.3))
        }
        XCTAssertNil(withSpeed.dopplerPace)
        XCTAssertNil(withoutSpeed.dopplerPace)
        XCTAssertEqual(withSpeed.totalDistance, withoutSpeed.totalDistance, accuracy: 0.0001)
        XCTAssertEqual(withSpeed.currentPace, withoutSpeed.currentPace)
        XCTAssertEqual(withSpeed.currentPace, withSpeed.windowPace)
        XCTAssertEqual(try XCTUnwrap(withSpeed.currentPace), 402.336, accuracy: 1.0)
    }

    func testDopplerGoesStaleAfterThreeSeconds() throws {
        var calc = started()
        // Doppler says 3.0 m/s (pace 536.4) while the positions move at 4 m/s (pace 402.3).
        for second in 0...10 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second), speed: 3.0, speedAccuracy: 0.3))
        }
        // Then the speed accuracy gets too poor to use.
        for second in 11...14 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second), speed: 3.0, speedAccuracy: 3.0))
            if second == 12 {
                // Two seconds after the last Doppler update: still the Doppler pace.
                XCTAssertEqual(try XCTUnwrap(calc.currentPace), metersPerMile / 3.0, accuracy: 0.5)
            }
        }
        // Four seconds after: back to the trailing-window pace.
        XCTAssertEqual(try XCTUnwrap(calc.currentPace), 402.336, accuracy: 1.0)
    }

    func testDopplerUsesLooserPositionGateThanDistance() {
        var calc = started()
        calc.add(sample(second: 0, meters: 0, accuracy: 30, speed: 3.5, speedAccuracy: 0.3))
        XCTAssertNotNil(calc.dopplerPace)
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.rejected(.accuracy))
        XCTAssertEqual(calc.totalDistance, 0, accuracy: 0.0001)

        var other = started()
        other.add(sample(second: 0, meters: 0, accuracy: 60, speed: 3.5, speedAccuracy: 0.3))
        XCTAssertNil(other.dopplerPace)
    }

    func testPauseAndResumeResetDoppler() {
        var calc = started()
        for second in 0...5 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second), speed: 4, speedAccuracy: 0.3))
        }
        XCTAssertNotNil(calc.dopplerPace)
        calc.pause(at: t0.addingTimeInterval(5))
        XCTAssertNil(calc.dopplerPace)
        XCTAssertNil(calc.currentPace)

        calc.resume(at: t0.addingTimeInterval(20))
        XCTAssertNil(calc.dopplerPace)
        // A sample from before the resume is ignored by Doppler too.
        calc.add(sample(second: 19, meters: 80, speed: 4, speedAccuracy: 0.3))
        XCTAssertNil(calc.dopplerPace)
        calc.add(sample(second: 21, meters: 84, speed: 4, speedAccuracy: 0.3))
        XCTAssertNotNil(calc.dopplerPace)
    }

    // MARK: Last outcome

    func testOutcomeAnchoredThenAccepted() {
        var calc = started()
        calc.add(sample(second: 0, meters: 0))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.anchored)
        calc.add(sample(second: 1, meters: 4))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.accepted)
    }

    func testOutcomeAccuracy() {
        var calc = started()
        calc.add(sample(second: 0, meters: 0))
        calc.add(sample(second: 1, meters: 4, accuracy: 50))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.rejected(.accuracy))
        calc.add(sample(second: 2, meters: 8, accuracy: -1))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.rejected(.accuracy))
    }

    func testOutcomeOutOfOrder() {
        var calc = started()
        calc.add(sample(second: 0, meters: 0))
        calc.add(sample(second: 5, meters: 20))
        calc.add(sample(second: 5, meters: 30))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.rejected(.outOfOrder))
        calc.add(sample(second: 4, meters: 30))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.rejected(.outOfOrder))
    }

    func testOutcomePausedAndBeforeStart() {
        var calc = started()
        calc.add(sample(second: -5, meters: 0))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.rejected(.beforeStart))

        calc.add(sample(second: 0, meters: 0))
        calc.pause(at: t0.addingTimeInterval(2))
        calc.add(sample(second: 3, meters: 12))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.rejected(.paused))
    }

    func testOutcomeJumpThenReanchor() {
        var calc = started()
        for second in 0...10 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        for second in 11...14 {
            calc.add(sample(second: Double(second), meters: 5000))
            XCTAssertEqual(calc.lastOutcome, SampleOutcome.rejected(.jump))
        }
        // The fifth jump in a row is taken as real and becomes the new reference point.
        calc.add(sample(second: 15, meters: 5000))
        XCTAssertEqual(calc.lastOutcome, SampleOutcome.anchored)
        XCTAssertEqual(calc.totalDistance, 40, accuracy: 0.05)
    }

    func testRejectReasonCases() {
        XCTAssertEqual(RejectReason.allCases.count, 5)
        XCTAssertEqual(RejectReason.outOfOrder.rawValue, "outOfOrder")
    }
}
