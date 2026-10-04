import XCTest
@testable import MilePace

final class PaceZonesTests: XCTestCase {
    func testAnchorRows() {
        let r412 = PaceZones.forMile(412)
        XCTAssertEqual(r412.easy, 575.0...630.0)
        XCTAssertEqual(r412.threshold, 478.0...483.0)
        XCTAssertEqual(r412.interval, 438.0...443.0)
        XCTAssertEqual(r412.rep400, 102.0...104.0)

        let r395 = PaceZones.forMile(395)
        XCTAssertEqual(r395.easy, 540.0...595.0)
        XCTAssertEqual(r395.threshold, 455.0...460.0)
        XCTAssertEqual(r395.interval, 418.0...423.0)
        XCTAssertEqual(r395.rep400, 97.0...99.0)

        let r365 = PaceZones.forMile(365)
        XCTAssertEqual(r365.easy, 510.0...565.0)
        XCTAssertEqual(r365.threshold, 423.0...428.0)
        XCTAssertEqual(r365.interval, 389.0...394.0)
        XCTAssertEqual(r365.rep400, 90.0...92.0)

        let r345 = PaceZones.forMile(345)
        XCTAssertEqual(r345.easy, 485.0...535.0)
        XCTAssertEqual(r345.threshold, 402.0...407.0)
        XCTAssertEqual(r345.interval, 370.0...375.0)
        XCTAssertEqual(r345.rep400, 85.0...87.0)

        let r330 = PaceZones.forMile(330)
        XCTAssertEqual(r330.easy, 465.0...515.0)
        XCTAssertEqual(r330.threshold, 388.0...393.0)
        XCTAssertEqual(r330.interval, 357.0...362.0)
        XCTAssertEqual(r330.rep400, 82.0...83.0)
    }

    func testInterpolationMidpointBetween395And365() {
        // 380 is exactly halfway between the 6:35 (395) and 6:05 (365) rows.
        let zones = PaceZones.forMile(380)
        XCTAssertEqual(zones.easy.lowerBound, 525, accuracy: 1e-9)
        XCTAssertEqual(zones.easy.upperBound, 580, accuracy: 1e-9)
        XCTAssertEqual(zones.threshold.lowerBound, 439, accuracy: 1e-9)
        XCTAssertEqual(zones.threshold.upperBound, 444, accuracy: 1e-9)
        XCTAssertEqual(zones.interval.lowerBound, 403.5, accuracy: 1e-9)
        XCTAssertEqual(zones.interval.upperBound, 408.5, accuracy: 1e-9)
        XCTAssertEqual(zones.rep400.lowerBound, 93.5, accuracy: 1e-9)
        XCTAssertEqual(zones.rep400.upperBound, 95.5, accuracy: 1e-9)
    }

    func testInterpolationIsMonotonic() {
        let slower = PaceZones.forMile(400)
        let faster = PaceZones.forMile(350)
        XCTAssertGreaterThan(slower.easy.lowerBound, faster.easy.lowerBound)
        XCTAssertGreaterThan(slower.interval.upperBound, faster.interval.upperBound)
        XCTAssertGreaterThan(slower.rep400.lowerBound, faster.rep400.lowerBound)
    }

    func testClamping() {
        XCTAssertEqual(PaceZones.forMile(300), PaceZones.forMile(330))
        XCTAssertEqual(PaceZones.forMile(0), PaceZones.forMile(330))
        XCTAssertEqual(PaceZones.forMile(500), PaceZones.forMile(420))
        // Between the slowest anchor (412) and the clamp ceiling (420) the 412 row applies.
        XCTAssertEqual(PaceZones.forMile(420), PaceZones.forMile(412))
        XCTAssertEqual(PaceZones.forMile(.nan), PaceZones.forMile(412))
    }

    func testTargetSeconds() {
        let zones = PaceZones.forMile(412)
        // Threshold midpoint is 480.5 s per mile.
        XCTAssertEqual(zones.targetSeconds(distanceMeters: metersPerMile, zone: .threshold), 480.5, accuracy: 1e-9)
        XCTAssertEqual(zones.targetSeconds(distanceMeters: metersPerMile / 2, zone: .threshold), 240.25, accuracy: 1e-9)
        // R midpoint is 103 s per 400 m.
        XCTAssertEqual(zones.targetSeconds(distanceMeters: 400, zone: .repetition), 103, accuracy: 1e-9)
        XCTAssertEqual(zones.targetSeconds(distanceMeters: 200, zone: .repetition), 51.5, accuracy: 1e-9)
        // Interval midpoint is 440.5 s per mile; 800 m is about half a mile.
        XCTAssertEqual(zones.targetSeconds(distanceMeters: 800, zone: .interval),
                       440.5 * 800 / metersPerMile, accuracy: 1e-9)
    }

    func testGoalConstants() {
        XCTAssertEqual(PaceZones.goalMileSeconds, 330)
        XCTAssertEqual(PaceZones.goalPer400, 82.5)
        XCTAssertEqual(PaceZones.goalMileSeconds / 4, PaceZones.goalPer400 as Double, accuracy: 1e-9)
    }
}
