import Foundation

/// A lightweight GPS sample so the calculator can be tested without CoreLocation.
struct PaceSample: Equatable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var speed: Double
    /// Accuracy of `speed` in m/s; negative when unknown.
    var speedAccuracy: Double
    /// Direction of travel in degrees; negative when unknown.
    var course: Double

    init(timestamp: Date,
         latitude: Double,
         longitude: Double,
         horizontalAccuracy: Double,
         speed: Double = -1,
         speedAccuracy: Double = -1,
         course: Double = -1) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
        self.speedAccuracy = speedAccuracy
        self.course = course
    }
}

/// Why a sample did not add distance.
enum RejectReason: String, CaseIterable {
    case paused
    case accuracy
    case beforeStart
    case outOfOrder
    case jump
}

/// What `PaceCalculator.add` did with the last sample.
enum SampleOutcome: Equatable {
    /// Counted: distance was added.
    case accepted
    /// Became the new reference point (first sample, after a resume, or after a long jump).
    case anchored
    case rejected(RejectReason)
}

/// One stored point of a run's route.
struct RoutePoint: Codable, Equatable {
    var lat: Double
    var lon: Double
    /// Moving elapsed seconds at this point.
    var t: Double
    /// Cumulative distance in meters at this point.
    var d: Double
    /// True for the first point of a run and after each pause or GPS re-anchor.
    var segmentStart: Bool = false
}

/// When a pace on screen stops being believable.
enum PaceFreshness {
    /// A pace with no new accepted sample or Doppler update for longer than this many seconds is dropped.
    static let staleSeconds: Double = 8

    /// `pace`, or nil when the last update that could have changed it is more than `staleSeconds` before
    /// `now`. With no update recorded yet there is nothing to judge, so `pace` is kept.
    static func pace(_ pace: Double?, lastUpdate: Date?, now: Date) -> Double? {
        guard let last = lastUpdate else { return pace }
        if now.timeIntervalSince(last) > staleSeconds {
            return nil
        }
        return pace
    }
}

/// Rolling pace, average pace, distance and mile splits from GPS samples.
struct PaceCalculator {
    static let maxAccuracy: Double = 20
    static let maxSpeed: Double = 9
    static let windowSeconds: Double = 30
    static let minWindowMeters: Double = 25
    static let smoothing: Double = 0.3
    static let maxConsecutiveJumps: Int = 5
    /// Minimum cumulative distance between stored route points.
    static let routeSpacing: Double = 10
    /// Doppler speed is trusted when its reported accuracy is at most this many m/s.
    static let maxDopplerSpeedAccuracy: Double = 1.5
    /// Looser than `maxAccuracy`: speed is still good when the position is mediocre.
    static let maxDopplerPositionAccuracy: Double = 50
    /// Time constant of the Doppler speed smoother, in seconds.
    static let dopplerTimeConstant: Double = 4
    /// Below this smoothed speed the runner counts as standing still.
    static let minDopplerSpeed: Double = 0.6
    /// A Doppler value this recent (in sample time) takes over from the trailing-window pace.
    static let dopplerFreshSeconds: Double = 3

    private struct Mark {
        var date: Date
        var distance: Double
    }

    private(set) var totalDistance: Double = 0
    /// Trailing 30 s pace (the v1.1 current pace).
    private(set) var windowPace: Double?
    /// Pace from the smoothed Doppler speed; nil when no valid speed or standing still.
    private(set) var dopplerPace: Double?
    private(set) var lastOutcome: SampleOutcome = .accepted
    private(set) var splits: [Double] = []
    private(set) var isPaused: Bool = false
    private(set) var startDate: Date?
    private(set) var route: [RoutePoint] = []

    private var pausedAccumulated: Double = 0
    private var pauseStart: Date?
    private var acceptFrom: Date?
    private var lastSample: PaceSample?
    private var window: [Mark] = []
    private var smoothed: Double?
    private var lastSplitElapsed: Double = 0
    private var jumpCount: Int = 0
    private var nextPointStartsSegment: Bool = true
    private var dopplerSpeed: Double?
    /// Sample time of the newest Doppler speed update; nil when there is none (or after a pause).
    private(set) var dopplerUpdatedAt: Date?
    /// Time of the newest sample seen while not paused.
    private var clock: Date?

    init() {}

    /// Pace shown to the runner: the Doppler pace while a Doppler update is under three seconds old
    /// (nil when that update says standing still), otherwise the trailing-window pace.
    var currentPace: Double? {
        if let updated = dopplerUpdatedAt, let now = clock,
           now.timeIntervalSince(updated) <= PaceCalculator.dopplerFreshSeconds {
            return dopplerPace
        }
        return windowPace
    }

    /// Great-circle distance in meters between two samples.
    static func distance(from a: PaceSample, to b: PaceSample) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * Double.pi / 180
        let lat2 = b.latitude * Double.pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * Double.pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    mutating func start(at date: Date) {
        self = PaceCalculator()
        startDate = date
    }

    mutating func pause(at date: Date) {
        guard !isPaused, startDate != nil else { return }
        isPaused = true
        pauseStart = date
        windowPace = nil
        smoothed = nil
        resetDoppler()
    }

    mutating func resume(at date: Date) {
        guard isPaused else { return }
        if let began = pauseStart {
            pausedAccumulated += max(0, date.timeIntervalSince(began))
        }
        pauseStart = nil
        isPaused = false
        acceptFrom = date
        lastSample = nil
        window = []
        smoothed = nil
        windowPace = nil
        jumpCount = 0
        nextPointStartsSegment = true
        resetDoppler()
    }

    private mutating func resetDoppler() {
        dopplerSpeed = nil
        dopplerUpdatedAt = nil
        dopplerPace = nil
    }

    /// Updates the smoothed Doppler speed from a sample. Uses a looser position gate than distance
    /// and ignores samples without a trustworthy speed, so v1.1 style samples (speed unknown or
    /// speed accuracy unknown) never touch it.
    private mutating func updateDoppler(_ sample: PaceSample) {
        guard sample.speed.isFinite, sample.speed >= 0,
              sample.speedAccuracy >= 0, sample.speedAccuracy <= PaceCalculator.maxDopplerSpeedAccuracy,
              sample.horizontalAccuracy >= 0,
              sample.horizontalAccuracy <= PaceCalculator.maxDopplerPositionAccuracy else { return }
        if let start = startDate, sample.timestamp < start { return }
        if let floor = acceptFrom, sample.timestamp < floor { return }

        var speed = sample.speed
        if let last = dopplerUpdatedAt, let previous = dopplerSpeed {
            let dt = sample.timestamp.timeIntervalSince(last)
            guard dt > 0 else { return }
            let alpha = 1 - exp(-dt / PaceCalculator.dopplerTimeConstant)
            speed = previous + alpha * (sample.speed - previous)
        }
        dopplerSpeed = speed
        dopplerUpdatedAt = sample.timestamp
        if speed < PaceCalculator.minDopplerSpeed {
            dopplerPace = nil
        } else {
            dopplerPace = metersPerMile / speed
        }
    }

    /// Stores a route point. Unless `force` is set, points closer than `routeSpacing` meters
    /// (cumulative distance) to the last stored point are skipped.
    private mutating func appendRoutePoint(_ sample: PaceSample, force: Bool) {
        if !force, let last = route.last, totalDistance - last.d < PaceCalculator.routeSpacing {
            return
        }
        route.append(RoutePoint(lat: sample.latitude,
                                lon: sample.longitude,
                                t: elapsed(at: sample.timestamp),
                                d: totalDistance,
                                segmentStart: nextPointStartsSegment))
        nextPointStartsSegment = false
    }

    /// Moving time in seconds (pauses excluded).
    func elapsed(at now: Date) -> Double {
        guard let start = startDate else { return 0 }
        var total = now.timeIntervalSince(start) - pausedAccumulated
        if let began = pauseStart {
            total -= now.timeIntervalSince(began)
        }
        return max(0, total)
    }

    /// Average pace in seconds per mile over moving time, or nil with under 10 m covered.
    func averagePace(at now: Date) -> Double? {
        guard totalDistance >= 10 else { return nil }
        let time = elapsed(at: now)
        guard time > 0 else { return nil }
        return time / totalDistance * metersPerMile
    }

    /// Feeds one sample. Returns the mile splits (seconds) completed by this sample.
    /// `lastOutcome` says what happened to the sample.
    @discardableResult
    mutating func add(_ sample: PaceSample) -> [Double] {
        guard !isPaused else {
            lastOutcome = .rejected(.paused)
            return []
        }
        if let latest = clock {
            if sample.timestamp > latest { clock = sample.timestamp }
        } else {
            clock = sample.timestamp
        }
        // Doppler speed has its own, looser quality gate, so it runs before the distance gate.
        updateDoppler(sample)

        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= PaceCalculator.maxAccuracy else {
            lastOutcome = .rejected(.accuracy)
            return []
        }
        if startDate == nil {
            startDate = sample.timestamp
        }
        if let start = startDate, sample.timestamp < start {
            lastOutcome = .rejected(.beforeStart)
            return []
        }
        if let floor = acceptFrom, sample.timestamp < floor {
            lastOutcome = .rejected(.beforeStart)
            return []
        }

        guard let previous = lastSample else {
            lastSample = sample
            window = [Mark(date: sample.timestamp, distance: totalDistance)]
            appendRoutePoint(sample, force: true)
            lastOutcome = .anchored
            return []
        }

        let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else {
            lastOutcome = .rejected(.outOfOrder)
            return []
        }

        let segment = PaceCalculator.distance(from: previous, to: sample)
        if segment / dt > PaceCalculator.maxSpeed {
            jumpCount += 1
            if jumpCount >= PaceCalculator.maxConsecutiveJumps {
                // The jump looks real (e.g. long GPS gap): re-anchor without adding distance.
                lastSample = sample
                window = [Mark(date: sample.timestamp, distance: totalDistance)]
                smoothed = nil
                windowPace = nil
                jumpCount = 0
                nextPointStartsSegment = true
                appendRoutePoint(sample, force: true)
                lastOutcome = .anchored
            } else {
                lastOutcome = .rejected(.jump)
            }
            return []
        }
        jumpCount = 0
        lastOutcome = .accepted

        let distanceBefore = totalDistance
        totalDistance += segment
        lastSample = sample
        appendRoutePoint(sample, force: false)

        // Mile splits, interpolating the crossing time inside this segment.
        var newSplits: [Double] = []
        let elapsedAtSample = elapsed(at: sample.timestamp)
        var nextMark = Double(splits.count + 1) * metersPerMile
        while totalDistance >= nextMark {
            let fraction = segment > 0 ? (nextMark - distanceBefore) / segment : 1
            let crossing = elapsedAtSample - (1 - fraction) * dt
            let split = max(0, crossing - lastSplitElapsed)
            splits.append(split)
            newSplits.append(split)
            lastSplitElapsed = crossing
            nextMark = Double(splits.count + 1) * metersPerMile
        }

        // Rolling pace over the trailing window.
        window.append(Mark(date: sample.timestamp, distance: totalDistance))
        let cutoff = sample.timestamp.addingTimeInterval(-PaceCalculator.windowSeconds)
        window.removeAll { $0.date < cutoff }

        if window.count >= 2, let oldest = window.first {
            let windowDistance = totalDistance - oldest.distance
            let windowTime = sample.timestamp.timeIntervalSince(oldest.date)
            if windowDistance >= PaceCalculator.minWindowMeters, windowTime > 0 {
                let raw = windowTime / windowDistance * metersPerMile
                if let previousSmoothed = smoothed {
                    smoothed = PaceCalculator.smoothing * raw + (1 - PaceCalculator.smoothing) * previousSmoothed
                } else {
                    smoothed = raw
                }
                windowPace = smoothed
            } else {
                smoothed = nil
                windowPace = nil
            }
        } else {
            smoothed = nil
            windowPace = nil
        }

        return newSplits
    }
}
