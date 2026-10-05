import XCTest
@testable import MilePace

final class MetronomePauseLogicTests: XCTestCase {
    private typealias State = MetronomePauseLogic.State

    func testPauseWhileRunningSuspends() {
        let state = State(running: true, suspended: false, interruptedWhileRunning: false)
        let paused = MetronomePauseLogic.onPause(state)
        XCTAssertEqual(paused, State(running: false, suspended: true, interruptedWhileRunning: false))
    }

    func testResumeAfterPauseStartsAudio() {
        let paused = State(running: false, suspended: true, interruptedWhileRunning: false)
        let result = MetronomePauseLogic.onResume(paused)
        XCTAssertTrue(result.startAudio)
        XCTAssertEqual(result.0, State(running: true, suspended: false, interruptedWhileRunning: false))
    }

    func testPauseAndResumeWithClickOffMakesNoAudio() {
        let off = State(running: false, suspended: false, interruptedWhileRunning: false)
        let paused = MetronomePauseLogic.onPause(off)
        XCTAssertEqual(paused, off)
        let result = MetronomePauseLogic.onResume(paused)
        XCTAssertFalse(result.startAudio)
        XCTAssertEqual(result.0, off)
    }

    func testInterruptedThenPausedThenInterruptionEndsMakesNoAudio() {
        let interrupted = State(running: false, suspended: false, interruptedWhileRunning: true)
        let paused = MetronomePauseLogic.onPause(interrupted)
        XCTAssertEqual(paused, State(running: false, suspended: true, interruptedWhileRunning: false))

        let ended = MetronomePauseLogic.onInterruptionEnded(paused, shouldResume: true)
        XCTAssertFalse(ended.startAudio)
        XCTAssertTrue(ended.0.suspended)

        let resumed = MetronomePauseLogic.onResume(ended.0)
        XCTAssertTrue(resumed.startAudio)
        XCTAssertEqual(resumed.0, State(running: true, suspended: false, interruptedWhileRunning: false))
    }

    func testSuspendedAndInterruptionEndedMakesNoAudio() {
        let paused = State(running: false, suspended: true, interruptedWhileRunning: false)
        let ended = MetronomePauseLogic.onInterruptionEnded(paused, shouldResume: true)
        XCTAssertFalse(ended.startAudio)
        XCTAssertEqual(ended.0, paused)
    }

    func testInterruptionEndedResumesOnlyWhenAsked() {
        let interrupted = State(running: false, suspended: false, interruptedWhileRunning: true)
        let yes = MetronomePauseLogic.onInterruptionEnded(interrupted, shouldResume: true)
        XCTAssertTrue(yes.startAudio)
        XCTAssertEqual(yes.0, State(running: true, suspended: false, interruptedWhileRunning: false))

        let no = MetronomePauseLogic.onInterruptionEnded(interrupted, shouldResume: false)
        XCTAssertFalse(no.startAudio)
        XCTAssertEqual(no.0, State(running: false, suspended: false, interruptedWhileRunning: false))
    }

    func testInterruptionEndedWithoutPriorClickMakesNoAudio() {
        let off = State(running: false, suspended: false, interruptedWhileRunning: false)
        XCTAssertFalse(MetronomePauseLogic.onInterruptionEnded(off, shouldResume: true).startAudio)
    }

    func testResumeWhenNotSuspendedChangesNothing() {
        let running = State(running: true, suspended: false, interruptedWhileRunning: false)
        let result = MetronomePauseLogic.onResume(running)
        XCTAssertFalse(result.startAudio)
        XCTAssertEqual(result.0, running)
    }
}
