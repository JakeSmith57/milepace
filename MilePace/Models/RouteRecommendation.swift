import Foundation

/// Sunrise and sunset from a small NOAA-style solar calculation (accurate to a couple of minutes at city
/// latitudes). Pure, so it can be tested; no network, no CoreLocation.
enum SolarTimes {
    struct Day: Equatable {
        let sunrise: Date
        let sunset: Date
    }

    /// Julian date at 0h UT of a calendar day (Gregorian).
    static func julianDate(year: Int, month: Int, day: Int) -> Double {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        let number = day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        return Double(number) - 0.5
    }

    private static func radians(_ degrees: Double) -> Double {
        return degrees * Double.pi / 180
    }

    private static func degrees(_ radians: Double) -> Double {
        return radians * 180 / Double.pi
    }

    /// Sunrise and sunset on the calendar day of `date` in `timeZone`, at the given point (longitude east
    /// positive). Nil during polar day or night.
    static func times(on date: Date,
                      latitude: Double,
                      longitude: Double,
                      timeZone: TimeZone = TimeZone.current) -> Day? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }

        let midnight = julianDate(year: year, month: month, day: day)
        // Time of the sun's position: about local solar noon of that day.
        let julian = midnight + 0.5 - longitude / 360
        let t: Double = (julian - 2_451_545.0) / 36_525.0

        let rawLongitude: Double = 280.46646 + t * (36_000.76983 + t * 0.0003032)
        let meanLongitude: Double = rawLongitude.truncatingRemainder(dividingBy: 360)
        let meanAnomaly: Double = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity: Double = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let anomaly = radians(meanAnomaly)
        let center1: Double = sin(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
        let center2: Double = sin(2 * anomaly) * (0.019993 - 0.000101 * t)
        let center3: Double = sin(3 * anomaly) * 0.000289
        let trueLongitude = meanLongitude + center1 + center2 + center3
        let omega = 125.04 - 1934.136 * t
        let apparent = trueLongitude - 0.00569 - 0.00478 * sin(radians(omega))

        let seconds: Double = 21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))
        let meanObliquity: Double = 23 + (26 + seconds / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(radians(omega))
        let declination = asin(sin(radians(obliquity)) * sin(radians(apparent)))

        let half = tan(radians(obliquity) / 2)
        let y = half * half
        let l0 = radians(meanLongitude)
        let term1 = y * sin(2 * l0)
        let term2 = 2 * eccentricity * sin(anomaly)
        let term3 = 4 * eccentricity * y * sin(anomaly) * cos(2 * l0)
        let term4 = 0.5 * y * y * sin(4 * l0)
        let term5 = 1.25 * eccentricity * eccentricity * sin(2 * anomaly)
        let equationOfTime = 4 * degrees(term1 - term2 + term3 - term4 - term5)

        let lat = radians(latitude)
        let zenith: Double = cos(radians(90.833)) / (cos(lat) * cos(declination))
        let argument: Double = zenith - tan(lat) * tan(declination)
        guard argument >= -1, argument <= 1 else { return nil }
        let hourAngle = degrees(acos(argument))

        let sunriseMinutes = 720 - 4 * (longitude + hourAngle) - equationOfTime
        let sunsetMinutes = 720 - 4 * (longitude - hourAngle) - equationOfTime
        let midnightUnix = (midnight - 2_440_587.5) * 86_400
        return Day(sunrise: Date(timeIntervalSince1970: midnightUnix + sunriseMinutes * 60),
                   sunset: Date(timeIntervalSince1970: midnightUnix + sunsetMinutes * 60))
    }
}

/// Where today's session should happen: the track for track sessions, the park loop for road workouts, a
/// route of about the planned distance for everything else.
enum RouteRecommendation {
    struct Pick: Equatable {
        /// The catalog route to show and follow; nil when there is no resolved route to point at.
        let routeId: String?
        let label: String
        let note: String?
    }

    static let trackId = "mccarren-track"
    static let roadWorkoutId = "mccarren-loop"
    /// The loops that can be repeated to make up a distance.
    static let lapIds = ["mcgolrick-loop", "mccarren-loop"]
    /// Every catalog id a recommendation can name (a test checks that each exists).
    static let targetIds = [trackId, roadWorkoutId] + lapIds
    /// How far from the planned distance a route may be: 15 %.
    static let tolerance: Double = 0.15
    /// Most laps of a loop that are suggested.
    static let maxLaps = 6

    /// The recommendation for a plan session. `resolved` maps a catalog route id to its resolved distance
    /// in miles (only routes that have a saved path). `sunrise` and `sunset` are today's, for the home
    /// point; either can be nil when unknown.
    static func pick(kind: SessionKind,
                     plannedMiles: Double?,
                     isTimedRoadWorkout: Bool,
                     now: Date,
                     sunrise: Date? = nil,
                     sunset: Date?,
                     resolved: [String: Double],
                     catalog: RouteCatalog) -> Pick? {
        switch kind {
        case .track, .timeTrial, .race:
            return trackPick(now: now, sunrise: sunrise, sunset: sunset, catalog: catalog)
        case .road:
            return roadPick(isTimed: isTimedRoadWorkout, catalog: catalog)
        case .easy, .long, .other:
            return distancePick(kind: kind, plannedMiles: plannedMiles, resolved: resolved, catalog: catalog)
        }
    }

    private static func known(_ id: String, _ catalog: RouteCatalog) -> String? {
        return catalog.route(id: id) == nil ? nil : id
    }

    private static func trackPick(now: Date, sunrise: Date?, sunset: Date?, catalog: RouteCatalog) -> Pick {
        var dark = false
        if let sunset = sunset, now > sunset {
            dark = true
        }
        if let sunrise = sunrise, now < sunrise {
            dark = true
        }
        let name = catalog.name(forId: trackId) ?? "mccarren park track"
        let note = dark ? "the track is open dawn to dusk" : "lane 1 = 400 m"
        return Pick(routeId: known(trackId, catalog), label: name, note: note)
    }

    private static func roadPick(isTimed: Bool, catalog: RouteCatalog) -> Pick {
        let name = catalog.name(forId: roadWorkoutId) ?? "mccarren park loop"
        let note: String? = isTimed ? "timed reps: any safe stretch works" : nil
        return Pick(routeId: known(roadWorkoutId, catalog), label: name, note: note)
    }

    /// One way to cover the planned distance: a route, run `laps` times.
    private struct Option {
        let routeId: String
        let name: String
        let laps: Int
        let miles: Double
    }

    private static func distancePick(kind: SessionKind,
                                     plannedMiles: Double?,
                                     resolved: [String: Double],
                                     catalog: RouteCatalog) -> Pick? {
        guard let planned = plannedMiles, planned.isFinite, planned > 0 else { return nil }
        let wanted = kind == .long ? "long" : "easy"
        var options: [Option] = []
        for route in catalog.routes {
            guard route.shape != .track, let miles = resolved[route.id], miles > 0 else { continue }
            if route.tags.contains(wanted) {
                options.append(Option(routeId: route.id, name: route.name, laps: 1, miles: miles))
            }
            if route.shape == .loop && lapIds.contains(route.id) {
                for laps in 2...maxLaps {
                    options.append(Option(routeId: route.id, name: route.name, laps: laps, miles: miles * Double(laps)))
                }
            }
        }
        var best: Option? = nil
        var bestError = Double.infinity
        for option in options {
            let error = abs(option.miles - planned) / planned
            guard error <= tolerance else { continue }
            if error < bestError - 0.000_001 {
                best = option
                bestError = error
            }
        }
        if let option = best {
            return Pick(routeId: option.routeId, label: label(for: option), note: nil)
        }
        return Pick(routeId: nil, label: "any \(milesText(planned)) mi route", note: nil)
    }

    private static func label(for option: Option) -> String {
        if option.laps <= 1 {
            return option.name
        }
        return "\(option.name) \u{00D7} \(option.laps) (\(String(format: "%.1f", option.miles)) mi)"
    }

    private static func milesText(_ miles: Double) -> String {
        if miles.rounded() == miles {
            return String(Int(miles))
        }
        return String(format: "%.1f", miles)
    }
}
