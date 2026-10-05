import XCTest
@testable import MilePace

final class InputParsingTests: XCTestCase {
    func testMileTimeReadsBareDigitsAsMinutesAndSeconds() {
        XCTAssertEqual(InputParsing.mileTime("645"), 405)
        XCTAssertEqual(InputParsing.mileTime("6:45"), 405)
        XCTAssertEqual(InputParsing.mileTime("1005"), 605)
        XCTAssertEqual(InputParsing.mileTime(" 530 "), 330)
        XCTAssertEqual(InputParsing.mileTime("5:30"), 330)
        // Two digits or fewer are seconds, as parseTime reads them.
        XCTAssertEqual(InputParsing.mileTime("75"), 75)
        XCTAssertNil(InputParsing.mileTime(""))
        XCTAssertNil(InputParsing.mileTime("abc"))
        XCTAssertNil(InputParsing.mileTime("6:75"))
    }

    func testValidMileTimeNeedsFiveToEightThirty() {
        XCTAssertEqual(InputParsing.validMileTime("5:00"), 300)
        XCTAssertEqual(InputParsing.validMileTime("8:30"), 510)
        XCTAssertEqual(InputParsing.validMileTime("645"), 405)
        XCTAssertNil(InputParsing.validMileTime("4:59"))
        XCTAssertNil(InputParsing.validMileTime("8:31"))
        XCTAssertNil(InputParsing.validMileTime("75"))
        XCTAssertNil(InputParsing.validMileTime("1005"))
        XCTAssertNil(InputParsing.validMileTime(""))
        XCTAssertNil(InputParsing.validMileTime("x"))
        XCTAssertEqual(InputParsing.mileTimeRange, 300.0...510.0)
        XCTAssertEqual(InputParsing.mileTimeNote, "use m:ss, 5:00 to 8:30")
    }

    func testAddedDurationTakesABareNumberAsMinutes() {
        XCTAssertEqual(InputParsing.addedDuration("45"), 2700)
        XCTAssertEqual(InputParsing.addedDuration("32.5"), 1950)
        XCTAssertEqual(InputParsing.addedDuration(" 20 "), 1200)
        XCTAssertEqual(InputParsing.addedDuration("25:30"), 1530)
        XCTAssertEqual(InputParsing.addedDuration("1:05:00"), 3900)
        XCTAssertNil(InputParsing.addedDuration("0"))
        XCTAssertNil(InputParsing.addedDuration("0:00"))
        XCTAssertNil(InputParsing.addedDuration(""))
        XCTAssertNil(InputParsing.addedDuration("abc"))
        XCTAssertNil(InputParsing.addedDuration("-5"))
        XCTAssertNil(InputParsing.addedDuration("1.2.3"))
        XCTAssertNil(InputParsing.addedDuration("5:75"))
    }

    func testAddedPaceMustBeBelievable() {
        XCTAssertTrue(InputParsing.isPlausiblePace(seconds: 1800, miles: 3))
        XCTAssertTrue(InputParsing.isPlausiblePace(seconds: 240, miles: 1))
        XCTAssertTrue(InputParsing.isPlausiblePace(seconds: 1200, miles: 1))
        // 2:00 per mile and 40:00 per mile are typos.
        XCTAssertFalse(InputParsing.isPlausiblePace(seconds: 600, miles: 5))
        XCTAssertFalse(InputParsing.isPlausiblePace(seconds: 7200, miles: 3))
        XCTAssertFalse(InputParsing.isPlausiblePace(seconds: 1800, miles: 0))
        XCTAssertFalse(InputParsing.isPlausiblePace(seconds: .nan, miles: 3))
        XCTAssertEqual(InputParsing.addedPaceRange, 240.0...1200.0)
    }

    func testAddedMiles() {
        XCTAssertEqual(InputParsing.addedMiles("3.1") ?? 0, 3.1, accuracy: 1e-9)
        XCTAssertEqual(InputParsing.addedMiles("3,1") ?? 0, 3.1, accuracy: 1e-9)
        XCTAssertEqual(InputParsing.addedMiles(" 6 ") ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(InputParsing.addedMiles("199.9") ?? 0, 199.9, accuracy: 1e-9)
        XCTAssertNil(InputParsing.addedMiles("0"))
        XCTAssertNil(InputParsing.addedMiles("-2"))
        XCTAssertNil(InputParsing.addedMiles("200"))
        XCTAssertNil(InputParsing.addedMiles("abc"))
        XCTAssertNil(InputParsing.addedMiles(""))
    }
}
