import XCTest
@testable import MilePace

final class LiveRouteSegmentsTests: XCTestCase {
    private func point(_ index: Int, segmentStart: Bool = false) -> RoutePoint {
        return RoutePoint(lat: 40 + Double(index) * 0.0001,
                          lon: -75,
                          t: Double(index) * 2.5,
                          d: Double(index) * 10,
                          segmentStart: segmentStart)
    }

    func testEmptyRouteGivesNoSegments() {
        XCTAssertTrue(LiveRouteSegments.split([]).isEmpty)
    }

    func testSingleSegmentStaysWhole() {
        let route = [point(0, segmentStart: true), point(1), point(2), point(3)]
        let pieces = LiveRouteSegments.split(route)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0], route)
    }

    func testSplitsWhereTheRunResumed() {
        let route = [point(0, segmentStart: true), point(1), point(2),
                     point(3, segmentStart: true), point(4), point(5)]
        let pieces = LiveRouteSegments.split(route)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].map { $0.d }, [0, 10, 20])
        XCTAssertEqual(pieces[1].map { $0.d }, [30, 40, 50])
        // The resumed point begins the second piece and is not shared with the first.
        XCTAssertTrue(pieces[1][0].segmentStart)
    }

    func testOnePointSegmentIsDropped() {
        let route = [point(0, segmentStart: true), point(1), point(2),
                     point(3, segmentStart: true),
                     point(4, segmentStart: true), point(5)]
        let pieces = LiveRouteSegments.split(route)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces[0].map { $0.d }, [0, 10, 20])
        XCTAssertEqual(pieces[1].map { $0.d }, [40, 50])
    }

    func testLoneFirstPointGivesNoSegments() {
        XCTAssertTrue(LiveRouteSegments.split([point(0, segmentStart: true)]).isEmpty)
    }
}
