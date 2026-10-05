import XCTest
@testable import MilePace

/// What the plan store starts from (saved progress and start date against the bundled plan file) and
/// the clock rules around the active session.
final class PlanLaunchTests: XCTestCase {
    private func planFile(version: Int = 2,
                          start: String = "2026-10-12",
                          raceDate: String? = nil,
                          withRace: Bool = true) -> PlanFile {
        var sessions = [PlanSession(week: 1, weekday: 2, phase: 1, kind: .easy, title: "2 mi easy",
                                    miles: 2, preset: nil, note: nil)]
        if withRace {
            // Week 2, weekday 6: 12 days after the start.
            sessions.append(PlanSession(week: 2, weekday: 6, phase: 1, kind: .race, title: "race",
                                        miles: nil, preset: "mile-tt", note: nil))
        }
        return PlanFile(name: "launch", version: version, startDate: start, raceDate: raceDate,
                        weeks: [], sessions: sessions)
    }

    private func saved(version: Int, statuses: [String: SessionStatus] = [:]) throws -> Data {
        return try JSONEncoder().encode(PlanProgress(statuses: statuses, planVersion: version))
    }

    func testAFreshInstallTakesTheFileStartAndNoProgress() {
        let launch = PlanLaunch.resolve(plan: planFile(), savedProgress: nil, savedStart: nil)
        XCTAssertEqual(launch.startYMD, "2026-10-12")
        XCTAssertEqual(launch.progress, PlanProgress(planVersion: 2))
        XCTAssertFalse(launch.versionChanged)
    }

    func testTheSameVersionKeepsProgressAndAChangedStartDate() throws {
        let data = try saved(version: 2, statuses: [PlanProgress.key(0): .done])
        let launch = PlanLaunch.resolve(plan: planFile(), savedProgress: data, savedStart: "2026-11-02")
        XCTAssertFalse(launch.versionChanged)
        XCTAssertEqual(launch.startYMD, "2026-11-02")
        XCTAssertEqual(launch.progress.statuses, [PlanProgress.key(0): .done])
    }

    func testANewPlanVersionResetsProgressAndTheSavedStartDate() throws {
        let data = try saved(version: 1, statuses: [PlanProgress.key(0): .done])
        let launch = PlanLaunch.resolve(plan: planFile(version: 2), savedProgress: data, savedStart: "2026-11-02")
        XCTAssertTrue(launch.versionChanged)
        XCTAssertEqual(launch.startYMD, "2026-10-12")
        XCTAssertEqual(launch.progress, PlanProgress(planVersion: 2))
    }

    func testProgressThatDoesNotReadBackStartsOverButKeepsTheStartDate() {
        let launch = PlanLaunch.resolve(plan: planFile(), savedProgress: Data("nope".utf8), savedStart: "2026-11-02")
        XCTAssertFalse(launch.versionChanged)
        XCTAssertEqual(launch.startYMD, "2026-11-02")
        XCTAssertEqual(launch.progress, PlanProgress(planVersion: 2))
    }

    func testAnUnusableSavedStartFallsBackToTheFileThenToTheBuiltInDate() throws {
        let data = try saved(version: 2)
        XCTAssertEqual(PlanLaunch.resolve(plan: planFile(start: "2026-10-19"), savedProgress: data,
                                          savedStart: "not a date").startYMD, "2026-10-19")
        XCTAssertEqual(PlanLaunch.resolve(plan: planFile(start: "garbage"), savedProgress: data,
                                          savedStart: nil).startYMD, PlanLaunch.fallbackStart)
        XCTAssertEqual(PlanLaunch.resolve(plan: nil, savedProgress: nil, savedStart: nil).startYMD,
                       PlanLaunch.fallbackStart)
        // A version change with an unusable file start keeps whatever start was saved.
        let old = try saved(version: 1)
        XCTAssertEqual(PlanLaunch.resolve(plan: planFile(start: "garbage"), savedProgress: old,
                                          savedStart: "2026-11-02").startYMD, "2026-11-02")
    }

    func testRaceDateIsCheckedAgainstTheStartAndTheRaceSession() {
        // Start Mon 2026-10-12 plus 12 days is Sat 2026-10-24.
        let matching = planFile(raceDate: "2026-10-24")
        XCTAssertNil(PlanLaunch.raceDateMismatch(plan: matching, startYMD: "2026-10-12"))
        let off = planFile(raceDate: "2026-10-25")
        let message = PlanLaunch.raceDateMismatch(plan: off, startYMD: "2026-10-12")
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("2026-10-25") ?? false)
        // A moved start no longer lines up with the file's race date.
        XCTAssertNotNil(PlanLaunch.raceDateMismatch(plan: matching, startYMD: "2026-10-19"))
        // Nothing to compare.
        XCTAssertNil(PlanLaunch.raceDateMismatch(plan: planFile(raceDate: nil), startYMD: "2026-10-12"))
        XCTAssertNil(PlanLaunch.raceDateMismatch(plan: planFile(raceDate: "2026-10-24", withRace: false),
                                                 startYMD: "2026-10-12"))
        XCTAssertNil(PlanLaunch.raceDateMismatch(plan: matching, startYMD: "garbage"))
    }

    func testADayChangeForgetsTheActiveSessionUnlessARunOrTrackSessionIsGoing() {
        XCTAssertNil(PlanClock.activeIndexAfterRefresh(dayChanged: true, active: 4, sessionInProgress: false))
        XCTAssertEqual(PlanClock.activeIndexAfterRefresh(dayChanged: true, active: 4, sessionInProgress: true), 4)
        XCTAssertEqual(PlanClock.activeIndexAfterRefresh(dayChanged: false, active: 4, sessionInProgress: false), 4)
        XCTAssertNil(PlanClock.activeIndexAfterRefresh(dayChanged: true, active: nil, sessionInProgress: true))
    }
}
