import XCTest
@testable import MilePace

/// Distances, projection onto a polyline, progress along a route and resampling (v1.15).
final class RouteGeometryTests: XCTestCase {
    private let metersPerDegree = 111_194.9

    /// A point `north` meters north and `east` meters east of 40.0 N, -74.0 E (flat approximation).
    private func point(north: Double, east: Double) -> GeoPoint {
        let lat = 40.0 + north / metersPerDegree
        let lon = -74.0 + east / (metersPerDegree * cos(40.0 * Double.pi / 180))
        return GeoPoint(lat: lat, lon: lon)
    }

    private func assertClose(_ value: Double, _ expected: Double, percent: Double,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(value, expected, accuracy: abs(expected) * percent / 100, file: file, line: line)
    }

    // MARK: Distance

    func testADegreeOfLatitudeIsAbout111Kilometers() {
        let d = RouteGeometry.distance(GeoPoint(lat: 40, lon: -74), GeoPoint(lat: 41, lon: -74))
        assertClose(d, 111_195, percent: 0.5)
    }

    func testADegreeOfLongitudeShrinksWithLatitude() {
        let d = RouteGeometry.distance(GeoPoint(lat: 40, lon: -74), GeoPoint(lat: 40, lon: -73))
        assertClose(d, 111_195 * cos(40 * Double.pi / 180), percent: 0.5)
    }

    func testDistanceFromAPointToItselfIsZero() {
        let p = GeoPoint(lat: 40.7, lon: -73.95)
        XCTAssertEqual(RouteGeometry.distance(p, p), 0, accuracy: 0.0001)
    }

    func testAKnownCityPair() {
        // Times Square to the Brooklyn Bridge: about 5.85 km (5.77 km north-south, 0.96 km east-west).
        let d = RouteGeometry.distance(GeoPoint(lat: 40.7580, lon: -73.9855), GeoPoint(lat: 40.7061, lon: -73.9969))
        XCTAssertEqual(d, 5_850, accuracy: 100)
    }

    func testLengthSumsTheSegments() {
        let line = [point(north: 0, east: 0), point(north: 1_000, east: 0), point(north: 1_000, east: 500)]
        assertClose(RouteGeometry.length(of: line), 1_500, percent: 0.5)
        XCTAssertEqual(RouteGeometry.length(of: []), 0)
        XCTAssertEqual(RouteGeometry.length(of: [point(north: 0, east: 0)]), 0)
    }

    // MARK: Projection

    /// 1000 m north, then 1000 m east.
    private var lShape: [GeoPoint] {
        return [point(north: 0, east: 0), point(north: 1_000, east: 0), point(north: 1_000, east: 1_000)]
    }

    func testProjectionOnTheFirstLeg() throws {
        let result = try XCTUnwrap(RouteGeometry.project(point(north: 300, east: 20), onto: lShape))
        XCTAssertEqual(result.alongMeters, 300, accuracy: 3)
        XCTAssertEqual(result.offsetMeters, 20, accuracy: 3)
    }

    func testProjectionOnTheSecondLeg() throws {
        let result = try XCTUnwrap(RouteGeometry.project(point(north: 1_050, east: 400), onto: lShape))
        XCTAssertEqual(result.alongMeters, 1_400, accuracy: 4)
        XCTAssertEqual(result.offsetMeters, 50, accuracy: 4)
    }

    func testProjectionBeyondTheEndsClampsToTheEnds() throws {
        let before = try XCTUnwrap(RouteGeometry.project(point(north: -100, east: 0), onto: lShape))
        XCTAssertEqual(before.alongMeters, 0, accuracy: 0.5)
        XCTAssertEqual(before.offsetMeters, 100, accuracy: 3)
        let after = try XCTUnwrap(RouteGeometry.project(point(north: 1_000, east: 1_200), onto: lShape))
        XCTAssertEqual(after.alongMeters, 2_000, accuracy: 4)
        XCTAssertEqual(after.offsetMeters, 200, accuracy: 4)
    }

    func testProjectionOnNothingAndOnOnePoint() throws {
        XCTAssertNil(RouteGeometry.project(point(north: 0, east: 0), onto: []))
        let single = try XCTUnwrap(RouteGeometry.project(point(north: 30, east: 0), onto: [point(north: 0, east: 0)]))
        XCTAssertEqual(single.alongMeters, 0, accuracy: 0.001)
        XCTAssertEqual(single.offsetMeters, 30, accuracy: 1)
    }

    // MARK: Progress

    /// 1000 m north and the same way back.
    private var outAndBack: [GeoPoint] {
        return [point(north: 0, east: 0), point(north: 1_000, east: 0), point(north: 0, east: 0)]
    }

    func testWithoutAPreviousValueTheFirstPassWins() throws {
        let result = try XCTUnwrap(RouteGeometry.progress(of: point(north: 500, east: 0),
                                                          on: outAndBack,
                                                          previousAlong: nil))
        XCTAssertEqual(result.alongMeters, 500, accuracy: 3)
    }

    func testTheWayBackCountsAsTheSecondHalf() throws {
        let result = try XCTUnwrap(RouteGeometry.progress(of: point(north: 800, east: 0),
                                                          on: outAndBack,
                                                          previousAlong: 1_000))
        XCTAssertEqual(result.alongMeters, 1_200, accuracy: 4)
    }

    func testJitterNeverMovesProgressBack() throws {
        let result = try XCTUnwrap(RouteGeometry.progress(of: point(north: 480, east: 0),
                                                          on: outAndBack,
                                                          previousAlong: 500))
        XCTAssertEqual(result.alongMeters, 500, accuracy: 0.001)
    }

    func testFollowingAWholeOutAndBackEndsNearTheEnd() throws {
        var track: [GeoPoint] = []
        var north = 0.0
        while north <= 1_000 {
            track.append(point(north: north, east: 2))
            north += 10
        }
        north = 990
        while north >= 0 {
            track.append(point(north: north, east: 2))
            north -= 10
        }
        let along = try XCTUnwrap(RouteGeometry.follow(track: track, on: outAndBack, startingAlong: nil))
        XCTAssertEqual(along, 2_000, accuracy: 60)
    }

    func testOffsetGrowsWhenOffTheRoute() throws {
        let result = try XCTUnwrap(RouteGeometry.progress(of: point(north: 500, east: 120),
                                                          on: outAndBack,
                                                          previousAlong: 400))
        XCTAssertEqual(result.offsetMeters, 120, accuracy: 4)
    }

    // MARK: Resample

    func testResamplingAStraightLine() {
        let line = [point(north: 0, east: 0), point(north: 1_000, east: 0)]
        let samples = RouteGeometry.resample(line, every: 100)
        XCTAssertEqual(samples.count, 11)
        XCTAssertEqual(RouteGeometry.distance(samples[0], line[0]), 0, accuracy: 0.01)
        XCTAssertEqual(RouteGeometry.distance(samples[10], line[1]), 0, accuracy: 1)
        for index in 1..<samples.count {
            XCTAssertEqual(RouteGeometry.distance(samples[index - 1], samples[index]), 100, accuracy: 1)
        }
    }

    func testResamplingKeepsTheEndWhenItIsNotOnAStep() {
        let line = [point(north: 0, east: 0), point(north: 250, east: 0)]
        let samples = RouteGeometry.resample(line, every: 100)
        XCTAssertEqual(samples.count, 4)
        XCTAssertEqual(RouteGeometry.distance(samples[3], line[1]), 0, accuracy: 1)
    }

    func testResamplingCarriesTheRemainderAroundACorner() {
        let samples = RouteGeometry.resample(lShape, every: 300)
        // Steps at 300, 600, 900, 1200, 1500 and 1800 along the path, then the end at 2000.
        XCTAssertEqual(samples.count, 8)
        // The 900 m and 1200 m steps are 100 m before and 200 m after the corner: a chord of about 224 m.
        XCTAssertEqual(RouteGeometry.distance(samples[3], samples[4]), 223.6, accuracy: 5)
    }

    func testResamplingATinyOrBadInputReturnsItUnchanged() {
        let one = [point(north: 0, east: 0)]
        XCTAssertEqual(RouteGeometry.resample(one, every: 50), one)
        let two = [point(north: 0, east: 0), point(north: 10, east: 0)]
        XCTAssertEqual(RouteGeometry.resample(two, every: 0), two)
        XCTAssertEqual(RouteGeometry.resample(two, every: 50).count, 2)
    }
}
