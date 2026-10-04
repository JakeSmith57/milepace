import XCTest
@testable import MilePace

final class RouteTests: XCTestCase {
    private let metersPerDegree = 2.0 * Double.pi * 6_371_000.0 / 360.0
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func sample(second: Double, meters: Double) -> PaceSample {
        return PaceSample(timestamp: t0.addingTimeInterval(second),
                          latitude: 40.0 + meters / metersPerDegree,
                          longitude: -75.0,
                          horizontalAccuracy: 5,
                          speed: 4)
    }

    private func point(_ index: Int, t: Double, segmentStart: Bool = false) -> RoutePoint {
        return RoutePoint(lat: 40 + Double(index) * 0.0001, lon: -75, t: t, d: Double(index) * 10,
                          segmentStart: segmentStart)
    }

    /// 40 points 10 m apart: 2.5 s per step (402 s/mi) except steps 14 through 23, which take 1.5 s.
    private func syntheticRoute() -> [RoutePoint] {
        var points: [RoutePoint] = []
        var time = 0.0
        for index in 0..<40 {
            if index > 0 {
                let step = index - 1
                time += (step >= 14 && step < 24) ? 1.5 : 2.5
            }
            points.append(point(index, t: time))
        }
        return points
    }

    // MARK: Recording

    func testRouteIsDownsampledToTenMeters() {
        var calc = PaceCalculator()
        calc.start(at: t0)
        for second in 0...60 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        let route = calc.route
        XCTAssertGreaterThan(route.count, 10)
        XCTAssertLessThan(route.count, 30)
        XCTAssertTrue(route[0].segmentStart)
        XCTAssertEqual(route[0].d, 0, accuracy: 0.001)
        XCTAssertEqual(route[0].t, 0, accuracy: 0.001)
        for index in 1..<route.count {
            XCTAssertGreaterThanOrEqual(route[index].d - route[index - 1].d, 10)
            XCTAssertFalse(route[index].segmentStart)
            XCTAssertGreaterThan(route[index].t, route[index - 1].t)
        }
    }

    func testResumeStartsNewSegment() {
        var calc = PaceCalculator()
        calc.start(at: t0)
        for second in 0...10 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        calc.pause(at: t0.addingTimeInterval(10))
        calc.resume(at: t0.addingTimeInterval(20))
        for second in 20...40 {
            calc.add(sample(second: Double(second), meters: 4.0 * Double(second)))
        }
        let starts = calc.route.enumerated().filter { $0.element.segmentStart }.map { $0.offset }
        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(starts.first, 0)
        if starts.count == 2 {
            let resumed = calc.route[starts[1]]
            // Moving time excludes the 10 s pause, and no distance is added across it.
            XCTAssertEqual(resumed.t, 10, accuracy: 0.001)
            XCTAssertEqual(resumed.d, 40, accuracy: 0.1)
        }
    }

    func testRouteIsCodable() throws {
        let original = [point(0, t: 0, segmentStart: true), point(1, t: 2.5)]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([RoutePoint].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: Pace bands

    func testFastMiddleSectionIsColoredFaster() {
        let segments = RouteSegments.colored(syntheticRoute(), averagePace: 402.336)
        XCTAssertEqual(segments.map { $0.band }, [.steady, .faster, .steady])
        XCTAssertEqual(segments.map { $0.id }, [0, 1, 2])
        // Points 0...12 steady, 13...25 faster, 26...39 steady; boundaries are shared.
        XCTAssertEqual(segments[0].points.count, 13)
        XCTAssertEqual(segments[1].points.count, 14)
        XCTAssertEqual(segments[2].points.count, 15)
    }

    func testAdjacentSegmentsShareBoundaryPoint() {
        let segments = RouteSegments.colored(syntheticRoute(), averagePace: 402.336)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].points.last, segments[1].points.first)
        XCTAssertEqual(segments[1].points.last, segments[2].points.first)
        XCTAssertEqual(segments[0].points.first?.d, 0)
        XCTAssertEqual(segments[2].points.last?.d, 390)
    }

    func testSegmentStartIsNotJoined() {
        var points: [RoutePoint] = []
        for index in 0..<10 {
            points.append(point(index, t: Double(index) * 2.5, segmentStart: index == 5))
        }
        let segments = RouteSegments.colored(points, averagePace: 402.336)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].points.count, 5)
        XCTAssertEqual(segments[1].points.count, 5)
        XCTAssertEqual(segments[0].points.last?.d, 40)
        XCTAssertEqual(segments[1].points.first?.d, 50)
        XCTAssertEqual(segments.map { $0.band }, [.steady, .steady])
    }

    func testSlowSectionAndDegenerateInputs() {
        var points: [RoutePoint] = []
        var time = 0.0
        for index in 0..<20 {
            if index > 0 { time += 4.0 }
            points.append(point(index, t: time))
        }
        // 4 s per 10 m is 644 s/mi, far slower than a 402 s/mi average.
        let slow = RouteSegments.colored(points, averagePace: 402.336)
        XCTAssertEqual(slow.map { $0.band }, [.slower])

        XCTAssertTrue(RouteSegments.colored([], averagePace: 400).isEmpty)
        let unknownAverage = RouteSegments.colored(points, averagePace: 0)
        XCTAssertEqual(unknownAverage.map { $0.band }, [.steady])
    }

    // MARK: Mile markers

    func testMileMarkers() {
        var points: [RoutePoint] = []
        for index in 0...33 {
            points.append(RoutePoint(lat: 40, lon: -75, t: Double(index) * 25, d: Double(index) * 100))
        }
        let markers = RouteSegments.mileMarkers(points)
        XCTAssertEqual(markers.map { $0.mile }, [1, 2])
        XCTAssertEqual(markers[0].point.d, 1700, accuracy: 0.001)
        XCTAssertEqual(markers[1].point.d, 3300, accuracy: 0.001)
        XCTAssertTrue(RouteSegments.mileMarkers([]).isEmpty)
    }
}
