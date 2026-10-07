import Foundation

/// One stop MapKit is asked to find: a named place (a search) or a street address (a geocode).
struct RouteWaypoint: Codable, Equatable {
    let query: String
    let kind: Kind

    enum Kind: String, Codable {
        case place
        case address
    }
}

/// How a route's stops are joined up.
enum RouteShape: String, Codable {
    case loop
    case outAndBack
    case oneWay
    /// The route only gets you to the track; the distance shown is "to the track".
    case track
}

/// One hand-written route from `routes.json`.
struct CuratedRoute: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let shape: RouteShape
    /// "home" for every shipped route; anything else is read as an address.
    let start: String
    let waypoints: [RouteWaypoint]
    let tags: [String]
    let notes: String
}

struct RouteCatalog: Codable, Equatable {
    let version: Int
    let home: String
    let routes: [CuratedRoute]

    func route(id: String) -> CuratedRoute? {
        return routes.first { $0.id == id }
    }

    /// The shipped route's name, or nil for an id the catalog does not have.
    func name(forId id: String) -> String? {
        return route(id: id)?.name
    }
}

enum RouteCatalogLoader {
    static func decode(_ data: Data) -> RouteCatalog? {
        return try? JSONDecoder().decode(RouteCatalog.self, from: data)
    }

    /// Reads `routes.json` from the bundle; nil when it is missing or does not parse.
    static func load(bundle: Bundle) -> RouteCatalog? {
        guard let url = bundle.url(forResource: "routes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decode(data)
    }

    /// The shipped catalog, read once.
    static let bundled: RouteCatalog? = RouteCatalogLoader.load(bundle: Bundle.main)
}

enum RouteLegs {
    /// The order of stops MapKit is asked to connect, from the shape:
    /// loop: start, the waypoints, start; outAndBack: start, the waypoints, the waypoints back in reverse
    /// (without repeating the turnaround), start; oneWay and track: start, the waypoints.
    static func stops<T>(start: T, waypoints: [T], shape: RouteShape) -> [T] {
        var result: [T] = [start]
        result.append(contentsOf: waypoints)
        switch shape {
        case .loop:
            result.append(start)
        case .outAndBack:
            let back: [T] = Array(waypoints.reversed().dropFirst())
            result.append(contentsOf: back)
            result.append(start)
        case .oneWay, .track:
            break
        }
        return result
    }
}

/// Where home is. The address is a setting (`SettingsKey.homeAddress`); its coordinate is kept after the
/// first geocode and used for the solar times and the place search region.
enum RouteHome {
    static let fallbackAddress = "17 Monitor St, Brooklyn, NY 11222"
    /// Used until the home address has been geocoded.
    static let fallbackPoint = GeoPoint(lat: 40.73, lon: -73.95)

    /// The address from the shipped catalog.
    static var defaultAddress: String {
        return RouteCatalogLoader.bundled?.home ?? fallbackAddress
    }

    /// The saved home address; the default when nothing (or only spaces) is saved.
    static var address: String {
        let saved = UserDefaults.standard.string(forKey: SettingsKey.homeAddress) ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultAddress : trimmed
    }

    /// The saved home point when it was geocoded from `address`; nil otherwise.
    static func geocodedPoint(for address: String) -> GeoPoint? {
        let defaults = UserDefaults.standard
        guard let geocoded = defaults.string(forKey: SettingsKey.homeGeocodedAddress),
              RouteCachePolicy.sameAddress(geocoded, address),
              let lat = defaults.object(forKey: SettingsKey.homeLatitude) as? Double,
              let lon = defaults.object(forKey: SettingsKey.homeLongitude) as? Double else {
            return nil
        }
        return GeoPoint(lat: lat, lon: lon)
    }

    /// The geocoded home point when it belongs to the current address, else the fallback.
    static var point: GeoPoint {
        return geocodedPoint(for: address) ?? fallbackPoint
    }

    /// Remembers the geocoded point of `address`.
    static func remember(point: GeoPoint, for address: String) {
        let defaults = UserDefaults.standard
        defaults.set(address, forKey: SettingsKey.homeGeocodedAddress)
        defaults.set(point.lat, forKey: SettingsKey.homeLatitude)
        defaults.set(point.lon, forKey: SettingsKey.homeLongitude)
    }
}

/// When a cached curated route has to be resolved again.
enum RouteCachePolicy {
    /// A curated route older than this is resolved again.
    static let maxAgeDays: Double = 90

    /// Case and surrounding spaces do not matter.
    static func sameAddress(_ a: String, _ b: String) -> Bool {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return left == right
    }

    /// True when the home address changed since the route was resolved, or it is older than 90 days.
    static func needsResolve(savedHome: String, currentHome: String, createdAt: Date, now: Date) -> Bool {
        if !sameAddress(savedHome, currentHome) {
            return true
        }
        let age = now.timeIntervalSince(createdAt)
        return age > maxAgeDays * 86_400
    }
}

/// Text for the routes screens.
enum RouteFormat {
    /// "2.4 mi"; for a track route "0.6 mi away" (the distance to the track, not a lap).
    static func distanceText(meters: Double, shape: RouteShape) -> String {
        guard meters.isFinite, meters > 0 else { return "\u{2014}" }
        let text = String(format: "%.1f mi", meters / metersPerMile)
        return shape == .track ? text + " away" : text
    }

    /// The street part of an address: "17 Monitor St, Brooklyn, NY 11222" gives "17 Monitor St".
    static func shortAddress(_ address: String) -> String {
        let first = address.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first
        let text = first.map { String($0) } ?? address
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Minutes, as "est. time" text: "24 min", or "1:05 h" from an hour up.
    static func timeText(meters: Double, secondsPerMile: Double) -> String {
        guard meters.isFinite, meters > 0, secondsPerMile.isFinite, secondsPerMile > 0 else { return "\u{2014}" }
        let minutes = Int((meters / metersPerMile * secondsPerMile / 60).rounded())
        if minutes >= 60 {
            return String(format: "%d:%02d h", minutes / 60, minutes % 60)
        }
        return "\(minutes) min"
    }

    /// "1.2 / 3.1 mi" for the run screen's route readout; "--" before the first position is known.
    static func followText(along: Double?, total: Double) -> String {
        let totalText = String(format: "%.1f", max(0, total) / metersPerMile)
        guard let along = along, along.isFinite else {
            return "-- / " + totalText + " mi"
        }
        let clamped = min(max(0, along), max(0, total))
        return String(format: "%.1f", clamped / metersPerMile) + " / " + totalText + " mi"
    }

    /// The middle of a pace range, in seconds per mile.
    static func middle(of range: ClosedRange<Double>) -> Double {
        return (range.lowerBound + range.upperBound) / 2
    }
}

/// A curated route after MapKit found its stops and walking paths.
struct ResolvedRoute: Equatable {
    let id: String
    let name: String
    let shape: RouteShape
    let points: [GeoPoint]
    /// The stops MapKit connected, start first (`RouteLegs.stops`).
    let stopsResolved: [GeoPoint]
    let resolvedAt: Date
    /// The home address the route was resolved from.
    let homeAddress: String

    var distanceMeters: Double {
        return RouteGeometry.length(of: points)
    }
}

enum RoutePolyline {
    /// Joins walking legs into one path, dropping a point that repeats the one before it (each leg starts
    /// where the last one ended).
    static func join(_ legs: [[GeoPoint]]) -> [GeoPoint] {
        var result: [GeoPoint] = []
        for leg in legs {
            for point in leg {
                if let last = result.last, RouteGeometry.distance(last, point) < 0.5 {
                    continue
                }
                result.append(point)
            }
        }
        return result
    }
}
