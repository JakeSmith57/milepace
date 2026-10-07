import XCTest
@testable import MilePace

/// Finding routes you repeat from saved runs (v1.15 part B).
final class RouteMatchingTests: XCTestCase {
    private let metersPerDegree = 111_194.9
    private let home = GeoPoint(lat: 40.0, lon: -74.0)

    private func point(north: Double, east: Double, fromNorth: Double = 0, fromEast: Double = 0) -> GeoPoint {
        let n = north + fromNorth
        let e = east + fromEast
        return GeoPoint(lat: 40.0 + n / metersPerDegree,
                        lon: -74.0 + e / (metersPerDegree * cos(40.0 * Double.pi / 180)))
    }

    /// Points every 10 m along straight legs through the given corners (north, east in meters).
    private func path(_ corners: [(Double, Double)], shiftNorth: Double = 0, shiftEast: Double = 0) -> [GeoPoint] {
        var points: [GeoPoint] = []
        for index in 1..<corners.count {
            let a = corners[index - 1]
            let b = corners[index]
            let length = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
            let steps = max(1, Int(length / 10))
            for step in 0..<steps {
                let fraction = Double(step) / Double(steps)
                points.append(point(north: a.0 + (b.0 - a.0) * fraction,
                                    east: a.1 + (b.1 - a.1) * fraction,
                                    fromNorth: shiftNorth,
                                    fromEast: shiftEast))
            }
        }
        if let last = corners.last {
            points.append(point(north: last.0, east: last.1, fromNorth: shiftNorth, fromEast: shiftEast))
        }
        return points
    }

    /// 1000 m north, then 1000 m east.
    private var lRoute: [(Double, Double)] {
        return [(0, 0), (1_000, 0), (1_000, 1_000)]
    }

    // MARK: Same route

    func testTheSamePathIsTheSameRoute() {
        XCTAssertTrue(RouteMatching.isSameRoute(path(lRoute), path(lRoute)))
    }

    func testAPathAFewMetersOffIsStillTheSameRoute() {
        XCTAssertTrue(RouteMatching.isSameRoute(path(lRoute), path(lRoute, shiftNorth: 8, shiftEast: 12)))
    }

    func testAPathFiftyMetersOffIsNot() {
        XCTAssertFalse(RouteMatching.isSameRoute(path(lRoute), path(lRoute, shiftNorth: 0, shiftEast: 50)))
    }

    func testAnotherStartIsNotTheSameRoute() {
        // The same shape, starting 500 m away.
        XCTAssertFalse(RouteMatching.isSameRoute(path(lRoute), path(lRoute, shiftNorth: 500, shiftEast: 0)))
    }

    func testTheSameStartWithAnotherWayIsNot() {
        let other: [(Double, Double)] = [(0, 0), (-1_000, 0), (-1_000, -1_000)]
        XCTAssertFalse(RouteMatching.isSameRoute(path(lRoute), path(other)))
    }

    func testEightyPercentSharedIsEnoughAndLessIsNot() {
        let straight = path([(0, 0), (1_000, 0)])
        // 900 m shared, then a 100 m detour: about 86 % of each path is near the other.
        XCTAssertTrue(RouteMatching.isSameRoute(straight, path([(0, 0), (900, 0), (900, 100)])))
        // 700 m shared, then 300 m away: about 71 %.
        XCTAssertFalse(RouteMatching.isSameRoute(straight, path([(0, 0), (700, 0), (700, 300)])))
    }

    func testTooFewPointsIsNeverARoute() {
        XCTAssertFalse(RouteMatching.isSameRoute([], path(lRoute)))
        XCTAssertFalse(RouteMatching.isSameRoute([point(north: 0, east: 0)], [point(north: 0, east: 0)]))
    }

    func testCoverageCountsThePointsNearTheOtherPath() {
        let line = path([(0, 0), (1_000, 0)])
        let samples = [point(north: 100, east: 5), point(north: 500, east: 10), point(north: 900, east: 200), point(north: 950, east: 300)]
        XCTAssertEqual(RouteMatching.coverage(of: samples, on: line, within: 30), 0.5, accuracy: 0.0001)
        XCTAssertEqual(RouteMatching.coverage(of: [], on: line, within: 30), 0)
    }

    // MARK: Groups

    private let day: TimeInterval = 86_400
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func run(_ id: String, daysAfter: Double, seconds: Double, points: [GeoPoint]) -> RunPath {
        return RunPath(id: id,
                       date: t0.addingTimeInterval(daysAfter * day),
                       seconds: seconds,
                       meters: RouteGeometry.length(of: points),
                       points: points)
    }

    func testGroupsListOnlyRoutesRunAtLeastTwice() {
        let farLoop: [(Double, Double)] = [(5_000, 5_000), (6_000, 5_000), (6_000, 6_000)]
        let paths = [
            run("a1", daysAfter: 0, seconds: 900, points: path(lRoute)),
            run("b1", daysAfter: 1, seconds: 1_200, points: path(farLoop)),
            run("a2", daysAfter: 3, seconds: 840, points: path(lRoute, shiftNorth: 5, shiftEast: 5)),
            run("a3", daysAfter: 6, seconds: 870, points: path(lRoute)),
            run("c1", daysAfter: 7, seconds: 600, points: path(farLoop, shiftNorth: 4, shiftEast: 0))
        ]
        let found = RouteMatching.groups(paths: paths, home: home)
        XCTAssertEqual(found.count, 2)
        // Newest route first: the far loop was last run on day 7.
        XCTAssertEqual(found[0].key, "b1")
        XCTAssertEqual(found[0].count, 2)
        XCTAssertEqual(found[1].key, "a1")
        XCTAssertEqual(found[1].count, 3)
        XCTAssertEqual(found[1].bestSeconds, 840, accuracy: 0.001)
        XCTAssertEqual(found[1].lastDate, t0.addingTimeInterval(6 * day))
    }

    func testAGroupUsesTheLatestRunForItsPathAndDistance() {
        let older = path(lRoute)
        let newer = path(lRoute, shiftNorth: 6, shiftEast: 0)
        let found = RouteMatching.groups(paths: [run("x", daysAfter: 0, seconds: 900, points: older),
                                                 run("y", daysAfter: 2, seconds: 880, points: newer)],
                                         home: home)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].points, newer)
        XCTAssertEqual(found[0].meters, RouteGeometry.length(of: newer), accuracy: 0.001)
    }

    func testRunsGivenOutOfOrderAreGroupedByDate() {
        let found = RouteMatching.groups(paths: [run("late", daysAfter: 5, seconds: 900, points: path(lRoute)),
                                                 run("early", daysAfter: 1, seconds: 910, points: path(lRoute))],
                                         home: home)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].key, "early")
    }

    func testOneRunOfEachIsNoRoute() {
        let other: [(Double, Double)] = [(0, 0), (-1_000, 0), (-1_000, -1_000)]
        XCTAssertTrue(RouteMatching.groups(paths: [run("a", daysAfter: 0, seconds: 1, points: path(lRoute)),
                                                   run("b", daysAfter: 1, seconds: 1, points: path(other))],
                                           home: home).isEmpty)
        XCTAssertTrue(RouteMatching.groups(paths: [], home: home).isEmpty)
    }

    func testTheDefaultNameSaysHomeOrGivesTheStart() {
        let near = RouteMatching.defaultName(meters: 5_000, start: point(north: 100, east: 0), home: home)
        XCTAssertEqual(near, "3.1 mi from home")
        let away = RouteMatching.defaultName(meters: 5_000, start: GeoPoint(lat: 40.5, lon: -74.25), home: home)
        XCTAssertEqual(away, "3.1 mi from 40.500, -74.250")
    }

    // MARK: Plain-value input

    private func input(_ id: String, daysAfter: Double, points: [GeoPoint]) throws -> RunPathInput {
        var route: [RoutePoint] = []
        for (index, point) in points.enumerated() {
            route.append(RoutePoint(lat: point.lat, lon: point.lon, t: Double(index) * 3, d: Double(index) * 10))
        }
        return RunPathInput(id: id,
                            date: t0.addingTimeInterval(daysAfter * day),
                            seconds: 900,
                            meters: RouteGeometry.length(of: points),
                            routeData: try JSONEncoder().encode(route))
    }

    func testGroupingFromSavedRouteData() throws {
        let inputs = [try input("one", daysAfter: 0, points: path(lRoute)),
                      try input("two", daysAfter: 4, points: path(lRoute))]
        let found = RouteMatching.groups(from: inputs, home: home)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].count, 2)
    }

    func testShortOrEmptyRoutesAreSkipped() throws {
        let tiny = try input("tiny", daysAfter: 0, points: path([(0, 0), (100, 0)]))
        let empty = RunPathInput(id: "empty", date: t0, seconds: 1, meters: 0, routeData: Data())
        XCTAssertNil(RouteMatching.decode(tiny))
        XCTAssertNil(RouteMatching.decode(empty))
        XCTAssertTrue(RouteMatching.groups(from: [tiny, tiny, empty], home: home).isEmpty)
    }

    func testTheSignatureChangesWithTheRuns() throws {
        let a = try input("a", daysAfter: 0, points: path(lRoute))
        let b = try input("b", daysAfter: 1, points: path(lRoute))
        XCTAssertEqual(YourRoutes.signature([a, b]), YourRoutes.signature([a, b]))
        XCTAssertNotEqual(YourRoutes.signature([a]), YourRoutes.signature([a, b]))
        XCTAssertNotEqual(YourRoutes.signature([a, b]), YourRoutes.signature([a, try input("c", daysAfter: 2, points: path(lRoute))]))
    }

    // MARK: Names

    func testNamesAreStoredAndCleared() {
        let key = "test-route-key-\(UUID().uuidString)"
        addTeardownBlock {
            RouteNameStore.set("", for: key)
        }
        XCTAssertNil(RouteNameStore.name(for: key))
        RouteNameStore.set("  my loop ", for: key)
        XCTAssertEqual(RouteNameStore.name(for: key), "my loop")
        RouteNameStore.set("   ", for: key)
        XCTAssertNil(RouteNameStore.name(for: key))
    }
}
