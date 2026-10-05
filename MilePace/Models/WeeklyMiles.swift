import Foundation

struct WeekBucket: Identifiable, Equatable {
    let weekStart: Date
    let label: String
    let miles: Double

    var id: Date { weekStart }
}

/// Weekly mileage in one place: the today screen, the log and the Sunday reminder all add up the same
/// per-day miles (`PlanActivities.milesByDay`: runs as recorded, track workouts estimated) over the same
/// calendar Monday-to-Sunday weeks.
enum WeeklyMiles {
    /// Miles over the seven days from `firstDay` (a day offset in the same numbering as the keys).
    static func sum(milesByDay: [Int: Double], firstDay: Int) -> Double {
        var total = 0.0
        for day in firstDay..<(firstDay + 7) {
            total += milesByDay[day] ?? 0
        }
        return total
    }

    /// The Monday on or before `date`, at the start of the day.
    static func monday(onOrBefore date: Date, calendar: Calendar = PlanCalendar.local) -> Date {
        let weekday = PlanCalendar.mondayWeekday(of: date, calendar: calendar)
        let day = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: day) ?? day
    }

    /// Miles per Monday-to-Sunday week for the last `weeks` weeks, oldest first; the last bucket is the
    /// week holding `now`. An activity belongs to the day it started on (before 03:00 counts for the
    /// day before), the same rule the plan uses.
    static func buckets(runs: [LoggedRun],
                        workouts: [LoggedWorkout],
                        weeks: Int = 10,
                        now: Date = Date(),
                        calendar: Calendar = PlanCalendar.local) -> [WeekBucket] {
        guard weeks > 0 else { return [] }
        let thisMonday = monday(onOrBefore: now, calendar: calendar)
        let milesByDay = PlanActivities.milesByDay(runs: runs,
                                                   workouts: workouts,
                                                   start: thisMonday,
                                                   calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M/d"

        var result: [WeekBucket] = []
        for back in stride(from: weeks - 1, through: 0, by: -1) {
            let firstDay = -7 * back
            let start = PlanCalendar.date(forOffset: firstDay, start: thisMonday, calendar: calendar)
            result.append(WeekBucket(weekStart: start,
                                     label: formatter.string(from: start),
                                     miles: sum(milesByDay: milesByDay, firstDay: firstDay)))
        }
        return result
    }
}
