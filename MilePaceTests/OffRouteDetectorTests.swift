import XCTest
@testable import MilePace

/// The off-route rule (v1.15 part B): over 40 m for 20 s is off, under 25 m is back.
final class OffRouteDetectorTests: XCTestCase {
    func testStayingOnTheRouteSaysNothing() {
        var detector = OffRouteDetector()
        for second in 0..<60 {
            XCTAssertNil(detector.feed(offsetMeters: 10, time: Double(second)))
        }
        XCTAssertFalse(detector.isOff)
    }

    func testOffComesAfterTwentySecondsAboveFortyMeters() {
        var detector = OffRouteDetector()
        XCTAssertNil(detector.feed(offsetMeters: 50, time: 100))
        XCTAssertNil(detector.feed(offsetMeters: 55, time: 110))
        XCTAssertNil(detector.feed(offsetMeters: 60, time: 119.9))
        XCTAssertEqual(detector.feed(offsetMeters: 60, time: 120), .off)
        XCTAssertTrue(detector.isOff)
    }

    func testOffIsSaidOncePerExcursion() {
        var detector = OffRouteDetector()
        _ = detector.feed(offsetMeters: 80, time: 0)
        XCTAssertEqual(detector.feed(offsetMeters: 80, time: 20), .off)
        for second in 21..<80 {
            XCTAssertNil(detector.feed(offsetMeters: 90, time: Double(second)))
        }
    }

    func testAShortExcursionIsForgotten() {
        var detector = OffRouteDetector()
        _ = detector.feed(offsetMeters: 60, time: 0)
        _ = detector.feed(offsetMeters: 60, time: 15)
        // Back under 40 m: the 20 seconds start over.
        XCTAssertNil(detector.feed(offsetMeters: 30, time: 16))
        XCTAssertNil(detector.feed(offsetMeters: 60, time: 17))
        XCTAssertNil(detector.feed(offsetMeters: 60, time: 36))
        XCTAssertEqual(detector.feed(offsetMeters: 60, time: 37), .off)
    }

    func testExactlyFortyMetersIsNotOff() {
        var detector = OffRouteDetector()
        XCTAssertNil(detector.feed(offsetMeters: 40, time: 0))
        XCTAssertNil(detector.feed(offsetMeters: 40, time: 100))
        XCTAssertFalse(detector.isOff)
    }

    func testBackNeedsToBeUnderTwentyFiveMeters() {
        var detector = OffRouteDetector()
        _ = detector.feed(offsetMeters: 60, time: 0)
        XCTAssertEqual(detector.feed(offsetMeters: 60, time: 20), .off)
        XCTAssertNil(detector.feed(offsetMeters: 35, time: 25))
        XCTAssertNil(detector.feed(offsetMeters: 25, time: 26))
        XCTAssertTrue(detector.isOff)
        XCTAssertEqual(detector.feed(offsetMeters: 24, time: 27), .back)
        XCTAssertFalse(detector.isOff)
    }

    func testASecondExcursionSaysOffAgain() {
        var detector = OffRouteDetector()
        _ = detector.feed(offsetMeters: 60, time: 0)
        XCTAssertEqual(detector.feed(offsetMeters: 60, time: 20), .off)
        XCTAssertEqual(detector.feed(offsetMeters: 5, time: 40), .back)
        XCTAssertNil(detector.feed(offsetMeters: 70, time: 50))
        XCTAssertEqual(detector.feed(offsetMeters: 70, time: 70), .off)
    }

    func testBetweenTheLimitsOnTheRouteResetsTheCount() {
        var detector = OffRouteDetector()
        _ = detector.feed(offsetMeters: 60, time: 0)
        // 30 m is under the off limit, so the count restarts even though it is over the back limit.
        _ = detector.feed(offsetMeters: 30, time: 10)
        XCTAssertNil(detector.feed(offsetMeters: 60, time: 25))
    }

    func testInvalidFixesChangeNothing() {
        var detector = OffRouteDetector()
        _ = detector.feed(offsetMeters: 60, time: 0)
        XCTAssertNil(detector.feed(offsetMeters: 5, time: 10, isValid: false))
        XCTAssertNil(detector.feed(offsetMeters: Double.nan, time: 12))
        XCTAssertEqual(detector.feed(offsetMeters: 60, time: 20), .off)
    }

    func testTimeGoingBackwardsStartsTheCountOver() {
        var detector = OffRouteDetector()
        _ = detector.feed(offsetMeters: 60, time: 100)
        XCTAssertNil(detector.feed(offsetMeters: 60, time: 5))
        XCTAssertNil(detector.feed(offsetMeters: 60, time: 24))
        XCTAssertEqual(detector.feed(offsetMeters: 60, time: 25), .off)
    }
}

/// Following a route from a run's saved fixes (v1.15 part B).
@MainActor
final class RouteFollowStateTests: XCTestCase {
    private let metersPerDegree = 111_194.9

    private func fix(north: Double, east: Double, t: Double) -> RoutePoint {
        return RoutePoint(lat: 40.0 + north / metersPerDegree,
                          lon: -74.0 + east / (metersPerDegree * cos(40.0 * Double.pi / 180)),
                          t: t,
                          d: north)
    }

    /// 2000 m north.
    private var route: [GeoPoint] {
        return [GeoPoint(lat: 40.0, lon: -74.0), GeoPoint(lat: 40.0 + 2_000 / metersPerDegree, lon: -74.0)]
    }

    func testProgressFollowsTheRun() {
        let state = RouteFollowState()
        var fixes: [RoutePoint] = []
        for step in 0...50 {
            fixes.append(fix(north: Double(step) * 10, east: 3, t: Double(step) * 3))
        }
        let events = state.advance(liveRoute: fixes, on: route)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(state.along ?? -1, 500, accuracy: 5)
        XCTAssertEqual(state.offsetMeters ?? -1, 3, accuracy: 2)
    }

    func testStrayingForTwentySecondsSaysOffOnce() {
        let state = RouteFollowState()
        var fixes: [RoutePoint] = []
        for step in 0..<10 {
            fixes.append(fix(north: Double(step) * 10, east: 0, t: Double(step) * 3))
        }
        // Then 60 m to the side for 30 seconds of running.
        for step in 10..<22 {
            fixes.append(fix(north: 100, east: 60 + Double(step), t: Double(step) * 3))
        }
        let events = state.advance(liveRoute: fixes, on: route)
        XCTAssertEqual(events, [.off])
    }

    func testNewFixesContinueWhereItStopped() {
        let state = RouteFollowState()
        var fixes: [RoutePoint] = [fix(north: 0, east: 0, t: 0), fix(north: 100, east: 0, t: 30)]
        _ = state.advance(liveRoute: fixes, on: route)
        fixes.append(fix(north: 200, east: 0, t: 60))
        _ = state.advance(liveRoute: fixes, on: route)
        XCTAssertEqual(state.along ?? -1, 200, accuracy: 3)
        // A shorter list means a new run: start over.
        _ = state.advance(liveRoute: [fix(north: 20, east: 0, t: 0)], on: route)
        XCTAssertEqual(state.along ?? -1, 20, accuracy: 3)
    }

    func testResetForgetsTheProgress() {
        let state = RouteFollowState()
        _ = state.advance(liveRoute: [fix(north: 300, east: 0, t: 0)], on: route)
        XCTAssertNotNil(state.along)
        state.reset()
        XCTAssertNil(state.along)
        XCTAssertNil(state.offsetMeters)
    }
}
