import XCTest
@testable import MilePace

final class FormattingTests: XCTestCase {
    func testFormatPace() {
        XCTAssertEqual(formatPace(secondsPerMile: 412), "6:52")
        XCTAssertEqual(formatPace(secondsPerMile: 425), "7:05")
        XCTAssertEqual(formatPace(secondsPerMile: 330), "5:30")
        XCTAssertEqual(formatPace(secondsPerMile: 59.6), "1:00")
    }

    func testFormatPaceInvalidValues() {
        XCTAssertEqual(formatPace(secondsPerMile: nil), "--:--")
        XCTAssertEqual(formatPace(secondsPerMile: .infinity), "--:--")
        XCTAssertEqual(formatPace(secondsPerMile: .nan), "--:--")
        XCTAssertEqual(formatPace(secondsPerMile: 0), "--:--")
        XCTAssertEqual(formatPace(secondsPerMile: -5), "--:--")
        XCTAssertEqual(formatPace(secondsPerMile: 1801), "--:--")
        XCTAssertEqual(formatPace(secondsPerMile: 1800), "30:00")
    }

    func testFormatDuration() {
        XCTAssertEqual(formatDuration(0), "0:00")
        XCTAssertEqual(formatDuration(59), "0:59")
        XCTAssertEqual(formatDuration(61), "1:01")
        XCTAssertEqual(formatDuration(3599.9), "59:59")
        XCTAssertEqual(formatDuration(3600), "1:00:00")
        XCTAssertEqual(formatDuration(3725), "1:02:05")
        XCTAssertEqual(formatDuration(-3), "0:00")
    }

    func testFormatSplit() {
        XCTAssertEqual(formatSplit(82.4), "1:22.4")
        XCTAssertEqual(formatSplit(41.04), "41.0")
        XCTAssertEqual(formatSplit(0), "0.0")
        XCTAssertEqual(formatSplit(59.96), "1:00.0")
        XCTAssertEqual(formatSplit(125), "2:05.0")
        XCTAssertEqual(formatSplit(51.5), "51.5")
    }

    func testFormatMiles() {
        XCTAssertEqual(formatMiles(0), "0.00")
        XCTAssertEqual(formatMiles(metersPerMile * 3.12), "3.12")
        XCTAssertEqual(formatMiles(1609.344), "1.00")
    }

    func testFormatDelta() {
        XCTAssertEqual(formatDelta(1.24), "+1.2")
        XCTAssertEqual(formatDelta(-0.8), "-0.8")
        XCTAssertEqual(formatDelta(0.01), "0.0")
        XCTAssertEqual(formatDelta(-0.01), "0.0")
    }

    func testParseTimeValid() {
        XCTAssertEqual(parseTime("6:52"), 412)
        XCTAssertEqual(parseTime("45"), 45)
        XCTAssertEqual(parseTime(" 5:30 "), 330)
        XCTAssertEqual(parseTime("1:05:00"), 3900)
        guard let split = parseTime("1:22.4") else {
            XCTFail("expected 1:22.4 to parse")
            return
        }
        XCTAssertEqual(split, 82.4, accuracy: 0.0001)
        guard let decimal = parseTime("82.5") else {
            XCTFail("expected 82.5 to parse")
            return
        }
        XCTAssertEqual(decimal, 82.5, accuracy: 0.0001)
    }

    func testParseTimeInvalid() {
        XCTAssertNil(parseTime(""))
        XCTAssertNil(parseTime("   "))
        XCTAssertNil(parseTime("abc"))
        XCTAssertNil(parseTime("6:75"))
        XCTAssertNil(parseTime("6:5x"))
        XCTAssertNil(parseTime("6::05"))
        XCTAssertNil(parseTime(":30"))
        XCTAssertNil(parseTime("-5"))
        XCTAssertNil(parseTime("1.5:30"))
    }

    func testRoundTrips() {
        XCTAssertEqual(parseTime(formatPace(secondsPerMile: 412)), 412)
        XCTAssertEqual(parseTime(formatDuration(3725)), 3725)
        guard let value = parseTime(formatSplit(82.4)) else {
            XCTFail("expected round trip to parse")
            return
        }
        XCTAssertEqual(value, 82.4, accuracy: 0.0001)
    }

    func testSpokenFormats() {
        XCTAssertEqual(spokenMinutesSeconds(581), "9 minutes 41")
        XCTAssertEqual(spokenMinutesSeconds(545), "9 minutes oh 5")
        XCTAssertEqual(spokenMinutesSeconds(540), "9 minutes")
        XCTAssertEqual(spokenMinutesSeconds(60), "1 minute")
        XCTAssertEqual(spokenMinutesSeconds(41), "41 seconds")
        XCTAssertEqual(spokenCompact(581), "9 41")
        XCTAssertEqual(spokenCompact(545), "9 oh 5")
        XCTAssertEqual(spokenCompact(540), "9")
    }
}
