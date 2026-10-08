import XCTest
@testable import MilePace

/// What the track coach says (v1.16).
final class TrackSpeechTests: XCTestCase {
    func testDeltaWording() {
        XCTAssertEqual(TrackSpeech.delta(0), "On target.")
        XCTAssertEqual(TrackSpeech.delta(0.3), "On target.")
        XCTAssertEqual(TrackSpeech.delta(-0.3), "On target.")
        XCTAssertEqual(TrackSpeech.delta(0.5), "Half a second slow.")
        XCTAssertEqual(TrackSpeech.delta(-0.5), "Half a second fast.")
        XCTAssertEqual(TrackSpeech.delta(0.8), "0.8 seconds slow.")
        XCTAssertEqual(TrackSpeech.delta(1.0), "1 second slow.")
        XCTAssertEqual(TrackSpeech.delta(1.04), "1 second slow.")
        XCTAssertEqual(TrackSpeech.delta(-2.0), "2 seconds fast.")
        XCTAssertEqual(TrackSpeech.delta(2.3), "2.3 seconds slow.")
        XCTAssertEqual(TrackSpeech.delta(-2.34), "2.3 seconds fast.")
        XCTAssertEqual(TrackSpeech.delta(Double.nan), "On target.")
    }

    func testTargetAndPlainTimes() {
        XCTAssertEqual(TrackSpeech.targetPhrase(55), "55 seconds")
        XCTAssertEqual(TrackSpeech.targetPhrase(55.4), "55 seconds")
        XCTAssertEqual(TrackSpeech.targetPhrase(1), "1 second")
        XCTAssertEqual(TrackSpeech.targetPhrase(64), "1 minute 4")
        XCTAssertEqual(TrackSpeech.targetPhrase(104), "1 minute 44")
        XCTAssertEqual(TrackSpeech.targetPhrase(120), "2 minutes")
        XCTAssertEqual(TrackSpeech.plainTime(52), "52")
        XCTAssertEqual(TrackSpeech.plainTime(104), "1 minute 44")
    }

    func testTenthsTime() {
        XCTAssertEqual(TrackSpeech.tenthsTime(55.8), "55.8")
        XCTAssertEqual(TrackSpeech.tenthsTime(55.76), "55.8")
        XCTAssertEqual(TrackSpeech.tenthsTime(104.2), "1 minute 44.2")
        XCTAssertEqual(TrackSpeech.tenthsTime(120), "2 minutes")
        XCTAssertEqual(TrackSpeech.tenthsTime(59.96), "1 minute")
    }

    func testRepIntro() {
        XCTAssertEqual(TrackSpeech.repIntro(rep: 2, total: 4, meters: 200, targetSeconds: 55),
                       "Rep 2 of 4. 200 meters. Target 55 seconds.")
        XCTAssertEqual(TrackSpeech.repIntro(rep: 4, total: 4, meters: 200, targetSeconds: 55),
                       "Last one. Rep 4 of 4. 200 meters. Target 55 seconds.")
        XCTAssertEqual(TrackSpeech.repIntro(rep: 1, total: 1, meters: 1609, targetSeconds: 330),
                       "1 mile. Target 5 minutes 30.")
        XCTAssertEqual(TrackSpeech.repIntro(rep: 1, total: 6, meters: 400, targetSeconds: 104),
                       "Rep 1 of 6. 400 meters. Target 1 minute 44.")
    }

    func testHalfwayVerdict() {
        XCTAssertEqual(TrackSpeech.halfway(elapsed: 52, halfTarget: 52.5), "Halfway. 52. On pace.")
        XCTAssertEqual(TrackSpeech.halfway(elapsed: 50, halfTarget: 52), "Halfway. 50. 2 seconds fast.")
        XCTAssertEqual(TrackSpeech.halfway(elapsed: 55, halfTarget: 52), "Halfway. 55. 3 seconds slow.")
        XCTAssertEqual(TrackSpeech.halfway(elapsed: 53.2, halfTarget: 52), "Halfway. 53. 1 second slow.")
    }

    func testRestAndRepDone() {
        XCTAssertEqual(TrackSpeech.restPhrase(seconds: 60), "Rest 60 seconds.")
        XCTAssertEqual(TrackSpeech.restPhrase(seconds: 90), "Rest 90 seconds.")
        XCTAssertEqual(TrackSpeech.restPhrase(seconds: 180), "Rest 3 minutes.")
        XCTAssertEqual(TrackSpeech.restPhrase(seconds: 150), "Rest 2 minutes 30.")
        XCTAssertEqual(TrackSpeech.restPhrase(seconds: 0), "")
        XCTAssertEqual(TrackSpeech.repDone(time: 55.8, delta: 0.5, restSeconds: 60),
                       "55.8. Half a second slow. Rest 60 seconds.")
        XCTAssertEqual(TrackSpeech.repDone(time: 54.1, delta: -1.0, restSeconds: nil), "54.1. 1 second fast.")
        XCTAssertEqual(TrackSpeech.repDone(time: 55.5, delta: 0, restSeconds: 0), "55.5. On target.")
        XCTAssertEqual(TrackSpeech.lastRepDone(average: 55.2), "Last rep done. Average 55.2.")
        XCTAssertEqual(TrackSpeech.hundredToGo, "100 to go.")
    }

    func testRestCountdownLines() {
        XCTAssertEqual(TrackSpeech.restCountdown(seconds: 30, restTotal: 60), "30 seconds.")
        XCTAssertNil(TrackSpeech.restCountdown(seconds: 30, restTotal: 45))
        XCTAssertEqual(TrackSpeech.restCountdown(seconds: 10, restTotal: 30), "10 seconds.")
        XCTAssertEqual(TrackSpeech.restCountdown(seconds: 3, restTotal: 0), "3, 2, 1.")
        XCTAssertNil(TrackSpeech.restCountdown(seconds: 5, restTotal: 60))
    }

    func testCueDistances() {
        XCTAssertEqual(TrackSpeech.halfwayMinMeters, 400)
        XCTAssertEqual(TrackSpeech.hundredToGoMinMeters, 300)
    }
}
