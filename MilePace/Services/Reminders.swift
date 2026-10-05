import Foundation
import Observation
import UserNotifications

/// Schedules the plan's local notifications and handles taps and actions on them. The window is
/// rebuilt whenever anything it depends on changes, so there is never a long queue to go stale.
@Observable
@MainActor
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    /// Last known notification permission. Only meaningful once `authorizationKnown` is true.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var authorizationKnown: Bool = false
    /// Pending `plan.` notifications, for the "scheduled" row in Set.
    private(set) var pendingCount: Int = 0

    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private var debounce: Task<Void, Never>?
    /// Set by a progress change; the next rebuild then also clears delivered session notifications.
    @ObservationIgnored private var clearDeliveredPending: Bool = false

    /// Calls within this many seconds of each other become one rebuild.
    static let debounceSeconds: Double = 1.0

    init(center: UNUserNotificationCenter = UNUserNotificationCenter.current()) {
        self.center = center
        super.init()
    }

    var isAuthorized: Bool {
        return authorization == .authorized || authorization == .provisional
    }

    // MARK: Launch

    /// Becomes the notification delegate and registers the session actions. Called from the app
    /// delegate at launch.
    func activate() {
        center.delegate = self
        registerCategories()
    }

    private func registerCategories() {
        let done = UNNotificationAction(identifier: ReminderPlanner.markDoneAction,
                                        title: "mark done",
                                        options: [])
        let skip = UNNotificationAction(identifier: ReminderPlanner.skipAction,
                                        title: "skip",
                                        options: [])
        let category = UNNotificationCategory(identifier: ReminderPlanner.sessionCategory,
                                              actions: [done, skip],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    // MARK: Permission

    func refreshAuthorization() {
        Task {
            await self.loadAuthorization()
            await self.loadPendingCount()
        }
    }

    private func loadAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        authorizationKnown = true
    }

    func requestPermission() {
        Task {
            _ = try? await self.center.requestAuthorization(options: [.alert, .sound, .badge])
            await self.loadAuthorization()
            self.reschedule()
        }
    }

    // MARK: Scheduling

    /// Rebuilds the reminder window after a short pause; repeated calls restart the pause. Pass
    /// `clearDelivered` after a progress change so notifications already in the notification center
    /// for today or later, which may now be wrong, are removed.
    func reschedule(clearDelivered: Bool = false) {
        if clearDelivered {
            clearDeliveredPending = true
        }
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(nanoseconds: UInt64(Reminders.debounceSeconds * 1_000_000_000))
            if Task.isCancelled { return }
            await self.rebuild()
        }
    }

    private func currentSpecs(runs: [LoggedRun], workouts: [LoggedWorkout]) -> [ReminderSpec] {
        let store = PlanStore.shared
        guard let schedule = store.schedule else { return [] }
        let start = store.startDate
        let parts = PlanCalendar.local.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let milesByDay = PlanActivities.milesByDay(runs: runs, workouts: workouts, start: start)
        return ReminderPlanner.build(schedule: schedule,
                                     todayOffset: store.todayOffset,
                                     nowMinutes: nowMinutes,
                                     settings: AppSettings.reminderSettings,
                                     loggedMilesByDay: milesByDay,
                                     zones: AppSettings.zones,
                                     goalMile: AppSettings.goalMile,
                                     startDate: start)
    }

    private func makeRequest(for spec: ReminderSpec, start: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.sound = UNNotificationSound.default
        if let category = spec.category {
            content.categoryIdentifier = category
        }
        if let index = spec.sessionIndex {
            content.userInfo = ["sessionIndex": index, "day": spec.dayOffset]
        }
        let calendar = PlanCalendar.local
        let day = PlanCalendar.date(forOffset: spec.dayOffset, start: start, calendar: calendar)
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = spec.minutes / 60
        parts.minute = spec.minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: spec.id, content: content, trigger: trigger)
    }

    /// Removes delivered `plan.` notifications for `today` or later, such as a morning note for a
    /// session that has since been done, skipped or moved.
    private func removeDelivered(from today: Int) async {
        let delivered = await center.deliveredNotifications()
        var ids: [String] = []
        for notification in delivered {
            let id = notification.request.identifier
            if let day = ReminderPlanner.dayOffset(ofIdentifier: id), day >= today {
                ids.append(id)
            }
        }
        if !ids.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    /// Replaces every pending `plan.` notification with the current window. Runs and workouts are
    /// read here from the shared store, so this works without any screen (a notification action can
    /// launch the app in the background).
    private func rebuild() async {
        await loadAuthorization()
        let activity = AppModel.shared.loadActivity()
        let store = PlanStore.shared
        store.refresh()
        store.reconcile(runs: activity.runs, workouts: activity.workouts)

        if clearDeliveredPending {
            clearDeliveredPending = false
            await removeDelivered(from: store.todayOffset)
        }

        let pending = await center.pendingNotificationRequests()
        let oldIds = pending.map { $0.identifier }.filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: oldIds)

        guard isAuthorized, store.plan != nil else {
            pendingCount = 0
            return
        }
        let specs = currentSpecs(runs: activity.runs, workouts: activity.workouts)
        if Task.isCancelled { return }
        let start = store.startDate
        for spec in specs {
            _ = try? await center.add(makeRequest(for: spec, start: start))
        }
        Diagnostics.shared.log(.state, "reminders scheduled \(specs.count)")
        await loadPendingCount()
    }

    private func loadPendingCount() async {
        let pending = await center.pendingNotificationRequests()
        pendingCount = pending.filter { $0.identifier.hasPrefix(ReminderPlanner.idPrefix) }.count
    }

    // MARK: Test

    /// Schedules one notification five seconds from now.
    func sendTest() {
        Task {
            await self.loadAuthorization()
            guard self.isAuthorized else { return }
            let content = UNMutableNotificationContent()
            content.title = "test: reminders work"
            content.body = "this is what a reminder looks like."
            content.sound = UNNotificationSound.default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(identifier: ReminderPlanner.testId,
                                                content: content,
                                                trigger: trigger)
            _ = try? await self.center.add(request)
        }
    }

    // MARK: Responses

    /// "Mark done" and "skip" only act when the session is still scheduled for the day the
    /// notification was made for and has no status; otherwise the notification is stale.
    private func handle(action: String, sessionIndex: Int?, day: Int?) async {
        let store = PlanStore.shared
        let isSessionAction = action == ReminderPlanner.markDoneAction || action == ReminderPlanner.skipAction
        if isSessionAction {
            store.refresh()
            if let index = sessionIndex,
               let day = day,
               let schedule = store.schedule,
               ReminderPlanner.actionApplies(schedule: schedule, sessionIndex: index, day: day) {
                if action == ReminderPlanner.markDoneAction {
                    store.markDone(index)
                } else {
                    store.skip(index)
                }
            }
        } else if action == UNNotificationDefaultActionIdentifier {
            store.requestedTab = .today
        }
        if isSessionAction {
            await rebuild()
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let identifier = notification.request.identifier
        if ReminderPlanner.showsInForeground(identifier) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([])
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        let index = info["sessionIndex"] as? Int
        let day = info["day"] as? Int
        Task { @MainActor in
            await self.handle(action: action, sessionIndex: index, day: day)
            completionHandler()
        }
    }
}
