import XCTest
@testable import MilePace

/// The make-a-loop geometry (v1.15 part B): the circle, the rescale, turns and ranking.
final class RouteGeneratorTests: XCTestCase {
    private let start = GeoPoint(lat: 40.7218, lon: -73.9420)
    private let target = 4_000.0

    private func radius(_ factor: Double = 0.8) -> Double {
        return target / (2 * Double.pi) * factor
    }

    private func angleGap(_ a: Double, _ b: Double) -> Double {
        return abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    // MARK: Circle

    func testThreeWaypointsOnACircleThroughTheStart() {
        for heading in [0.0, 120.0, 240.0] {
            let points = RouteGenerator.waypoints(start: start, distanceMeters: target, headingDegrees: heading)
            XCTAssertEqual(points.count, 3)
            let center = RouteGeometry.destination(from: start, bearingDegrees: heading, meters: radius())
            // The start is on the circle, and so is every waypoint.
            XCTAssertEqual(RouteGeometry.distance(center, start), radius(), accuracy: radius() * 0.005)
            for point in points {
                XCTAssertEqual(RouteGeometry.distance(center, point), radius(), accuracy: radius() * 0.005)
            }
        }
    }

    func testTheStartLiesOppositeTheHeadingAndTheWaypointsAreAQuarterTurnApart() {
        let heading = 120.0
        let center = RouteGeometry.destination(from: start, bearingDegrees: heading, meters: radius())
        XCTAssertLessThan(angleGap(RouteGeometry.bearing(from: center, to: start), heading + 180), 1)
        let points = RouteGenerator.waypoints(start: start, distanceMeters: target, headingDegrees: heading)
        for (index, point) in points.enumerated() {
            let expected = heading + 180 + 90 * Double(index + 1)
            XCTAssertLessThan(angleGap(RouteGeometry.bearing(from: center, to: point), expected), 1, "waypoint \(index)")
        }
    }

    func testTheMiddleWaypointIsAcrossTheCircleFromTheStart() {
        let points = RouteGenerator.waypoints(start: start, distanceMeters: target, headingDegrees: 0)
        XCTAssertEqual(RouteGeometry.distance(start, points[1]), 2 * radius(), accuracy: radius() * 0.01)
        XCTAssertEqual(RouteGeometry.distance(start, points[0]), radius() * 2.0.squareRoot(), accuracy: radius() * 0.01)
    }

    func testTheRadiusFactorScalesTheCircle() {
        let wide = RouteGenerator.waypoints(start: start, distanceMeters: target, headingDegrees: 0, radiusFactor: 1.0)
        let narrow = RouteGenerator.waypoints(start: start, distanceMeters: target, headingDegrees: 0, radiusFactor: 0.5)
        XCTAssertEqual(RouteGeometry.distance(start, wide[1]), 2 * radius(1.0), accuracy: 5)
        XCTAssertEqual(RouteGeometry.distance(start, narrow[1]), 2 * radius(0.5), accuracy: 5)
    }

    func testBearingAndDestinationAgree() {
        let there = RouteGeometry.destination(from: start, bearingDegrees: 90, meters: 1_000)
        XCTAssertEqual(RouteGeometry.distance(start, there), 1_000, accuracy: 1)
        XCTAssertLessThan(angleGap(RouteGeometry.bearing(from: start, to: there), 90), 0.5)
        let north = RouteGeometry.destination(from: start, bearingDegrees: 0, meters: 1_000)
        XCTAssertGreaterThan(north.lat, start.lat)
        XCTAssertEqual(north.lon, start.lon, accuracy: 0.000_001)
    }

    // MARK: Rescale

    func testTheNextFactorScalesByTargetOverMeasured() {
        XCTAssertEqual(RouteGenerator.nextRadiusFactor(current: 0.8, target: 4_000, measured: 5_000), 0.64, accuracy: 0.0001)
        XCTAssertEqual(RouteGenerator.nextRadiusFactor(current: 0.8, target: 4_000, measured: 3_200), 1.0, accuracy: 0.0001)
    }

    func testTheNextFactorIsClamped() {
        XCTAssertEqual(RouteGenerator.nextRadiusFactor(current: 1.0, target: 1_000, measured: 5_000), 0.4, accuracy: 0.0001)
        XCTAssertEqual(RouteGenerator.nextRadiusFactor(current: 1.0, target: 5_000, measured: 1_000), 1.2, accuracy: 0.0001)
    }

    func testAnUnusableMeasurementKeepsTheFactor() {
        XCTAssertEqual(RouteGenerator.nextRadiusFactor(current: 0.8, target: 4_000, measured: 0), 0.8, accuracy: 0.0001)
        XCTAssertEqual(RouteGenerator.nextRadiusFactor(current: 0.8, target: 4_000, measured: Double.nan), 0.8, accuracy: 0.0001)
    }

    func testRescalingConvergesTowardTheTarget() {
        // A made-up street grid whose loop is not quite proportional to the circle.
        func measured(_ factor: Double) -> Double {
            return target * (0.9 + 0.5 * factor) * factor / 0.8
        }
        var factor = RouteGenerator.defaultRadiusFactor
        var errors: [Double] = []
        for _ in 0..<RouteGenerator.maxTries {
            let length = measured(factor)
            errors.append(abs(length - target) / target)
            factor = RouteGenerator.nextRadiusFactor(current: factor, target: target, measured: length)
        }
        XCTAssertLessThan(errors[1], errors[0])
        XCTAssertLessThan(errors[2], errors[1])
        XCTAssertLessThan(errors[2], RouteGenerator.tolerance)
    }

    func testTheRequestBudgetIsThreeTriesOfFourLegs() {
        XCTAssertEqual(RouteGenerator.maxTries * RouteGenerator.legsPerTry, RouteGenerator.maxRequests)
        XCTAssertEqual(RouteGenerator.maxRequests, 12)
        XCTAssertEqual(RouteGenerator.headings.map { $0.degrees }, [0, 120, 240])
    }

    // MARK: Names

    func testLoopName() {
        XCTAssertEqual(RouteGenerator.loopName(meters: 4 * metersPerMile, heading: "north"), "loop 4.0 mi, north")
        XCTAssertEqual(RouteGenerator.loopName(meters: 2.46 * metersPerMile, heading: "southwest"), "loop 2.5 mi, southwest")
    }

    // MARK: Turns

    /// Corners of a square, 400 m a side, going north, east, south and west.
    private var square: [GeoPoint] {
        var points = [start]
        for bearing in [0.0, 90, 180, 270] {
            if let last = points.last {
                points.append(RouteGeometry.destination(from: last, bearingDegrees: bearing, meters: 400))
            }
        }
        return points
    }

    func testAStraightPathHasNoTurns() {
        let line = [start, RouteGeometry.destination(from: start, bearingDegrees: 30, meters: 1_000)]
        XCTAssertEqual(RouteGenerator.turns(in: line), 0)
    }

    func testASquareHasThreeCorners() {
        XCTAssertEqual(RouteGenerator.turns(in: square), 3)
    }

    func testAGentleCurveHasNoTurns() {
        let center = RouteGeometry.destination(from: start, bearingDegrees: 0, meters: 300)
        var circle: [GeoPoint] = []
        for step in 0...72 {
            let bearing = 180 + Double(step) * 5
            circle.append(RouteGeometry.destination(from: center, bearingDegrees: bearing.truncatingRemainder(dividingBy: 360), meters: 300))
        }
        XCTAssertEqual(RouteGenerator.turns(in: circle), 0)
    }

    // MARK: Ranking

    private func candidate(_ id: Int, meters: Double, turns: Int) -> LoopCandidate {
        return LoopCandidate(id: id,
                             headingName: "north",
                             points: [],
                             stops: [],
                             meters: meters,
                             targetMeters: 4_000,
                             turns: turns)
    }

    func testTheCloserDistanceWins() {
        let close = candidate(0, meters: 4_040, turns: 30)
        let far = candidate(1, meters: 4_400, turns: 2)
        XCTAssertTrue(RouteGenerator.isBetter(close, than: far))
        XCTAssertFalse(RouteGenerator.isBetter(far, than: close))
    }

    func testFewerTurnsBreakNearTies() {
        let smooth = candidate(0, meters: 4_100, turns: 4)
        let busy = candidate(1, meters: 4_040, turns: 20)
        XCTAssertTrue(RouteGenerator.isBetter(smooth, than: busy))
    }

    func testRankedPutsTheBestFirst() {
        let order = RouteGenerator.ranked([candidate(0, meters: 4_500, turns: 2),
                                           candidate(1, meters: 4_020, turns: 9),
                                           candidate(2, meters: 4_050, turns: 3)])
        XCTAssertEqual(order.map { $0.id }, [2, 1, 0])
        XCTAssertTrue(RouteGenerator.ranked([]).isEmpty)
    }

    func testErrorFractionAndName() {
        let item = candidate(0, meters: 4 * metersPerMile, turns: 0)
        XCTAssertEqual(item.name, "loop 4.0 mi, north")
        XCTAssertEqual(candidate(0, meters: 4_200, turns: 0).errorFraction, 0.05, accuracy: 0.0001)
    }
}
