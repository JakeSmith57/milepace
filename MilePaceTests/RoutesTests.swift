import XCTest
@testable import MilePace

/// The route catalog (v1.15): the shipped `routes.json`, the stop order of each shape, the cache rule and the
/// text helpers.
final class RoutesTests: XCTestCase {
    private func bundled() throws -> RouteCatalog {
        let catalog = RouteCatalogLoader.load(bundle: Bundle(for: PlanStore.self))
        return try XCTUnwrap(catalog, "routes.json is missing from the app bundle or does not parse")
    }

    // MARK: Catalog

    func testTheShippedFileDecodes() throws {
        let catalog = try bundled()
        XCTAssertEqual(catalog.version, 1)
        XCTAssertEqual(catalog.home, "17 Monitor St, Brooklyn, NY 11222")
        XCTAssertEqual(catalog.routes.count, 10)
    }

    func testRouteIdsAreUnique() throws {
        let ids = try bundled().routes.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEveryRouteStartsAtHomeAndHasWaypointsAndNotes() throws {
        for route in try bundled().routes {
            XCTAssertEqual(route.start, "home", route.id)
            XCTAssertFalse(route.waypoints.isEmpty, route.id)
            XCTAssertFalse(route.notes.isEmpty, route.id)
            XCTAssertFalse(route.tags.isEmpty, route.id)
        }
    }

    func testTheTrackRouteHasOneWaypointAndTheTrackShape() throws {
        let catalog = try bundled()
        let route = try XCTUnwrap(catalog.route(id: "mccarren-track"))
        XCTAssertEqual(route.shape, .track)
        XCTAssertEqual(route.waypoints.count, 1)
    }

    func testEveryRecommendationTargetExists() throws {
        let catalog = try bundled()
        for id in RouteRecommendation.targetIds {
            XCTAssertNotNil(catalog.route(id: id), id)
        }
    }

    func testAnUnknownIdHasNoRoute() throws {
        let catalog = try bundled()
        XCTAssertNil(catalog.route(id: "nowhere"))
        XCTAssertNil(catalog.name(forId: "nowhere"))
    }

    func testTheCatalogRoundTripsThroughJSON() throws {
        let catalog = try bundled()
        let data = try JSONEncoder().encode(catalog)
        XCTAssertEqual(RouteCatalogLoader.decode(data), catalog)
    }

    func testGarbageDoesNotDecode() {
        XCTAssertNil(RouteCatalogLoader.decode(Data("not json".utf8)))
    }

    // MARK: Legs

    func testALoopReturnsToTheStart() {
        let stops = RouteLegs.stops(start: "S", waypoints: ["a", "b"], shape: .loop)
        XCTAssertEqual(stops, ["S", "a", "b", "S"])
    }

    func testAnOutAndBackRetracesTheWaypointsWithoutRepeatingTheTurn() {
        XCTAssertEqual(RouteLegs.stops(start: "S", waypoints: ["a", "b"], shape: .outAndBack),
                       ["S", "a", "b", "a", "S"])
        XCTAssertEqual(RouteLegs.stops(start: "S", waypoints: ["a"], shape: .outAndBack),
                       ["S", "a", "S"])
        XCTAssertEqual(RouteLegs.stops(start: "S", waypoints: ["a", "b", "c"], shape: .outAndBack),
                       ["S", "a", "b", "c", "b", "a", "S"])
    }

    func testOneWayAndTrackEndAtTheLastWaypoint() {
        XCTAssertEqual(RouteLegs.stops(start: "S", waypoints: ["a", "b"], shape: .oneWay), ["S", "a", "b"])
        XCTAssertEqual(RouteLegs.stops(start: "S", waypoints: ["t"], shape: .track), ["S", "t"])
    }

    func testNoWaypointsStillGivesTheStart() {
        XCTAssertEqual(RouteLegs.stops(start: "S", waypoints: [], shape: .loop), ["S", "S"])
        XCTAssertEqual(RouteLegs.stops(start: "S", waypoints: [], shape: .oneWay), ["S"])
    }

    func testJoiningLegsDropsTheRepeatedJoint() {
        let a = GeoPoint(lat: 40.0, lon: -74.0)
        let b = GeoPoint(lat: 40.001, lon: -74.0)
        let c = GeoPoint(lat: 40.002, lon: -74.0)
        XCTAssertEqual(RoutePolyline.join([[a, b], [b, c]]), [a, b, c])
        XCTAssertEqual(RoutePolyline.join([]), [])
    }

    // MARK: Cache rule

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testAFreshRouteForTheSameHomeIsKept() {
        XCTAssertFalse(RouteCachePolicy.needsResolve(savedHome: "17 Monitor St, Brooklyn, NY 11222",
                                                     currentHome: "17 monitor st, brooklyn, ny 11222 ",
                                                     createdAt: now.addingTimeInterval(-30 * 86_400),
                                                     now: now))
    }

    func testAChangedHomeNeedsResolving() {
        XCTAssertTrue(RouteCachePolicy.needsResolve(savedHome: "17 Monitor St, Brooklyn, NY 11222",
                                                    currentHome: "1 Main St, Brooklyn, NY",
                                                    createdAt: now,
                                                    now: now))
    }

    func testARouteOlderThanNinetyDaysNeedsResolving() {
        XCTAssertFalse(RouteCachePolicy.needsResolve(savedHome: "a", currentHome: "a",
                                                     createdAt: now.addingTimeInterval(-89 * 86_400), now: now))
        XCTAssertTrue(RouteCachePolicy.needsResolve(savedHome: "a", currentHome: "a",
                                                    createdAt: now.addingTimeInterval(-91 * 86_400), now: now))
    }

    // MARK: Text

    func testDistanceText() {
        XCTAssertEqual(RouteFormat.distanceText(meters: 2.4 * metersPerMile, shape: .loop), "2.4 mi")
        XCTAssertEqual(RouteFormat.distanceText(meters: 0.6 * metersPerMile, shape: .track), "0.6 mi away")
        XCTAssertEqual(RouteFormat.distanceText(meters: 0, shape: .loop), "\u{2014}")
    }

    func testShortAddress() {
        XCTAssertEqual(RouteFormat.shortAddress("17 Monitor St, Brooklyn, NY 11222"), "17 Monitor St")
        XCTAssertEqual(RouteFormat.shortAddress("Home"), "Home")
    }

    func testTimeTextUsesThePace() {
        // 3 mi at 10:00 per mile, then 7 mi.
        XCTAssertEqual(RouteFormat.timeText(meters: 3 * metersPerMile, secondsPerMile: 600), "30 min")
        XCTAssertEqual(RouteFormat.timeText(meters: 7 * metersPerMile, secondsPerMile: 600), "1:10 h")
        XCTAssertEqual(RouteFormat.timeText(meters: 0, secondsPerMile: 600), "\u{2014}")
    }

    func testFollowText() {
        XCTAssertEqual(RouteFormat.followText(along: 1.2 * metersPerMile, total: 3.1 * metersPerMile), "1.2 / 3.1 mi")
        XCTAssertEqual(RouteFormat.followText(along: nil, total: 3.1 * metersPerMile), "-- / 3.1 mi")
        XCTAssertEqual(RouteFormat.followText(along: 9 * metersPerMile, total: 3.1 * metersPerMile), "3.1 / 3.1 mi")
    }

    func testMiddleOfARange() {
        XCTAssertEqual(RouteFormat.middle(of: 500...600), 550, accuracy: 0.001)
    }
}
