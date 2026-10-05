import Foundation
import Observation

/// What the plan store starts from, worked out apart from `UserDefaults` so it can be tested.
struct PlanLaunch: Equatable {
    /// Start date used when neither the saved value nor the plan file gives a usable one.
    static let fallbackStart = "2026-10-12"

    var progress: PlanProgress
    /// The plan start as "yyyy-MM-dd".
    var startYMD: String
    /// True when the saved progress belonged to another plan version. Progress starts over and so does
    /// the saved start date, which the old plan's schedule may have moved.
    var versionChanged: Bool

    static func resolve(plan: PlanFile?, savedProgress: Data?, savedStart: String?) -> PlanLaunch {
        let version = plan?.version ?? 1
        var changed = false
        if let data = savedProgress,
           let decoded = try? JSONDecoder().decode(PlanProgress.self, from: data),
           decoded.planVersion != version {
            changed = true
        }
        var fileStart: String? = nil
        if let text = plan?.startDate, PlanCalendar.parse(text) != nil {
            fileStart = text
        }
        var ymd = PlanLaunch.fallbackStart
        if changed, let text = fileStart {
            ymd = text
        } else if let text = savedStart, PlanCalendar.parse(text) != nil {
            ymd = text
        } else if let text = fileStart {
            ymd = text
        }
        return PlanLaunch(progress: PlanProgress.restored(from: savedProgress, planVersion: version),
                          startYMD: ymd,
                          versionChanged: changed)
    }

    /// A message when the file's race date is not the plan start plus the race session's day; nil when
    /// they agree or the file has nothing to compare.
    static func raceDateMismatch(plan: PlanFile, startYMD: String) -> String? {
        guard let raceDate = plan.raceDate,
              let start = PlanCalendar.parse(startYMD),
              let race = plan.sessions.last(where: { $0.kind == .race }) else {
            return nil
        }
        let offset = (race.week - 1) * 7 + (race.weekday - 1)
        let expected = PlanCalendar.ymd(PlanCalendar.date(forOffset: offset, start: start))
        guard expected != raceDate else { return nil }
        return "plan race date \(raceDate) is not start \(startYMD) plus \(offset) days (\(expected))"
    }
}

/// The clock rules of the plan store, apart from the store so they can be tested.
enum PlanClock {
    /// The active session after a clock refresh: a new day forgets it, unless a run or track session is
    /// still going, which must still complete it when it is saved.
    static func activeIndexAfterRefresh(dayChanged: Bool, active: Int?, sessionInProgress: Bool) -> Int? {
        return dayChanged && !sessionInProgress ? nil : active
    }
}

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
    /// `UserDefaults` key for the "yyyy-MM-dd" the test week started on; absent or empty when it is off.
    static let testWeekKey = SettingsKey.testWeekStart
    /// `UserDefaults` key for the JSON-encoded `PlanProgress` of the test week. The real `progressKey`
    /// is never read or written while the test week is on.
    static let testProgressKey = "testPlanProgress"

    /// The plan everything shows: the bundled plan, or the test plan while the test week is on. nil when
    /// `plan.json` is missing or does not parse.
    private(set) var plan: PlanFile?
    /// The start of `plan` as "yyyy-MM-dd". Only the text is kept; `startDate` converts it in the
    /// calendar and time zone that are current at the moment it is asked for.
    private(set) var startYMD: String
    /// Progress through `plan`.
    private(set) var progress: PlanProgress
    /// The day the test week started on as "yyyy-MM-dd"; empty when it is off.
    private(set) var testStartYMD: String
    /// The bundled plan, kept aside while the test week is on.
    private var realPlan: PlanFile?
    /// The real plan's start as "yyyy-MM-dd" (the test plan has its own `startYMD`).
    private(set) var realStartYMD: String
    /// The real progress, kept aside while the test week is on and never changed then.
    private var realProgress: PlanProgress
    /// Days from the plan start to today (negative before the start).
    private(set) var todayOffset: Int
    /// The plan session the runner started from the today screen, until it is saved or discarded.
    /// Never saved to disk, so it is clear on every launch; also cleared when the day changes (not while
    /// a run or track session is going) and when the screen the route opened is left without starting.
    var activeSessionIndex: Int? = nil
    /// Set by "start"; the run or track screen applies it and clears it.
    var pendingRoute: PlanRoute? = nil
    /// Set when a tapped reminder wants a tab; `ContentView` switches to it and clears it.
    var requestedTab: AppTab? = nil

    private init() {
        let loaded = PlanLoader.load(bundle: Bundle.main)
        let launch = PlanLaunch.resolve(plan: loaded,
                                        savedProgress: UserDefaults.standard.data(forKey: PlanStore.progressKey),
                                        savedStart: UserDefaults.standard.string(forKey: PlanStore.startDateKey))
        if launch.versionChanged {
            // A new plan version starts over: write the fresh progress and start date now, so the next
            // launch does not see the old version again and reset a start date the runner has changed since.
            UserDefaults.standard.set(launch.startYMD, forKey: PlanStore.startDateKey)
            if let data = try? JSONEncoder().encode(launch.progress) {
                UserDefaults.standard.set(data, forKey: PlanStore.progressKey)
            }
            Diagnostics.shared.log(.state, "plan version changed: progress and start date reset to \(launch.startYMD)")
        }
        if let file = loaded, let message = PlanLaunch.raceDateMismatch(plan: file, startYMD: launch.startYMD) {
            Diagnostics.shared.log(.state, message)
        }

        let realStart = PlanCalendar.parse(launch.startYMD) ?? Date()
        realPlan = loaded
        realStartYMD = launch.startYMD
        realProgress = launch.progress

        var activePlan = loaded
        var activeStartYMD = launch.startYMD
        var activeProgress = launch.progress
        var activeTestYMD = ""
        let savedTest = UserDefaults.standard.string(forKey: PlanStore.testWeekKey) ?? ""
        if let testPlan = PlanStore.makeTestPlan(startYMD: savedTest, realStart: realStart) {
            activePlan = testPlan
            activeStartYMD = testPlan.startDate
            activeProgress = PlanProgress.restored(from: UserDefaults.standard.data(forKey: PlanStore.testProgressKey),
                                                   planVersion: TestWeek.planVersion)
            activeTestYMD = savedTest
        }
        plan = activePlan
        startYMD = activeStartYMD
        progress = activeProgress
        testStartYMD = activeTestYMD
        let start = PlanCalendar.parse(activeStartYMD) ?? Date()
        todayOffset = PlanCalendar.activityDay(of: Date(), start: start)
    }

    /// The test plan for a saved start day; nil when there is none or it is not a date.
    private static func makeTestPlan(startYMD: String, realStart: Date) -> PlanFile? {
        guard !startYMD.isEmpty, let day = PlanCalendar.parse(startYMD) else { return nil }
        return TestWeek.plan(startingOn: day, mileSeconds: AppSettings.mileTime, realStart: realStart)
    }

    /// The plan start in the current calendar and time zone. Computed on every call, never cached.
    var startDate: Date {
        return PlanCalendar.parse(startYMD) ?? PlanCalendar.local.startOfDay(for: Date())
    }

    /// The real plan's start in the current calendar and time zone, also while the test week is on.
    var realStartDate: Date {
        return PlanCalendar.parse(realStartYMD) ?? PlanCalendar.local.startOfDay(for: Date())
    }

    var schedule: PlanSchedule? {
        guard let plan = plan else { return nil }
        return PlanSchedule(plan: plan,
                            progress: progress,
                            startWeekday: PlanCalendar.mondayWeekday(of: startDate))
    }

    // MARK: Clock

    /// True while a run is being recorded (set by the run screen).
    var runInProgress = false
    /// True while the track session screen is open (set by that screen).
    var trackInProgress = false

    /// Recomputes today's offset. Called from a one-minute timer and when the app becomes active. Today
    /// changes at 03:00, the same boundary as `PlanCalendar.activityDay`, so a late run still belongs to
    /// the day it started on. A new day also forgets the active session, unless a run or track session
    /// is in progress.
    func refresh() {
        if isTestWeek, shouldAutoEndTestWeek(), endTestWeek() {
            return
        }
        let offset = PlanCalendar.activityDay(of: Date(), start: startDate)
        let changed = offset != todayOffset
        if changed {
            todayOffset = offset
        }
        let kept = PlanClock.activeIndexAfterRefresh(dayChanged: changed,
                                                     active: activeSessionIndex,
                                                     sessionInProgress: runInProgress || trackInProgress)
        if kept != activeSessionIndex {
            activeSessionIndex = kept
        }
    }

    /// Sets the real plan's start. While the test week is on only the real start changes; the test plan
    /// keeps its own.
    func setStartDate(_ date: Date) {
        let text = PlanCalendar.ymd(date)
        guard PlanCalendar.parse(text) != nil else { return }
        realStartYMD = text
        if !isTestWeek {
            startYMD = text
        }
        UserDefaults.standard.set(text, forKey: PlanStore.startDateKey)
        refresh()
        Reminders.shared.reschedule(clearDelivered: true)
    }

    // MARK: Test week

    /// True while the test week is on: `plan` is the test plan and the test progress key is in use.
    var isTestWeek: Bool {
        return !testStartYMD.isEmpty
    }

    /// A test week is offered before the real plan starts, when it is not on and nothing is recording.
    var canStartTestWeek: Bool {
        return !isTestWeek
            && !runInProgress
            && !trackInProgress
            && TestWeekLifecycle.canStart(today: Date(), realStart: realStartDate)
    }

    /// "oct 5 \u{2013} oct 11" while the test week is on, from the day it started to its last Sunday.
    var testWeekRangeText: String {
        guard isTestWeek, let first = PlanCalendar.parse(testStartYMD) else { return "" }
        let last = TestWeekLifecycle.lastDay(testStart: first, weeks: plan?.weeks.count ?? 1)
        return PlanFormat.shortDate(first) + " \u{2013} " + PlanFormat.shortDate(last)
    }

    /// Whether the test week is over by the clock and nothing blocks ending it.
    private func shouldAutoEndTestWeek() -> Bool {
        guard let first = PlanCalendar.parse(testStartYMD) else { return true }
        return TestWeekLifecycle.shouldAutoEnd(today: Date(),
                                               testStart: first,
                                               realStart: realStartDate,
                                               weeks: plan?.weeks.count ?? 1,
                                               sessionActive: runInProgress || trackInProgress)
    }

    /// Starts the test week today. False when it is not offered (see `canStartTestWeek`).
    @discardableResult
    func startTestWeek() -> Bool {
        guard canStartTestWeek else { return false }
        let ymd = PlanCalendar.ymd(TestWeek.startDay(now: Date()))
        guard let testPlan = PlanStore.makeTestPlan(startYMD: ymd, realStart: realStartDate) else { return false }
        realProgress = progress
        UserDefaults.standard.removeObject(forKey: PlanStore.testProgressKey)
        UserDefaults.standard.set(ymd, forKey: PlanStore.testWeekKey)
        testStartYMD = ymd
        plan = testPlan
        startYMD = testPlan.startDate
        progress = PlanProgress(planVersion: TestWeek.planVersion)
        activeSessionIndex = nil
        pendingRoute = nil
        todayOffset = PlanCalendar.activityDay(of: Date(), start: startDate)
        Diagnostics.shared.log(.state, "test week started \(ymd)")
        Reminders.shared.reschedule(clearDelivered: true)
        return true
    }

    /// Ends the test week: deletes every test run and workout, the test progress and any test draft, and
    /// goes back to the real plan. False, with nothing changed, while a run or track session is going or
    /// when the records could not be deleted.
    @discardableResult
    func endTestWeek() -> Bool {
        guard isTestWeek, !runInProgress, !trackInProgress else { return false }
        guard AppModel.shared.deleteTestRecords() else {
            Diagnostics.shared.log(.state, "test week not ended: test records could not be deleted")
            return false
        }
        clearTestDrafts()
        UserDefaults.standard.removeObject(forKey: PlanStore.testProgressKey)
        UserDefaults.standard.removeObject(forKey: PlanStore.testWeekKey)
        testStartYMD = ""
        plan = realPlan
        startYMD = realStartYMD
        progress = realProgress
        activeSessionIndex = nil
        pendingRoute = nil
        todayOffset = PlanCalendar.activityDay(of: Date(), start: startDate)
        Diagnostics.shared.log(.state, "test week ended")
        Reminders.shared.reschedule(clearDelivered: true)
        return true
    }

    /// Removes a saved run or track draft that belongs to the test week.
    private func clearTestDrafts() {
        if let draft = RunDraftStore.load(), draft.isTest {
            RunDraftStore.clear()
        }
        if let draft = TrackSessionStore.load(), draft.isTest {
            TrackSessionStore.clear()
        }
    }

    // MARK: Progress

    /// Saves `progress` under the key of the plan that is showing, and keeps the real progress in step
    /// when it is the real plan.
    private func persist() {
        guard let data = try? JSONEncoder().encode(progress) else { return }
        if isTestWeek {
            UserDefaults.standard.set(data, forKey: PlanStore.testProgressKey)
        } else {
            realProgress = progress
            UserDefaults.standard.set(data, forKey: PlanStore.progressKey)
        }
    }

    private func apply(_ updated: PlanProgress) {
        guard updated != progress else { return }
        progress = updated
        persist()
        Reminders.shared.reschedule(clearDelivered: true)
    }

    /// "Do it today" for a missed session: it moves to today (or the first allowed day after it this
    /// week) and the rest of this calendar week is re-placed around it; see `PlanSchedule.pushingBack`.
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

    /// Takes a finished session back to unfinished, after the run that finished it was discarded.
    func reopen(_ index: Int) {
        guard let schedule = schedule else { return }
        apply(schedule.reopening(index))
    }

    /// Marks sessions done when a saved run or workout of the right kind started on their day, and
    /// skips sessions missed more than two days ago. Test records count only while the test week is on,
    /// and then only they do. After a run or workout was deleted
    /// (`activitiesRemoved`), the done marks that activities earned are taken back first, so only the
    /// sessions that saved activities still match stay done; manual done and skip are never cleared.
    func reconcile(runs: [LoggedRun], workouts: [LoggedWorkout], activitiesRemoved: Bool = false) {
        guard let schedule = schedule else { return }
        let testWeek = isTestWeek
        let activities = PlanActivities.days(runs: TestRecordFilter.runs(runs, testWeek: testWeek),
                                             workouts: TestRecordFilter.workouts(workouts, testWeek: testWeek),
                                             start: startDate)
        if activitiesRemoved {
            apply(schedule.reconciledAfterRemoval(activities: activities, today: todayOffset))
        } else {
            apply(schedule.reconciled(activities: activities, today: todayOffset))
        }
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
    /// activity is what that session asks for (`PlanSchedule.matches`: an easy or long run needs half its
    /// miles, a road session its workout, a time trial the mile trial). Anything else leaves it alone.
    /// The mark counts as earned by the activity, so deleting the activity takes it back. Returns the
    /// index of the session that was marked done, so a later discard can reopen it.
    @discardableResult
    func completeActive(_ kind: ActivityDay.Kind) -> Int? {
        guard let index = activeSessionIndex else { return nil }
        guard let schedule = schedule, schedule.plan.sessions.indices.contains(index) else {
            activeSessionIndex = nil
            return nil
        }
        guard PlanSchedule.matches(kind, session: schedule.plan.sessions[index]) else { return nil }
        activeSessionIndex = nil
        guard schedule.status(index) == nil else { return nil }
        apply(schedule.markingDone(index, auto: true))
        return index
    }

    /// Forgets the active session without marking it: a run or workout was discarded, or the screen
    /// the route opened was left without starting.
    func discardActive() {
        if activeSessionIndex != nil {
            activeSessionIndex = nil
        }
    }
}
