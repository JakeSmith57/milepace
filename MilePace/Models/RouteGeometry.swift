import Foundation

/// A latitude and longitude in degrees. Plain values, so routes can be stored and tested without CoreLocation.
struct GeoPoint: Codable, Equatable {
    var lat: Double
    var lon: Double
}

/// Distances along and across polylines, at city scale.
enum RouteGeometry {
    /// Mean earth radius in meters.
    static let earthRadius: Double = 6_371_000
    private static let metersPerDegree: Double = earthRadius * Double.pi / 180

    /// Great-circle distance in meters (haversine).
    static func distance(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.lat * Double.pi / 180
        let lat2 = b.lat * Double.pi / 180
        let dLat = (b.lat - a.lat) * Double.pi / 180
        let dLon = (b.lon - a.lon) * Double.pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        let root = min(1.0, sqrt(h))
        return 2 * earthRadius * asin(root)
    }

    /// Length of a polyline in meters; 0 with fewer than two points.
    static func length(of polyline: [GeoPoint]) -> Double {
        guard polyline.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<polyline.count {
            total += distance(polyline[index - 1], polyline[index])
        }
        return total
    }

    /// Where a point sits against a polyline: how far along it (meters from its start) the nearest spot is,
    /// and how far off it (meters). Uses a flat local projection around the point, which is plenty at city
    /// scale. Nil for an empty polyline; a one-point polyline gives along 0 and the distance to that point.
    static func project(_ point: GeoPoint, onto polyline: [GeoPoint]) -> (alongMeters: Double, offsetMeters: Double)? {
        let all = candidates(for: point, on: polyline)
        guard var best = all.first else { return nil }
        for item in all where item.offset < best.offset {
            best = item
        }
        return (alongMeters: best.along, offsetMeters: best.offset)
    }

    /// The projection to use for the next GPS fix of a run that follows `polyline`. Other spots of the
    /// polyline can be just as close (an out-and-back passes every point twice, a loop ends where it
    /// starts), so among the spots that are about as near as the nearest (within `tolerance` meters), it
    /// takes the first one that is not more than `backwardLimit` meters behind `previousAlong`, and never
    /// reports less than `previousAlong`: progress only moves forward, so GPS jitter and the turnaround of an
    /// out-and-back cannot send it back. With no such spot it keeps `previousAlong`. Without a previous
    /// value it is the first of the nearest spots.
    static func progress(of point: GeoPoint,
                         on polyline: [GeoPoint],
                         previousAlong: Double?,
                         backwardLimit: Double = 50,
                         tolerance: Double = 25) -> (alongMeters: Double, offsetMeters: Double)? {
        let all = candidates(for: point, on: polyline)
        guard let minOffset = all.map({ $0.offset }).min() else { return nil }
        let near = all.filter { $0.offset <= minOffset + tolerance }
        guard let previous = previousAlong else {
            let first = near.min { $0.along < $1.along }
            return first.map { (alongMeters: $0.along, offsetMeters: $0.offset) }
        }
        let forward = near.filter { $0.along >= previous - backwardLimit }
        if let pick = forward.min(by: { $0.along < $1.along }) {
            return (alongMeters: max(pick.along, previous), offsetMeters: pick.offset)
        }
        return (alongMeters: previous, offsetMeters: minOffset)
    }

    /// Runs `progress` over a whole track of fixes, in order, and returns the last along value.
    static func follow(track: [GeoPoint], on polyline: [GeoPoint], startingAlong: Double?) -> Double? {
        var along = startingAlong
        for fix in track {
            if let step = progress(of: fix, on: polyline, previousAlong: along) {
                along = step.alongMeters
            }
        }
        return along
    }

    /// Points `meters` apart along the polyline, starting with its first point and ending with its last.
    static func resample(_ polyline: [GeoPoint], every meters: Double) -> [GeoPoint] {
        guard polyline.count >= 2, meters > 0, meters.isFinite else { return polyline }
        var result: [GeoPoint] = [polyline[0]]
        // Distance from the last emitted point to the start of the current segment.
        var carried = 0.0
        for index in 1..<polyline.count {
            let a = polyline[index - 1]
            let b = polyline[index]
            let segment = distance(a, b)
            guard segment > 0 else { continue }
            var position = meters - carried
            while position <= segment {
                let fraction = position / segment
                result.append(GeoPoint(lat: a.lat + (b.lat - a.lat) * fraction,
                                       lon: a.lon + (b.lon - a.lon) * fraction))
                position += meters
            }
            carried = segment - (position - meters)
        }
        if let last = polyline.last, let emitted = result.last, distance(emitted, last) > 0.5 {
            result.append(last)
        }
        return result
    }

    // MARK: Projection internals

    private struct Spot {
        let along: Double
        let offset: Double
    }

    /// The nearest spot of every segment: its distance along the polyline and from the point.
    private static func candidates(for point: GeoPoint, on polyline: [GeoPoint]) -> [Spot] {
        guard let first = polyline.first else { return [] }
        if polyline.count == 1 {
            return [Spot(along: 0, offset: distance(point, first))]
        }
        let lonScale = cos(point.lat * Double.pi / 180)
        var spots: [Spot] = []
        var before = 0.0
        for index in 1..<polyline.count {
            let a = polyline[index - 1]
            let b = polyline[index]
            let segment = distance(a, b)
            // Local meters, with the point at the origin.
            let ax = (a.lon - point.lon) * metersPerDegree * lonScale
            let ay = (a.lat - point.lat) * metersPerDegree
            let bx = (b.lon - point.lon) * metersPerDegree * lonScale
            let by = (b.lat - point.lat) * metersPerDegree
            let dx = bx - ax
            let dy = by - ay
            let squared = dx * dx + dy * dy
            var t = 0.0
            if squared > 0 {
                t = min(1.0, max(0.0, -(ax * dx + ay * dy) / squared))
            }
            let cx = ax + t * dx
            let cy = ay + t * dy
            spots.append(Spot(along: before + t * segment, offset: (cx * cx + cy * cy).squareRoot()))
            before += segment
        }
        return spots
    }
}
