import XCTest
@testable import MilePace

final class InstrumentFormatTests: XCTestCase {
    // MARK: Pace meter

    private let zone: ClosedRange<Double> = 400...410

    func testInZoneIsOneOfTheMiddleCells() {
        for pace in [400.0, 402.0, 405.0, 408.0, 410.0] {
            let cell = PaceMeterModel.cell(pace: pace, zone: zone)
            XCTAssertTrue(cell == 3 || cell == 4, "pace \(pace) gave cell \(cell)")
        }
        XCTAssertEqual(PaceMeterModel.cell(pace: 402, zone: zone), 3)
        XCTAssertEqual(PaceMeterModel.cell(pace: 408, zone: zone), 4)
    }

    func testMuchFasterIsFirstCellAndMuchSlowerIsLast() {
        XCTAssertEqual(PaceMeterModel.cell(pace: 300, zone: zone), 0)
        XCTAssertEqual(PaceMeterModel.cell(pace: 600, zone: zone), 7)
        XCTAssertEqual(PaceMeterModel.cell(pace: 0, zone: zone), 0)
        XCTAssertEqual(PaceMeterModel.cell(pace: 100_000, zone: zone), 7)
    }

    func testOutsideCellsAreHalfAZoneWide() {
        // The zone is 10 s wide, so each cell covers 5 s.
        XCTAssertEqual(PaceMeterModel.cell(pace: 399, zone: zone), 2)
        XCTAssertEqual(PaceMeterModel.cell(pace: 395, zone: zone), 2)
        XCTAssertEqual(PaceMeterModel.cell(pace: 394, zone: zone), 1)
        XCTAssertEqual(PaceMeterModel.cell(pace: 389, zone: zone), 0)
        XCTAssertEqual(PaceMeterModel.cell(pace: 411, zone: zone), 5)
        XCTAssertEqual(PaceMeterModel.cell(pace: 415, zone: zone), 5)
        XCTAssertEqual(PaceMeterModel.cell(pace: 416, zone: zone), 6)
        XCTAssertEqual(PaceMeterModel.cell(pace: 421, zone: zone), 7)
    }

    func testCellNeverDecreasesAsPaceGetsSlower() {
        var previous = 0
        var pace = 350.0
        while pace <= 470 {
            let cell = PaceMeterModel.cell(pace: pace, zone: zone)
            XCTAssertGreaterThanOrEqual(cell, previous)
            previous = cell
            pace += 0.5
        }
    }

    func testOtherCellCountsAndBadInput() {
        XCTAssertEqual(PaceMeterModel.zoneCells(), 3...4)
        XCTAssertEqual(PaceMeterModel.zoneCells(cells: 6), 2...3)
        XCTAssertEqual(PaceMeterModel.cell(pace: 300, zone: zone, cells: 6), 0)
        XCTAssertEqual(PaceMeterModel.cell(pace: 600, zone: zone, cells: 6), 5)
        XCTAssertEqual(PaceMeterModel.cell(pace: .nan, zone: zone), 3)
        // A zero-width zone must not divide by zero.
        XCTAssertEqual(PaceMeterModel.cell(pace: 500, zone: 400...400), 7)
    }

    // MARK: Readout text

    func testDotLeaders() {
        XCTAssertEqual(ReadoutFormat.leader("avg", width: 12), "avg ........")
        XCTAssertEqual(ReadoutFormat.leader("avg"), "avg ........")
        XCTAssertEqual(ReadoutFormat.leader("cadence", width: 12), "cadence ....")
        XCTAssertEqual(ReadoutFormat.leader("elevenchars", width: 12), "elevenchars ")
        XCTAssertEqual(ReadoutFormat.leader("avg", width: 12).count, 12)
    }

    func testLongKeysAreCutWithAnEllipsis() {
        let text = ReadoutFormat.leader("thresholds-long", width: 12)
        XCTAssertEqual(text, "thresholds\u{2026} ")
        XCTAssertEqual(text.count, 12)
    }

    func testSignedDeltaUsesARealMinusSign() {
        XCTAssertEqual(ReadoutFormat.signedDelta(1.6), "+1.6")
        XCTAssertEqual(ReadoutFormat.signedDelta(-0.6), "\u{2212}0.6")
        XCTAssertEqual(ReadoutFormat.signedDelta(0), "0.0")
    }

    func testDeltaWords() {
        XCTAssertEqual(ReadoutFormat.deltaWords(1.6), "+1.6 slow")
        XCTAssertEqual(ReadoutFormat.deltaWords(-4), "\u{2212}4.0 fast")
        XCTAssertEqual(ReadoutFormat.deltaWords(0.9), "on pace")
        XCTAssertEqual(ReadoutFormat.deltaWords(-1.0), "on pace")
    }

    func testPaceRangeText() {
        XCTAssertEqual(ReadoutFormat.paceRange(478...483), "7:58\u{2013}8:03")
    }

    func testLogStamp() {
        XCTAssertEqual(ReadoutFormat.stamp(191.8), "03:11.8")
        XCTAssertEqual(ReadoutFormat.stamp(0), "00:00.0")
        XCTAssertEqual(ReadoutFormat.stamp(-1), "--:--.-")
    }

    // MARK: GPS state

    func testGPSStateEvaluation() {
        XCTAssertEqual(GPSState.evaluate(accuracy: 4, age: 1), GPSState.ready(4))
        XCTAssertEqual(GPSState.evaluate(accuracy: 10, age: 3), GPSState.ready(10))
        XCTAssertEqual(GPSState.evaluate(accuracy: 12, age: 1), GPSState.weak(12))
        XCTAssertEqual(GPSState.evaluate(accuracy: 4, age: 5), GPSState.weak(4))
        XCTAssertEqual(GPSState.evaluate(accuracy: 4, age: 11), GPSState.searching)
        XCTAssertEqual(GPSState.evaluate(accuracy: nil, age: nil), GPSState.searching)
        XCTAssertEqual(GPSState.evaluate(accuracy: -1, age: 1), GPSState.searching)
    }

    func testGPSStateLabels() {
        XCTAssertEqual(GPSState.off.label, "gps off")
        XCTAssertEqual(GPSState.searching.label, "gps searching")
        XCTAssertEqual(GPSState.weak(27.4).label, "gps 27m weak")
        XCTAssertEqual(GPSState.ready(4.1).label, "gps 4m")
        XCTAssertTrue(GPSState.ready(4).isReady)
        XCTAssertTrue(GPSState.searching.isSearching)
        XCTAssertFalse(GPSState.weak(20).isReady)
    }

    // MARK: Diagnostics CSV

    func testCSVHeader() {
        XCTAssertEqual(DiagnosticsCSV.header,
                       "t,lat,lon,hAcc,speed,speedAcc,course,accepted,reason,distance,windowPace,dopplerPace,currentPace,cadence")
    }

    func testCSVRow() {
        let record = DiagnosticsRecord(t: 191.84,
                                       latitude: 40.123456789,
                                       longitude: -75.5,
                                       horizontalAccuracy: 4.1,
                                       speed: 3.21,
                                       speedAccuracy: 0.3,
                                       course: 87.6,
                                       accepted: true,
                                       reason: "ok",
                                       distance: 512.34,
                                       windowPace: 500.04,
                                       dopplerPace: nil,
                                       currentPace: 499.96,
                                       cadence: 172.4)
        XCTAssertEqual(DiagnosticsCSV.row(record),
                       "191.8,40.123457,-75.500000,4.1,3.21,0.30,88,1,ok,512.3,500.0,,500.0,172")
        XCTAssertEqual(DiagnosticsCSV.row(record).split(separator: ",", omittingEmptySubsequences: false).count, 14)
    }

    func testCSVRowForARejectedSample() {
        let record = DiagnosticsRecord(t: 5,
                                       latitude: 0,
                                       longitude: 0,
                                       horizontalAccuracy: 27,
                                       speed: -1,
                                       speedAccuracy: -1,
                                       course: -1,
                                       accepted: false,
                                       reason: "accuracy",
                                       distance: 0,
                                       windowPace: nil,
                                       dopplerPace: nil,
                                       currentPace: nil,
                                       cadence: nil)
        XCTAssertEqual(DiagnosticsCSV.row(record),
                       "5.0,0.000000,0.000000,27.0,-1.00,-1.00,-1,0,accuracy,0.0,,,,")
    }

    func testCSVDocument() {
        let record = DiagnosticsRecord(t: 1, latitude: 1, longitude: 2, horizontalAccuracy: 3,
                                       speed: 4, speedAccuracy: 5, course: 6, accepted: true,
                                       reason: "ok", distance: 7, windowPace: nil, dopplerPace: nil,
                                       currentPace: nil, cadence: nil)
        let text = DiagnosticsCSV.document([record])
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], DiagnosticsCSV.header)
        XCTAssertEqual(lines[1], DiagnosticsCSV.row(record))
        XCTAssertEqual(lines[2], "")
    }

    func testCSVFileName() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(DiagnosticsCSV.fileName(for: Date(timeIntervalSince1970: 0), timeZone: utc),
                       "milepace-run-19700101-0000.csv")
        XCTAssertEqual(DiagnosticsCSV.fileName(for: Date(timeIntervalSince1970: 1_700_000_000), timeZone: utc),
                       "milepace-run-20231114-2213.csv")
    }

    // MARK: Voice wording

    func testZoneCueWording() {
        XCTAssertEqual(ZoneGuard.spokenText(for: .easyUp), "Slow down")
        XCTAssertEqual(ZoneGuard.spokenText(for: .pickItUp), "Speed up")
    }

    func testSecondsOutsideTracksTheCurrentStretch() throws {
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        var zoneGuard = ZoneGuard()
        XCTAssertNil(zoneGuard.secondsOutside(at: t0))
        _ = zoneGuard.update(pace: 380, zone: 400...410, now: t0)
        XCTAssertEqual(try XCTUnwrap(zoneGuard.secondsOutside(at: t0.addingTimeInterval(12))), 12, accuracy: 0.001)
        _ = zoneGuard.update(pace: 405, zone: 400...410, now: t0.addingTimeInterval(13))
        XCTAssertNil(zoneGuard.secondsOutside(at: t0.addingTimeInterval(14)))
    }
}
