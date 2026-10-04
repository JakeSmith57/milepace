import Foundation
import CoreMotion
import Observation

/// Step cadence from the phone's pedometer.
@Observable
@MainActor
final class CadenceTracker {
    /// Steps per minute from the pedometer's current cadence, or nil when unavailable.
    private(set) var currentSPM: Double?
    /// Steps counted since `start(at:)`.
    private(set) var steps: Int = 0

    @ObservationIgnored private let pedometer = CMPedometer()
    /// Bumped on every start and stop so late pedometer callbacks are ignored.
    @ObservationIgnored private var generation = 0

    static var isAvailable: Bool {
        return CMPedometer.isCadenceAvailable() && CMPedometer.isStepCountingAvailable()
    }

    func start(at date: Date) {
        generation += 1
        steps = 0
        currentSPM = nil
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
    }

    /// Average cadence over moving time, or nil with under a minute of data or no steps.
    func averageSPM(movingSeconds: Double) -> Double? {
        guard movingSeconds.isFinite, movingSeconds >= 60, steps > 0 else { return nil }
        return Double(steps) / movingSeconds * 60
    }

    private func apply(steps stepCount: Int, stepsPerSecond: Double?, token: Int) {
        guard token == generation else { return }
        steps = stepCount
        if let rate = stepsPerSecond, rate.isFinite, rate > 0 {
            currentSPM = rate * 60
        } else {
            currentSPM = nil
        }
    }
}
