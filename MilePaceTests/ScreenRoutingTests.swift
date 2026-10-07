import XCTest
@testable import MilePace

/// Which screen a request lands on (v1.9): a recording is never left.
final class ScreenRoutingTests: XCTestCase {
    private func resolve(current: AppTab = .today,
                         requested: AppTab,
                         run: Bool = false,
                         track: Bool = false) -> AppTab {
        return ScreenRouting.resolve(current: current,
                                     requested: requested,
                                     runInProgress: run,
                                     trackInProgress: track)
    }

    func testARunInProgressForcesTheRunScreenForEveryRequest() {
        for requested in AppTab.allCases {
            XCTAssertEqual(resolve(current: .run, requested: requested, run: true), .run)
        }
    }

    func testATrackSessionInProgressForcesTheTrackScreenForEveryRequest() {
        for requested in AppTab.allCases {
            XCTAssertEqual(resolve(current: .track, requested: requested, track: true), .track)
        }
    }

    func testNeitherInProgressGrantsTheRequest() {
        for current in AppTab.allCases {
            for requested in AppTab.allCases {
                XCTAssertEqual(resolve(current: current, requested: requested), requested)
            }
        }
    }

    func testGoingHomeWhileIdleShowsToday() {
        XCTAssertEqual(resolve(current: .run, requested: .today), .today)
        XCTAssertEqual(resolve(current: .set, requested: .today), .today)
    }

    func testATappedReminderDuringARunStaysOnTheRunScreen() {
        XCTAssertEqual(resolve(current: .run, requested: .today, run: true), .run)
    }

    func testGoingHomeDuringATrackSessionIsIgnored() {
        XCTAssertEqual(resolve(current: .track, requested: .today, track: true), .track)
    }

    func testTheRoutinesScreenIsOverriddenWhileARunIsInProgress() {
        XCTAssertEqual(resolve(current: .run, requested: .routines, run: true), .run)
        XCTAssertEqual(resolve(current: .track, requested: .routines, track: true), .track)
    }

    func testTheRoutinesScreenOpensWhenIdle() {
        XCTAssertEqual(resolve(requested: .routines), .routines)
    }

    func testTheRunWinsWhenBothAreSomehowInProgress() {
        XCTAssertEqual(resolve(requested: .log, run: true, track: true), .run)
    }
}
