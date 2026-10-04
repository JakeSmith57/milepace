import XCTest
@testable import MilePace

/// Checks the real `plan.json` in the app bundle against the presets in the app.
final class BundledPlanTests: XCTestCase {
    private func bundledPlan() throws -> PlanFile {
        let plan = PlanLoader.load(bundle: Bundle(for: PlanStore.self))
        return try XCTUnwrap(plan, "plan.json is missing from the app bundle or does not parse")
    }

    func testHas48Weeks() throws {
        let plan = try bundledPlan()
        XCTAssertEqual(plan.weeks.count, 48)
        for (index, week) in plan.weeks.enumerated() {
            XCTAssertEqual(week.week, index + 1)
        }
    }

    func testSessionsAreSortedByWeekAndWeekday() throws {
        let plan = try bundledPlan()
        XCTAssertFalse(plan.sessions.isEmpty)
        for index in 1..<plan.sessions.count {
            let before = plan.sessions[index - 1]
            let after = plan.sessions[index]
            let ordered = before.week < after.week || (before.week == after.week && before.weekday < after.weekday)
            XCTAssertTrue(ordered, "session \(index) is out of order")
        }
        for session in plan.sessions {
            XCTAssertTrue((1...7).contains(session.weekday))
            XCTAssertTrue((1...48).contains(session.week))
        }
    }

    func testRoadPresetsExist() throws {
        let plan = try bundledPlan()
        let names = Set(RoadWorkoutPresets.all.map { $0.name })
        for session in plan.sessions where session.kind == .road {
            let name = session.preset ?? ""
            XCTAssertTrue(names.contains(name), "unknown road workout: \(name)")
        }
    }

    func testTrackPresetsExistExceptSharpener() throws {
        let plan = try bundledPlan()
        let ids = Set(WorkoutPresets.all.map { $0.id })
        for session in plan.sessions where session.isTrackSession {
            let id = session.preset ?? ""
            if id == "sharpener" { continue }
            XCTAssertTrue(ids.contains(id), "unknown track preset: \(id)")
        }
    }

    func testExactlyOneRaceInWeek48() throws {
        let plan = try bundledPlan()
        let races = plan.sessions.filter { $0.kind == .race }
        XCTAssertEqual(races.count, 1)
        XCTAssertEqual(races.first?.week, 48)
    }

    func testScheduleStartsOnPlanStartDate() throws {
        let plan = try bundledPlan()
        XCTAssertNotNil(PlanCalendar.parse(plan.startDate))
        let schedule = PlanSchedule(plan: plan, progress: PlanProgress())
        XCTAssertEqual(schedule.dayOffset(0), 1)
        XCTAssertEqual(schedule.currentWeek(today: -1), 0)
        XCTAssertEqual(schedule.currentWeek(today: schedule.raceDayOffset + 1), 48)
    }
}
