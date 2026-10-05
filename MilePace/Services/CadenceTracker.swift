import Foundation
import CoreMotion
import Observation

/// Cadence arithmetic without CoreMotion, so it can be tested.
enum CadenceMath {
    /// Average steps per minute over moving time: the steps taken over the whole run minus the steps
    /// taken while paused, divided by moving time. Nil with under a minute of moving time or no steps left.
    static func averageSPM(totalSteps: Int, pausedSteps: Int, movingSeconds: Double) -> Double? {
        guard movingSeconds.isFinite, movingSeconds >= 60 else { return nil }
        let moving = totalSteps - max(0, pausedSteps)
        guard moving > 0 else { return nil }
        return Double(moving) / movingSeconds * 60
    }
}

/// What the end-of-run pedometer query needs, kept apart from the tracker so it survives `reset()`.
struct CadenceQueryPlan: Equatable {
    /// The whole run, start to stop.
    var run: DateInterval
    /// Every stretch of the run spent paused.
    var pauses: [DateInterval]
}

/// Step cadence from the phone's pedometer.
@Observable
@MainActor
final class CadenceTracker {
    /// Steps per minute from the pedometer's current cadence, or nil when unavailable.
    private(set) var currentSPM: Double?
    /// Steps counted since `start(at:)`, paused time included.
    private(set) var steps: Int = 0

    @ObservationIgnored private let pedometer = CMPedometer()
    /// Bumped on every start and stop so late pedometer callbacks are ignored.
    @ObservationIgnored private var generation = 0
    /// Finished pauses of the current run.
    @ObservationIgnored private var pauses: [DateInterval] = []
    /// When the current pause began, and the live step count then.
    @ObservationIgnored private var pauseStartedAt: Date?
    @ObservationIgnored private var stepsAtPauseStart = 0
    /// Live steps counted during the finished pauses.
    @ObservationIgnored private var pausedSteps = 0

    static var isAvailable: Bool {
        return CMPedometer.isCadenceAvailable() && CMPedometer.isStepCountingAvailable()
    }

    func start(at date: Date) {
        generation += 1
        steps = 0
        currentSPM = nil
        pauses = []
        pauseStartedAt = nil
        stepsAtPauseStart = 0
        pausedSteps = 0
        guard CadenceTracker.isAvailable else { return }
        let token = generation
        // The handler runs on a background queue: pull out plain numbers, then hop to the main actor.
        pedometer.startUpdates(from: date) { @Sendable [weak self] data, _ in
            guard let data = data else { return }
            let stepCount = data.numberOfSteps.intValue
            let stepsPerSecond = data.currentCadence?.doubleValue
            Task { @MainActor in
                self?.apply(steps: stepCount, stepsPerSecond: stepsPerSecond, token: token)
            }
        }
    }

    func stop() {
        generation += 1
        pedometer.stopUpdates()
        currentSPM = nil
    }

    /// Clears the last run's numbers.
    func reset() {
        steps = 0
        currentSPM = nil
        pauses = []
        pauseStartedAt = nil
        stepsAtPauseStart = 0
        pausedSteps = 0
    }

    // MARK: Pauses

    /// The run was paused: remembers when, and how many steps had been counted.
    func pause(at date: Date) {
        guard pauseStartedAt == nil else { return }
        pauseStartedAt = date
        stepsAtPauseStart = steps
        currentSPM = nil
    }

    /// The run resumed (or ended while paused): closes the pause.
    func resume(at date: Date) {
        guard let began = pauseStartedAt else { return }
        pauseStartedAt = nil
        if date > began {
            pauses.append(DateInterval(start: began, end: date))
        }
        pausedSteps += max(0, steps - stepsAtPauseStart)
    }

    /// Steps counted so far outside pauses, from the live updates.
    var movingSteps: Int {
        var paused = pausedSteps
        if pauseStartedAt != nil {
            paused += max(0, steps - stepsAtPauseStart)
        }
        return max(0, steps - paused)
    }

    /// Average cadence over moving time from the live count with paused steps left out, or nil with
    /// under a minute of data or no steps.
    func averageSPM(movingSeconds: Double) -> Double? {
        return CadenceMath.averageSPM(totalSteps: movingSteps, pausedSteps: 0, movingSeconds: movingSeconds)
    }

    // MARK: End of run

    /// The pedometer queries to make for a run that ended at `end`.
    func queryPlan(runStart: Date, end: Date) -> CadenceQueryPlan {
        return CadenceQueryPlan(run: DateInterval(start: runStart, end: max(end, runStart)), pauses: pauses)
    }

    /// Average cadence worked out from the pedometer's history: steps over the whole run minus steps in
    /// each pause, over moving time. Unlike the live count it does not miss steps taken while the
    /// phone was locked. Nil when the pedometer cannot say; callers then keep the live number.
    func refinedAverageSPM(plan: CadenceQueryPlan, movingSeconds: Double) async -> Double? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let source = pedometer
        guard let total = await CadenceTracker.steps(in: plan.run, using: source) else { return nil }
        var paused = 0
        for interval in plan.pauses where interval.duration >= 1 {
            guard let count = await CadenceTracker.steps(in: interval, using: source) else { return nil }
            paused += count
        }
        return CadenceMath.averageSPM(totalSteps: total, pausedSteps: paused, movingSeconds: movingSeconds)
    }

    private nonisolated static func steps(in interval: DateInterval, using pedometer: CMPedometer) async -> Int? {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Int?, Never>) in
            pedometer.queryPedometerData(from: interval.start, to: interval.end) { @Sendable data, error in
                if error != nil {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: data?.numberOfSteps.intValue)
                }
            }
        }
    }

    private func apply(steps stepCount: Int, stepsPerSecond: Double?, token: Int) {
        guard token == generation else { return }
        steps = stepCount
        if pauseStartedAt != nil {
            // Steps while paused still count towards `steps`, but they are not the runner's current cadence.
            currentSPM = nil
            return
        }
        if let rate = stepsPerSecond, rate.isFinite, rate > 0 {
            currentSPM = rate * 60
        } else {
            currentSPM = nil
        }
    }
}
