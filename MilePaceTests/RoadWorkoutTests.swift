import XCTest
@testable import MilePace

final class RoadWorkoutTests: XCTestCase {
    private func label(_ event: RoadWorkoutSession.Event) -> String {
        switch event {
        case .repStarted(let number, let total): return "start\(number)/\(total)"
        case .halfway(let number): return "half\(number)"
        case .timeLeft(let number, let seconds): return "left\(seconds)-\(number)"
        case .repEnded(let number, _): return "end\(number)"
        case .recoveryCountdown(let seconds): return "cd\(seconds)"
        case .workoutComplete: return "complete"
        }
    }

    private func labels(_ events: [RoadWorkoutSession.Event]) -> [String] {
        return events.map { label($0) }
    }

    private func timedSpec(reps: Int = 2, seconds: Int = 60, recovery: Int = 30) -> RoadWorkoutSpec {
        return RoadWorkoutSpec(name: "test", reps: reps, length: .time(seconds: seconds),
                               target: .threshold, recoverySeconds: recovery)
    }

    func testTwoTimedRepsEventSequence() {
        var session = RoadWorkoutSession(spec: timedSpec())
        XCTAssertEqual(session.phase, .warmup)

        // Nothing happens during warm-up.
        XCTAssertTrue(session.update(elapsed: 5, distance: 20).isEmpty)

        // Reps start at 5 s: 30 s left at 35 (replacing halfway), end at 65, recovery to 95, rep 2 ends at 155.
        var events = session.startReps(elapsed: 5, distance: 20)
        XCTAssertEqual(session.phase, .rep(1))
        for second in 6...155 {
            events += session.update(elapsed: Double(second), distance: 4.0 * Double(second))
        }
        XCTAssertEqual(labels(events), ["start1/2", "left30-1", "end1", "cd10", "cd3",
                                        "start2/2", "left30-2", "end2", "complete"])
        XCTAssertEqual(session.phase, .cooldown)
    }

    func testRepAveragePaceFromDistanceAndTime() {
        var session = RoadWorkoutSession(spec: timedSpec())
        session.startReps(elapsed: 0, distance: 0)
        var ended: [Double?] = []
        for second in 1...150 {
            let events = session.update(elapsed: Double(second), distance: 4.0 * Double(second))
            for event in events {
                if case .repEnded(_, let pace) = event {
                    ended.append(pace)
                }
            }
        }
        XCTAssertEqual(ended.count, 2)
        for pace in ended {
            XCTAssertEqual(pace ?? 0, 402.336, accuracy: 0.01)
        }
    }

    func testDistanceBasedRepEndsOnDistance() {
        let spec = RoadWorkoutSpec(name: "d", reps: 2, length: .distance(meters: 400),
                                   target: .threshold, recoverySeconds: 0)
        var session = RoadWorkoutSession(spec: spec)
        XCTAssertEqual(labels(session.startReps(elapsed: 0, distance: 0)), ["start1/2"])
        XCTAssertEqual(labels(session.update(elapsed: 50, distance: 200)), ["half1"])
        XCTAssertTrue(session.update(elapsed: 80, distance: 320).isEmpty)

        let events = session.update(elapsed: 100, distance: 400)
        XCTAssertEqual(labels(events), ["end1", "start2/2"])
        if case .repEnded(_, let pace)? = events.first {
            XCTAssertEqual(pace ?? 0, 402.336, accuracy: 0.01)
        } else {
            XCTFail("Expected repEnded first")
        }
        XCTAssertEqual(session.phase, .rep(2))

        let remaining = session.remaining(elapsed: 120, distance: 500)
        XCTAssertNil(remaining.seconds)
        XCTAssertEqual(remaining.meters ?? 0, 300, accuracy: 0.001)
    }

    func testSkipEndsRepEarlyThenRecovery() {
        var session = RoadWorkoutSession(spec: timedSpec())
        session.startReps(elapsed: 0, distance: 0)
        XCTAssertTrue(session.update(elapsed: 10, distance: 40).isEmpty)

        let skipRep = session.skip(elapsed: 10, distance: 40)
        XCTAssertEqual(labels(skipRep), ["end1"])
        if case .repEnded(_, let pace)? = skipRep.first {
            XCTAssertEqual(pace ?? 0, 402.336, accuracy: 0.01)
        } else {
            XCTFail("Expected repEnded")
        }
        XCTAssertEqual(session.phase, .recovery(1))

        XCTAssertTrue(session.update(elapsed: 20, distance: 80).isEmpty)
        let skipRecovery = session.skip(elapsed: 20, distance: 80)
        XCTAssertEqual(labels(skipRecovery), ["start2/2"])
        XCTAssertEqual(session.phase, .rep(2))
    }

    func testSkipDoesNothingInWarmupAndCooldown() {
        var session = RoadWorkoutSession(spec: timedSpec(reps: 1, seconds: 60, recovery: 0))
        XCTAssertTrue(session.skip(elapsed: 5, distance: 10).isEmpty)
        XCTAssertEqual(session.phase, .warmup)
        session.startReps(elapsed: 5, distance: 10)
        let done = session.update(elapsed: 70, distance: 300)
        XCTAssertEqual(labels(done), ["end1", "complete"])
        XCTAssertTrue(session.skip(elapsed: 71, distance: 304).isEmpty)
        XCTAssertEqual(session.phase, .cooldown)
    }

    func testUpdateIsIdempotent() {
        var session = RoadWorkoutSession(spec: timedSpec())
        session.startReps(elapsed: 0, distance: 0)
        XCTAssertEqual(labels(session.update(elapsed: 30, distance: 120)), ["left30-1"])
        XCTAssertTrue(session.update(elapsed: 30, distance: 120).isEmpty)

        XCTAssertEqual(labels(session.update(elapsed: 60, distance: 240)), ["end1"])
        XCTAssertTrue(session.update(elapsed: 60, distance: 240).isEmpty)

        XCTAssertEqual(labels(session.update(elapsed: 80, distance: 320)), ["cd10"])
        XCTAssertTrue(session.update(elapsed: 80, distance: 320).isEmpty)
    }

    func testNoRecoveryAfterLastRep() {
        var session = RoadWorkoutSession(spec: timedSpec(reps: 1, seconds: 60, recovery: 30))
        session.startReps(elapsed: 0, distance: 0)
        XCTAssertEqual(labels(session.update(elapsed: 60, distance: 240)), ["end1", "complete"])
        XCTAssertEqual(session.phase, .cooldown)
        XCTAssertTrue(session.update(elapsed: 100, distance: 400).isEmpty)
        XCTAssertTrue(session.update(elapsed: 200, distance: 800).isEmpty)
    }

    func testRemainingAndPhaseTitles() {
        var session = RoadWorkoutSession(spec: timedSpec(reps: 4, seconds: 360, recovery: 120))
        XCTAssertEqual(session.phaseTitle, "Warm-up")
        XCTAssertNil(session.remaining(elapsed: 10, distance: 0).seconds)
        XCTAssertFalse(session.isInRepOrRecovery)

        session.startReps(elapsed: 100, distance: 400)
        XCTAssertEqual(session.phaseTitle, "Rep 1 of 4")
        XCTAssertTrue(session.isInRep)
        XCTAssertEqual(session.remaining(elapsed: 160, distance: 640).seconds ?? 0, 300, accuracy: 0.001)
        XCTAssertNil(session.remaining(elapsed: 160, distance: 640).meters)

        session.update(elapsed: 460, distance: 1840)
        XCTAssertEqual(session.phaseTitle, "Recovery")
        XCTAssertTrue(session.isInRepOrRecovery)
        XCTAssertFalse(session.isInRep)
        XCTAssertEqual(session.remaining(elapsed: 500, distance: 1900).seconds ?? 0, 80, accuracy: 0.001)
    }

    func testShortRecoverySkipsCountdowns() {
        var session = RoadWorkoutSession(spec: timedSpec(reps: 2, seconds: 60, recovery: 3))
        session.startReps(elapsed: 0, distance: 0)
        var events: [RoadWorkoutSession.Event] = []
        for second in 1...70 {
            events += session.update(elapsed: Double(second), distance: 4.0 * Double(second))
        }
        XCTAssertEqual(labels(events), ["left30-1", "end1", "start2/2"])
    }

    // MARK: Presets and specs

    func testPresets() throws {
        let presets = RoadWorkoutPresets.all
        XCTAssertEqual(presets.count, 15)
        XCTAssertEqual(Set(presets.map { $0.id }).count, presets.count)
        XCTAssertEqual(presets.first?.name, "3 × 5 min threshold")
        XCTAssertTrue(presets.contains { $0.name == "20 min tempo" })
        XCTAssertTrue(presets.allSatisfy { $0.target == .threshold })

        let tempo = try XCTUnwrap(presets.first { $0.name == "25 min tempo" })
        XCTAssertEqual(tempo.reps, 1)
        XCTAssertEqual(tempo.recoverySeconds, 0)
        XCTAssertEqual(tempo.length, .time(seconds: 1500))

        let miles = try XCTUnwrap(presets.first { $0.name == "3 × 1 mi threshold" })
        XCTAssertEqual(miles.recoverySeconds, 60)
        if case .distance(let meters) = miles.length {
            XCTAssertEqual(meters, 1609.344, accuracy: 1e-6)
        } else {
            XCTFail("Expected a distance rep")
        }
        let long = try XCTUnwrap(presets.first { $0.name == "3 × 1.5 mi threshold" })
        XCTAssertEqual(long.recoverySeconds, 120)
        if case .distance(let meters) = long.length {
            XCTAssertEqual(meters, 2414.016, accuracy: 1e-6)
        } else {
            XCTFail("Expected a distance rep")
        }
    }

    func testSpecIsCodable() throws {
        for spec in RoadWorkoutPresets.all {
            let data = try JSONEncoder().encode(spec)
            let decoded = try JSONDecoder().decode(RoadWorkoutSpec.self, from: data)
            XCTAssertEqual(decoded, spec)
        }
    }

    func testTargetRanges() {
        let zones = PaceZones.forMile(412)
        XCTAssertEqual(RepTarget.threshold.range(zones: zones, goalMile: 330), zones.threshold)
        XCTAssertEqual(RepTarget.interval.range(zones: zones, goalMile: 330), zones.interval)
        XCTAssertEqual(RepTarget.goal.range(zones: zones, goalMile: 330), 327...333)
    }

    func testSpokenLength() {
        XCTAssertEqual(timedSpec(seconds: 360).spokenLength, "6 minutes")
        XCTAssertEqual(timedSpec(seconds: 60).spokenLength, "1 minute")
        let mile = RoadWorkoutSpec(name: "m", reps: 1, length: .distance(meters: 1609.344),
                                   target: .goal, recoverySeconds: 0)
        XCTAssertEqual(mile.spokenLength, "1 mile")
        let long = RoadWorkoutSpec(name: "l", reps: 1, length: .distance(meters: 2414.016),
                                   target: .goal, recoverySeconds: 0)
        XCTAssertEqual(long.spokenLength, "1.5 miles")
    }

    func testTwoMinuteRepCallsOneMinuteAndThirtySecondsLeft() {
        var session = RoadWorkoutSession(spec: timedSpec(reps: 2, seconds: 120, recovery: 60))
        var events = session.startReps(elapsed: 0, distance: 0)
        for second in 1...300 {
            events += session.update(elapsed: Double(second), distance: 4.0 * Double(second))
        }
        XCTAssertEqual(labels(events), ["start1/2", "left60-1", "left30-1", "end1", "cd10", "cd3",
                                        "start2/2", "left60-2", "left30-2", "end2", "complete"])
        XCTAssertEqual(session.phase, .cooldown)
    }

    func testLongRepKeepsHalfwayAndTimeLeftCues() {
        var session = RoadWorkoutSession(spec: timedSpec(reps: 1, seconds: 300, recovery: 0))
        var events = session.startReps(elapsed: 0, distance: 0)
        for second in 1...300 {
            events += session.update(elapsed: Double(second), distance: 4.0 * Double(second))
        }
        XCTAssertEqual(labels(events), ["start1/1", "half1", "left60-1", "left30-1", "end1", "complete"])
    }

    func testLateUpdateSkipsStaleTimeLeftCue() {
        var session = RoadWorkoutSession(spec: timedSpec(reps: 1, seconds: 120, recovery: 0))
        session.startReps(elapsed: 0, distance: 0)
        // Nothing reached the app between 50 s and 100 s: only the cue that is still true is said.
        XCTAssertTrue(session.update(elapsed: 50, distance: 200).isEmpty)
        XCTAssertEqual(labels(session.update(elapsed: 100, distance: 400)), ["left30-1"])
    }

    func testSkipRightAfterAPhaseChangeIsIgnored() {
        var session = RoadWorkoutSession(spec: timedSpec(reps: 2, seconds: 120, recovery: 60))
        session.startReps(elapsed: 0, distance: 0)
        _ = session.update(elapsed: 180, distance: 720)
        XCTAssertEqual(session.phase, .rep(2))
        // Rep 2 began at 180 s; a tap 1 s later was meant for "skip rest" and must not end rep 2.
        XCTAssertTrue(session.skip(elapsed: 181, distance: 724).isEmpty)
        XCTAssertEqual(session.phase, .rep(2))
        XCTAssertEqual(labels(session.skip(elapsed: 200, distance: 800)), ["end2", "complete"])
    }
}
