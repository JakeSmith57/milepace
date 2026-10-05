import XCTest
import AVFoundation
@testable import MilePace

final class AudioSessionPlanTests: XCTestCase {
    func testIdleReleasesTheSession() {
        let plan = AudioSessionPlan.make(speechCount: 0, metronomeCount: 0)
        XCTAssertEqual(plan.action, .deactivate)
    }

    func testSpeechAloneDucksOtherAudio() {
        let plan = AudioSessionPlan.make(speechCount: 1, metronomeCount: 0)
        XCTAssertEqual(plan, AudioSessionPlan(action: .activate, voicePromptMode: true, duck: true))
        XCTAssertEqual(AudioSessionPlan.make(speechCount: 3, metronomeCount: 0), plan)
    }

    func testTheMetronomeNeverDucksAndNeverChangesUnderSpeech() {
        let click = AudioSessionPlan.make(speechCount: 0, metronomeCount: 1)
        XCTAssertEqual(click, AudioSessionPlan(action: .activate, voicePromptMode: false, duck: false))
        // Speech starting or ending under the metronome leaves the plan, and so the category, unchanged.
        XCTAssertEqual(AudioSessionPlan.make(speechCount: 1, metronomeCount: 1), click)
        XCTAssertEqual(AudioSessionPlan.make(speechCount: 2, metronomeCount: 1), click)
    }
}

final class AudioSessionEventsTests: XCTestCase {
    func testInterruptionEndedAsksToResumeOnlyWithTheFlag() {
        XCTAssertTrue(AudioSessionEvents.shouldResume(optionsRaw: AVAudioSession.InterruptionOptions.shouldResume.rawValue))
        XCTAssertFalse(AudioSessionEvents.shouldResume(optionsRaw: 0))
        XCTAssertFalse(AudioSessionEvents.shouldResume(optionsRaw: nil))
    }

    func testOnlyALostOutputStopsTheClick() {
        XCTAssertTrue(AudioSessionEvents.isOutputLost(
            reasonRaw: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue))
        XCTAssertFalse(AudioSessionEvents.isOutputLost(
            reasonRaw: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue))
        XCTAssertFalse(AudioSessionEvents.isOutputLost(
            reasonRaw: AVAudioSession.RouteChangeReason.categoryChange.rawValue))
        XCTAssertFalse(AudioSessionEvents.isOutputLost(reasonRaw: nil))
        XCTAssertFalse(AudioSessionEvents.isOutputLost(reasonRaw: 9999))
    }
}

final class MileAnnouncementTests: XCTestCase {
    func testAnnouncedUnlessSuppressedOffOrReplacedByMileCues() {
        for interval in [CueInterval.off, .quarter, .half] {
            XCTAssertTrue(MileAnnouncement.shouldAnnounce(interval: interval, announceSetting: true, suppressed: false))
        }
        // One-mile pace cues replace the announcement.
        XCTAssertFalse(MileAnnouncement.shouldAnnounce(interval: .mile, announceSetting: true, suppressed: false))
        // The setting off, or a rep or recovery running, silences it.
        XCTAssertFalse(MileAnnouncement.shouldAnnounce(interval: .off, announceSetting: false, suppressed: false))
        XCTAssertFalse(MileAnnouncement.shouldAnnounce(interval: .half, announceSetting: true, suppressed: true))
        XCTAssertFalse(MileAnnouncement.shouldAnnounce(interval: .quarter, announceSetting: false, suppressed: true))
    }
}

final class PaceFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 5000)

    func testAFreshPaceIsKept() {
        XCTAssertEqual(PaceFreshness.pace(412, lastUpdate: now.addingTimeInterval(-3), now: now), 412)
        XCTAssertEqual(PaceFreshness.pace(412, lastUpdate: now.addingTimeInterval(-8), now: now), 412)
    }

    func testAStalePaceIsDropped() {
        XCTAssertNil(PaceFreshness.pace(412, lastUpdate: now.addingTimeInterval(-8.5), now: now))
        XCTAssertNil(PaceFreshness.pace(412, lastUpdate: now.addingTimeInterval(-60), now: now))
        XCTAssertEqual(PaceFreshness.staleSeconds, 8)
    }

    func testWithNoUpdateYetThePaceIsLeftAlone() {
        XCTAssertEqual(PaceFreshness.pace(412, lastUpdate: nil, now: now), 412)
        XCTAssertNil(PaceFreshness.pace(nil, lastUpdate: nil, now: now))
        XCTAssertNil(PaceFreshness.pace(nil, lastUpdate: now, now: now))
    }
}
