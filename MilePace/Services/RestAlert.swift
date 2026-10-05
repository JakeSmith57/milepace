import Foundation
import UserNotifications

/// A notification for the end of a track rest, for when the phone is locked or the app is in the
/// background and the on-screen countdown cannot be seen or heard.
enum RestAlert {
    static let identifier = "track.rest"

    /// "go when ready. rep 4 of 6."
    static func body(nextRep: Int, totalReps: Int) -> String {
        return "go when ready. rep \(nextRep) of \(totalReps)."
    }

    /// Schedules the alert for `seconds` from now. Does nothing for a rest that is already over or when
    /// notifications are not allowed.
    static func schedule(inSeconds seconds: Double, nextRep: Int, totalReps: Int) {
        guard seconds > 1 else { return }
        let text = body(nextRep: nextRep, totalReps: totalReps)
        let center = UNUserNotificationCenter.current()
        Task {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "rest over"
            content.body = text
            content.sound = UNNotificationSound.default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            _ = try? await center.add(request)
        }
    }

    /// Removes the pending and the delivered alert.
    static func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}
