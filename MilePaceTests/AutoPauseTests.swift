import XCTest
@testable import MilePace

final class AutoPauseTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func time(_ seconds: Double) -> Date {
        return t0.addingTimeInterval(seconds)
    }

    /// Feeds the same speed once a second from `from` up to and including `to` and returns the events.
    private func feed(_ detector: inout AutoPauseDetector,
                      speed: Double,
                      accuracy: Double = 0.5,
                      from: Int,
                      to: Int,
                      paused: Bool = false) -> [AutoPauseDetector.Event] {
        var events: [AutoPauseDetector.Event] = []
        for second in from...to {
            if let event = detector.update(speed: speed,
                                           speedAccuracy: accuracy,
                                           at: time(Double(second)),
                                           paused: paused) {
                events.append(event)
            }
        }
        return events
    }

    func testSteadyRunningNeverPauses() {
        var detector = AutoPauseDetector()
        XCTAssertTrue(feed(&detector, speed: 3.5, from: 0, to: 600).isEmpty)
    }

    func testFourSecondsSlowDoesNotPause() {
        var detector = AutoPauseDetector()
        XCTAssertTrue(feed(&detector, speed: 0.2, from: 0, to: 4).isEmpty)
    }

    func testFiveSecondsSlowPausesOnce() {
        var detector = AutoPauseDetector()
        let events = feed(&detector, speed: 0.2, from: 0, to: 5)
        XCTAssertEqual(events, [AutoPauseDetector.Event.pause])
    }

    func testAMovingSampleClearsTheStopWindow() {
        var detector = AutoPauseDetector()
        XCTAssertTrue(feed(&detector, speed: 0.2, from: 0, to: 3).isEmpty)
        XCTAssertTrue(feed(&detector, speed: 2.5, from: 4, to: 4).isEmpty)
        // A new stretch starts at 5: it needs 5 more seconds.
        XCTAssertTrue(feed(&detector, speed: 0.2, from: 5, to: 9).isEmpty)
        XCTAssertEqual(feed(&detector, speed: 0.2, from: 10, to: 10), [AutoPauseDetector.Event.pause])
    }

    func testInvalidSamplesAreIgnoredWhileRunning() {
        var detector = AutoPauseDetector()
        // Garbage never starts a stop window.
        XCTAssertTrue(feed(&detector, speed: -1, from: 0, to: 20).isEmpty)
        XCTAssertTrue(feed(&detector, speed: 0.1, accuracy: -1, from: 0, to: 20).isEmpty)
        XCTAssertTrue(feed(&detector, speed: 0.1, accuracy: 3.0, from: 0, to: 20).isEmpty)
        XCTAssertTrue(feed(&detector, speed: Double.nan, from: 0, to: 20).isEmpty)

        // Garbage in the middle of a stop neither breaks nor extends the window.
        var stopped = AutoPauseDetector()
        XCTAssertTrue(feed(&stopped, speed: 0.2, from: 0, to: 2).isEmpty)
        XCTAssertTrue(feed(&stopped, speed: -1, from: 3, to: 4).isEmpty)
        XCTAssertEqual(feed(&stopped, speed: 0.2, from: 5, to: 5), [AutoPauseDetector.Event.pause])
    }

    func testResumeNeedsTwoConsecutiveFastSamples() {
        var detector = AutoPauseDetector()
        XCTAssertTrue(feed(&detector, speed: 2.5, from: 0, to: 0, paused: true).isEmpty)
        XCTAssertEqual(feed(&detector, speed: 2.5, from: 1, to: 1, paused: true), [AutoPauseDetector.Event.resume])
    }

    func testASlowSampleBetweenResetsTheResumeCount() {
        var detector = AutoPauseDetector()
        XCTAssertTrue(feed(&detector, speed: 2.5, from: 0, to: 0, paused: true).isEmpty)
        // 1.0 m/s is not slow enough to matter and not fast enough to count.
        XCTAssertTrue(feed(&detector, speed: 1.0, from: 1, to: 1, paused: true).isEmpty)
        XCTAssertTrue(feed(&detector, speed: 2.5, from: 2, to: 2, paused: true).isEmpty)
        XCTAssertEqual(feed(&detector, speed: 2.5, from: 3, to: 3, paused: true), [AutoPauseDetector.Event.resume])
    }

    func testInvalidSamplesNeverResumeAndBreakTheCount() {
        var detector = AutoPauseDetector()
        XCTAssertTrue(feed(&detector, speed: 5.0, accuracy: -1, from: 0, to: 10, paused: true).isEmpty)
        XCTAssertTrue(feed(&detector, speed: 5.0, accuracy: 4.0, from: 0, to: 10, paused: true).isEmpty)
        XCTAssertTrue(feed(&detector, speed: 2.5, from: 11, to: 11, paused: true).isEmpty)
        XCTAssertTrue(feed(&detector, speed: 2.5, accuracy: -1, from: 12, to: 12, paused: true).isEmpty)
        // The bad sample broke the run of fast ones: two more are needed.
        XCTAssertTrue(feed(&detector, speed: 2.5, from: 13, to: 13, paused: true).isEmpty)
        XCTAssertEqual(feed(&detector, speed: 2.5, from: 14, to: 14, paused: true), [AutoPauseDetector.Event.resume])
    }

    func testResetClearsTheStopWindowAndTheGoCount() {
        var detector = AutoPauseDetector()
        XCTAssertTrue(feed(&detector, speed: 0.2, from: 0, to: 4).isEmpty)
        detector.reset()
        // The window restarted: the sample at 5 s is the first slow one now.
        XCTAssertTrue(feed(&detector, speed: 0.2, from: 5, to: 9).isEmpty)
        XCTAssertEqual(feed(&detector, speed: 0.2, from: 10, to: 10), [AutoPauseDetector.Event.pause])

        var going = AutoPauseDetector()
        XCTAssertTrue(feed(&going, speed: 2.5, from: 0, to: 0, paused: true).isEmpty)
        going.reset()
        XCTAssertTrue(feed(&going, speed: 2.5, from: 1, to: 1, paused: true).isEmpty)
        XCTAssertEqual(feed(&going, speed: 2.5, from: 2, to: 2, paused: true), [AutoPauseDetector.Event.resume])
    }

    func testThresholdsMatchTheSpec() {
        XCTAssertEqual(AutoPauseDetector.stopSpeed, 0.8)
        XCTAssertEqual(AutoPauseDetector.goSpeed, 1.6)
        XCTAssertEqual(AutoPauseDetector.stopSeconds, 5.0)
        XCTAssertEqual(AutoPauseDetector.goSamples, 2)
        XCTAssertEqual(AutoPauseDetector.maxSpeedAccuracy, 1.5)
    }
}
