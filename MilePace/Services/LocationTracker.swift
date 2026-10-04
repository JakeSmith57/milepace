import Foundation
import CoreLocation
import Observation

enum RunPhase: Equatable {
    case idle
    case running
    case paused
}

/// Result of a finished run, shown in the summary sheet before saving.
struct RunSummary: Identifiable, Equatable {
    let id = UUID()
    var date: Date
    var distanceMeters: Double
    var durationSeconds: Double
    /// Seconds per mile; 0 when distance is too short to compute.
    var averagePace: Double
    var splits: [Double]
}

@Observable
@MainActor
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private(set) var phase: RunPhase = .idle
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var distanceMeters: Double = 0
    private(set) var elapsed: Double = 0
    private(set) var currentPace: Double?
    private(set) var averagePace: Double?
    private(set) var splits: [Double] = []
    private(set) var errorMessage: String?

    /// Called on each completed mile: (mile number, split seconds, average pace seconds per mile).
    @ObservationIgnored var onMile: (@MainActor (Int, Double, Double?) -> Void)?
    /// Called once per second while running with the current pace.
    @ObservationIgnored var onTick: (@MainActor (Double?) -> Void)?

    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var calculator = PaceCalculator()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var lastSampleAt: Date?

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    // MARK: Authorization

    var isAuthorized: Bool {
        return authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        return authorization == .denied || authorization == .restricted
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: Run control

    func start() {
        guard phase == .idle, isAuthorized else { return }
        let now = Date()
        calculator = PaceCalculator()
        calculator.start(at: now)
        startedAt = now
        lastSampleAt = nil
        distanceMeters = 0
        elapsed = 0
        currentPace = nil
        averagePace = nil
        splits = []
        errorMessage = nil

        // Only valid once authorized, and the Info.plist declares the location background mode.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()

        phase = .running
        startTimer()
    }

    func pause() {
        guard phase == .running else { return }
        calculator.pause(at: Date())
        currentPace = nil
        phase = .paused
        refreshClock()
    }

    func resume() {
        guard phase == .paused else { return }
        calculator.resume(at: Date())
        lastSampleAt = nil
        phase = .running
        refreshClock()
    }

    /// Stops tracking and returns the run's summary.
    @discardableResult
    func stop() -> RunSummary {
        let now = Date()
        if phase == .paused {
            calculator.resume(at: now)
        }
        let duration = calculator.elapsed(at: now)
        let distance = calculator.totalDistance
        let average = distance >= 10 ? duration / distance * metersPerMile : 0
        let summary = RunSummary(date: startedAt,
                                 distanceMeters: distance,
                                 durationSeconds: duration,
                                 averagePace: average,
                                 splits: calculator.splits)

        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        stopTimer()
        phase = .idle
        return summary
    }

    /// Clears live metrics after a run has been saved or discarded.
    func reset() {
        calculator = PaceCalculator()
        distanceMeters = 0
        elapsed = 0
        currentPace = nil
        averagePace = nil
        splits = []
        lastSampleAt = nil
    }

    // MARK: Internals

    private func startTimer() {
        timer?.invalidate()
        let newTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshClock() {
        let now = Date()
        elapsed = calculator.elapsed(at: now)
        averagePace = calculator.averagePace(at: now)
    }

    private func tick() {
        refreshClock()
        guard phase == .running else { return }
        if let last = lastSampleAt, Date().timeIntervalSince(last) > 10 {
            currentPace = nil
        }
        onTick?(currentPace)
    }

    private func handle(_ samples: [PaceSample]) {
        guard phase == .running else { return }
        for sample in samples {
            let before = calculator.splits.count
            calculator.add(sample)
            let after = calculator.splits.count
            if after > before {
                for index in before..<after {
                    let completed = Array(calculator.splits.prefix(index + 1))
                    let average = completed.reduce(0, +) / Double(completed.count)
                    onMile?(index + 1, calculator.splits[index], average)
                }
            }
        }
        distanceMeters = calculator.totalDistance
        currentPace = calculator.currentPace
        splits = calculator.splits
        lastSampleAt = Date()
        refreshClock()
    }

    private func setAuthorization(_ status: CLAuthorizationStatus) {
        authorization = status
    }

    private func setError(_ message: String) {
        errorMessage = message
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let samples = locations.map { location in
            PaceSample(timestamp: location.timestamp,
                       latitude: location.coordinate.latitude,
                       longitude: location.coordinate.longitude,
                       horizontalAccuracy: location.horizontalAccuracy,
                       speed: location.speed)
        }
        Task { @MainActor in
            self.handle(samples)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.setAuthorization(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }
        let message = error.localizedDescription
        Task { @MainActor in
            self.setError(message)
        }
    }
}
