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
         isTreadmill: Bool = false) {
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
