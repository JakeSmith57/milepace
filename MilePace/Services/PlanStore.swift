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
    /// Start date used when neither the saved value nor the plan file gives a usable one.
    static let fallbackStart = "2026-10-12"

    /// nil when `plan.json` is missing or does not parse.
    private(set) var plan: PlanFile?
    /// The plan start as "yyyy-MM-dd". Only the text is kept; `startDate` converts it in the
    /// calendar and time zone that are current at the moment it is asked for.
    private(set) var startYMD: String
    private(set) var progress: PlanProgress
    /// Days from the plan start to today (negative before the start).
    private(set) var todayOffset: Int
    /// The plan session the runner started from the today screen, until it is saved or discarded.
    /// Never saved to disk, so it is clear on every launch; also cleared when the day changes and
    /// when the screen the route opened is left without starting.
    var activeSessionIndex: Int? = nil
    /// Set by "start"; the run or track screen applies it and clears it.
    var pendingRoute: PlanRoute? = nil
    /// Set when a tapped reminder wants a tab; `ContentView` switches to it and clears it.
    var requestedTab: AppTab? = nil

    private init() {
        let loaded = PlanLoader.load(bundle: Bundle.main)
        var ymd = PlanStore.fallbackStart
        if let text = UserDefaults.standard.string(forKey: PlanStore.startDateKey),
           PlanCalendar.parse(text) != nil {
            ymd = text
        } else if let text = loaded?.startDate, PlanCalendar.parse(text) != nil {
            ymd = text
        }

        let restored = PlanProgress.restored(from: UserDefaults.standard.data(forKey: PlanStore.progressKey),
                                             planVersion: loaded?.version ?? 1)
        let start = PlanCalendar.parse(ymd) ?? Date()

        plan = loaded
        startYMD = ymd
        progress = restored
        todayOffset = PlanCalendar.dayOffset(of: Date(), start: start)
    }

    /// The plan start in the current calendar and time zone. Computed on every call, never cached.
    var startDate: Date {
        return PlanCalendar.parse(startYMD) ?? PlanCalendar.local.startOfDay(for: Date())
    }

    var schedule: PlanSchedule? {
        guard let plan = plan else { return nil }
        return PlanSchedule(plan: plan,
                            progress: progress,
                            startWeekday: PlanCalendar.mondayWeekday(of: startDate))
    }

    // MARK: Clock

    /// Recomputes today's offset. Called from a one-minute timer and when the app becomes active.
    /// A new day also forgets the active session.
    func refresh() {
        let offset = PlanCalendar.dayOffset(of: Date(), start: startDate)
        if offset != todayOffset {
            todayOffset = offset
            activeSessionIndex = nil
        }
    }

    func setStartDate(_ date: Date) {
        let text = PlanCalendar.ymd(date)
        guard PlanCalendar.parse(text) != nil else { return }
        startYMD = text
        UserDefaults.standard.set(text, forKey: PlanStore.startDateKey)
        refresh()
        Reminders.shared.reschedule(clearDelivered: true)
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
        Reminders.shared.reschedule(clearDelivered: true)
    }

    /// "Do it today" for a missed key session: it takes the first free easy day left this week, or is
    /// skipped when there is none (see `PlanSchedule.pushingBack`).
    func doItToday(missed index: Int) {
        guard let schedule = schedule else { return }
        apply(schedule.pushingBack(missed: index, today: todayOffset).progress)
    }

    func skip(_ index: Int) {
        guard let schedule = schedule else { return }
        apply(schedule.skipping(index))
    }

    func markDone(_ index: Int) {
        guard let schedule = schedule else { return }
        apply(schedule.markingDone(index))
    }

    /// Marks sessions done when a saved run or workout of the right kind started on their day, and
    /// skips sessions missed more than two days ago.
    func reconcile(runs: [LoggedRun], workouts: [LoggedWorkout]) {
        guard let schedule = schedule else { return }
        let activities = PlanActivities.days(runs: runs, workouts: workouts, start: startDate)
        apply(schedule.reconciled(activities: activities, today: todayOffset))
    }

    func resetProgress() {
        activeSessionIndex = nil
        apply(PlanProgress(planVersion: plan?.version ?? 1))
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

    /// Called when a run or workout is saved: marks the active session done, but only when the saved
    /// activity is the kind that session asks for (a run for easy, long and road sessions, a track
    /// workout for track, time trial and race sessions). Anything else leaves it alone.
    func completeActive(_ kind: ActivityDay.Kind) {
        guard let index = activeSessionIndex else { return }
        guard let schedule = schedule, schedule.plan.sessions.indices.contains(index) else {
            activeSessionIndex = nil
            return
        }
        guard PlanSchedule.isSameFamily(kind, session: schedule.plan.sessions[index]) else { return }
        activeSessionIndex = nil
        guard schedule.status(index) == nil else { return }
        apply(schedule.markingDone(index))
    }

    /// Forgets the active session without marking it: a run or workout was discarded, or the screen
    /// the route opened was left without starting.
    func discardActive() {
        if activeSessionIndex != nil {
            activeSessionIndex = nil
        }
    }
}
