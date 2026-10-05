import UIKit

/// Only here so the notification delegate is set before the first notification can arrive.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Reminders.shared.activate()
        return true
    }
}
