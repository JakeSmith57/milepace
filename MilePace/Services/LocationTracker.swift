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
    /// GPS quality for the status line. `.off` unless warming up or running.
    private(set) var gpsState: GPSState = .off
    /// The run's route so far (downsampled to at least 10 m between points, the same points that get
    /// saved), for the live map. Only republished when a point was added.
    private(set) var liveRoute: [RoutePoint] = []
    /// The latest accepted fix, for the "you are here" marker. `CLLocationCoordinate2D` is not
    /// Equatable, so views must not compare it (use `liveRoute.count` or `distanceMeters` to react).
    private(set) var lastCoordinate: CLLocationCoordinate2D?

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
    /// True while the Run tab wants the GPS warmed up.
    @ObservationIgnored private var warmupWanted = false
    /// True while location updates run for warm-up (idle, no background flag).
    @ObservationIgnored private var warmupActive = false
    @ObservationIgnored private var warmupStartedAt: Date?
    /// Latest fix with a valid accuracy, from warm-up or a run.
    @ObservationIgnored private var lastFix: PaceSample?

    /// Idle warm-up stops by itself after this many seconds to save battery.
    static let warmupTimeoutSeconds: Double = 180
    /// A warm-up fix at most this old (seconds) and this accurate (meters) seeds the run.
    static let seedMaxAge: Double = 3
    static let seedMaxAccuracy: Double = 20

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

    // MARK: GPS warm-up

    /// Starts location updates ahead of a run so the first fix is already good when you tap start.
    /// Does nothing unless authorized and idle. Samples are not fed to any run.
    func beginWarmup() {
        warmupWanted = true
        startWarmupIfPossible()
    }

    /// Stops warm-up updates when idle.
    func endWarmup() {
        warmupWanted = false
        guard phase == .idle, warmupActive else { return }
        stopWarmupUpdates(note: "warm-up end")
    }

    private func startWarmupIfPossible() {
        guard warmupWanted, phase == .idle, isAuthorized, !warmupActive else { return }
        warmupActive = true
        warmupStartedAt = Date()
        lastFix = nil
        Diagnostics.shared.setClock(-1)
        Diagnostics.shared.log(.state, "warm-up begin")
        manager.startUpdatingLocation()
        startTimer()
        refreshGPS()
    }

    private func stopWarmupUpdates(note: String) {
        warmupActive = false
        warmupStartedAt = nil
        manager.stopUpdatingLocation()
        stopTimer()
        lastFix = nil
        Diagnostics.shared.log(.state, note)
        refreshGPS()
    }

    /// The latest warm-up fix, re-stamped at the start time, when it is fresh and accurate enough.
    private func warmupSeed(at now: Date) -> PaceSample? {
        guard warmupActive, let fix = lastFix else { return nil }
        let age = now.timeIntervalSince(fix.timestamp)
        guard age <= LocationTracker.seedMaxAge,
              fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= LocationTracker.seedMaxAccuracy else { return nil }
        return PaceSample(timestamp: now,
                          latitude: fix.latitude,
                          longitude: fix.longitude,
                          horizontalAccuracy: fix.horizontalAccuracy)
    }

    private func refreshGPS() {
        let state: GPSState
        if phase == .idle && !warmupActive {
            state = .off
        } else {
            let age = lastFix.map { Date().timeIntervalSince($0.timestamp) }
            state = GPSState.evaluate(accuracy: lastFix?.horizontalAccuracy, age: age)
        }
        if state != gpsState {
            gpsState = state
        }
        Diagnostics.shared.setGPS(state)
    }

    // MARK: Run control

    func start() {
        guard phase == .idle, isAuthorized else { return }
        let now = Date()
        let seed = warmupSeed(at: now)
        calculator = PaceCalculator()
        calculator.start(at: now)
        startedAt = now
        lastSampleAt = nil
        distanceMeters = 0
        elapsed = 0
        currentPace = nil
        averagePace = nil
        splits = []
        liveRoute = []
        lastCoordinate = nil
        errorMessage = nil

        let diagnostics = Diagnostics.shared
        diagnostics.beginRun(at: now)
        diagnostics.log(.state, "state start")
        if let seed = seed {
            // Distance starts from where the runner stands. Position only, no speed, so the
            // Doppler smoother starts with the first real fix.
            calculator.add(seed)
            diagnostics.recordSample(seed,
                                     outcome: calculator.lastOutcome,
                                     distance: calculator.totalDistance,
                                     windowPace: calculator.windowPace,
                                     dopplerPace: calculator.dopplerPace,
                                     currentPace: calculator.currentPace,
                                     cadence: nil,
                                     elapsed: 0)
            liveRoute = calculator.route
            lastCoordinate = CLLocationCoordinate2D(latitude: seed.latitude, longitude: seed.longitude)
        }

        cueTracker = AppSettings.cueInterval.meters.map { DistanceCueTracker(intervalMeters: $0) }
        cueTracker?.update(distance: 0, elapsed: 0)
        cadence.start(at: now)

        // Only valid once authorized, and the Info.plist declares the location background mode.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        if !warmupActive {
            manager.startUpdatingLocation()
        }
        // After a warm-up the updates keep running (no restart); they now belong to the run.
        warmupActive = false
        warmupWanted = false
        warmupStartedAt = nil

        phase = .running
        startTimer()
        refreshGPS()
    }

    func pause() {
        guard phase == .running else { return }
        calculator.pause(at: Date())
        currentPace = nil
        phase = .paused
        refreshClock()
        Diagnostics.shared.log(.state, "state pause")
    }

    func resume() {
        guard phase == .paused else { return }
        calculator.resume(at: Date())
        lastSampleAt = nil
        phase = .running
        refreshClock()
        Diagnostics.shared.log(.state, "state resume")
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
        warmupActive = false
        warmupWanted = false
        warmupStartedAt = nil
        lastFix = nil
        Diagnostics.shared.log(.state, "state stop")
        Diagnostics.shared.setClock(-1)
        refreshGPS()
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
        liveRoute = []
        lastCoordinate = nil
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
        if phase == .idle {
            tickWarmup()
            return
        }
        refreshClock()
        refreshGPS()
        let diagnostics = Diagnostics.shared
        diagnostics.setClock(elapsed)
        diagnostics.setCadence(cadence.currentSPM)
        diagnostics.refresh(now: Date())
        guard phase == .running else { return }
        if let last = lastSampleAt, Date().timeIntervalSince(last) > 10 {
            currentPace = nil
        }
        let events = workout?.update(elapsed: elapsed, distance: calculator.totalDistance) ?? []
        forward(events)
        onTick?(currentPace)
    }

    /// One-second tick while idle: warm-up timeout and GPS status.
    private func tickWarmup() {
        guard warmupActive else { return }
        if let began = warmupStartedAt,
           Date().timeIntervalSince(began) >= LocationTracker.warmupTimeoutSeconds {
            warmupWanted = false
            stopWarmupUpdates(note: "warm-up timeout")
            return
        }
        refreshGPS()
        Diagnostics.shared.refresh(now: Date())
    }

    private func handle(_ samples: [PaceSample]) {
        let diagnostics = Diagnostics.shared
        for sample in samples {
            diagnostics.noteFix(sample)
            if sample.horizontalAccuracy >= 0 {
                lastFix = sample
            }
        }
        refreshGPS()

        guard phase == .running else {
            // Warm-up fixes (and fixes while paused) never reach the run calculator.
            if phase == .paused {
                for sample in samples {
                    diagnostics.recordSample(sample,
                                             outcome: .rejected(.paused),
                                             distance: calculator.totalDistance,
                                             windowPace: nil,
                                             dopplerPace: nil,
                                             currentPace: nil,
                                             cadence: cadence.currentSPM,
                                             elapsed: elapsed)
                }
            }
            return
        }
        var latestAccepted: PaceSample?
        for sample in samples {
            let before = calculator.splits.count
            calculator.add(sample)
            if calculator.lastOutcome == .accepted || calculator.lastOutcome == .anchored {
                latestAccepted = sample
            }
            let sampleElapsed = calculator.elapsed(at: sample.timestamp)
            diagnostics.setClock(sampleElapsed)
            diagnostics.recordSample(sample,
                                     outcome: calculator.lastOutcome,
                                     distance: calculator.totalDistance,
                                     windowPace: calculator.windowPace,
                                     dopplerPace: calculator.dopplerPace,
                                     currentPace: calculator.currentPace,
                                     cadence: cadence.currentSPM,
                                     elapsed: sampleElapsed)
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
        publishLiveRoute(latestAccepted)
        lastSampleAt = Date()
        refreshClock()

        if let stamp = samples.last?.timestamp {
            advanceProgress(at: stamp)
        }
    }

    /// Publishes the route and the latest accepted fix for the live map. The route array is only
    /// replaced when a point was added, so the map is not redrawn for every sample.
    private func publishLiveRoute(_ latest: PaceSample?) {
        if calculator.route.count != liveRoute.count {
            liveRoute = calculator.route
        }
        if let fix = latest {
            lastCoordinate = CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
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
        // Permission may have just been granted while the Run tab is waiting to warm up.
        startWarmupIfPossible()
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
                       speed: location.speed,
                       speedAccuracy: location.speedAccuracy,
                       course: location.course)
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
