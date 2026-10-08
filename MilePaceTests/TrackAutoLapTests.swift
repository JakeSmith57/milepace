import XCTest
@testable import MilePace

/// GPS auto-lap rules (v1.16): lap ends, crossing time, guards, calibration and the saved draft.
final class TrackAutoLapTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 5000)

    private func spec(_ distance: Int, target: Double = 100) -> WorkoutSpec {
        return WorkoutSpec(name: "w", reps: 2, repDistance: distance, targetRepSeconds: target, restSeconds: 60)
    }

    private func fix(before: Double,
                     after: Double,
                     previous: Double,
                     time: Double,
                     accuracy: Double = 5,
                     previousAccuracy: Double = 5) -> TrackAutoLap.Fix {
        return TrackAutoLap.Fix(before: before,
                                after: after,
                                previousTime: t0.addingTimeInterval(previous),
                                time: t0.addingTimeInterval(time),
                                accuracy: accuracy,
                                previousAccuracy: previousAccuracy)
    }

    // MARK: Boundaries

    func testLapBoundaries() {
        XCTAssertEqual(TrackAutoLap.lapBoundaries(spec(200)), [200])
        XCTAssertEqual(TrackAutoLap.lapBoundaries(spec(400)), [400])
        XCTAssertEqual(TrackAutoLap.lapBoundaries(spec(800)), [400, 800])
        let six = TrackAutoLap.lapBoundaries(spec(600))
        XCTAssertEqual(six.count, 2)
        XCTAssertEqual(six[0], 400, accuracy: 1e-9)
        XCTAssertEqual(six[1], 600, accuracy: 1e-9)
        let mile = TrackAutoLap.lapBoundaries(spec(1609))
        XCTAssertEqual(mile.count, 4)
        XCTAssertEqual(mile[0], 402.25, accuracy: 1e-9)
        XCTAssertEqual(mile[3], 1609, accuracy: 1e-9)
    }

    func testBoundaryByLap() {
        let twelve = spec(1200)
        XCTAssertEqual(TrackAutoLap.boundary(twelve, lap: 1), 400)
        XCTAssertEqual(TrackAutoLap.boundary(twelve, lap: 3), 1200)
        XCTAssertNil(TrackAutoLap.boundary(twelve, lap: 4))
        XCTAssertNil(TrackAutoLap.boundary(twelve, lap: 0))
    }

    // MARK: Crossing time

    func testCrossingIsInterpolated() {
        let crossing = TrackAutoLap.crossingTime(before: 190,
                                                 after: 210,
                                                 previousTime: t0,
                                                 time: t0.addingTimeInterval(2),
                                                 boundary: 200)
        XCTAssertEqual(crossing.timeIntervalSince(t0), 1.0, accuracy: 1e-9)
        let quarter = TrackAutoLap.crossingTime(before: 190,
                                                after: 240,
                                                previousTime: t0,
                                                time: t0.addingTimeInterval(5),
                                                boundary: 200)
        XCTAssertEqual(quarter.timeIntervalSince(t0), 1.0, accuracy: 1e-9)
    }

    func testCrossingAtOrWithoutProgressUsesFixTime() {
        let end = t0.addingTimeInterval(2)
        XCTAssertEqual(TrackAutoLap.crossingTime(before: 190, after: 200, previousTime: t0, time: end, boundary: 200), end)
        XCTAssertEqual(TrackAutoLap.crossingTime(before: 200, after: 200, previousTime: t0, time: end, boundary: 200), end)
    }

    // MARK: Decisions

    func testWaitsBeforeTheBoundary() {
        let decision = TrackAutoLap.evaluate(fix: fix(before: 150, after: 170, previous: 30, time: 32),
                                             boundary: 200,
                                             lapStart: t0,
                                             lapTarget: 40)
        XCTAssertEqual(decision, .wait)
    }

    func testCrossesAtTheInterpolatedMoment() {
        let decision = TrackAutoLap.evaluate(fix: fix(before: 195, after: 205, previous: 30, time: 32),
                                             boundary: 200,
                                             lapStart: t0,
                                             lapTarget: 40)
        XCTAssertEqual(decision, .cross(t0.addingTimeInterval(31)))
    }

    func testEarlyCrossingIsNotBelieved() {
        // 60 % of 40 s is 24 s; a "crossing" at 6 s is a GPS jump.
        let decision = TrackAutoLap.evaluate(fix: fix(before: 195, after: 205, previous: 5, time: 7),
                                             boundary: 200,
                                             lapStart: t0,
                                             lapTarget: 40)
        XCTAssertEqual(decision, .wait)
        let justEnough = TrackAutoLap.evaluate(fix: fix(before: 195, after: 205, previous: 24, time: 26),
                                               boundary: 200,
                                               lapStart: t0,
                                               lapTarget: 40)
        XCTAssertEqual(justEnough, .cross(t0.addingTimeInterval(25)))
    }

    func testRoughFixesAreNotTrusted() {
        XCTAssertEqual(TrackAutoLap.evaluate(fix: fix(before: 195, after: 205, previous: 30, time: 32, accuracy: 20),
                                             boundary: 200, lapStart: t0, lapTarget: 40), .weakGPS)
        XCTAssertEqual(TrackAutoLap.evaluate(fix: fix(before: 195, after: 205, previous: 30, time: 32, previousAccuracy: 20),
                                             boundary: 200, lapStart: t0, lapTarget: 40), .weakGPS)
        XCTAssertEqual(TrackAutoLap.evaluate(fix: fix(before: 195, after: 205, previous: 30, time: 32, accuracy: -1),
                                             boundary: 200, lapStart: t0, lapTarget: 40), .weakGPS)
        // 15 m is still good.
        XCTAssertEqual(TrackAutoLap.evaluate(fix: fix(before: 195, after: 205, previous: 30, time: 32, accuracy: 15, previousAccuracy: 15),
                                             boundary: 200, lapStart: t0, lapTarget: 40), .cross(t0.addingTimeInterval(31)))
    }

    func testLateCrossingUsesTheFixTimeAndOnlyNeedsItsOwnAccuracy() {
        // The boundary was passed before this fix (an earlier one was rough): stamp this fix.
        let decision = TrackAutoLap.evaluate(fix: fix(before: 205, after: 215, previous: 32, time: 33, previousAccuracy: 30),
                                             boundary: 200,
                                             lapStart: t0,
                                             lapTarget: 40)
        XCTAssertEqual(decision, .cross(t0.addingTimeInterval(33)))
    }

    func testTimeGuardComesBeforeAccuracy() {
        let decision = TrackAutoLap.evaluate(fix: fix(before: 195, after: 205, previous: 5, time: 7, accuracy: 30),
                                             boundary: 200,
                                             lapStart: t0,
                                             lapTarget: 40)
        XCTAssertEqual(decision, .wait)
    }

    func testAutoTimestampFeedsTheStateMachine() {
        var workout = TrackWorkout(spec: spec(200, target: 55.5))
        workout.start(now: t0)
        let outcome = workout.lapTap(now: t0.addingTimeInterval(55.5))
        XCTAssertEqual(outcome, .lapDone(split: 55.5, delta: 0, repFinished: true, workoutFinished: false))
        XCTAssertEqual(workout.repTimes, [55.5])
    }

    // MARK: Calibration

    func testCalibrationFactor() {
        XCTAssertEqual(TrackAutoLap.calibrationFactor(measured: 400) ?? 0, 1.0, accuracy: 1e-9)
        XCTAssertEqual(TrackAutoLap.calibrationFactor(measured: 392) ?? 0, 400.0 / 392.0, accuracy: 1e-9)
        XCTAssertEqual(TrackAutoLap.calibrationFactor(measured: 300) ?? 0, 1.15, accuracy: 1e-9)
        XCTAssertEqual(TrackAutoLap.calibrationFactor(measured: 500) ?? 0, 0.85, accuracy: 1e-9)
        XCTAssertNil(TrackAutoLap.calibrationFactor(measured: 100))
        XCTAssertNil(TrackAutoLap.calibrationFactor(measured: Double.nan))
    }

    func testRepMeter() {
        var meter = TrackRepMeter()
        XCTAssertFalse(meter.isValid)
        XCTAssertNil(meter.meters(atRaw: 10))
        meter.factor = 1.02
        meter.begin(atRaw: 100)
        XCTAssertTrue(meter.isValid)
        XCTAssertEqual(meter.meters(atRaw: 150) ?? 0, 51, accuracy: 1e-9)
        XCTAssertEqual(meter.meters(atRaw: 90) ?? -1, 0, accuracy: 1e-9)
        meter.snap(toMeters: 400, atRaw: 500)
        XCTAssertEqual(meter.meters(atRaw: 500) ?? 0, 400, accuracy: 1e-9)
        XCTAssertEqual(meter.meters(atRaw: 510) ?? 0, 410.2, accuracy: 1e-9)
        meter.invalidate()
        XCTAssertNil(meter.meters(atRaw: 510))
    }

    func testCalibrationAgeAndStore() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000_000)
        let fresh = TrackCalibration(factor: 1.03, date: now.addingTimeInterval(-59 * 86_400))
        let old = TrackCalibration(factor: 1.03, date: now.addingTimeInterval(-61 * 86_400))
        XCTAssertFalse(fresh.isStale(now: now))
        XCTAssertTrue(old.isStale(now: now))

        let suite = "TrackAutoLapTests.store"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("no defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suite)
        XCTAssertNil(TrackCalibrationStore.load(defaults: defaults))
        TrackCalibrationStore.save(fresh, defaults: defaults)
        XCTAssertEqual(TrackCalibrationStore.load(defaults: defaults), fresh)
        TrackCalibrationStore.save(TrackCalibration(factor: 2.0, date: now), defaults: defaults)
        XCTAssertNil(TrackCalibrationStore.load(defaults: defaults))
        TrackCalibrationStore.clear(defaults: defaults)
        XCTAssertNil(TrackCalibrationStore.load(defaults: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    // MARK: Draft

    func testDraftKeepsAutoEndedAndReadsOldDrafts() throws {
        let workout = TrackWorkout(spec: spec(200))
        let draft = TrackSessionDraft(workout: workout,
                                      sessionStart: t0,
                                      savedAt: t0,
                                      isTest: false,
                                      autoEnded: [1, 3])
        let data = try JSONEncoder().encode(draft)
        XCTAssertEqual(try JSONDecoder().decode(TrackSessionDraft.self, from: data).autoEnded, [1, 3])

        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("draft is not a JSON object")
            return
        }
        object.removeValue(forKey: "autoEnded")
        let old = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(TrackSessionDraft.self, from: old).autoEnded, [])
    }
}
