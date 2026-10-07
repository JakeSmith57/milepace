import Foundation

// MARK: - Input

/// A saved run, reduced to what the export lists. Plain values, so the builder needs no SwiftData.
struct ExportRun: Equatable {
    let date: Date
    let distanceMeters: Double
    let durationSeconds: Double
    /// Seconds per mile; 0 when unknown.
    let averagePace: Double
    let splits: [Double]
    /// Steps per minute; 0 when unknown.
    let averageCadence: Double
    /// Empty for a free run or a manual entry.
    let workoutName: String
    let notes: String
    let hasRoute: Bool
    /// Made during the test week. The builder leaves these out.
    var isTest: Bool = false
    /// Made on a treadmill: the distance was typed in, and the splits column says "treadmill".
    var isTreadmill: Bool = false
    /// Effort 1 to 10 after the run; 0 when not set.
    var effort: Int = 0
    /// Foot pain 0 to 10 after the run; -1 when not set.
    var footPain: Int = -1
}

/// A saved track workout, reduced to what the export lists.
struct ExportWorkout: Equatable {
    let date: Date
    let name: String
    let spec: WorkoutSpec?
    let repTimes: [Double]
    let lapSplits: [[Double]]
    /// Made during the test week. The builder leaves these out.
    var isTest: Bool = false
    /// Effort 1 to 10 after the workout; 0 when not set.
    var effort: Int = 0
    /// Foot pain 0 to 10 after the workout; -1 when not set.
    var footPain: Int = -1
}

struct ExportSettings: Equatable {
    let mileTime: Double
    let goalMile: Double
    let paceWindow: Double
    let metronomeBPM: Int
    let metronomeEnabled: Bool
    let voiceEnabled: Bool
    let cueInterval: String
}

struct ExportInput {
    let generatedAt: Date
    let appVersion: String
    let plan: PlanFile?
    let startYMD: String
    let progress: PlanProgress
    let schedule: PlanSchedule?
    /// Days from the plan start to today.
    let todayOffset: Int
    let settings: ExportSettings
    let zones: PaceZones
    let runs: [ExportRun]
    let workouts: [ExportWorkout]
    /// The test week is on: `plan`, `progress` and `todayOffset` are the real ones and test data is left out.
    var testWeekActive: Bool = false
    /// The fastest time per distance from each outdoor run's route (test runs left out by the caller).
    var gpsBests: [DistanceBest] = []
}

// MARK: - Builder

/// Everything the app knows about the runner's training as one markdown file, written for a coach (a
/// person or an AI) to read. Pure: no SwiftData, no SwiftUI, no clock.
enum ProgressExport {
    /// "milepace-progress-2026-10-06.md".
    static func fileName(for date: Date, calendar: Calendar = PlanCalendar.local) -> String {
        return "milepace-progress-" + PlanCalendar.ymd(date, calendar: calendar) + ".md"
    }

    static func markdown(_ input: ExportInput, calendar: Calendar = PlanCalendar.local) -> String {
        let context = ExportContext(input: input, calendar: calendar)
        var lines: [String] = []
        lines.append(contentsOf: headerLines(context))
        lines.append(contentsOf: settingsLines(context))
        lines.append(contentsOf: sessionLines(context))
        lines.append(contentsOf: weeklyLines(context))
        lines.append(contentsOf: runLines(context))
        lines.append(contentsOf: workoutLines(context))
        lines.append(contentsOf: trialLines(context))
        lines.append(contentsOf: mileProgressLines(context))
        lines.append(contentsOf: footLines(context))
        lines.append(contentsOf: totalsLines(context))
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Text helpers

    /// A table cell: no pipes or line breaks.
    static func cell(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return flat.isEmpty ? "\u{2014}" : flat
    }

    private static func row(_ cells: [String]) -> String {
        return "| " + cells.map { cell($0) }.joined(separator: " | ") + " |"
    }

    private static func tableHead(_ names: [String]) -> [String] {
        let rule = names.map { _ in "---" }
        return [row(names), "| " + rule.joined(separator: " | ") + " |"]
    }

    private static func miles(_ meters: Double) -> String {
        return formatMiles(meters)
    }

    private static func oneDecimal(_ value: Double) -> String {
        return String(format: "%.1f", value)
    }

    // MARK: 1. Header

    private static func headerLines(_ context: ExportContext) -> [String] {
        let input = context.input
        var lines: [String] = ["# MilePace progress export", ""]
        lines.append("- generated: " + context.stampText(input.generatedAt))
        lines.append("- app version: " + input.appVersion)
        if let plan = input.plan {
            lines.append("- plan: \(plan.name) (version \(plan.version))")
            lines.append("- plan start: " + context.dayText(context.start))
            lines.append("- race date: " + (plan.raceDate ?? "none"))
        } else {
            lines.append("- plan: none loaded")
        }
        lines.append("- today: " + context.todayText)
        if input.testWeekActive {
            lines.append("- test week active (test data excluded)")
        }
        return lines
    }

    // MARK: 2. Settings

    private static func settingsLines(_ context: ExportContext) -> [String] {
        let settings = context.input.settings
        let zones = context.input.zones
        var lines: [String] = ["", "## Settings", ""]
        lines.append("- current mile: " + formatDuration(settings.mileTime))
        lines.append("- goal mile: " + formatDuration(settings.goalMile))
        lines.append("- easy zone: " + ReadoutFormat.paceRange(zones.easy) + " /mi")
        lines.append("- threshold zone: " + ReadoutFormat.paceRange(zones.threshold) + " /mi")
        lines.append("- interval zone: " + ReadoutFormat.paceRange(zones.interval) + " /mi")
        lines.append("- repetition zone: " + repRangeText(zones.rep400))
        lines.append("- pace window: \u{00B1}\(Int(settings.paceWindow.rounded())) s/mi")
        lines.append("- metronome: \(settings.metronomeBPM) spm, " + onOff(settings.metronomeEnabled))
        lines.append("- voice: " + onOff(settings.voiceEnabled))
        lines.append("- pace cue interval: " + settings.cueInterval)
        return lines
    }

    private static func repRangeText(_ range: ClosedRange<Double>) -> String {
        return formatSplit(range.lowerBound) + "\u{2013}" + formatSplit(range.upperBound) + " per 400 m"
    }

    private static func onOff(_ value: Bool) -> String {
        return value ? "on" : "off"
    }

    // MARK: 3. Sessions

    private static func sessionLines(_ context: ExportContext) -> [String] {
        var lines: [String] = ["", "## Sessions", ""]
        guard let schedule = context.schedule else {
            lines.append("no plan loaded.")
            return lines
        }
        let limitWeek = context.currentWeek + 1
        let shown = schedule.plan.sessions.indices
            .filter { schedule.plan.sessions[$0].week <= limitWeek }
            .sorted { left, right in
                let a = schedule.dayOffset(left)
                let b = schedule.dayOffset(right)
                return a != b ? a < b : left < right
            }
        lines.append("Week 1 through week \(limitWeek) (the week after today's). The date is the day the session is on now, after any moves.")
        lines.append("")
        lines.append(contentsOf: tableHead(["date", "week", "kind", "title", "miles", "target", "status"]))
        for index in shown {
            lines.append(sessionRow(index, schedule: schedule, context: context))
        }
        lines.append(contentsOf: moveLines(schedule: schedule, context: context))
        return lines
    }

    private static func sessionRow(_ index: Int, schedule: PlanSchedule, context: ExportContext) -> String {
        let session = schedule.plan.sessions[index]
        let day = schedule.dayOffset(index)
        let target = session.targetSeconds.map { formatDuration($0) } ?? ""
        return row([context.dayText(offset: day),
                    String(session.week),
                    session.kind.rawValue,
                    session.title,
                    PlanFormat.miles(session.miles),
                    target,
                    statusText(index, day: day, schedule: schedule, today: context.input.todayOffset)])
    }

    /// `done`, `done (auto)`, `skipped`, `missed`, `today` or `planned`.
    static func statusText(_ index: Int, day: Int, schedule: PlanSchedule, today: Int) -> String {
        let key = PlanProgress.key(index)
        switch schedule.status(index) {
        case .some(.done):
            return schedule.progress.autoDone.contains(key) ? "done (auto)" : "done"
        case .some(.skipped):
            return "skipped"
        case .none:
            if day < today { return "missed" }
            if day == today { return "today" }
            return "planned"
        }
    }

    private static func moveLines(schedule: PlanSchedule, context: ExportContext) -> [String] {
        var lines: [String] = []
        let sessions = schedule.plan.sessions
        for shift in schedule.progress.shifts {
            let title = sessions.indices.contains(shift.fromIndex) ? sessions[shift.fromIndex].title : "session \(shift.fromIndex + 1)"
            lines.append("- moved session \(title) by \(PlanFormat.daysText(shift.days))")
        }
        let overrides = schedule.progress.dayOverrides.compactMap { entry -> (Int, Int)? in
            guard let index = Int(entry.key), sessions.indices.contains(index) else { return nil }
            return (index, entry.value)
        }.sorted { $0.0 < $1.0 }
        for (index, day) in overrides {
            let session = sessions[index]
            let was = context.dayText(offset: schedule.baseOffset(index))
            lines.append("- day override: \(session.title) (week \(session.week)) is on \(context.dayText(offset: day)), planned \(was)")
        }
        if lines.isEmpty {
            return []
        }
        return [""] + lines
    }

    // MARK: 4. Weekly mileage

    private static func weeklyLines(_ context: ExportContext) -> [String] {
        var lines: [String] = ["", "## Weekly mileage", ""]
        guard let schedule = context.schedule else {
            lines.append("no plan loaded.")
            return lines
        }
        let weeks = schedule.plan.weeks.filter { $0.week >= 1 && $0.week <= context.currentWeek }.sorted { $0.week < $1.week }
        guard !weeks.isEmpty else {
            lines.append("none yet.")
            return lines
        }
        let milesByDay = context.milesByDay
        lines.append("Actual miles are runs as recorded plus track workouts estimated (rep distance plus a 2 mi warm-up and cool-down), over the Monday-to-Sunday week.")
        lines.append("")
        lines.append(contentsOf: tableHead(["week", "phase", "planned mi", "actual mi", "sessions done"]))
        for week in weeks {
            let monday = schedule.startOffset(ofWeek: week.week)
            let actual = WeeklyMiles.sum(milesByDay: milesByDay, firstDay: monday)
            let mine = schedule.plan.sessions.indices.filter { schedule.plan.sessions[$0].week == week.week }
            let done = mine.filter { schedule.status($0) == SessionStatus.done }.count
            lines.append(row([String(week.week),
                              String(week.phase),
                              oneDecimal(week.miles),
                              oneDecimal(actual),
                              "\(done)/\(mine.count)"]))
        }
        return lines
    }

    // MARK: 5. Runs

    private static func runLines(_ context: ExportContext) -> [String] {
        var lines: [String] = ["", "## Runs", ""]
        guard !context.runs.isEmpty else {
            lines.append("none yet.")
            return lines
        }
        // The "feel" column (effort and foot pain) only appears once any run has one.
        let showFeel = context.runs.contains { FeelText.exportText(effort: $0.effort, footPain: $0.footPain) != nil }
        var names = ["date", "miles", "time", "avg /mi", "cadence", "workout", "mile splits"]
        if showFeel {
            names.append("feel")
        }
        names.append("notes")
        lines.append(contentsOf: tableHead(names))
        for run in context.runs {
            lines.append(runRow(run, context: context, showFeel: showFeel))
        }
        return lines
    }

    private static func runRow(_ run: ExportRun, context: ExportContext, showFeel: Bool) -> String {
        let time = run.durationSeconds > 0 ? formatDuration(run.durationSeconds) : ""
        let cadence = run.averageCadence > 0 ? "\(Int(run.averageCadence.rounded())) spm" : ""
        let workout = run.workoutName.isEmpty ? "free" : run.workoutName
        var cells = [context.dayText(run.date),
                     miles(run.distanceMeters),
                     time,
                     formatPace(secondsPerMile: run.averagePace),
                     cadence,
                     workout,
                     splitsText(run)]
        if showFeel {
            cells.append(FeelText.exportText(effort: run.effort, footPain: run.footPain) ?? "")
        }
        cells.append(run.notes)
        return row(cells)
    }

    private static func splitsText(_ run: ExportRun) -> String {
        if run.isTreadmill {
            return "treadmill"
        }
        if run.splits.isEmpty {
            return run.hasRoute ? "" : "manual"
        }
        return run.splits.map { formatDuration($0) }.joined(separator: ", ")
    }

    // MARK: 6. Track workouts

    private static func workoutLines(_ context: ExportContext) -> [String] {
        var lines: [String] = ["", "## Track workouts"]
        guard !context.workouts.isEmpty else {
            lines.append("")
            lines.append("none yet.")
            return lines
        }
        for workout in context.workouts {
            lines.append("")
            lines.append(contentsOf: workoutBlock(workout, context: context))
        }
        return lines
    }

    private static func workoutBlock(_ workout: ExportWorkout, context: ExportContext) -> [String] {
        var lines: [String] = ["### " + context.dayText(workout.date) + " " + workout.name]
        guard let spec = workout.spec else {
            lines.append("- spec unavailable")
            if let feel = FeelText.exportText(effort: workout.effort, footPain: workout.footPain) {
                lines.append("- feel: " + feel)
            }
            lines.append("- reps: " + (workout.repTimes.isEmpty ? "none" : workout.repTimes.map { formatSplit($0) }.joined(separator: ", ")))
            return lines
        }
        lines.append("- workout: " + specText(spec))
        if let feel = FeelText.exportText(effort: workout.effort, footPain: workout.footPain) {
            lines.append("- feel: " + feel)
        }
        guard !workout.repTimes.isEmpty else {
            lines.append("- reps: none completed")
            return lines
        }
        let reps = workout.repTimes.map { repText($0, target: spec.targetRepSeconds) }
        lines.append("- reps: " + reps.joined(separator: ", "))
        let average = workout.repTimes.reduce(0, +) / Double(workout.repTimes.count)
        lines.append("- average rep: \(formatSplit(average)) vs target \(formatSplit(spec.targetRepSeconds)) (\(ReadoutFormat.signedDelta(average - spec.targetRepSeconds)))")
        for (index, laps) in workout.lapSplits.enumerated() where laps.count > 1 {
            lines.append("- laps, rep \(index + 1): " + laps.map { formatSplit($0) }.joined(separator: ", "))
        }
        return lines
    }

    /// "6 \u{00D7} 400 m @ 1:28.0, rest 90 s"; with sets, "3 sets of 4 \u{00D7} 400 m @ 1:28.0, rest 90 s, set rest 180 s".
    static func specText(_ spec: WorkoutSpec) -> String {
        let reps = "\(spec.reps) \u{00D7} \(spec.repDistance) m @ \(formatSplit(spec.targetRepSeconds)), rest \(spec.restSeconds) s"
        guard spec.sets > 1 else { return reps }
        return "\(spec.sets) sets of " + reps + ", set rest \(spec.setRestSeconds) s"
    }

    /// "1:27.0 (\u{2212}1.0)".
    static func repText(_ time: Double, target: Double) -> String {
        return "\(formatSplit(time)) (\(ReadoutFormat.signedDelta(time - target)))"
    }

    // MARK: 7. Time trials and races

    private static func trialLines(_ context: ExportContext) -> [String] {
        var lines: [String] = ["", "## Time trials and races", ""]
        var found: [String] = []
        if let schedule = context.schedule {
            for index in schedule.plan.sessions.indices {
                let session = schedule.plan.sessions[index]
                guard session.kind == .timeTrial || session.kind == .race,
                      schedule.status(index) == SessionStatus.done else { continue }
                found.append(trialLine(index, schedule: schedule, context: context))
            }
        }
        if found.isEmpty {
            lines.append("none yet.")
        } else {
            lines.append(contentsOf: found)
        }
        return lines
    }

    private static func trialLine(_ index: Int, schedule: PlanSchedule, context: ExportContext) -> String {
        let session = schedule.plan.sessions[index]
        let day = schedule.dayOffset(index)
        let label = "- " + context.dayText(offset: day) + " week \(session.week) " + session.kind.rawValue + " (" + session.title + "): "
        guard let result = context.trialResult(onDay: day) else {
            return label + "done, no matching workout or run saved"
        }
        var text = label + result.text
        if let target = session.targetSeconds {
            text += " vs target \(formatDuration(target)) (\(ReadoutFormat.signedDelta(result.seconds - target)))"
        } else {
            text += ", no target set"
        }
        return text
    }

    // MARK: 8. Mile progress

    private static func mileProgressLines(_ context: ExportContext) -> [String] {
        let snapshot = context.mileSnapshot
        var lines: [String] = ["", "## Mile progress", ""]
        if let latestDate = snapshot.latestDate {
            lines.append("- latest mile: \(formatDuration(snapshot.latest)) (track, " + context.dayText(latestDate) + ")")
        } else {
            lines.append("- latest mile: \(formatDuration(snapshot.latest)) (the mile time setting; no track mile yet)")
        }
        lines.append("- goal mile: " + formatDuration(snapshot.goal))
        if snapshot.latest > snapshot.goal {
            lines.append("- to go: " + formatDuration(snapshot.toGo))
        } else {
            lines.append("- goal reached")
        }
        lines.append("")
        lines.append("Bests (track reps count at their exact distance; the rest come from GPS routes):")
        lines.append("")
        lines.append(contentsOf: tableHead(["distance", "best", "date"]))
        for distance in MileProgress.bestDistances {
            if let best = snapshot.bests.first(where: { $0.distance == distance }) {
                lines.append(row([MileProgress.distanceLabel(distance),
                                  MileProgress.timeText(best.seconds, distance: distance),
                                  context.dayText(best.date)]))
            } else {
                lines.append(row([MileProgress.distanceLabel(distance), "\u{2014}", "\u{2014}"]))
            }
        }
        lines.append("")
        lines.append("Time trials and races against the plan target:")
        lines.append("")
        if snapshot.results.isEmpty {
            lines.append("none yet.")
        } else {
            for result in snapshot.results.reversed() {
                lines.append(context.mileResultLine(result))
            }
        }
        return lines
    }

    // MARK: 9. Foot

    private static func footLines(_ context: ExportContext) -> [String] {
        var lines: [String] = ["", "## Foot", ""]
        var entries: [(date: Date, value: Int, text: String)] = []
        for run in context.runs where run.footPain >= 1 {
            entries.append((run.date, run.footPain, "run \(miles(run.distanceMeters)) mi"))
        }
        for workout in context.workouts where workout.footPain >= 1 {
            entries.append((workout.date, workout.footPain, "workout " + workout.name))
        }
        guard !entries.isEmpty else {
            lines.append("no foot pain logged")
            return lines
        }
        for entry in entries.sorted(by: { $0.date > $1.date }) {
            lines.append("- " + context.dayText(entry.date) + ": foot \(entry.value), " + entry.text)
        }
        return lines
    }

    // MARK: 10. Totals

    private static func totalsLines(_ context: ExportContext) -> [String] {
        let meters = context.runs.reduce(0) { $0 + $1.distanceMeters }
        var dates: [Date] = context.runs.map { $0.date }
        dates.append(contentsOf: context.workouts.map { $0.date })
        let since = dates.min().map { context.dayText($0) } ?? "no activity yet"
        return ["",
                "Totals: \(context.runs.count) runs, \(miles(meters)) mi; \(context.workouts.count) track workouts; since \(since)."]
    }
}

// MARK: - Context

/// What the builder works from: the input with test data left out, the schedule, and date formatting
/// in the calendar it was given.
private struct ExportContext {
    let input: ExportInput
    let calendar: Calendar
    let start: Date
    let schedule: PlanSchedule?
    /// Newest first, test runs left out.
    let runs: [ExportRun]
    /// Newest first, test workouts left out.
    let workouts: [ExportWorkout]
    /// Plan week of today: 0 before the start, the last week after the race.
    let currentWeek: Int
    private let dayFormatter: DateFormatter
    private let stampFormatter: DateFormatter

    init(input: ExportInput, calendar: Calendar) {
        self.input = input
        self.calendar = calendar
        let startDate = PlanCalendar.parse(input.startYMD, calendar: calendar) ?? calendar.startOfDay(for: input.generatedAt)
        self.start = startDate
        var built: PlanSchedule? = input.schedule
        if built == nil, let plan = input.plan {
            built = PlanSchedule(plan: plan,
                                 progress: input.progress,
                                 startWeekday: PlanCalendar.mondayWeekday(of: startDate, calendar: calendar))
        }
        self.schedule = built
        self.runs = input.runs.filter { !$0.isTest }.sorted { $0.date > $1.date }
        self.workouts = input.workouts.filter { !$0.isTest }.sorted { $0.date > $1.date }
        self.currentWeek = built?.currentWeek(today: input.todayOffset) ?? 0
        self.dayFormatter = ExportContext.makeFormatter("yyyy-MM-dd (EEE)", calendar: calendar)
        self.stampFormatter = ExportContext.makeFormatter("yyyy-MM-dd (EEE) HH:mm", calendar: calendar)
    }

    private static func makeFormatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }

    /// "2026-10-06 (Tue)".
    func dayText(_ date: Date) -> String {
        return dayFormatter.string(from: date)
    }

    func dayText(offset: Int) -> String {
        return dayText(PlanCalendar.date(forOffset: offset, start: start, calendar: calendar))
    }

    /// "2026-10-06 (Tue) 14:05".
    func stampText(_ date: Date) -> String {
        return stampFormatter.string(from: date)
    }

    /// "2026-10-06 (Tue), plan week 3 of 20, phase 1", or where today is outside the plan.
    var todayText: String {
        let day = dayText(offset: input.todayOffset)
        guard let plan = input.plan else { return day }
        if input.todayOffset < 0 {
            return day + ", before the plan starts"
        }
        let total = plan.weeks.count
        let phase = plan.weeks.first(where: { $0.week == currentWeek })?.phase
        var text = day + ", plan week \(currentWeek) of \(total)"
        if let phase = phase {
            text += ", phase \(phase)"
        }
        if let schedule = schedule, input.todayOffset > schedule.raceDayOffset {
            text += ", plan finished"
        }
        return text
    }

    /// Miles per plan day from the non-test runs and workouts, the way the app adds them up.
    var milesByDay: [Int: Double] {
        let logged = runs.map { LoggedRun(date: $0.date, meters: $0.distanceMeters, workoutName: $0.workoutName) }
        let tracks = workouts.map { workout -> LoggedWorkout in
            let distance = Double(workout.spec?.repDistance ?? 0)
            return LoggedWorkout(date: workout.date, name: workout.name, repMeters: Double(workout.repTimes.count) * distance)
        }
        return PlanActivities.milesByDay(runs: logged, workouts: tracks, start: start, calendar: calendar)
    }

    /// The mile chart's numbers, from the saved track workouts, the GPS bests and the settings.
    var mileSnapshot: MileSnapshot {
        let raceDays = Set(raceDayOffsets)
        let tracks = workouts.map { workout -> MileTrackInput in
            let day = PlanCalendar.activityDay(of: workout.date, start: start, calendar: calendar)
            return MileTrackInput(date: workout.date,
                                  repDistance: workout.spec?.repDistance ?? 0,
                                  totalReps: workout.spec?.totalReps ?? 0,
                                  repTimes: workout.repTimes,
                                  isRace: raceDays.contains(day))
        }
        return MileProgress.snapshot(tracks: tracks,
                                     gps: input.gpsBests,
                                     plan: [],
                                     goal: input.settings.goalMile,
                                     mileTime: input.settings.mileTime)
    }

    /// Plan days of the race sessions.
    private var raceDayOffsets: [Int] {
        guard let schedule = schedule else { return [] }
        return schedule.plan.sessions.indices
            .filter { schedule.plan.sessions[$0].kind == .race }
            .map { schedule.dayOffset($0) }
    }

    /// "- 2026-10-17 (Sat) time trial: 6:31 vs plan target 6:35 (\u{2212}4)" or "..., no plan target".
    func mileResultLine(_ result: MileResult) -> String {
        let kind = result.source == .race ? "race" : "time trial"
        var text = "- " + dayText(result.date) + " " + kind + ": " + formatDuration(result.seconds)
        if let target = planTarget(onDay: PlanCalendar.activityDay(of: result.date, start: start, calendar: calendar)) {
            text += " vs plan target " + formatDuration(target) + " (" + ReadoutFormat.signedDelta(result.seconds - target) + ")"
        } else {
            text += ", no plan target that day"
        }
        return text
    }

    /// The target of the plan's time trial or race on plan day `day`.
    private func planTarget(onDay day: Int) -> Double? {
        guard let schedule = schedule else { return nil }
        for index in schedule.plan.sessions.indices {
            let session = schedule.plan.sessions[index]
            guard session.kind == .timeTrial || session.kind == .race,
                  schedule.dayOffset(index) == day,
                  let target = session.targetSeconds else { continue }
            return target
        }
        return nil
    }

    /// The result of the time trial or race held on plan day `day`: a track workout of that day when there
    /// is one (its only rep, or the fastest), else the longest run of that day.
    func trialResult(onDay day: Int) -> (seconds: Double, text: String)? {
        let sameDay = workouts.filter { PlanCalendar.activityDay(of: $0.date, start: start, calendar: calendar) == day }
        for workout in sameDay {
            guard let best = workout.repTimes.min() else { continue }
            let label = workout.repTimes.count == 1 ? "result" : "fastest rep"
            return (best, "track workout \(workout.name), \(label) \(formatSplit(best))")
        }
        let runsOnDay = self.runs.filter { PlanCalendar.activityDay(of: $0.date, start: start, calendar: calendar) == day && $0.durationSeconds > 0 }
        if let run = runsOnDay.max(by: { $0.distanceMeters < $1.distanceMeters }) {
            return (run.durationSeconds, "run \(formatMiles(run.distanceMeters)) mi, time \(formatSplit(run.durationSeconds))")
        }
        return nil
    }
}
