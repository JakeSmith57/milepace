import Foundation

/// A saved run, reduced to what the plan needs.
struct LoggedRun: Equatable {
    /// When the run started.
    let date: Date
    let meters: Double
    /// Name of the guided road workout; empty for a free run.
    let workoutName: String
}

/// A saved track workout, reduced to what the plan needs.
struct LoggedWorkout: Equatable {
    /// When the workout started.
    let date: Date
    let name: String
    /// Total meters of the reps that were run.
    let repMeters: Double
}

/// One saved activity placed on a plan day.
struct ActivityDay: Equatable {
    enum Kind: Equatable {
        case run(miles: Double, workoutName: String?)
        case track(presetName: String)
    }

    let day: Int
    let kind: Kind
}

/// Turns saved runs and workouts into plan days and weekly miles.
enum PlanActivities {
    /// Warm-up and cool-down added to a track workout's rep distance when estimating its miles.
    static let trackWarmupCooldownMiles: Double = 2.0

    /// "total rep meters / 1609.344 + 2.0".
    static func estimatedTrackMiles(repMeters: Double) -> Double {
        return max(0, repMeters) / metersPerMile + trackWarmupCooldownMiles
    }

    /// Every run and workout as an activity on the plan day it started on. The free runs of one day are
    /// added up into a single activity (an easy session asks for total miles that day); each guided road
    /// workout and each track workout stands alone.
    static func days(runs: [LoggedRun],
                     workouts: [LoggedWorkout],
                     start: Date,
                     calendar: Calendar = PlanCalendar.local) -> [ActivityDay] {
        var freeMiles: [Int: Double] = [:]
        var freeOrder: [Int] = []
        var result: [ActivityDay] = []
        for run in runs {
            let day = PlanCalendar.activityDay(of: run.date, start: start, calendar: calendar)
            let miles = run.meters / metersPerMile
            if run.workoutName.isEmpty {
                if freeMiles[day] == nil {
                    freeOrder.append(day)
                }
                freeMiles[day, default: 0] += miles
            } else {
                result.append(ActivityDay(day: day, kind: .run(miles: miles, workoutName: run.workoutName)))
            }
        }
        for day in freeOrder {
            result.append(ActivityDay(day: day, kind: .run(miles: freeMiles[day] ?? 0, workoutName: nil)))
        }
        for workout in workouts {
            let day = PlanCalendar.activityDay(of: workout.date, start: start, calendar: calendar)
            result.append(ActivityDay(day: day, kind: .track(presetName: workout.name)))
        }
        return result
    }

    /// Miles per plan day: runs as recorded, track workouts estimated.
    static func milesByDay(runs: [LoggedRun],
                           workouts: [LoggedWorkout],
                           start: Date,
                           calendar: Calendar = PlanCalendar.local) -> [Int: Double] {
        var miles: [Int: Double] = [:]
        for run in runs {
            let day = PlanCalendar.activityDay(of: run.date, start: start, calendar: calendar)
            miles[day, default: 0] += run.meters / metersPerMile
        }
        for workout in workouts {
            let day = PlanCalendar.activityDay(of: workout.date, start: start, calendar: calendar)
            miles[day, default: 0] += estimatedTrackMiles(repMeters: workout.repMeters)
        }
        return miles
    }
}
