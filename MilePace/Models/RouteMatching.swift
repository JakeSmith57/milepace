import Foundation

/// What the matcher needs of one saved run, as plain values: nothing from SwiftData crosses threads.
struct RunPathInput: Equatable {
    let id: String
    let date: Date
    let seconds: Double
    let meters: Double
    /// JSON-encoded `[RoutePoint]`, as `RunRecord.routeData`.
    let routeData: Data
}

/// A run's path, decoded.
struct RunPath: Equatable {
    let id: String
    let date: Date
    let seconds: Double
    let meters: Double
    let points: [GeoPoint]
}

/// A route the runner has run at least twice, found from saved GPS runs.
struct YourRoute: Identifiable, Equatable {
    /// The id of the oldest run in the group: stable while that run exists, so a rename sticks.
    let key: String
    let count: Int
    /// The fastest time of the group's runs, 0 when none had a time.
    let bestSeconds: Double
    let lastDate: Date
    /// The distance of the most recent run.
    let meters: Double
    let start: GeoPoint
    /// The path of the most recent run.
    let points: [GeoPoint]
    /// "3.1 mi from home".
    let defaultName: String

    var id: String { key }
}

/// Is this the same route as that one, and which saved runs repeat a route.
enum RouteMatching {
    /// Starts must be this close, in meters.
    static let startRadius: Double = 200
    /// Paths are compared at points this far apart, in meters.
    static let sampleSpacing: Double = 50
    /// A point is on the other path when it is within this many meters of it.
    static let corridor: Double = 30
    /// Share of each path's points that must be on the other path.
    static let share: Double = 0.8
    /// Runs in a group to list it.
    static let minimumRuns = 2
    /// Shorter paths are not routes.
    static let minimumMeters: Double = 400
    /// A start this close to home is called "home", in meters.
    static let homeRadius: Double = 300

    /// Share of `samples` that lie within `meters` of `polyline`; 0 for no samples.
    static func coverage(of samples: [GeoPoint], on polyline: [GeoPoint], within meters: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        var near = 0
        for sample in samples {
            if let spot = RouteGeometry.project(sample, onto: polyline), spot.offsetMeters <= meters {
                near += 1
            }
        }
        return Double(near) / Double(samples.count)
    }

    /// The same route: starts within 200 m, and at least 80 % of the points of each path (every 50 m) within
    /// 30 m of the other.
    static func isSameRoute(_ a: [GeoPoint], _ b: [GeoPoint]) -> Bool {
        guard let startA = a.first, let startB = b.first, a.count >= 2, b.count >= 2 else { return false }
        guard RouteGeometry.distance(startA, startB) <= startRadius else { return false }
        return matches(RouteGeometry.resample(a, every: sampleSpacing), RouteGeometry.resample(b, every: sampleSpacing))
    }

    /// The point test of `isSameRoute`, for paths already resampled.
    private static func matches(_ a: [GeoPoint], _ b: [GeoPoint]) -> Bool {
        return coverage(of: a, on: b, within: corridor) >= share && coverage(of: b, on: a, within: corridor) >= share
    }

    /// A run's path from its saved route; nil when it does not decode or is too short to be a route.
    static func decode(_ input: RunPathInput) -> RunPath? {
        guard !input.routeData.isEmpty,
              let route = try? JSONDecoder().decode([RoutePoint].self, from: input.routeData),
              route.count >= 2 else {
            return nil
        }
        let points = route.map { point in
            GeoPoint(lat: point.lat, lon: point.lon)
        }
        guard RouteGeometry.length(of: points) >= minimumMeters else { return nil }
        return RunPath(id: input.id, date: input.date, seconds: input.seconds, meters: input.meters, points: points)
    }

    /// Decodes the runs and groups them. Plain values in and out, so it can run on any thread.
    static func groups(from inputs: [RunPathInput], home: GeoPoint) -> [YourRoute] {
        let paths = inputs.compactMap { decode($0) }
        return groups(paths: paths, home: home)
    }

    private struct Cluster {
        var sample: [GeoPoint]
        var start: GeoPoint
        var members: [RunPath]
    }

    /// Runs that repeat a route, newest route first. Each run is compared with the first run of every group
    /// so far (oldest runs first) and joins the first group it matches, or starts a new one. Groups of fewer
    /// than two runs are left out.
    static func groups(paths: [RunPath], home: GeoPoint) -> [YourRoute] {
        let ordered = paths.sorted { $0.date < $1.date }
        var found: [Cluster] = []
        for path in ordered {
            guard let start = path.points.first else { continue }
            let sample = RouteGeometry.resample(path.points, every: sampleSpacing)
            var joined = false
            for index in found.indices {
                guard RouteGeometry.distance(start, found[index].start) <= startRadius else { continue }
                if matches(sample, found[index].sample) {
                    found[index].members.append(path)
                    joined = true
                    break
                }
            }
            if !joined {
                found.append(Cluster(sample: sample, start: start, members: [path]))
            }
        }
        var result: [YourRoute] = []
        for group in found where group.members.count >= minimumRuns {
            if let route = summary(of: group.members, home: home) {
                result.append(route)
            }
        }
        result.sort { $0.lastDate > $1.lastDate }
        return result
    }

    /// `members` are oldest first.
    private static func summary(of members: [RunPath], home: GeoPoint) -> YourRoute? {
        guard let oldest = members.first, let latest = members.last, let start = latest.points.first else { return nil }
        var best = 0.0
        for member in members where member.seconds > 0 {
            best = best == 0 ? member.seconds : min(best, member.seconds)
        }
        return YourRoute(key: oldest.id,
                         count: members.count,
                         bestSeconds: best,
                         lastDate: latest.date,
                         meters: latest.meters,
                         start: start,
                         points: latest.points,
                         defaultName: defaultName(meters: latest.meters, start: start, home: home))
    }

    /// "3.1 mi from home", or "3.1 mi from 40.730, -73.950" when the start is not near home.
    static func defaultName(meters: Double, start: GeoPoint, home: GeoPoint) -> String {
        let distance = String(format: "%.1f", meters / metersPerMile) + " mi from "
        if RouteGeometry.distance(start, home) <= homeRadius {
            return distance + "home"
        }
        return distance + String(format: "%.3f, %.3f", start.lat, start.lon)
    }
}

/// The names the runner gave to routes found from runs, by `YourRoute.key`.
enum RouteNameStore {
    static let defaultsKey = "yourRouteNames"

    static func names() -> [String: String] {
        return (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
    }

    static func name(for key: String) -> String? {
        return names()[key]
    }

    /// An empty (or only spaces) name goes back to the default.
    static func set(_ name: String, for key: String) {
        var all = names()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            all.removeValue(forKey: key)
        } else {
            all[key] = trimmed
        }
        UserDefaults.standard.set(all, forKey: defaultsKey)
    }
}
