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

    init(date: Date,
         distanceMeters: Double,
         durationSeconds: Double,
         averagePace: Double,
         splits: [Double] = [],
         notes: String = "") {
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.averagePace = averagePace
        self.splits = splits
        self.notes = notes
    }
}

@Model
final class WorkoutRecord {
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
