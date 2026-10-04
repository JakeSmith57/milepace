import Foundation

/// Pace relative to the run's average.
enum PaceBand: Int, CaseIterable {
    case faster
    case steady
    case slower
}

struct ColoredSegment: Identifiable {
    let id: Int
    let band: PaceBand
    let points: [RoutePoint]
}

enum RouteSegments {
    /// Seconds per mile either side of the average that still counts as steady.
    static let bandMargin: Double = 10
    /// Points either side of a point used to estimate its pace.
    static let paceWindow: Int = 2

    /// Splits the route into runs of consecutive points with the same band. Each point's pace is
    /// computed over the surrounding points (within the same segment), faster means more than
    /// `bandMargin` seconds under the average and slower more than that over it. Adjacent segments
    /// share their boundary point so the line is continuous; a point with `segmentStart` begins a new
    /// segment that is not joined to the previous one.
    static func colored(_ route: [RoutePoint], averagePace: Double) -> [ColoredSegment] {
        guard !route.isEmpty else { return [] }
        let bands = pointBands(route, averagePace: averagePace)

        var segments: [ColoredSegment] = []
        var currentBand = bands[0]
        var currentPoints: [RoutePoint] = [route[0]]

        for index in 1..<route.count {
            let point = route[index]
            if point.segmentStart {
                segments.append(ColoredSegment(id: segments.count, band: currentBand, points: currentPoints))
                currentBand = bands[index]
                currentPoints = [point]
            } else if bands[index] == currentBand {
                currentPoints.append(point)
            } else {
                segments.append(ColoredSegment(id: segments.count, band: currentBand, points: currentPoints))
                currentBand = bands[index]
                currentPoints = [route[index - 1], point]
            }
        }
        segments.append(ColoredSegment(id: segments.count, band: currentBand, points: currentPoints))
        return segments
    }

    /// The first point at or after each whole mile.
    static func mileMarkers(_ route: [RoutePoint]) -> [(mile: Int, point: RoutePoint)] {
        var result: [(mile: Int, point: RoutePoint)] = []
        var next = 1
        for point in route {
            while point.d >= Double(next) * metersPerMile {
                result.append((mile: next, point: point))
                next += 1
            }
        }
        return result
    }

    private static func pointBands(_ route: [RoutePoint], averagePace: Double) -> [PaceBand] {
        guard averagePace.isFinite, averagePace > 0 else {
            return Array(repeating: PaceBand.steady, count: route.count)
        }

        // First and last index of the segment each point belongs to.
        var segmentFirst = Array(repeating: 0, count: route.count)
        var currentFirst = 0
        for index in 0..<route.count {
            if route[index].segmentStart {
                currentFirst = index
            }
            segmentFirst[index] = currentFirst
        }
        var segmentLast = Array(repeating: route.count - 1, count: route.count)
        var currentLast = route.count - 1
        for index in stride(from: route.count - 1, through: 0, by: -1) {
            segmentLast[index] = currentLast
            if route[index].segmentStart && index > 0 {
                currentLast = index - 1
            }
        }

        var bands: [PaceBand] = []
        bands.reserveCapacity(route.count)
        for index in 0..<route.count {
            let low = max(segmentFirst[index], index - paceWindow)
            let high = min(segmentLast[index], index + paceWindow)
            let meters = route[high].d - route[low].d
            let seconds = route[high].t - route[low].t
            guard meters > 0, seconds > 0 else {
                bands.append(.steady)
                continue
            }
            let pace = seconds / meters * metersPerMile
            if pace < averagePace - bandMargin {
                bands.append(.faster)
            } else if pace > averagePace + bandMargin {
                bands.append(.slower)
            } else {
                bands.append(.steady)
            }
        }
        return bands
    }
}
