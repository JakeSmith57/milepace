import XCTest
@testable import MilePace

/// The v1.15 export addition: the route a run followed.
final class ProgressExportRouteTests: XCTestCase {
    private var calendar: Calendar {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return utc
    }

    private func date(_ month: Int, _ day: Int) throws -> Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = month
        parts.day = day
        parts.hour = 12
        return try XCTUnwrap(calendar.date(from: parts))
    }

    private func run(_ date: Date, routeName: String = "") -> ExportRun {
        return ExportRun(date: date,
                         distanceMeters: 3 * metersPerMile,
                         durationSeconds: 1_800,
                         averagePace: 600,
                         splits: [],
                         averageCadence: 0,
                         workoutName: "",
                         notes: "",
                         hasRoute: false,
                         routeName: routeName)
    }

    private func build(runs: [ExportRun]) throws -> String {
        let settings = ExportSettings(mileTime: 412,
                                      goalMile: 330,
                                      paceWindow: 8,
                                      metronomeBPM: 166,
                                      metronomeEnabled: false,
                                      voiceEnabled: true,
                                      cueInterval: "1 mi")
        let input = ExportInput(generatedAt: try date(10, 20),
                                appVersion: "1.15",
                                plan: nil,
                                startYMD: "2026-10-12",
                                progress: PlanProgress(),
                                schedule: nil,
                                todayOffset: 8,
                                settings: settings,
                                zones: PaceZones.forMile(412),
                                runs: runs,
                                workouts: [],
                                gpsBests: [])
        return ProgressExport.markdown(input, calendar: calendar)
    }

    func testNoRouteColumnWhenNoRunFollowedARoute() throws {
        let text = try build(runs: [run(try date(10, 18))])
        XCTAssertTrue(text.contains("| date | miles | time | avg /mi | cadence | workout | mile splits | notes |"))
        XCTAssertFalse(text.contains("| route |"))
    }

    func testTheRouteColumnNamesTheRoute() throws {
        let text = try build(runs: [run(try date(10, 18), routeName: "mccarren park loop"), run(try date(10, 19))])
        XCTAssertTrue(text.contains("| mile splits | route | notes |"))
        XCTAssertTrue(text.contains("mccarren park loop"))
    }
}
