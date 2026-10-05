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

    init(date: Date,
         distanceMeters: Double,
         durationSeconds: Double,
         averagePace: Double,
         splits: [Double] = [],
         notes: String = "",
         route: [RoutePoint] = [],
         averageCadence: Double = 0,
         workoutName: String = "") {
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averagePace = averagePace
        self.splits = splits
        self.notes = notes
        self.routeData = route.isEmpty ? Data() : ((try? JSONEncoder().encode(route)) ?? Data())
        self.averageCadence = averageCadence
        self.workoutName = workoutName
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

    init(date: Date,
         name: String,
         spec: WorkoutSpec,
         repTimes: [Double],
         lapSplits: [[Double]]) {
        self.date = date
        self.name = name
        self.specData = (try? JSONEncoder().encode(spec)) ?? Data()
        self.repTimes = repTimes
        self.lapSplitsData = (try? JSONEncoder().encode(lapSplits)) ?? Data()
    }

    var spec: WorkoutSpec? {
        return try? JSONDecoder().decode(WorkoutSpec.self, from: specData)
    }

    var lapSplits: [[Double]] {
        return (try? JSONDecoder().decode([[Double]].self, from: lapSplitsData)) ?? []
    }
}
