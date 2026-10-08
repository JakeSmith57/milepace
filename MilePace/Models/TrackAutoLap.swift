import Foundation

/// Pure rules for ending laps and reps by GPS on a track: where the laps end, when a GPS crossing is
/// believed, and the time the runner crossed (interpolated between two fixes). Kept free of CoreLocation.
enum TrackAutoLap {
    /// Both fixes around a crossing need a horizontal accuracy of at most this many meters.
    static let maxAccuracy: Double = 15
    /// No automatic finish before this share of the lap's target time has gone (guards against GPS jumps).
    static let minTimeFraction: Double = 0.6
    /// Calibration factor limits.
    static let factorRange: ClosedRange<Double> = 0.85...1.15
    /// One calibration lap.
    static let calibrationLapMeters: Double = 400
    /// A calibration measurement shorter than this is not a lap.
    static let minCalibrationMeters: Double = 150

    /// One GPS fix as the rep meter saw it: calibrated rep distance before and after, the fix times and
    /// their horizontal accuracies. Negative accuracy means unknown (not good enough).
    struct Fix: Equatable {
        var before: Double
        var after: Double
        var previousTime: Date
        var time: Date
        var accuracy: Double
        var previousAccuracy: Double
    }

    enum Decision: Equatable {
        /// Not there yet (or too early to believe it).
        case wait
        /// The distance says the lap is over but the fixes are too rough to trust.
        case weakGPS
        /// The lap ended at this moment.
        case cross(Date)
    }

    /// Cumulative rep distance in meters at the end of each lap (one entry per lap tap).
    static func lapBoundaries(_ spec: WorkoutSpec) -> [Double] {
        var total = 0.0
        var result: [Double] = []
        for fraction in spec.lapFractions {
            total += fraction * Double(spec.repDistance)
            result.append(total)
        }
        if !result.isEmpty {
            result[result.count - 1] = Double(spec.repDistance)
        }
        return result
    }

    /// The rep distance at which the one-based `lap` ends; nil for a lap that does not exist.
    static func boundary(_ spec: WorkoutSpec, lap: Int) -> Double? {
        let all = lapBoundaries(spec)
        guard lap >= 1, lap <= all.count else { return nil }
        return all[lap - 1]
    }

    /// The moment the boundary was crossed between two fixes, by straight-line interpolation of distance.
    static func crossingTime(before: Double, after: Double, previousTime: Date, time: Date, boundary: Double) -> Date {
        let span = after - before
        guard span > 0 else { return time }
        let fraction = min(1, max(0, (boundary - before) / span))
        return previousTime.addingTimeInterval(time.timeIntervalSince(previousTime) * fraction)
    }

    /// What one fix means for the lap in progress. `lapStart` and `lapTarget` (seconds) belong to that lap.
    /// A crossing that happened before this fix is stamped with the fix time (the best that is left).
    static func evaluate(fix: Fix, boundary: Double, lapStart: Date, lapTarget: Double) -> Decision {
        guard fix.after >= boundary else { return .wait }
        let interpolated = fix.before < boundary
        let crossing: Date
        if interpolated {
            crossing = crossingTime(before: fix.before,
                                    after: fix.after,
                                    previousTime: fix.previousTime,
                                    time: fix.time,
                                    boundary: boundary)
        } else {
            crossing = fix.time
        }
        if crossing.timeIntervalSince(lapStart) < minTimeFraction * lapTarget {
            return .wait
        }
        let currentGood = fix.accuracy >= 0 && fix.accuracy <= maxAccuracy
        let previousGood = fix.previousAccuracy >= 0 && fix.previousAccuracy <= maxAccuracy
        if !currentGood || (interpolated && !previousGood) {
            return .weakGPS
        }
        return .cross(crossing)
    }

    // MARK: Calibration

    /// 400 / measured, clamped to 0.85...1.15; nil when the measurement is not a believable lap.
    static func calibrationFactor(measured: Double) -> Double? {
        guard measured.isFinite, measured >= minCalibrationMeters else { return nil }
        let raw = calibrationLapMeters / measured
        return min(factorRange.upperBound, max(factorRange.lowerBound, raw))
    }
}

/// Meters run in the current rep, from the GPS distance counter. Calibrated by `factor`.
struct TrackRepMeter: Equatable {
    /// Counter reading when the rep (lap 0) started; nil when the meter is not trustworthy.
    private(set) var base: Double?
    var factor: Double = 1

    var isValid: Bool { base != nil }

    mutating func begin(atRaw raw: Double) {
        base = raw
    }

    mutating func invalidate() {
        base = nil
    }

    /// The runner tapped at a line: from now the meter reads exactly `meters` at counter reading `raw`.
    mutating func snap(toMeters meters: Double, atRaw raw: Double) {
        guard factor > 0 else { return }
        base = raw - meters / factor
    }

    /// Calibrated rep distance at a counter reading; nil when invalid.
    func meters(atRaw raw: Double) -> Double? {
        guard let start = base else { return nil }
        return max(0, (raw - start) * factor)
    }
}

/// The track's calibration factor and when it was measured.
struct TrackCalibration: Codable, Equatable {
    static let maxAgeDays: Double = 60

    var factor: Double
    var date: Date

    func isStale(now: Date) -> Bool {
        return now.timeIntervalSince(date) > TrackCalibration.maxAgeDays * 86_400
    }
}

/// The calibration in `UserDefaults`, as JSON (key "trackCalibration").
enum TrackCalibrationStore {
    static let key = "trackCalibration"

    static func save(_ calibration: TrackCalibration, defaults: UserDefaults = UserDefaults.standard) {
        guard let data = try? JSONEncoder().encode(calibration) else { return }
        defaults.set(data, forKey: key)
    }

    static func load(defaults: UserDefaults = UserDefaults.standard) -> TrackCalibration? {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(TrackCalibration.self, from: data),
              value.factor.isFinite,
              TrackAutoLap.factorRange.contains(value.factor) else { return nil }
        return value
    }

    static func clear(defaults: UserDefaults = UserDefaults.standard) {
        defaults.removeObject(forKey: key)
    }
}
