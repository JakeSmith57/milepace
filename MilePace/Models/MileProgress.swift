import Foundation

/// One mile result on the progress chart.
struct MileResult: Equatable {
    enum Source: Equatable {
        case trackTimeTrial
        case race
        case gpsBest
    }

    let date: Date
    let seconds: Double
    let source: Source
}

/// The fastest time for one distance and the day it was run.
struct DistanceBest: Equatable {
    /// Meters: 400, 800, 1609, 3218 or 5000.
    let distance: Double
    let seconds: Double
    let date: Date
}

/// A planned time trial or race: its target at the day it is scheduled.
struct PlanMilePoint: Equatable {
    let date: Date
    let seconds: Double
}

/// A saved track workout, reduced to what the mile progress needs. Plain values, no SwiftData.
struct MileTrackInput: Equatable {
    let date: Date
    let repDistance: Int
    let totalReps: Int
    let repTimes: [Double]
    /// Held on the plan's race day, so its mile is a race and not a time trial.
    var isRace: Bool = false
    var isTest: Bool = false
}

/// Everything the mile chart, the bests list and the readout line need, worked out once.
struct MileSnapshot: Equatable {
    /// Track time trials and races, oldest first.
    let results: [MileResult]
    /// GPS miles from runs that passed the noise rule, oldest first.
    let gpsPoints: [MileResult]
    /// Plan time trials and races with a target, oldest first.
    let plan: [PlanMilePoint]
    /// 400 m, 800 m, 1 mi, 2 mi, 5 km: only the distances that have a time.
    let bests: [DistanceBest]
    let goal: Double
    /// The most recent track mile, else the mile time setting.
    let latest: Double
    let latestDate: Date?
    /// Seconds still to go to the goal; 0 when the goal is reached.
    let toGo: Double
    /// Best-to-worst seconds the chart's y axis spans (goal minus 10 s up to the slower of 7:10 and the slowest point plus 10 s).
    let yDomain: ClosedRange<Double>
}

enum MileProgress {
    static let mileMeters: Double = 1609
    /// The distances the bests list shows.
    static let bestDistances: [Double] = [400, 800, 1609, 3218, 5000]
    /// A run's GPS mile is chart-worthy only when it is this close to (or faster than) the latest mile.
    static let gpsNoiseSeconds: Double = 15
    /// Faster than this speed (m/s) is GPS noise, not a time: a 400 m in 40 s.
    static let maxPlausibleSpeed: Double = 10
    /// Slowest mile the y axis shows without a slower point: 7:10.
    static let slowestAxisSeconds: Double = 430

    // MARK: GPS routes

    /// Fastest continuous 1609 m inside a run's route, or nil when the route covers less.
    static func fastestMile(route: [RoutePoint]) -> Double? {
        return fastest(distance: mileMeters, route: route)
    }

    /// Fastest continuous `distance` meters inside a route. `t` is moving time (pauses are already left out)
    /// and `d` is cumulative distance, so a sliding window over the points works. The time at an exact distance
    /// is interpolated between the two points around it. Because the time is piecewise linear in distance, the
    /// fastest window has its start or its end on a point; both are tried. Nil when the route covers less than
    /// `distance`, or when only impossible speeds come out.
    static func fastest(distance: Double, route: [RoutePoint]) -> Double? {
        guard distance > 0, route.count >= 2, let first = route.first, let last = route.last else { return nil }
        guard last.d - first.d >= distance else { return nil }
        var best: Double? = nil
        func consider(_ seconds: Double) {
            guard seconds.isFinite, seconds > 0, distance / seconds <= maxPlausibleSpeed else { return }
            if let current = best, current <= seconds { return }
            best = seconds
        }

        // Windows that end on a point.
        var low = 0
        for end in 1..<route.count {
            let startDistance = route[end].d - distance
            if startDistance < first.d { continue }
            while low + 1 < end && route[low + 1].d <= startDistance {
                low += 1
            }
            let a = route[low]
            let b = route[low + 1]
            consider(route[end].t - interpolatedTime(a, b, atDistance: startDistance))
        }

        // Windows that start on a point.
        var high = 1
        for start in 0..<(route.count - 1) {
            let endDistance = route[start].d + distance
            if endDistance > last.d { break }
            if high <= start { high = start + 1 }
            while high < route.count - 1 && route[high].d < endDistance {
                high += 1
            }
            let a = route[high - 1]
            let b = route[high]
            consider(interpolatedTime(a, b, atDistance: endDistance) - route[start].t)
        }
        return best
    }

    /// The moving time at cumulative distance `distance`, between points `a` and `b`.
    private static func interpolatedTime(_ a: RoutePoint, _ b: RoutePoint, atDistance distance: Double) -> Double {
        let span = b.d - a.d
        guard span > 0 else { return a.t }
        let fraction = min(1, max(0, (distance - a.d) / span))
        return a.t + (b.t - a.t) * fraction
    }

    /// The fastest time for each of the bests distances that the route covers, all stamped with `date`.
    static func gpsBests(date: Date, route: [RoutePoint]) -> [DistanceBest] {
        var result: [DistanceBest] = []
        for distance in bestDistances {
            if let seconds = fastest(distance: distance, route: route) {
                result.append(DistanceBest(distance: distance, seconds: seconds, date: date))
            }
        }
        return result
    }

    // MARK: Track workouts

    /// The rep time of a workout that is a single 1609 m rep (the mile time trial, or any one-rep mile), else nil.
    static func trackMile(repDistance: Int, totalReps: Int, repTimes: [Double]) -> Double? {
        guard repDistance == Int(mileMeters), totalReps == 1, repTimes.count == 1 else { return nil }
        let time = repTimes[0]
        return time.isFinite && time > 0 ? time : nil
    }

    /// The fastest rep of a track workout, as a best for its rep distance, when that is one of 400, 800 or 1609 m.
    static func trackBests(date: Date, repDistance: Int, repTimes: [Double]) -> [DistanceBest] {
        let distance = Double(repDistance)
        guard [400.0, 800.0, mileMeters].contains(distance) else { return [] }
        let valid = repTimes.filter { $0.isFinite && $0 > 0 }
        guard let fastestRep = valid.min() else { return [] }
        return [DistanceBest(distance: distance, seconds: fastestRep, date: date)]
    }

    // MARK: Merging

    /// The fastest candidate per distance (the earlier date wins a tie), for the distances in `bestDistances`
    /// that have one, in distance order.
    static func bests(_ candidates: [DistanceBest]) -> [DistanceBest] {
        var result: [DistanceBest] = []
        for distance in bestDistances {
            let mine = candidates.filter { $0.distance == distance }
            var winner: DistanceBest? = nil
            for item in mine {
                guard let current = winner else {
                    winner = item
                    continue
                }
                if item.seconds < current.seconds || (item.seconds == current.seconds && item.date < current.date) {
                    winner = item
                }
            }
            if let found = winner {
                result.append(found)
            }
        }
        return result
    }

    // MARK: Noise rule and new bests

    /// A run's GPS mile is shown on the chart only when it is faster than the reference mile or within
    /// `gpsNoiseSeconds` of it; slower ones are easy-run noise. The reference is the latest track mile,
    /// else the mile time setting.
    static func isChartWorthy(gpsMile seconds: Double, reference: Double) -> Bool {
        return seconds <= reference + gpsNoiseSeconds
    }

    /// The mile of a just-finished run when it is a new best: faster than every earlier best and faster than
    /// the mile time setting. Nil otherwise.
    static func newBestMile(current: Double?, previousBest: Double?, mileTime: Double) -> Double? {
        guard let time = current, time.isFinite, time > 0 else { return nil }
        if let previous = previousBest, time >= previous { return nil }
        return time < mileTime ? time : nil
    }

    // MARK: Chart axis

    /// The y-axis span in seconds: from the goal minus 10 s up to the slower of 7:10 and the slowest point plus 10 s.
    static func yDomain(goal: Double, points: [Double]) -> ClosedRange<Double> {
        let lower = goal - 10
        let slowest = points.filter { $0.isFinite }.max() ?? 0
        let upper = max(slowestAxisSeconds, slowest + 10)
        return lower...max(upper, lower + 1)
    }

    // MARK: Snapshot

    /// Works out the chart, bests and readout from plain inputs. Test records are left out of `tracks`;
    /// the caller leaves test runs out of `gps`.
    static func snapshot(tracks: [MileTrackInput],
                         gps: [DistanceBest],
                         plan: [PlanMilePoint],
                         goal: Double,
                         mileTime: Double) -> MileSnapshot {
        let liveTracks = tracks.filter { !$0.isTest }

        var results: [MileResult] = []
        for track in liveTracks {
            if let time = trackMile(repDistance: track.repDistance, totalReps: track.totalReps, repTimes: track.repTimes) {
                results.append(MileResult(date: track.date,
                                          seconds: time,
                                          source: track.isRace ? .race : .trackTimeTrial))
            }
        }
        results.sort { $0.date < $1.date }

        let latestResult = results.last
        let reference = latestResult?.seconds ?? mileTime
        var gpsPoints: [MileResult] = []
        for item in gps where item.distance == mileMeters && isChartWorthy(gpsMile: item.seconds, reference: reference) {
            gpsPoints.append(MileResult(date: item.date, seconds: item.seconds, source: .gpsBest))
        }
        gpsPoints.sort { $0.date < $1.date }

        var candidates = gps
        for track in liveTracks {
            candidates.append(contentsOf: trackBests(date: track.date, repDistance: track.repDistance, repTimes: track.repTimes))
        }

        let sortedPlan = plan.sorted { $0.date < $1.date }
        var spanned: [Double] = sortedPlan.map { $0.seconds }
        spanned.append(contentsOf: results.map { $0.seconds })
        spanned.append(contentsOf: gpsPoints.map { $0.seconds })

        let latest = latestResult?.seconds ?? mileTime
        return MileSnapshot(results: results,
                            gpsPoints: gpsPoints,
                            plan: sortedPlan,
                            bests: bests(candidates),
                            goal: goal,
                            latest: latest,
                            latestDate: latestResult?.date,
                            toGo: max(0, latest - goal),
                            yDomain: yDomain(goal: goal, points: spanned))
    }

    /// "latest mile 6:52 \u{00B7} goal 5:30 \u{00B7} 1:22 to go", or "goal reached" when the latest is at the goal.
    static func summaryLine(latest: Double, goal: Double) -> String {
        var text = "latest mile " + formatDuration(latest) + " \u{00B7} goal " + formatDuration(goal)
        if latest > goal {
            text += " \u{00B7} " + formatDuration(latest - goal) + " to go"
        } else {
            text += " \u{00B7} goal reached"
        }
        return text
    }

    /// "400 m", "800 m", "1 mi", "2 mi", "5 km".
    static func distanceLabel(_ distance: Double) -> String {
        switch distance {
        case 400: return "400 m"
        case 800: return "800 m"
        case 1609: return "1 mi"
        case 3218: return "2 mi"
        case 5000: return "5 km"
        default: return String(format: "%.0f m", distance)
        }
    }

    /// A time for the bests list: tenths up to 800 m (track reps are timed to a tenth), whole seconds beyond.
    static func timeText(_ seconds: Double, distance: Double) -> String {
        return distance <= 800 ? formatSplit(seconds) : formatDuration(seconds)
    }
}
