import Foundation
import CoreLocation

/// GPS for the track screen: its own location manager, separate from `LocationTracker` (which belongs to
/// road runs). Feeds a fresh `PaceCalculator` for its distance filtering and keeps the distance run in the
/// current rep. Whether a lap ended is decided by `TrackAutoLap`; this class only measures.
@Observable
@MainActor
final class TrackGPS: NSObject, CLLocationManagerDelegate {
    enum Status: Equatable {
        /// Not started (auto-lap off, treadmill, or not yet asked).
        case off
        /// Location permission has not been asked yet.
        case needsPermission
        /// Location is denied or restricted: the session works in tap mode.
        case denied
        /// Updates are on but no usable fix yet.
        case searching
        /// Recent fixes are good enough to end laps.
        case ready
        /// Fixes are rougher than `TrackAutoLap.maxAccuracy`.
        case weak
    }

    /// A counted GPS step in raw (uncalibrated) counter readings.
    private struct RawFix {
        var before: Double
        var after: Double
        var previousTime: Date
        var time: Date
        var accuracy: Double
        var previousAccuracy: Double
    }

    /// Fixes older than this many seconds are cached positions and are ignored.
    static let maxFixAge: Double = 10
    /// The accuracy reading is forgotten after this many seconds without a fix.
    static let accuracyStaleSeconds: Double = 8
    /// Most steps kept waiting for the session screen to look at them.
    private static let maxPending = 200

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var updating: Bool = false
    /// Horizontal accuracy of the latest fix in meters; negative when unknown.
    private(set) var accuracy: Double = -1
    private(set) var lastFixAt: Date?
    /// Distance counter of the filtered track, in meters, not calibrated.
    private(set) var rawTotal: Double = 0
    private(set) var meter = TrackRepMeter()

    @ObservationIgnored private var manager: CLLocationManager?
    @ObservationIgnored private var calculator = PaceCalculator()
    @ObservationIgnored private var lastSample: PaceSample?
    @ObservationIgnored private var pending: [RawFix] = []
    /// True between `start()` and `stop()`; lets a late permission answer begin the updates.
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var live = false

    // MARK: State

    /// What the session screen shows about the GPS. `now` lets a silent GPS go back to searching.
    func status(now: Date) -> Status {
        switch authorization {
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return wanted ? .needsPermission : .off
        default:
            break
        }
        guard updating else { return .off }
        guard let last = lastFixAt, now.timeIntervalSince(last) <= TrackGPS.accuracyStaleSeconds else {
            return .searching
        }
        if accuracy >= 0 && accuracy <= TrackAutoLap.maxAccuracy {
            return .ready
        }
        return .weak
    }

    /// Calibrated meters run in the current rep; nil when the meter is not trustworthy (tap mode).
    var repMeters: Double? {
        return meter.meters(atRaw: rawTotal)
    }

    // MARK: Control

    /// Starts location updates (asks for permission first when it was never asked).
    func start() {
        wanted = true
        let manager = ensureManager()
        authorization = manager.authorizationStatus
        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            beginUpdates(manager)
        default:
            break
        }
    }

    /// The session is running (reps started): keep updating in the background. False again for the ready screen.
    func setLive(_ value: Bool) {
        live = value
        guard let manager = manager, updating else { return }
        manager.allowsBackgroundLocationUpdates = value
        manager.showsBackgroundLocationIndicator = value
    }

    func stop() {
        wanted = false
        live = false
        if let manager = manager {
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
        }
        updating = false
        pending.removeAll()
        meter.invalidate()
        calculator = PaceCalculator()
        lastSample = nil
        rawTotal = 0
        accuracy = -1
        lastFixAt = nil
    }

    func setFactor(_ factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        meter.factor = factor
    }

    /// A rep starts here: the rep distance counts from zero.
    func beginRep() {
        meter.begin(atRaw: rawTotal)
        pending.removeAll()
    }

    /// The rep distance can no longer be trusted (undo, resumed session): tap mode until the next rep.
    func invalidate() {
        meter.invalidate()
        pending.removeAll()
    }

    /// The runner tapped at a line inside a rep: the distance reads exactly `meters` from now on.
    func snap(toMeters meters: Double) {
        guard meter.isValid else { return }
        meter.snap(toMeters: meters, atRaw: rawTotal)
        pending.removeAll()
    }

    /// Looks at the GPS steps that came in since the last call, oldest first, and says whether the lap that
    /// ends at `boundary` meters (calibrated, from the rep start) is over. The first crossing wins and the
    /// rest of the batch is dropped.
    func poll(boundary: Double, lapStart: Date, lapTarget: Double) -> TrackAutoLap.Decision {
        let fixes = pending
        pending.removeAll()
        guard meter.isValid else { return .wait }
        var result: TrackAutoLap.Decision = .wait
        for raw in fixes {
            guard let before = meter.meters(atRaw: raw.before),
                  let after = meter.meters(atRaw: raw.after) else { continue }
            let fix = TrackAutoLap.Fix(before: before,
                                       after: after,
                                       previousTime: raw.previousTime,
                                       time: raw.time,
                                       accuracy: raw.accuracy,
                                       previousAccuracy: raw.previousAccuracy)
            let decision = TrackAutoLap.evaluate(fix: fix, boundary: boundary, lapStart: lapStart, lapTarget: lapTarget)
            switch decision {
            case .cross:
                return decision
            case .weakGPS:
                result = .weakGPS
            case .wait:
                break
            }
        }
        return result
    }

    /// Drops the steps waiting (rest, ready screen): nothing looks at them.
    func discardPending() {
        pending.removeAll()
    }

    // MARK: Updates

    private func ensureManager() -> CLLocationManager {
        if let existing = manager {
            return existing
        }
        let created = CLLocationManager()
        created.delegate = self
        created.activityType = .fitness
        created.desiredAccuracy = kCLLocationAccuracyBest
        created.distanceFilter = kCLDistanceFilterNone
        created.pausesLocationUpdatesAutomatically = false
        manager = created
        return created
    }

    private func beginUpdates(_ manager: CLLocationManager) {
        guard !updating else { return }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.allowsBackgroundLocationUpdates = live
        manager.showsBackgroundLocationIndicator = live
        manager.startUpdatingLocation()
        updating = true
    }

    private func authorizationChanged(_ status: CLAuthorizationStatus) {
        authorization = status
        guard wanted, !updating, let manager = manager else { return }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            beginUpdates(manager)
        }
    }

    private func handle(_ samples: [PaceSample]) {
        guard updating else { return }
        for sample in samples {
            if Date().timeIntervalSince(sample.timestamp) > TrackGPS.maxFixAge { continue }
            accuracy = sample.horizontalAccuracy
            lastFixAt = Date()
            let before = calculator.totalDistance
            calculator.add(sample)
            let after = calculator.totalDistance
            switch calculator.lastOutcome {
            case .accepted:
                if let previous = lastSample {
                    pending.append(RawFix(before: before,
                                          after: after,
                                          previousTime: previous.timestamp,
                                          time: sample.timestamp,
                                          accuracy: sample.horizontalAccuracy,
                                          previousAccuracy: previous.horizontalAccuracy))
                    if pending.count > TrackGPS.maxPending {
                        pending.removeFirst(pending.count - TrackGPS.maxPending)
                    }
                }
                lastSample = sample
            case .anchored:
                lastSample = sample
            case .rejected:
                break
            }
            rawTotal = after
        }
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
            self.authorizationChanged(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A missing fix is not an error here: the screen shows "searching" and the session works by taps.
    }
}
