import XCTest
@testable import MilePace

/// Where Today sends the runner (v1.15) and the sunrise and sunset it relies on.
final class RouteRecommendationTests: XCTestCase {
    private func catalog() throws -> RouteCatalog {
        let loaded = RouteCatalogLoader.load(bundle: Bundle(for: PlanStore.self))
        return try XCTUnwrap(loaded, "routes.json is missing from the app bundle or does not parse")
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = hour
        parts.minute = minute
        return try XCTUnwrap(calendar.date(from: parts))
    }

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func pick(_ kind: SessionKind,
                      miles: Double? = nil,
                      timed: Bool = false,
                      now: Date? = nil,
                      sunrise: Date? = nil,
                      sunset: Date? = nil,
                      resolved: [String: Double] = [:]) throws -> RouteRecommendation.Pick? {
        return RouteRecommendation.pick(kind: kind,
                                        plannedMiles: miles,
                                        isTimedRoadWorkout: timed,
                                        now: now ?? noon,
                                        sunrise: sunrise,
                                        sunset: sunset,
                                        resolved: resolved,
                                        catalog: try catalog())
    }

    // MARK: Track and road

    func testTrackSessionsGoToTheTrack() throws {
        for kind in [SessionKind.track, .timeTrial, .race] {
            let result = try XCTUnwrap(try pick(kind))
            XCTAssertEqual(result.routeId, "mccarren-track")
            XCTAssertEqual(result.note, "lane 1 = 400 m")
        }
    }

    func testTheTrackIsStillTheTrackAfterSunsetButTheNoteChanges() throws {
        let sunset = noon.addingTimeInterval(-3_600)
        let result = try XCTUnwrap(try pick(.track, now: noon, sunset: sunset))
        XCTAssertEqual(result.routeId, "mccarren-track")
        XCTAssertEqual(result.note, "the track is open dawn to dusk")
    }

    func testTheTrackNoteChangesBeforeSunriseToo() throws {
        let sunrise = noon.addingTimeInterval(3_600)
        let result = try XCTUnwrap(try pick(.timeTrial, now: noon, sunrise: sunrise))
        XCTAssertEqual(result.note, "the track is open dawn to dusk")
    }

    func testDaylightKeepsTheLaneNote() throws {
        let result = try XCTUnwrap(try pick(.race,
                                            now: noon,
                                            sunrise: noon.addingTimeInterval(-18_000),
                                            sunset: noon.addingTimeInterval(18_000)))
        XCTAssertEqual(result.note, "lane 1 = 400 m")
    }

    func testRoadWorkoutsGoToThePark() throws {
        let result = try XCTUnwrap(try pick(.road, miles: 4, timed: false))
        XCTAssertEqual(result.routeId, "mccarren-loop")
        XCTAssertNil(result.note)
        let timed = try XCTUnwrap(try pick(.road, miles: 4, timed: true))
        XCTAssertEqual(timed.routeId, "mccarren-loop")
    }

    // MARK: Distance

    func testEasyRunPicksTheLoopRepeatedToTheDistance() throws {
        let catalog = try self.catalog()
        let resolved = ["mcgolrick-loop": 0.6, "mccarren-loop": 2.2, "transmitter": 3.4]
        let result = try XCTUnwrap(try pick(.easy, miles: 2.4, resolved: resolved))
        XCTAssertEqual(result.routeId, "mcgolrick-loop")
        let name = try XCTUnwrap(catalog.name(forId: "mcgolrick-loop"))
        XCTAssertEqual(result.label, name + " \u{00D7} 4 (2.4 mi)")
    }

    func testAnEasyRouteOfTheRightLengthIsTakenAsIs() throws {
        let catalog = try self.catalog()
        let resolved = ["transmitter": 3.0, "nature-walk": 1.4]
        let result = try XCTUnwrap(try pick(.easy, miles: 3, resolved: resolved))
        XCTAssertEqual(result.routeId, "transmitter")
        XCTAssertEqual(result.label, try XCTUnwrap(catalog.name(forId: "transmitter")))
    }

    func testALongRunPrefersARouteTaggedLong() throws {
        let resolved = ["waterfront": 6.2, "transmitter": 6.0]
        let result = try XCTUnwrap(try pick(.long, miles: 6, resolved: resolved))
        XCTAssertEqual(result.routeId, "waterfront")
    }

    func testARouteOutsideFifteenPercentIsNotUsed() throws {
        // 4.0 mi is 20 % under 5 mi.
        let result = try XCTUnwrap(try pick(.easy, miles: 5, resolved: ["transmitter": 4.0]))
        XCTAssertNil(result.routeId)
        XCTAssertEqual(result.label, "any 5 mi route")
    }

    func testARouteJustInsideFifteenPercentIsUsed() throws {
        let result = try XCTUnwrap(try pick(.easy, miles: 4, resolved: ["transmitter": 3.5]))
        XCTAssertEqual(result.routeId, "transmitter")
    }

    func testNothingResolvedFallsBackToAnyRoute() throws {
        let result = try XCTUnwrap(try pick(.easy, miles: 4))
        XCTAssertNil(result.routeId)
        XCTAssertEqual(result.label, "any 4 mi route")
        let fractional = try XCTUnwrap(try pick(.other, miles: 3.5))
        XCTAssertEqual(fractional.label, "any 3.5 mi route")
    }

    func testTheClosestOptionWins() throws {
        let resolved = ["transmitter": 3.4, "cooper-park": 3.1]
        let result = try XCTUnwrap(try pick(.easy, miles: 3, resolved: resolved))
        XCTAssertEqual(result.routeId, "cooper-park")
    }

    func testTheTrackAndHillRoutesAreNeverPickedForAnEasyRun() throws {
        let resolved = ["mccarren-track": 3.0, "kosciuszko": 3.0, "wburg-bridge": 3.0]
        let result = try XCTUnwrap(try pick(.easy, miles: 3, resolved: resolved))
        XCTAssertNil(result.routeId)
    }

    func testNoPlannedMilesMeansNoRecommendation() throws {
        XCTAssertNil(try pick(.easy, miles: nil))
        XCTAssertNil(try pick(.long, miles: 0))
    }

    // MARK: Sunrise and sunset

    private func assertMinutes(_ date: Date, _ expected: Date, _ message: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(date.timeIntervalSince(expected), 0, accuracy: 3 * 60, message, file: file, line: line)
    }

    private var newYork: TimeZone {
        return TimeZone(identifier: "America/New_York") ?? TimeZone.current
    }

    func testSummerSolsticeInNewYork() throws {
        // 5:25 am and 8:31 pm EDT.
        let day = try XCTUnwrap(SolarTimes.times(on: try utc(2026, 6, 21, 16, 0),
                                                 latitude: 40.7128,
                                                 longitude: -74.0060,
                                                 timeZone: newYork))
        assertMinutes(day.sunrise, try utc(2026, 6, 21, 9, 25), "sunrise")
        assertMinutes(day.sunset, try utc(2026, 6, 22, 0, 31), "sunset")
    }

    func testWinterSolsticeInNewYork() throws {
        // 7:16 am and 4:32 pm EST.
        let day = try XCTUnwrap(SolarTimes.times(on: try utc(2026, 12, 21, 17, 0),
                                                 latitude: 40.7128,
                                                 longitude: -74.0060,
                                                 timeZone: newYork))
        assertMinutes(day.sunrise, try utc(2026, 12, 21, 12, 16), "sunrise")
        assertMinutes(day.sunset, try utc(2026, 12, 21, 21, 32), "sunset")
    }

    func testTheSunRisesBeforeItSets() throws {
        let day = try XCTUnwrap(SolarTimes.times(on: try utc(2026, 10, 7, 16, 0),
                                                 latitude: 40.73,
                                                 longitude: -73.95,
                                                 timeZone: newYork))
        XCTAssertLessThan(day.sunrise, day.sunset)
        let hours = day.sunset.timeIntervalSince(day.sunrise) / 3_600
        XCTAssertEqual(hours, 11.5, accuracy: 0.5)
    }

    func testDaysGetLongerFromWinterToSummer() throws {
        let winter = try XCTUnwrap(SolarTimes.times(on: try utc(2026, 12, 21, 17, 0), latitude: 40.73, longitude: -73.95, timeZone: newYork))
        let summer = try XCTUnwrap(SolarTimes.times(on: try utc(2026, 6, 21, 16, 0), latitude: 40.73, longitude: -73.95, timeZone: newYork))
        XCTAssertGreaterThan(summer.sunset.timeIntervalSince(summer.sunrise),
                             winter.sunset.timeIntervalSince(winter.sunrise) + 4 * 3_600)
    }

    func testThereIsNoSunsetInThePolarDay() throws {
        XCTAssertNil(SolarTimes.times(on: try utc(2026, 6, 21, 12, 0), latitude: 80, longitude: 0, timeZone: TimeZone(identifier: "UTC") ?? TimeZone.current))
    }

    func testJulianDateOfTheEpoch() {
        // 2000-01-01 12:00 UT is JD 2451545.0, so 0h UT is 2451544.5.
        XCTAssertEqual(SolarTimes.julianDate(year: 2000, month: 1, day: 1), 2_451_544.5, accuracy: 0.0001)
    }
}
