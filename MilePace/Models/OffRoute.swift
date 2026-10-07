import Foundation
import Observation

/// Decides when a run has left the route it follows. Off when the distance from the route stays above 40 m
/// for 20 seconds; back on when it drops under 25 m. `.off` comes once per excursion; `.back` is silent.
struct OffRouteDetector: Equatable {
    enum Event: Equatable {
        case off
        case back
    }

    static let offMeters: Double = 40
    static let backMeters: Double = 25
    static let offSeconds: Double = 20

    private(set) var isOff: Bool = false
    /// When the current stretch above 40 m began.
    private var offSince: Double? = nil
    private var lastTime: Double? = nil

    /// Takes the next fix: its distance from the route and its time in seconds. A fix that is not valid
    /// changes nothing. Time going backwards starts the 20 seconds over.
    mutating func feed(offsetMeters: Double, time: Double, isValid: Bool = true) -> Event? {
        guard isValid, offsetMeters.isFinite, time.isFinite else { return nil }
        if let last = lastTime, time < last {
            offSince = nil
        }
        lastTime = time
        if isOff {
            if offsetMeters < OffRouteDetector.backMeters {
                isOff = false
                offSince = nil
                return .back
            }
            return nil
        }
        guard offsetMeters > OffRouteDetector.offMeters else {
            offSince = nil
            return nil
        }
        guard let since = offSince else {
            offSince = time
            return nil
        }
        if time - since >= OffRouteDetector.offSeconds {
            isOff = true
            offSince = nil
            return .off
        }
        return nil
    }
}

/// How far along the followed route a run is, and whether it is off it. Fed with the run's saved fixes
/// (`RunView` holds one while a route is followed), so it also catches up after the data view was away.
@Observable
@MainActor
final class RouteFollowState {
    private(set) var along: Double? = nil
    private(set) var offsetMeters: Double? = nil

    @ObservationIgnored private var processed: Int = 0
    @ObservationIgnored private var detector = OffRouteDetector()

    func reset() {
        along = nil
        offsetMeters = nil
        processed = 0
        detector = OffRouteDetector()
    }

    /// Moves along the route with the fixes that arrived since the last call and returns the off-route events
    /// they caused, in order. The time of a fix is its moving time, so a pause does not count.
    func advance(liveRoute: [RoutePoint], on polyline: [GeoPoint]) -> [OffRouteDetector.Event] {
        if liveRoute.count < processed {
            reset()
        }
        guard liveRoute.count > processed else { return [] }
        var events: [OffRouteDetector.Event] = []
        var currentAlong = along
        var currentOffset = offsetMeters
        for point in liveRoute[processed...] {
            let fix = GeoPoint(lat: point.lat, lon: point.lon)
            guard let step = RouteGeometry.progress(of: fix, on: polyline, previousAlong: currentAlong) else { continue }
            currentAlong = step.alongMeters
            currentOffset = step.offsetMeters
            if let event = detector.feed(offsetMeters: step.offsetMeters, time: point.t) {
                events.append(event)
            }
        }
        processed = liveRoute.count
        along = currentAlong
        offsetMeters = currentOffset
        return events
    }
}
