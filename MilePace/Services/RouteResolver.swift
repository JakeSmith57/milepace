import Foundation
import Observation
import MapKit
import CoreLocation
import SwiftData

/// Why a route could not be resolved, in words that fit a row on the routes screen.
enum RouteResolveError: Error, Equatable {
    case notFound(String)
    case noPath
    case offline
    case throttled
    case failed(String)

    var message: String {
        switch self {
        case .notFound(let query): return "couldn't find '\(query)'"
        case .noPath: return "no walking path found"
        case .offline: return "no network"
        case .throttled: return "mapkit is busy. try again in a minute."
        case .failed(let text): return text
        }
    }

    /// Maps what CoreLocation, MapKit or URLSession threw to one of the cases above. `query` names what was
    /// being looked up, for a "not found" message.
    static func classify(_ error: Error, query: String) -> RouteResolveError {
        if let known = error as? RouteResolveError {
            return known
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .dataNotAllowed:
                return .offline
            default:
                break
            }
        }
        if let locationError = error as? CLError {
            if locationError.code == .network {
                return .offline
            }
            if locationError.code == .geocodeFoundNoResult {
                return .notFound(query)
            }
        }
        if let mapError = error as? MKError {
            if mapError.code == .placemarkNotFound {
                return .notFound(query)
            }
            if mapError.code == .directionsNotFound {
                return .noPath
            }
            if mapError.code == .loadingThrottled {
                return .throttled
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorNotConnectedToInternet {
            return .offline
        }
        return .failed("couldn't resolve: " + ns.localizedDescription)
    }
}

/// Finds a curated route's stops and walking paths with Apple's MapKit, and keeps the result in SwiftData
/// (`SavedRoute`) so a run never needs the network. The network is used only here, when a route is resolved
/// or refreshed.
@Observable
@MainActor
final class RouteResolver {
    static let shared = RouteResolver()

    /// Routes being resolved now.
    private(set) var busyIds: Set<String> = []
    /// The last error of each route that failed, as a plain message.
    private(set) var errors: [String: String] = [:]
    /// Progress of `resolveAll`: routes done of routes to do.
    private(set) var batchDone: Int = 0
    private(set) var batchTotal: Int = 0
    private(set) var isBatchRunning: Bool = false

    /// Coordinates found this session, by lookup, so a stop shared by routes is searched once.
    @ObservationIgnored private var coordinateCache: [String: GeoPoint] = [:]
    /// Pause between MapKit requests (MapKit throttles bursts), in nanoseconds.
    private let requestGap: UInt64 = 300_000_000
    /// Wait before trying again after MapKit says it is throttling, in nanoseconds.
    private let throttleWait: UInt64 = 8_000_000_000

    private init() {}

    // MARK: Cache

    func savedRoute(id: String) -> SavedRoute? {
        let context = AppModel.shared.container.mainContext
        var descriptor = FetchDescriptor<SavedRoute>(predicate: #Predicate<SavedRoute> { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// True when a saved curated route has no path, was resolved for another home address, or is older than
    /// 90 days.
    func isStale(_ saved: SavedRoute, now: Date = Date()) -> Bool {
        if saved.pointsData.isEmpty {
            return true
        }
        return RouteCachePolicy.needsResolve(savedHome: saved.homeAddress,
                                             currentHome: RouteHome.address,
                                             createdAt: saved.createdAt,
                                             now: now)
    }

    /// Notes the route was used for a run.
    func markUsed(id: String) {
        guard let saved = savedRoute(id: id) else { return }
        saved.lastUsedAt = Date()
        try? AppModel.shared.container.mainContext.save()
    }

    /// Saves a route that did not come from the catalog (a generated loop or one learned from runs), or
    /// replaces the path of one saved before under the same id. False when the save failed.
    @discardableResult
    func upsert(id: String,
                name: String,
                kind: SavedRouteKind,
                points: [GeoPoint],
                stops: [GeoPoint],
                notes: String) -> Bool {
        let context = AppModel.shared.container.mainContext
        let meters = RouteGeometry.length(of: points)
        if let existing = savedRoute(id: id) {
            existing.name = name
            existing.kind = kind.rawValue
            existing.notes = notes
            existing.update(points: points,
                            stops: stops,
                            distanceMeters: meters,
                            homeAddress: RouteHome.address,
                            createdAt: Date())
        } else {
            context.insert(SavedRoute(id: id,
                                      name: name,
                                      kind: kind,
                                      points: points,
                                      stops: stops,
                                      distanceMeters: meters,
                                      notes: notes,
                                      homeAddress: RouteHome.address))
        }
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    /// Deletes a saved route, and forgets it as the chosen route when it was that.
    func delete(id: String) {
        guard let saved = savedRoute(id: id) else { return }
        let context = AppModel.shared.container.mainContext
        context.delete(saved)
        try? context.save()
        if PlanStore.shared.selectedRouteId == id {
            PlanStore.shared.selectedRouteId = nil
        }
    }

    private func store(_ resolved: ResolvedRoute, notes: String) {
        let context = AppModel.shared.container.mainContext
        if let existing = savedRoute(id: resolved.id) {
            existing.name = resolved.name
            existing.notes = notes
            existing.update(points: resolved.points,
                            stops: resolved.stopsResolved,
                            distanceMeters: resolved.distanceMeters,
                            homeAddress: resolved.homeAddress,
                            createdAt: resolved.resolvedAt)
        } else {
            let saved = SavedRoute(id: resolved.id,
                                   name: resolved.name,
                                   kind: .curated,
                                   points: resolved.points,
                                   stops: resolved.stopsResolved,
                                   distanceMeters: resolved.distanceMeters,
                                   notes: notes,
                                   homeAddress: resolved.homeAddress,
                                   createdAt: resolved.resolvedAt)
            context.insert(saved)
        }
        try? context.save()
    }

    // MARK: Resolving

    /// Resolves a route unless a fresh copy is saved (or `force`). A failure keeps whatever was saved before
    /// and leaves its message in `errors`. True when the route has a usable saved path afterwards.
    @discardableResult
    func ensureResolved(_ route: CuratedRoute, force: Bool = false) async -> Bool {
        if busyIds.contains(route.id) {
            return false
        }
        if !force, let saved = savedRoute(id: route.id), !isStale(saved) {
            errors[route.id] = nil
            return true
        }
        busyIds.insert(route.id)
        errors[route.id] = nil
        defer {
            busyIds.remove(route.id)
        }
        do {
            let resolved = try await resolve(route)
            store(resolved, notes: route.notes)
            return true
        } catch is CancellationError {
            return false
        } catch {
            errors[route.id] = RouteResolveError.classify(error, query: route.name).message
            return false
        }
    }

    /// Resolves every route of the catalog one after the other. Stops early when there is no network.
    func resolveAll(catalog: RouteCatalog, force: Bool = false) async {
        guard !isBatchRunning else { return }
        isBatchRunning = true
        batchDone = 0
        batchTotal = catalog.routes.count
        for route in catalog.routes {
            if Task.isCancelled {
                break
            }
            await ensureResolved(route, force: force)
            batchDone += 1
            if errors[route.id] == RouteResolveError.offline.message {
                break
            }
        }
        isBatchRunning = false
    }

    /// Finds the stops of `route` and a walking path between each pair, in order. Legs are requested one
    /// at a time with a short pause.
    func resolve(_ route: CuratedRoute) async throws -> ResolvedRoute {
        let address = RouteHome.address
        let home = try await resolveHome(address: address)
        var start = home
        if route.start.lowercased() != "home" {
            start = try await geocode(route.start)
        }
        var waypoints: [GeoPoint] = []
        for waypoint in route.waypoints {
            try Task.checkCancellation()
            waypoints.append(try await locate(waypoint, near: home))
        }
        let stops = RouteLegs.stops(start: start, waypoints: waypoints, shape: route.shape)
        guard stops.count >= 2 else {
            throw RouteResolveError.noPath
        }
        var legs: [[GeoPoint]] = []
        for index in 1..<stops.count {
            try Task.checkCancellation()
            let from = stops[index - 1]
            let to = stops[index]
            if RouteGeometry.distance(from, to) < 5 {
                continue
            }
            if !legs.isEmpty {
                try await Task.sleep(nanoseconds: requestGap)
            }
            legs.append(try await walkingLeg(from: from, to: to))
        }
        let points = RoutePolyline.join(legs)
        guard points.count >= 2 else {
            throw RouteResolveError.noPath
        }
        return ResolvedRoute(id: route.id,
                             name: route.name,
                             shape: route.shape,
                             points: points,
                             stopsResolved: stops,
                             resolvedAt: Date(),
                             homeAddress: address)
    }

    /// Where the first waypoint of a saved route is (the track, for the track route), for "open in maps".
    func firstStop(of saved: SavedRoute) -> GeoPoint? {
        let stops = saved.stops
        if stops.count >= 2 {
            return stops[1]
        }
        return saved.points.last
    }

    /// The home address's point: the saved one, or one geocode (needs the network the first time).
    func homePoint() async throws -> GeoPoint {
        return try await resolveHome(address: RouteHome.address)
    }

    // MARK: Lookups

    private func resolveHome(address: String) async throws -> GeoPoint {
        if let known = RouteHome.geocodedPoint(for: address) {
            return known
        }
        let point = try await geocode(address)
        RouteHome.remember(point: point, for: address)
        return point
    }

    private func locate(_ waypoint: RouteWaypoint, near home: GeoPoint) async throws -> GeoPoint {
        switch waypoint.kind {
        case .address:
            return try await geocode(waypoint.query)
        case .place:
            return try await search(waypoint.query, near: home)
        }
    }

    private func coordinate(_ point: GeoPoint) -> CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)
    }

    /// `CLGeocoder().geocodeAddressString(_:) async throws -> [CLPlacemark]`.
    private func geocode(_ address: String) async throws -> GeoPoint {
        let key = "address|" + address.lowercased()
        if let cached = coordinateCache[key] {
            return cached
        }
        let marks: [CLPlacemark]
        do {
            marks = try await CLGeocoder().geocodeAddressString(address)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RouteResolveError.classify(error, query: address)
        }
        guard let found = marks.first?.location?.coordinate else {
            throw RouteResolveError.notFound(address)
        }
        let point = GeoPoint(lat: found.latitude, lon: found.longitude)
        coordinateCache[key] = point
        try await Task.sleep(nanoseconds: requestGap)
        return point
    }

    /// `MKLocalSearch(request:).start() async throws -> MKLocalSearch.Response`, in a region of 10 km
    /// (5 km each way) around home. The first result within 25 km of home wins.
    private func search(_ query: String, near home: GeoPoint) async throws -> GeoPoint {
        let key = "place|" + query.lowercased() + "|" + String(format: "%.3f,%.3f", home.lat, home.lon)
        if let cached = coordinateCache[key] {
            return cached
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate(home),
                                            latitudinalMeters: 10_000,
                                            longitudinalMeters: 10_000)
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RouteResolveError.classify(error, query: query)
        }
        for item in response.mapItems {
            let found = item.placemark.coordinate
            let point = GeoPoint(lat: found.latitude, lon: found.longitude)
            if RouteGeometry.distance(point, home) <= 25_000 {
                coordinateCache[key] = point
                try await Task.sleep(nanoseconds: requestGap)
                return point
            }
        }
        throw RouteResolveError.notFound(query)
    }

    /// One walking leg: `MKDirections(request:).calculate() async throws -> MKDirections.Response`, the
    /// first route's polyline. Tries again twice after a throttling error.
    func walkingLeg(from: GeoPoint, to: GeoPoint, retryOnThrottle: Bool = true) async throws -> [GeoPoint] {
        var attempt = 0
        while true {
            do {
                return try await requestLeg(from: from, to: to)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let mapped = RouteResolveError.classify(error, query: "")
                if retryOnThrottle && mapped == RouteResolveError.throttled && attempt < 2 {
                    attempt += 1
                    try await Task.sleep(nanoseconds: throttleWait)
                    continue
                }
                throw mapped
            }
        }
    }

    private func requestLeg(from: GeoPoint, to: GeoPoint) async throws -> [GeoPoint] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(from)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate(to)))
        request.transportType = .walking
        request.requestsAlternateRoutes = false
        let response = try await MKDirections(request: request).calculate()
        guard let first = response.routes.first else {
            throw RouteResolveError.noPath
        }
        let points = RouteResolver.points(of: first.polyline)
        guard points.count >= 2 else {
            throw RouteResolveError.noPath
        }
        return points
    }

    /// `MKMultiPoint.points()` (an `UnsafeMutablePointer<MKMapPoint>`) and `pointCount`, each point turned
    /// into a coordinate with `MKMapPoint.coordinate`.
    private static func points(of polyline: MKPolyline) -> [GeoPoint] {
        let count = polyline.pointCount
        guard count > 0 else { return [] }
        let raw = polyline.points()
        var result: [GeoPoint] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let found = raw[index].coordinate
            result.append(GeoPoint(lat: found.latitude, lon: found.longitude))
        }
        return result
    }
}
