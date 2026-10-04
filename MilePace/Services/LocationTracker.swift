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
    /// Name of the guided workout, if the run was one.
    var workoutName: String? = nil
    /// Steps per minute over the run; nil when the pedometer gave no data.
    var averageCadence: Double? = nil
    var route: [RoutePoint] = []
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
    /// The guided workout for this run, if any. Set with `beginWorkout(_:)` before `start()`.
    private(set) var workout: RoadWorkoutSession?
    /// Step cadence for the current run.
    let cadence = CadenceTracker()

    /// Called on each completed mile: (mile number, split seconds, average pace seconds per mile).
    @ObservationIgnored var onMile: (@MainActor (Int, Double, Double?) -> Void)?
    /// Called once per second while running with the current pace.
    @ObservationIgnored var onTick: (@MainActor (Double?) -> Void)?
    /// Called for each pace-cue boundary crossed (quarter, half or full mile, per settings).
    @ObservationIgnored var onDistanceCue: (@MainActor (DistanceCue) -> Void)?
    /// Called for each guided-workout event.
    @ObservationIgnored var onWorkoutEvent: (@MainActor (RoadWorkoutSession.Event) -> Void)?

    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var calculator = PaceCalculator()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var lastSampleAt: Date?
    @ObservationIgnored private var cueTracker: DistanceCueTracker?

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

        cueTracker = AppSettings.cueInterval.meters.map { DistanceCueTracker(intervalMeters: $0) }
        cueTracker?.update(distance: 0, elapsed: 0)
        cadence.start(at: now)

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
                                 splits: calculator.splits,
                                 workoutName: workout?.spec.name,
                                 averageCadence: cadence.averageSPM(movingSeconds: duration),
                                 route: calculator.route)

        cadence.stop()
        cueTracker = nil
        workout = nil
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
        cueTracker = nil
        workout = nil
        cadence.reset()
    }

    // MARK: Guided workout

    /// Sets up a guided workout. Call before `start()`.
    func beginWorkout(_ spec: RoadWorkoutSpec) {
        guard phase == .idle else { return }
        workout = RoadWorkoutSession(spec: spec)
    }

    /// Drops any workout set up with `beginWorkout(_:)` (for a free run).
    func clearWorkout() {
        guard phase == .idle else { return }
        workout = nil
    }

    /// Ends the warm-up and starts rep 1.
    func startReps() {
        guard phase != .idle else { return }
        let events = workout?.startReps(elapsed: calculator.elapsed(at: Date()),
                                        distance: calculator.totalDistance) ?? []
        forward(events)
    }

    /// Ends the current rep or recovery early.
    func skipPhase() {
        guard phase != .idle else { return }
        let events = workout?.skip(elapsed: calculator.elapsed(at: Date()),
                                   distance: calculator.totalDistance) ?? []
        forward(events)
    }

    private func forward(_ events: [RoadWorkoutSession.Event]) {
        for event in events {
            onWorkoutEvent?(event)
        }
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
        let events = workout?.update(elapsed: elapsed, distance: calculator.totalDistance) ?? []
        forward(events)
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

        if let stamp = samples.last?.timestamp {
            advanceProgress(at: stamp)
        }
    }

    /// Feeds distance cues and the guided workout after a batch of samples, using the sample's own time.
    private func advanceProgress(at stamp: Date) {
        let sampleElapsed = calculator.elapsed(at: stamp)
        let distance = calculator.totalDistance

        let events = workout?.update(elapsed: sampleElapsed, distance: distance) ?? []
        forward(events)

        let cues = cueTracker?.update(distance: distance, elapsed: sampleElapsed) ?? []
        // No distance cues while a rep or recovery is running, so they never talk over the workout.
        let suppressed = workout?.isInRepOrRecovery ?? false
        if !suppressed {
            for cue in cues {
                onDistanceCue?(cue)
            }
        }
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
