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
        XCTAssertEqual(WorkoutPresets.all.count, 25)
        for group in PresetGroup.allCases {
            XCTAssertFalse(WorkoutPresets.presets(in: group).isEmpty)
        }
    }

    // MARK: Bounce guard, undo and persistence

    func testLapTapsUnderTenSecondsAreIgnored() {
        var workout = TrackWorkout(spec: twoByEightHundred())
        workout.start(now: at(0))
        XCTAssertEqual(workout.lapTap(now: at(9.9)), .tooSoon)
        XCTAssertEqual(workout.state, .running(rep: 1, lap: 1))
        XCTAssertFalse(workout.canUndo)
        XCTAssertEqual(workout.lapSplits, [[]])

        // Exactly ten seconds counts.
        let first = workout.lapTap(now: at(10))
        XCTAssertEqual(first, .lapDone(split: 10, delta: -90, repFinished: false, workoutFinished: false))
        // The next lap's clock starts at that tap.
        XCTAssertEqual(workout.lapTap(now: at(15)), .tooSoon)
        XCTAssertEqual(workout.state, .running(rep: 1, lap: 2))
        XCTAssertEqual(TrackWorkout.minLapSeconds, 10)
    }

    func testTheFirstLapAfterGoIsAlsoGuarded() {
        var workout = TrackWorkout(spec: twoByEightHundred())
        workout.start(now: at(0))
        _ = workout.lapTap(now: at(98))
        _ = workout.lapTap(now: at(200))
        XCTAssertTrue(workout.tick(now: at(260)))
        XCTAssertEqual(workout.lapTap(now: at(270)), .startedRep)
        XCTAssertEqual(workout.lapTap(now: at(275)), .tooSoon)
        XCTAssertEqual(workout.state, .running(rep: 2, lap: 1))
    }

    func testUndoBringsBackASkippedRest() {
        var workout = TrackWorkout(spec: twoByEightHundred())
        workout.start(now: at(0))
        _ = workout.lapTap(now: at(98))
        _ = workout.lapTap(now: at(200))
        XCTAssertEqual(workout.state, .resting(until: at(260)))

        workout.skipRest(now: at(210))
        XCTAssertTrue(workout.isRestComplete)
        XCTAssertTrue(workout.canUndo)

        XCTAssertTrue(workout.undoLastTap())
        XCTAssertFalse(workout.isRestComplete)
        XCTAssertEqual(workout.state, .resting(until: at(260)))
        XCTAssertEqual(workout.repTimes.count, 1)

        // The next undo takes back the lap tap that ended rep 1.
        XCTAssertTrue(workout.undoLastTap())
        XCTAssertEqual(workout.state, .running(rep: 1, lap: 2))
        XCTAssertEqual(workout.repTimes, [])
    }

    func testUndoFromFinishedGoesBackToTheLastLap() {
        let single = WorkoutSpec(name: "1 x 400", reps: 1, repDistance: 400, targetRepSeconds: 80, restSeconds: 0)
        var workout = TrackWorkout(spec: single)
        workout.start(now: at(0))
        let outcome = workout.lapTap(now: at(80))
        XCTAssertEqual(outcome, .lapDone(split: 80, delta: 0, repFinished: true, workoutFinished: true))
        XCTAssertEqual(workout.state, .finished)

        XCTAssertTrue(workout.undoLastTap())
        XCTAssertEqual(workout.state, .running(rep: 1, lap: 1))
        XCTAssertEqual(workout.repTimes, [])
        XCTAssertEqual(workout.lapSplits, [[]])
        XCTAssertFalse(workout.undoLastTap())
    }

    func testAWorkoutSurvivesEncodingMidRest() throws {
        var workout = TrackWorkout(spec: twoByEightHundred())
        workout.start(now: at(0))
        _ = workout.lapTap(now: at(98))
        _ = workout.lapTap(now: at(200))
        let data = try JSONEncoder().encode(workout)
        var decoded = try JSONDecoder().decode(TrackWorkout.self, from: data)
        XCTAssertEqual(decoded, workout)
        XCTAssertEqual(decoded.state, .resting(until: at(260)))
        XCTAssertEqual(decoded.repTimes.count, 1)
        // The undo history came along.
        XCTAssertTrue(decoded.canUndo)
        XCTAssertTrue(decoded.undoLastTap())
        XCTAssertEqual(decoded.state, .running(rep: 1, lap: 2))
    }

    func testEveryTrackStateEncodes() throws {
        let states: [TrackState] = [.ready, .running(rep: 2, lap: 1), .resting(until: at(5)),
                                    .setRest(until: at(9)), .finished]
        for state in states {
            let data = try JSONEncoder().encode(state)
            XCTAssertEqual(try JSONDecoder().decode(TrackState.self, from: data), state)
        }
    }

    // MARK: Draft

    func testTrackDraftFreshnessAndTitles() {
        var workout = TrackWorkout(spec: twoByEightHundred())
        workout.start(now: at(0))
        let saved = Date(timeIntervalSinceReferenceDate: 100_000)
        let draft = TrackSessionDraft(workout: workout, sessionStart: saved.addingTimeInterval(-600), savedAt: saved)
        XCTAssertTrue(draft.isFresh(now: saved))
        XCTAssertTrue(draft.isFresh(now: saved.addingTimeInterval(3 * 3600)))
        XCTAssertFalse(draft.isFresh(now: saved.addingTimeInterval(3 * 3600 + 1)))
        XCTAssertFalse(draft.isFresh(now: saved.addingTimeInterval(-1)))
        XCTAssertFalse(draft.isFinished)
        XCTAssertEqual(draft.title, "resume 2 x 800")
        XCTAssertEqual(draft.actionTitle, "resume")

        var over = workout
        over.finishEarly()
        let finished = TrackSessionDraft(workout: over, sessionStart: saved, savedAt: saved)
        XCTAssertTrue(finished.isFinished)
        XCTAssertEqual(finished.title, "unsaved results: 2 x 800")
        XCTAssertEqual(finished.actionTitle, "open")
    }

    func testTrackDraftStore() throws {
        let suite = "milepace.tests.trackdraft"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        var workout = TrackWorkout(spec: twoByEightHundred())
        workout.start(now: at(0))
        _ = workout.lapTap(now: at(98))
        let saved = Date(timeIntervalSinceReferenceDate: 100_000)
        let draft = TrackSessionDraft(workout: workout, sessionStart: saved.addingTimeInterval(-300), savedAt: saved)

        XCTAssertNil(TrackSessionStore.load(now: saved, defaults: defaults))
        TrackSessionStore.save(draft, defaults: defaults)
        XCTAssertEqual(TrackSessionStore.load(now: saved.addingTimeInterval(60), defaults: defaults), draft)

        // An old draft is forgotten and removed.
        XCTAssertNil(TrackSessionStore.load(now: saved.addingTimeInterval(4 * 3600), defaults: defaults))
        XCTAssertNil(defaults.data(forKey: TrackSessionStore.key))

        // So is one that does not read back.
        defaults.set(Data("nope".utf8), forKey: TrackSessionStore.key)
        XCTAssertNil(TrackSessionStore.load(now: saved, defaults: defaults))
        XCTAssertNil(defaults.data(forKey: TrackSessionStore.key))

        TrackSessionStore.save(draft, defaults: defaults)
        TrackSessionStore.clear(defaults: defaults)
        XCTAssertNil(TrackSessionStore.load(now: saved, defaults: defaults))
    }

    private func finishedOneByFourHundred() -> TrackWorkout {
        var workout = TrackWorkout(spec: WorkoutSpec(name: "1 x 400", reps: 1, repDistance: 400,
                                                     targetRepSeconds: 80, restSeconds: 0))
        workout.start(now: at(0))
        workout.lapTap(now: at(80))
        return workout
    }

    func testAFinishedDraftNeverExpiresButAnUnfinishedOneDoes() throws {
        let suite = "milepace.tests.trackdraft.finished"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let finished = finishedOneByFourHundred()
        XCTAssertEqual(finished.state, .finished)
        let saved = Date(timeIntervalSinceReferenceDate: 100_000)
        let draft = TrackSessionDraft(workout: finished, sessionStart: saved.addingTimeInterval(-300), savedAt: saved)
        XCTAssertTrue(draft.isFinished)
        XCTAssertFalse(draft.isFresh(now: saved.addingTimeInterval(4 * 3600)))
        XCTAssertTrue(draft.isKept(now: saved.addingTimeInterval(4 * 3600)))

        // Three days later it is still offered, and still on disk.
        TrackSessionStore.save(draft, defaults: defaults)
        XCTAssertEqual(TrackSessionStore.load(now: saved.addingTimeInterval(3 * 86_400), defaults: defaults), draft)
        XCTAssertNotNil(defaults.data(forKey: TrackSessionStore.key))

        // An unfinished one keeps the three hour rule.
        var running = TrackWorkout(spec: twoByEightHundred())
        running.start(now: at(0))
        let open = TrackSessionDraft(workout: running, sessionStart: saved, savedAt: saved)
        XCTAssertTrue(open.isKept(now: saved.addingTimeInterval(3 * 3600)))
        XCTAssertFalse(open.isKept(now: saved.addingTimeInterval(3 * 3600 + 1)))
        TrackSessionStore.save(open, defaults: defaults)
        XCTAssertNil(TrackSessionStore.load(now: saved.addingTimeInterval(4 * 3600), defaults: defaults))
        XCTAssertNil(defaults.data(forKey: TrackSessionStore.key))
    }

    func testAFinishedDraftBecomesAWorkoutRecord() {
        let draft = TrackSessionDraft(workout: finishedOneByFourHundred(),
                                      sessionStart: Date(timeIntervalSinceReferenceDate: 99_700),
                                      savedAt: Date(timeIntervalSinceReferenceDate: 100_000))
        XCTAssertTrue(draft.hasResults)
        let record = draft.makeRecord()
        XCTAssertEqual(record.date, Date(timeIntervalSinceReferenceDate: 99_700))
        XCTAssertEqual(record.name, "1 x 400")
        XCTAssertEqual(record.repTimes, [80])
        XCTAssertEqual(record.spec?.name, "1 x 400")
        XCTAssertEqual(record.lapSplits, [[80]])

        // Ended before the first rep was timed: nothing to save, and an unfinished draft has no results.
        var empty = TrackWorkout(spec: twoByEightHundred())
        empty.start(now: at(0))
        let unfinished = TrackSessionDraft(workout: empty, sessionStart: at(0), savedAt: at(1))
        XCTAssertFalse(unfinished.hasResults)
        empty.finishEarly()
        let ended = TrackSessionDraft(workout: empty, sessionStart: at(0), savedAt: at(1))
        XCTAssertTrue(ended.isFinished)
        XCTAssertFalse(ended.hasResults)
    }

    func testTheSessionScreenWritesTheDraftOnlyWhileTheWorkoutIsOpen() {
        let running = TrackState.running(rep: 1, lap: 1)
        XCTAssertTrue(TrackSessionStore.shouldPersist(started: true, state: running, saved: false, saving: false))
        XCTAssertTrue(TrackSessionStore.shouldPersist(started: true, state: .finished, saved: false, saving: false))
        // Before the first rep, nothing is written.
        XCTAssertFalse(TrackSessionStore.shouldPersist(started: false, state: .ready, saved: false, saving: false))
        XCTAssertFalse(TrackSessionStore.shouldPersist(started: true, state: .ready, saved: false, saving: false))
        // Once saved or being saved, the finished draft must not come back (scene phase change under the pace offer).
        XCTAssertFalse(TrackSessionStore.shouldPersist(started: true, state: .finished, saved: true, saving: false))
        XCTAssertFalse(TrackSessionStore.shouldPersist(started: true, state: .finished, saved: false, saving: true))
    }

    // MARK: Goal-based presets and setup

    func testGoalPresetsFollowTheGoalMile() {
        let zones = PaceZones.forMile(412)
        let short = WorkoutPresets.all.first { $0.id == "10x200-goal" }
        XCTAssertEqual(short?.spec(zones: zones, goalMile: 330).targetRepSeconds ?? 0, 41.3, accuracy: 0.0001)
        let longer = WorkoutPresets.all.first { $0.id == "3x400-goal" }
        XCTAssertEqual(longer?.spec(zones: zones, goalMile: 330).targetRepSeconds ?? 0, 82.5, accuracy: 0.0001)
        XCTAssertEqual(longer?.spec(zones: zones, goalMile: 345).targetRepSeconds ?? 0, 86.3, accuracy: 0.0001)
        XCTAssertEqual(WorkoutPresets.goalPer400(goalMile: 330), 82.5, accuracy: 1e-9)
    }

    func testTimeTrialStartSpecUsesTheSessionTargetOrTheCurrentMile() throws {
        let zones = PaceZones.forMile(412)
        let trial = try XCTUnwrap(WorkoutPresets.all.first { $0.id == "mile-tt" })
        XCTAssertEqual(trial.startSpec(zones: zones, goalMile: 330, mileTime: 395).targetRepSeconds, 395, accuracy: 0.0001)
        XCTAssertEqual(trial.startSpec(zones: zones, goalMile: 330, mileTime: 395, planTarget: 365).targetRepSeconds,
                       365, accuracy: 0.0001)
        XCTAssertEqual(trial.startSpec(zones: zones, goalMile: 330, mileTime: 394.96).targetRepSeconds,
                       395, accuracy: 0.0001)
        XCTAssertEqual(trial.startSpec(zones: zones, goalMile: 330, mileTime: .nan).targetRepSeconds,
                       330, accuracy: 0.0001)
        XCTAssertEqual(trial.startSpec(zones: zones, goalMile: 330, mileTime: 0, planTarget: 0).targetRepSeconds,
                       330, accuracy: 0.0001)
        // Other presets are not changed by it.
        let rep = try XCTUnwrap(WorkoutPresets.all.first { $0.id == "6x400-r" })
        XCTAssertEqual(rep.startSpec(zones: zones, goalMile: 330, mileTime: 395, planTarget: 365),
                       rep.spec(zones: zones, goalMile: 330))
    }

    func testEditingKeepsTheSameTargetPace() {
        XCTAssertEqual(WorkoutEditing.rescaledTarget(82.5, fromDistance: 400, toDistance: 200), 41.25, accuracy: 1e-9)
        XCTAssertEqual(WorkoutEditing.rescaledTarget(41.25, fromDistance: 200, toDistance: 800), 165, accuracy: 1e-9)
        XCTAssertEqual(WorkoutEditing.rescaledTarget(80, fromDistance: 0, toDistance: 200), 80, accuracy: 1e-9)
        XCTAssertEqual(WorkoutEditing.setRest(current: 0, repRest: 60, sets: 2), 120)
        XCTAssertEqual(WorkoutEditing.setRest(current: 300, repRest: 60, sets: 2), 300)
        XCTAssertEqual(WorkoutEditing.setRest(current: 0, repRest: 60, sets: 1), 0)
    }
}
