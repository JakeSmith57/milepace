import XCTest
@testable import MilePace

final class TrackWorkoutTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1000)

    private func at(_ seconds: Double) -> Date {
        return t0.addingTimeInterval(seconds)
    }

    private func twoByEightHundred() -> WorkoutSpec {
        return WorkoutSpec(name: "2 x 800", reps: 2, repDistance: 800, targetRepSeconds: 200, restSeconds: 60)
    }

    func testLapFractions() {
        XCTAssertEqual(WorkoutSpec(name: "a", reps: 1, repDistance: 200, targetRepSeconds: 40, restSeconds: 0).lapsPerRep, 1)
        XCTAssertEqual(WorkoutSpec(name: "a", reps: 1, repDistance: 300, targetRepSeconds: 60, restSeconds: 0).lapsPerRep, 1)
        XCTAssertEqual(WorkoutSpec(name: "a", reps: 1, repDistance: 400, targetRepSeconds: 80, restSeconds: 0).lapsPerRep, 1)
        XCTAssertEqual(WorkoutSpec(name: "a", reps: 1, repDistance: 800, targetRepSeconds: 160, restSeconds: 0).lapsPerRep, 2)
        XCTAssertEqual(WorkoutSpec(name: "a", reps: 1, repDistance: 1200, targetRepSeconds: 240, restSeconds: 0).lapsPerRep, 3)
        let mile = WorkoutSpec(name: "mile", reps: 1, repDistance: 1609, targetRepSeconds: 330, restSeconds: 0)
        XCTAssertEqual(mile.lapsPerRep, 4)
        XCTAssertEqual(mile.lapTarget(lap: 0), 82.5, accuracy: 1e-9)
        XCTAssertEqual(mile.lapTarget(lap: 3), 82.5, accuracy: 1e-9)
        let sixHundred = WorkoutSpec(name: "600", reps: 1, repDistance: 600, targetRepSeconds: 120, restSeconds: 0)
        XCTAssertEqual(sixHundred.lapsPerRep, 2)
        XCTAssertEqual(sixHundred.lapFractions.reduce(0, +), 1.0, accuracy: 1e-9)
    }

    func testSpecIsCodable() throws {
        let spec = WorkoutSpec(name: "x", reps: 4, repDistance: 400, targetRepSeconds: 83,
                               restSeconds: 60, sets: 2, setRestSeconds: 300)
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(WorkoutSpec.self, from: data)
        XCTAssertEqual(decoded, spec)
    }

    func testTwoByEightHundredFlow() {
        var workout = TrackWorkout(spec: twoByEightHundred())
        XCTAssertEqual(workout.state, .ready)
        XCTAssertEqual(workout.lapTap(now: at(0)), .ignored)

        workout.start(now: at(0))
        XCTAssertEqual(workout.state, .running(rep: 1, lap: 1))

        // Lap 1 of rep 1: 98 s against a 100 s lap target.
        let first = workout.lapTap(now: at(98))
        XCTAssertEqual(first, .lapDone(split: 98, delta: -2, repFinished: false, workoutFinished: false))
        XCTAssertEqual(workout.state, .running(rep: 1, lap: 2))

        // Lap 2 finishes the rep: 102 s, rep time 200.
        let second = workout.lapTap(now: at(200))
        XCTAssertEqual(second, .lapDone(split: 102, delta: 2, repFinished: true, workoutFinished: false))
        XCTAssertEqual(workout.repTimes.count, 1)
        XCTAssertEqual(workout.repTimes[0], 200, accuracy: 1e-9)
        XCTAssertEqual(workout.state, .resting(until: at(260)))
        XCTAssertFalse(workout.isRestComplete)

        // Taps are ignored until the rest completes, and the rest does not auto-start the rep.
        XCTAssertEqual(workout.lapTap(now: at(210)), .ignored)
        XCTAssertFalse(workout.tick(now: at(259)))
        XCTAssertTrue(workout.tick(now: at(260)))
        XCTAssertTrue(workout.isRestComplete)
        XCTAssertFalse(workout.tick(now: at(261)))
        XCTAssertEqual(workout.state, .resting(until: at(260)))

        // GO starts rep 2.
        XCTAssertEqual(workout.lapTap(now: at(270)), .startedRep)
        XCTAssertEqual(workout.state, .running(rep: 2, lap: 1))

        _ = workout.lapTap(now: at(270 + 100))
        let last = workout.lapTap(now: at(270 + 205))
        XCTAssertEqual(last, .lapDone(split: 105, delta: 5, repFinished: true, workoutFinished: true))
        XCTAssertEqual(workout.state, .finished)

        XCTAssertEqual(workout.lapSplits.count, 2)
        XCTAssertEqual(workout.lapSplits.flatMap { $0 }.count, 4)
        XCTAssertEqual(workout.repTimes.count, 2)
        XCTAssertEqual(workout.repTimes[1], 205, accuracy: 1e-9)
        XCTAssertEqual(workout.repDelta(rep: 1) ?? 99, 0, accuracy: 1e-9)
        XCTAssertEqual(workout.repDelta(rep: 2) ?? 99, 5, accuracy: 1e-9)
        XCTAssertEqual(workout.averageRepTime ?? 0, 202.5, accuracy: 1e-9)
        XCTAssertEqual(workout.lapDelta(rep: 1, lap: 1) ?? 99, -2, accuracy: 1e-9)
        XCTAssertEqual(workout.lapDelta(rep: 2, lap: 2) ?? 99, 5, accuracy: 1e-9)
        XCTAssertNil(workout.lapDelta(rep: 3, lap: 1))
    }

    func testSkipRestThenGo() {
        var workout = TrackWorkout(spec: twoByEightHundred())
        workout.start(now: at(0))
        workout.lapTap(now: at(100))
        workout.lapTap(now: at(200))
        XCTAssertTrue(workout.isResting)
        workout.skipRest(now: at(205))
        XCTAssertTrue(workout.isRestComplete)
        XCTAssertEqual(workout.restRemaining(at: at(205)), 0)
        XCTAssertEqual(workout.lapTap(now: at(206)), .startedRep)
    }

    func testUndoLastTap() {
        var workout = TrackWorkout(spec: twoByEightHundred())
        XCTAssertFalse(workout.undoLastTap())
        workout.start(now: at(0))
        XCTAssertFalse(workout.canUndo)

        workout.lapTap(now: at(98))
        XCTAssertTrue(workout.canUndo)
        XCTAssertEqual(workout.lapSplits[0].count, 1)

        XCTAssertTrue(workout.undoLastTap())
        XCTAssertEqual(workout.state, .running(rep: 1, lap: 1))
        XCTAssertEqual(workout.lapSplits[0].count, 0)
        XCTAssertEqual(workout.lapStart, at(0))

        // Undo of a rep-finishing tap returns to running and removes the rep time.
        workout.lapTap(now: at(100))
        workout.lapTap(now: at(200))
        XCTAssertEqual(workout.repTimes.count, 1)
        XCTAssertTrue(workout.undoLastTap())
        XCTAssertEqual(workout.repTimes.count, 0)
        XCTAssertEqual(workout.state, .running(rep: 1, lap: 2))

        // Undo of GO returns to the completed rest.
        workout.lapTap(now: at(200))
        workout.tick(now: at(260))
        workout.lapTap(now: at(270))
        XCTAssertEqual(workout.state, .running(rep: 2, lap: 1))
        XCTAssertTrue(workout.undoLastTap())
        XCTAssertTrue(workout.isResting)
        XCTAssertTrue(workout.isRestComplete)
    }

    func testSetRestBetweenSets() {
        let spec = WorkoutSpec(name: "2 sets", reps: 2, repDistance: 400, targetRepSeconds: 83,
                               restSeconds: 60, sets: 2, setRestSeconds: 300)
        var workout = TrackWorkout(spec: spec)
        XCTAssertEqual(spec.totalReps, 4)
        workout.start(now: at(0))
        workout.lapTap(now: at(83))
        XCTAssertEqual(workout.state, .resting(until: at(143)))
        XCTAssertTrue(workout.tick(now: at(143)))
        workout.lapTap(now: at(150))
        workout.lapTap(now: at(233))
        XCTAssertEqual(workout.state, .setRest(until: at(533)))
        XCTAssertEqual(workout.restTotal, 300, accuracy: 1e-9)
        XCTAssertEqual(workout.setNumber(forRep: 2), 1)
        XCTAssertEqual(workout.setNumber(forRep: 3), 2)
    }

    func testFinishEarlyKeepsOnlyCompletedReps() {
        var workout = TrackWorkout(spec: twoByEightHundred())
        workout.start(now: at(0))
        workout.lapTap(now: at(100))
        workout.lapTap(now: at(200))
        workout.tick(now: at(260))
        workout.lapTap(now: at(270))
        workout.lapTap(now: at(370))
        workout.finishEarly()
        XCTAssertEqual(workout.state, .finished)
        XCTAssertEqual(workout.repTimes.count, 1)
        XCTAssertEqual(workout.lapSplits.count, 1)
    }

    func testVerdictThreshold() {
        XCTAssertEqual(SplitVerdict.verdict(delta: 1.0), .onPace)
        XCTAssertEqual(SplitVerdict.verdict(delta: -1.0), .onPace)
        XCTAssertEqual(SplitVerdict.verdict(delta: 1.1), .slow)
        XCTAssertEqual(SplitVerdict.verdict(delta: -1.1), .fast)
        XCTAssertEqual(SplitVerdict.verdict(delta: 0), .onPace)
    }

    func testPresetsUseZonesAndGoal() {
        let zones = PaceZones.forMile(412)
        let preset = WorkoutPresets.all.first { $0.id == "6x200-r" }
        XCTAssertNotNil(preset)
        let spec = preset?.spec(zones: zones, goalMile: 330)
        XCTAssertEqual(spec?.targetRepSeconds ?? 0, 51.5, accuracy: 0.0001)
        XCTAssertEqual(spec?.restSeconds, 75)

        let trial = WorkoutPresets.all.first { $0.group == .timeTrial }
        XCTAssertEqual(trial?.spec(zones: zones, goalMile: 330).targetRepSeconds ?? 0, 330, accuracy: 0.0001)
        XCTAssertEqual(trial?.spec(zones: zones, goalMile: 345).targetRepSeconds ?? 0, 345, accuracy: 0.0001)

        let sets = WorkoutPresets.all.first { $0.id == "4s-2x400-84" }?.spec(zones: zones, goalMile: 330)
        XCTAssertEqual(sets?.sets, 4)
        XCTAssertEqual(sets?.setRestSeconds, 240)
        XCTAssertEqual(WorkoutPresets.all.count, 17)
        for group in PresetGroup.allCases {
            XCTAssertFalse(WorkoutPresets.presets(in: group).isEmpty)
        }
    }
}
