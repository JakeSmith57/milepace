import XCTest
@testable import MilePace

final class ZoneGuardTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)
    private let zone: ClosedRange<Double> = 400...410

    func testDefaultTimings() {
        var zoneGuard = ZoneGuard()
        _ = zoneGuard.update(pace: 380, zone: zone, now: t0)
        let early = zoneGuard.update(pace: 380, zone: zone, now: t0.addingTimeInterval(12))
        XCTAssertNil(early)
        let cue = zoneGuard.update(pace: 380, zone: zone, now: t0.addingTimeInterval(20))
        XCTAssertEqual(cue, ZoneGuard.Cue.easyUp)
    }

    func testCustomTimings() {
        var zoneGuard = ZoneGuard(outsideSecondsRequired: 12, minSecondsBetweenCues: 30)
        let first = zoneGuard.update(pace: 380, zone: zone, now: t0)
        XCTAssertNil(first)
        let early = zoneGuard.update(pace: 380, zone: zone, now: t0.addingTimeInterval(11))
        XCTAssertNil(early)
        let cue = zoneGuard.update(pace: 380, zone: zone, now: t0.addingTimeInterval(12))
        XCTAssertEqual(cue, ZoneGuard.Cue.easyUp)
        let tooSoon = zoneGuard.update(pace: 380, zone: zone, now: t0.addingTimeInterval(30))
        XCTAssertNil(tooSoon)
        let again = zoneGuard.update(pace: 380, zone: zone, now: t0.addingTimeInterval(42))
        XCTAssertEqual(again, ZoneGuard.Cue.easyUp)
    }

    func testSlowCueAndReset() {
        var zoneGuard = ZoneGuard(outsideSecondsRequired: 12, minSecondsBetweenCues: 30)
        _ = zoneGuard.update(pace: 430, zone: zone, now: t0)
        let cue = zoneGuard.update(pace: 430, zone: zone, now: t0.addingTimeInterval(15))
        XCTAssertEqual(cue, ZoneGuard.Cue.pickItUp)
        zoneGuard.reset()
        let afterReset = zoneGuard.update(pace: 430, zone: zone, now: t0.addingTimeInterval(16))
        XCTAssertNil(afterReset)
    }
}
