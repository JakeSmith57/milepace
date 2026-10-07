import Foundation
import SwiftData

@Model
final class RunRecord {
    var date: Date
    var distanceMeters: Double
    var durationSeconds: Double
    /// Average pace in seconds per mile; 0 when unknown.
    var averagePace: Double
    /// Mile split durations in seconds. Empty for manually added runs.
    var splits: [Double]
    var notes: String
    /// JSON-encoded `[RoutePoint]`. Empty for runs without a recorded route.
    var routeData: Data = Data()
    /// Average cadence in steps per minute; 0 when unknown.
    var averageCadence: Double = 0
    /// Name of the guided road workout this run was; empty for a free run or a manual entry.
    var workoutName: String = ""
    /// True for a run made during the test week; those are deleted when the test week ends.
    var isTest: Bool = false
    /// True for a run on a treadmill: no route, and the distance was typed in (or the pedometer's guess).
    var isTreadmill: Bool = false
    /// Effort after the run, 1 to 10; 0 when not set.
    var effort: Int = 0
    /// Big toe or foot pain after the run, 0 to 10; -1 when not set.
    var footPain: Int = -1
    /// Id of the route (catalog id or `SavedRoute.id`) the run followed; empty when none.
    var routeId: String = ""

    init(date: Date,
         distanceMeters: Double,
         durationSeconds: Double,
         averagePace: Double,
         splits: [Double] = [],
         notes: String = "",
         route: [RoutePoint] = [],
         averageCadence: Double = 0,
         workoutName: String = "",
         isTest: Bool = false,
         isTreadmill: Bool = false,
         routeId: String = "") {
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averagePace = averagePace
        self.splits = splits
        self.notes = notes
        self.routeData = route.isEmpty ? Data() : ((try? JSONEncoder().encode(route)) ?? Data())
        self.averageCadence = averageCadence
        self.workoutName = workoutName
        self.isTest = isTest
        self.isTreadmill = isTreadmill
        self.routeId = routeId
    }

    var route: [RoutePoint] {
        guard !routeData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([RoutePoint].self, from: routeData)) ?? []
    }
}

@Model
final class WorkoutRecord {
    /// When the workout started.
    var date: Date
    var name: String
    /// JSON-encoded `WorkoutSpec`.
    var specData: Data
    var repTimes: [Double]
    /// JSON-encoded `[[Double]]` (lap splits per rep).
    var lapSplitsData: Data
    /// True for a workout made during the test week; those are deleted when the test week ends.
    var isTest: Bool = false
    /// Effort after the workout, 1 to 10; 0 when not set.
    var effort: Int = 0
    /// Big toe or foot pain after the workout, 0 to 10; -1 when not set.
    var footPain: Int = -1

    init(date: Date,
         name: String,
         spec: WorkoutSpec,
         repTimes: [Double],
         lapSplits: [[Double]],
         isTest: Bool = false) {
        self.date = date
        self.name = name
        self.specData = (try? JSONEncoder().encode(spec)) ?? Data()
        self.repTimes = repTimes
        self.lapSplitsData = (try? JSONEncoder().encode(lapSplits)) ?? Data()
        self.isTest = isTest
    }

    var spec: WorkoutSpec? {
        return try? JSONDecoder().decode(WorkoutSpec.self, from: specData)
    }

    var lapSplits: [[Double]] {
        return (try? JSONDecoder().decode([[Double]].self, from: lapSplitsData)) ?? []
    }
}

/// A route kept on the device so runs never need the network: a curated route after MapKit resolved it
/// (`kind` "curated"), or, from the next part, a generated or learned one.
@Model
final class SavedRoute {
    /// A catalog id for a curated route.
    var id: String = ""
    var name: String = ""
    /// `SavedRouteKind` raw value: "curated", "generated" or "learned".
    var kind: String = "curated"
    /// JSON-encoded `[GeoPoint]`.
    var pointsData: Data = Data()
    var distanceMeters: Double = 0
    var notes: String = ""
    /// The home address the route was resolved from.
    var homeAddress: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date? = nil
    /// JSON-encoded `[GeoPoint]`: the stops MapKit connected (start first). Empty when unknown.
    var stopsData: Data = Data()

    init(id: String,
         name: String,
         kind: SavedRouteKind,
         points: [GeoPoint],
         stops: [GeoPoint] = [],
         distanceMeters: Double,
         notes: String,
         homeAddress: String,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.kind = kind.rawValue
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        self.stopsData = stops.isEmpty ? Data() : ((try? JSONEncoder().encode(stops)) ?? Data())
        self.distanceMeters = distanceMeters
        self.notes = notes
        self.homeAddress = homeAddress
        self.createdAt = createdAt
    }

    var points: [GeoPoint] {
        guard !pointsData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([GeoPoint].self, from: pointsData)) ?? []
    }

    var stops: [GeoPoint] {
        guard !stopsData.isEmpty else { return [] }
        return (try? JSONDecoder().decode([GeoPoint].self, from: stopsData)) ?? []
    }

    /// Replaces the path and the numbers that come from it.
    func update(points: [GeoPoint], stops: [GeoPoint], distanceMeters: Double, homeAddress: String, createdAt: Date) {
        self.pointsData = (try? JSONEncoder().encode(points)) ?? Data()
        self.stopsData = stops.isEmpty ? Data() : ((try? JSONEncoder().encode(stops)) ?? Data())
        self.distanceMeters = distanceMeters
        self.homeAddress = homeAddress
        self.createdAt = createdAt
    }
}

enum SavedRouteKind: String {
    case curated
    case generated
    case learned
}
