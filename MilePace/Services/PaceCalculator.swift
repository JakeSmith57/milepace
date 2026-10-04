import Foundation

/// A lightweight GPS sample so the calculator can be tested without CoreLocation.
struct PaceSample: Equatable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var speed: Double

    init(timestamp: Date,
         latitude: Double,
         longitude: Double,
         horizontalAccuracy: Double,
         speed: Double = -1) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
    }
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

    private struct Mark {
        var date: Date
        var distance: Double
    }

    private(set) var totalDistance: Double = 0
    private(set) var currentPace: Double?
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

    init() {}

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
        currentPace = nil
        smoothed = nil
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
        currentPace = nil
        jumpCount = 0
        nextPointStartsSegment = true
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
    @discardableResult
    mutating func add(_ sample: PaceSample) -> [Double] {
        guard !isPaused else { return [] }
        guard sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= PaceCalculator.maxAccuracy else {
            return []
        }
        if startDate == nil {
            startDate = sample.timestamp
        }
        if let start = startDate, sample.timestamp < start { return [] }
        if let floor = acceptFrom, sample.timestamp < floor { return [] }

        guard let previous = lastSample else {
            lastSample = sample
            window = [Mark(date: sample.timestamp, distance: totalDistance)]
            appendRoutePoint(sample, force: true)
            return []
        }

        let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
        guard dt > 0 else { return [] }

        let segment = PaceCalculator.distance(from: previous, to: sample)
        if segment / dt > PaceCalculator.maxSpeed {
            jumpCount += 1
            if jumpCount >= PaceCalculator.maxConsecutiveJumps {
                // The jump looks real (e.g. long GPS gap): re-anchor without adding distance.
                lastSample = sample
                window = [Mark(date: sample.timestamp, distance: totalDistance)]
                smoothed = nil
                currentPace = nil
                jumpCount = 0
                nextPointStartsSegment = true
                appendRoutePoint(sample, force: true)
            }
            return []
        }
        jumpCount = 0

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
                currentPace = smoothed
            } else {
                smoothed = nil
                currentPace = nil
            }
        } else {
            smoothed = nil
            currentPace = nil
        }

        return newSplits
    }
}
