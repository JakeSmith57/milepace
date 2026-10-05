import Foundation

/// Splits a live route into drawable pieces for the map.
enum LiveRouteSegments {
    /// Contiguous runs of points, split before every point with `segmentStart` (a pause or a GPS
    /// re-anchor), so the map never draws a line across a gap. Runs with fewer than two points
    /// have nothing to draw and are dropped.
    static func split(_ route: [RoutePoint]) -> [[RoutePoint]] {
        var pieces: [[RoutePoint]] = []
        var current: [RoutePoint] = []
        for point in route {
            if point.segmentStart && !current.isEmpty {
                pieces.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty {
            pieces.append(current)
        }
        return pieces.filter { $0.count >= 2 }
    }
}
