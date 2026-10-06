import XCTest
@testable import MilePace

final class MidRunAudioLabelsTests: XCTestCase {
    func testTitlesShowTheCurrentState() {
        XCTAssertEqual(MidRunAudioLabels.voiceTitle(on: true), "voice on")
        XCTAssertEqual(MidRunAudioLabels.voiceTitle(on: false), "voice off")
        XCTAssertEqual(MidRunAudioLabels.clickTitle(on: true), "click on")
        XCTAssertEqual(MidRunAudioLabels.clickTitle(on: false), "click off")
    }

    func testAccessibilityLabelsSayWhatATapDoes() {
        XCTAssertEqual(MidRunAudioLabels.voiceAccessibility(on: true), "voice on, double tap to mute")
        XCTAssertEqual(MidRunAudioLabels.voiceAccessibility(on: false), "voice off, double tap to unmute")
        XCTAssertEqual(MidRunAudioLabels.clickAccessibility(on: true), "click on, double tap to turn off")
        XCTAssertEqual(MidRunAudioLabels.clickAccessibility(on: false), "click off, double tap to turn on")
    }
}
