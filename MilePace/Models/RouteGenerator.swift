import Foundation

/// A direction a generated loop heads off in.
struct LoopHeading: Equatable {
    let degrees: Double
    let name: String
}

/// One generated loop: the path MapKit found for four walking legs around a circle.
struct LoopCandidate: Identifiable, Equatable {
    /// The heading in whole degrees (unique among the candidates of one make).
    let id: Int
    let headingName: String
    let points: [GeoPoint]
    /// Start, the three waypoints, start.
    let stops: [GeoPoint]
    let meters: Double
    let targetMeters: Double
    let turns: Int

    var errorFraction: Double {
        guard targetMeters > 0 else { return 0 }
        return abs(meters - targetMeters) / targetMeters
    }

    var turnsPerMile: Double {
        let miles = meters / metersPerMile
        return miles > 0 ? Double(turns) / miles : 0
    }

    /// "loop 4.0 mi, north".
    var name: String {
        return RouteGenerator.loopName(meters: meters, heading: headingName)
    }
}

/// Make-a-loop geometry, apart from MapKit so it can be tested.
enum RouteGenerator {
    /// The three directions tried, in order.
    static let headings: [LoopHeading] = [LoopHeading(degrees: 0, name: "north"),
                                          LoopHeading(degrees: 120, name: "southeast"),
                                          LoopHeading(degrees: 240, name: "southwest")]
    static let defaultRadiusFactor: Double = 0.8
    static let radiusFactorRange: ClosedRange<Double> = 0.4...1.2
    /// A loop within this share of the target distance is good enough: 7 %.
    static let tolerance: Double = 0.07
    /// Tries per candidate to get within the tolerance (each rescales the circle).
    static let maxTries = 3
    /// Walking legs per try (start, three waypoints, start).
    static let legsPerTry = 4
    /// Hard cap of MKDirections requests per candidate.
    static let maxRequests = 12
    /// A turn is a change of direction of more than this many degrees.
    static let turnDegrees: Double = 60

    /// Three waypoints on a circle of radius r = distance / (2 pi) * radiusFactor. The start lies on the
    /// circle, so the center is `r` from the start along `headingDegrees`. The waypoints are 90, 180 and
    /// 270 degrees around the circle from the start (clockwise).
    static func waypoints(start: GeoPoint,
                          distanceMeters: Double,
                          headingDegrees: Double,
                          radiusFactor: Double = 0.8) -> [GeoPoint] {
        let radius = circleRadius(distanceMeters: distanceMeters, radiusFactor: radiusFactor)
        let center = RouteGeometry.destination(from: start, bearingDegrees: headingDegrees, meters: radius)
        let startBearing = headingDegrees + 180
        var result: [GeoPoint] = []
        for quarter in 1...3 {
            let bearing = (startBearing + 90 * Double(quarter)).truncatingRemainder(dividingBy: 360)
            result.append(RouteGeometry.destination(from: center, bearingDegrees: bearing, meters: radius))
        }
        return result
    }

    static func circleRadius(distanceMeters: Double, radiusFactor: Double) -> Double {
        return distanceMeters / (2 * Double.pi) * radiusFactor
    }

    /// The radius factor for the next try: the current one scaled by target over measured, kept between 0.4
    /// and 1.2. An unusable measurement keeps the current factor.
    static func nextRadiusFactor(current: Double, target: Double, measured: Double) -> Double {
        guard measured.isFinite, measured > 0, target.isFinite, target > 0 else {
            return min(max(current, radiusFactorRange.lowerBound), radiusFactorRange.upperBound)
        }
        let scaled = current * target / measured
        return min(max(scaled, radiusFactorRange.lowerBound), radiusFactorRange.upperBound)
    }

    static func loopName(meters: Double, heading: String) -> String {
        return "loop " + String(format: "%.1f", meters / metersPerMile) + " mi, " + heading
    }

    // MARK: Ranking

    private static func angleBetween(_ a: Double, _ b: Double) -> Double {
        let raw = (b - a + 540).truncatingRemainder(dividingBy: 360) - 180
        return abs(raw)
    }

    /// How many sharp turns (more than 60 degrees) a path has: a proxy for intersections. Looks at the
    /// direction every 30 m and compares the stretch before a point with the stretch after it, so a corner
    /// is counted once however the samples fall.
    static func turns(in polyline: [GeoPoint]) -> Int {
        let samples = RouteGeometry.resample(polyline, every: 30)
        guard samples.count >= 4 else { return 0 }
        var bearings: [Double] = []
        for index in 1..<samples.count {
            bearings.append(RouteGeometry.bearing(from: samples[index - 1], to: samples[index]))
        }
        var count = 0
        var index = 1
        while index + 1 < bearings.count {
            if angleBetween(bearings[index - 1], bearings[index + 1]) > turnDegrees {
                count += 1
                index += 3
            } else {
                index += 1
            }
        }
        return count
    }

    /// True when `a` is the better loop: clearly closer to the target distance (more than 2 points of
    /// error apart), otherwise fewer sharp turns per mile.
    static func isBetter(_ a: LoopCandidate, than b: LoopCandidate) -> Bool {
        let gap = a.errorFraction - b.errorFraction
        if abs(gap) > 0.02 {
            return gap < 0
        }
        return a.turnsPerMile < b.turnsPerMile
    }

    /// Best first.
    static func ranked(_ candidates: [LoopCandidate]) -> [LoopCandidate] {
        var rest = candidates
        var result: [LoopCandidate] = []
        while !rest.isEmpty {
            var bestIndex = 0
            for index in 1..<rest.count where isBetter(rest[index], than: rest[bestIndex]) {
                bestIndex = index
            }
            result.append(rest.remove(at: bestIndex))
        }
        return result
    }
}
