import Foundation
import Observation

/// Holds the bundled training plan, the runner's progress through it and the hand-off between the
/// today screen and the run and track screens.
@Observable
@MainActor
final class PlanStore {
    static let shared = PlanStore()

    /// `UserDefaults` key for the plan start date, stored as "yyyy-MM-dd".
    static let startDateKey = "planStartDate"
    /// `UserDefaults` key for the JSON-encoded `PlanProgress`.
    static let progressKey = "planProgress"

    /// nil when `plan.json` is missing or does not parse.
    private(set) var plan: PlanFile?
    private(set) var startDate: Date
    private(set) var progress: PlanProgress
    /// Days from the plan start to today (negative before the start).
    private(set) var todayOffset: Int
    /// The plan session the runner started from the today screen, until it is saved or discarded.
    var activeSessionIndex: Int? = nil
    /// Set by "start"; the run or track screen applies it and clears it.
    var pendingRoute: PlanRoute? = nil

    private init() {
        let loaded = PlanLoader.load(bundle: Bundle.main)
        let fileStart = PlanCalendar.parse(loaded?.startDate ?? "2026-10-12")
        let fallbackStart = fileStart ?? PlanCalendar.parse("2026-10-12") ?? Date()

        var start = fallbackStart
        if let text = UserDefaults.standard.string(forKey: PlanStore.startDateKey),
           let saved = PlanCalendar.parse(text) {
            start = saved
        }

        var restored = PlanProgress()
        if let data = UserDefaults.standard.data(forKey: PlanStore.progressKey),
           let decoded = try? JSONDecoder().decode(PlanProgress.self, from: data) {
            restored = decoded
        }

        plan = loaded
        startDate = start
        progress = restored
        todayOffset = PlanCalendar.dayOffset(of: Date(), start: start)
    }

    var schedule: PlanSchedule? {
        guard let plan = plan else { return nil }
        return PlanSchedule(plan: plan, progress: progress)
    }

    // MARK: Clock

    /// Recomputes today's offset. Called from a one-minute timer and when the app becomes active.
    func refresh() {
        let offset = PlanCalendar.dayOffset(of: Date(), start: startDate)
        if offset != todayOffset {
            todayOffset = offset
        }
    }

    func setStartDate(_ date: Date) {
        let day = PlanCalendar.local.startOfDay(for: date)
        startDate = day
        UserDefaults.standard.set(PlanCalendar.ymd(day), forKey: PlanStore.startDateKey)
        refresh()
    }

    // MARK: Progress

    private func persist() {
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: PlanStore.progressKey)
        }
    }

    private func apply(_ updated: PlanProgress) {
        guard updated != progress else { return }
        progress = updated
        persist()
    }

    /// "Do it today" for a missed session: it and everything after it move back.
    func doItToday(missed index: Int) {
        guard let schedule = schedule else { return }
        apply(schedule.pushingBack(missed: index, today: todayOffset))
    }

    func skip(_ index: Int) {
        guard let schedule = schedule else { return }
        apply(schedule.skipping(index))
    }

    func markDone(_ index: Int) {
        guard let schedule = schedule else { return }
        apply(schedule.markingDone(index))
    }

    /// Marks sessions done when their scheduled day has a saved run or workout.
    func reconcile(runDates: [Date], workoutDates: [Date]) {
        guard let schedule = schedule else { return }
        let calendar = PlanCalendar.local
        var days = Set<Int>()
        for date in runDates {
            days.insert(PlanCalendar.dayOffset(of: date, start: startDate, calendar: calendar))
        }
        for date in workoutDates {
            days.insert(PlanCalendar.dayOffset(of: date, start: startDate, calendar: calendar))
        }
        apply(schedule.reconciled(activityDays: days))
    }

    func resetProgress() {
        activeSessionIndex = nil
        apply(PlanProgress())
    }

    // MARK: Starting a session

    /// Remembers which session the runner is about to do, without changing screens.
    func markActive(_ index: Int) {
        guard let schedule = schedule, schedule.plan.sessions.indices.contains(index) else { return }
        activeSessionIndex = index
    }

    /// Remembers the session and asks the run or track screen to set itself up for it.
    func start(_ index: Int) {
        guard let schedule = schedule, schedule.plan.sessions.indices.contains(index) else { return }
        activeSessionIndex = index
        pendingRoute = PlanRoute.route(for: schedule.plan.sessions[index])
    }

    /// Called when a run or workout is saved: marks the active session done.
    func completeActive() {
        guard let index = activeSessionIndex else { return }
        activeSessionIndex = nil
        guard let schedule = schedule, schedule.status(index) == nil else { return }
        apply(schedule.markingDone(index))
    }

    /// Called when a run or workout is discarded: forgets the active session without marking it.
    func discardActive() {
        activeSessionIndex = nil
    }
}
