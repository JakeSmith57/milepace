import Foundation
import Observation
import MapKit
import CoreLocation

/// Makes loops of a chosen length from a start, like Strava's suggested routes: a circle of three
/// waypoints (`RouteGenerator`) joined by MapKit walking legs, rescaled up to three times to land within
/// 7 % of the target. Three candidates are made, heading north, southeast and southwest, and ranked.
@Observable
@MainActor
final class RouteMaker {
    private(set) var candidates: [LoopCandidate] = []
    private(set) var isMaking: Bool = false
    /// "making 2 / 3" while it works.
    private(set) var progressText: String = ""
    private(set) var errorText: String? = nil

    @ObservationIgnored private var task: Task<Void, Never>? = nil

    /// Starts making loops from `start`, or from home when it is nil. Does nothing while already making.
    func make(start: GeoPoint?, targetMeters: Double, viaParks: Bool) {
        guard !isMaking else { return }
        isMaking = true
        candidates = []
        errorText = nil
        progressText = ""
        task = Task {
            await self.run(start: start, targetMeters: targetMeters, viaParks: viaParks)
        }
    }

    /// Stops making (the sheet was closed).
    func cancel() {
        task?.cancel()
        task = nil
        isMaking = false
        progressText = ""
    }

    private func run(start: GeoPoint?, targetMeters: Double, viaParks: Bool) async {
        defer {
            isMaking = false
            progressText = ""
        }
        let origin: GeoPoint
        if let given = start {
            origin = given
        } else {
            do {
                origin = try await RouteResolver.shared.homePoint()
            } catch {
                errorText = RouteResolveError.classify(error, query: RouteHome.address).message
                return
            }
        }
        var made: [LoopCandidate] = []
        let headings = RouteGenerator.headings
        for (index, heading) in headings.enumerated() {
            if Task.isCancelled {
                return
            }
            progressText = "making \(index + 1) / \(headings.count)"
            do {
                if let candidate = try await build(origin: origin,
                                                   heading: heading,
                                                   targetMeters: targetMeters,
                                                   viaParks: viaParks) {
                    made.append(candidate)
                }
            } catch is CancellationError {
                return
            } catch {
                // Stop early on an error: keep what was made so far.
                errorText = RouteResolveError.classify(error, query: "").message
                break
            }
        }
        candidates = RouteGenerator.ranked(made)
        if candidates.isEmpty && errorText == nil {
            errorText = "couldn't make a loop here."
        }
    }

    /// One candidate: tries the circle up to three times, rescaling it, and keeps the closest to the target.
    /// At most 12 directions requests (3 tries of 4 legs).
    private func build(origin: GeoPoint,
                       heading: LoopHeading,
                       targetMeters: Double,
                       viaParks: Bool) async throws -> LoopCandidate? {
        var factor = RouteGenerator.defaultRadiusFactor
        var requests = 0
        var best: LoopCandidate? = nil
        for _ in 0..<RouteGenerator.maxTries {
            try Task.checkCancellation()
            var waypoints = RouteGenerator.waypoints(start: origin,
                                                     distanceMeters: targetMeters,
                                                     headingDegrees: heading.degrees,
                                                     radiusFactor: factor)
            if viaParks, waypoints.count == 3 {
                let radius = RouteGenerator.circleRadius(distanceMeters: targetMeters, radiusFactor: factor)
                if let park = await nearestPark(to: waypoints[1], within: radius) {
                    waypoints[1] = park
                }
            }
            var stops: [GeoPoint] = [origin]
            stops.append(contentsOf: waypoints)
            stops.append(origin)
            guard requests + RouteGenerator.legsPerTry <= RouteGenerator.maxRequests else { break }
            guard let legs = try await walk(stops, requests: &requests) else { break }
            let points = RoutePolyline.join(legs)
            guard points.count >= 2 else { break }
            let candidate = LoopCandidate(id: Int(heading.degrees),
                                          headingName: heading.name,
                                          points: points,
                                          stops: stops,
                                          meters: RouteGeometry.length(of: points),
                                          targetMeters: targetMeters,
                                          turns: RouteGenerator.turns(in: points))
            if best == nil || candidate.errorFraction < (best?.errorFraction ?? Double.infinity) {
                best = candidate
            }
            if candidate.errorFraction <= RouteGenerator.tolerance {
                break
            }
            factor = RouteGenerator.nextRadiusFactor(current: factor, target: targetMeters, measured: candidate.meters)
        }
        return best
    }

    /// Walking legs between consecutive stops, one request each (counted in `requests`), 0.3 s apart. Nil
    /// when a stop pair could not be walked.
    private func walk(_ stops: [GeoPoint], requests: inout Int) async throws -> [[GeoPoint]]? {
        var legs: [[GeoPoint]] = []
        for index in 1..<stops.count {
            try Task.checkCancellation()
            let from = stops[index - 1]
            let to = stops[index]
            if RouteGeometry.distance(from, to) < 5 {
                continue
            }
            if !legs.isEmpty {
                try await Task.sleep(nanoseconds: 300_000_000)
            }
            requests += 1
            legs.append(try await RouteResolver.shared.walkingLeg(from: from, to: to, retryOnThrottle: false))
        }
        return legs.isEmpty ? nil : legs
    }

    /// The nearest park to `point` within `radius` meters: an `MKLocalSearch` with a points-of-interest filter
    /// for parks. Nil when none is found or the search fails (the waypoint then stays where it is).
    private func nearestPark(to point: GeoPoint, within radius: Double) async -> GeoPoint? {
        let center = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "park"
        request.region = MKCoordinateRegion(center: center,
                                            latitudinalMeters: radius * 2,
                                            longitudinalMeters: radius * 2)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.park])
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        var nearest: GeoPoint? = nil
        var nearestDistance = radius
        for item in response.mapItems {
            let found = item.placemark.coordinate
            let candidate = GeoPoint(lat: found.latitude, lon: found.longitude)
            let distance = RouteGeometry.distance(candidate, point)
            if distance <= nearestDistance {
                nearest = candidate
                nearestDistance = distance
            }
        }
        return nearest
    }
}
