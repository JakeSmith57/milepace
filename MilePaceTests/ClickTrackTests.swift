import XCTest
@testable import MilePace

final class ClickTrackTests: XCTestCase {
    func testLengthAtOneSixtySixBpm() {
        let samples = ClickTrack.beatSamples(bpm: 166, sampleRate: 48_000)
        XCTAssertEqual(samples.count, Int((48_000.0 * 60 / 166.0).rounded()))
        XCTAssertEqual(samples.count, 17_349)
    }

    func testSilenceAfterClick() {
        let samples = ClickTrack.beatSamples(bpm: 166, sampleRate: 48_000)
        let clickLength = 1_200
        XCTAssertGreaterThan(samples.count, clickLength)
        XCTAssertTrue(samples[clickLength...].allSatisfy { $0 == 0 })
    }

    func testPeakAndNonSilentClick() throws {
        let samples = ClickTrack.beatSamples(bpm: 170, sampleRate: 44_100)
        let peak = try XCTUnwrap(samples.map { abs($0) }.max())
        XCTAssertLessThanOrEqual(peak, 0.9)
        XCTAssertGreaterThan(peak, 0.1)
    }

    func testLengthMatchesFormulaAcrossRange() {
        for bpm in stride(from: ClickTrack.bpmRange.lowerBound, through: ClickTrack.bpmRange.upperBound, by: 6) {
            let samples = ClickTrack.beatSamples(bpm: bpm, sampleRate: 44_100)
            XCTAssertEqual(samples.count, Int((44_100.0 * 60 / Double(bpm)).rounded()))
        }
    }

    func testInvalidInputGivesNoSamples() {
        XCTAssertTrue(ClickTrack.beatSamples(bpm: 0, sampleRate: 48_000).isEmpty)
        XCTAssertTrue(ClickTrack.beatSamples(bpm: 166, sampleRate: 0).isEmpty)
    }

    func testSuggestedBPM() {
        XCTAssertEqual(ClickTrack.bpmRange, 140...200)
        XCTAssertEqual(ClickTrack.suggestedBPM(averageCadence: 166), 174)
        XCTAssertEqual(ClickTrack.suggestedBPM(averageCadence: 250), 200)
        XCTAssertEqual(ClickTrack.suggestedBPM(averageCadence: 100), 140)
        XCTAssertEqual(ClickTrack.suggestedBPM(averageCadence: 170) % 2, 0)
    }
}
