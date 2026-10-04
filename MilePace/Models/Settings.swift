import Foundation

/// Keys for `@AppStorage` / `UserDefaults`.
enum SettingsKey {
    static let mileTime = "mileTimeSeconds"
    static let goalMile = "goalMileSeconds"
    static let announceMiles = "announceMiles"
    static let zoneGuard = "zoneGuardCues"
    static let trackCountdown = "trackRestCountdown"
    static let lapFeedback = "trackLapFeedback"
    static let haptics = "hapticsEnabled"
    static let runZone = "runZoneTarget"
}

/// The zone the run screen guards pace against.
enum RunZoneTarget: String, CaseIterable, Identifiable {
    case off
    case easy
    case threshold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "None"
        case .easy: return "Easy"
        case .threshold: return "Threshold"
        }
    }

    /// Seconds-per-mile range to guard, or nil when guarding is off.
    func range(in zones: PaceZones) -> ClosedRange<Double>? {
        switch self {
        case .off: return nil
        case .easy: return zones.easy
        case .threshold: return zones.threshold
        }
    }
}

/// Typed access to settings for non-view code (Coach, etc.).
enum AppSettings {
    static let defaultMileTime: Double = 412
    static let defaultGoalMile: Double = 330
    static let validMileRange: ClosedRange<Double> = 240...720

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.mileTime: defaultMileTime,
            SettingsKey.goalMile: defaultGoalMile,
            SettingsKey.announceMiles: true,
            SettingsKey.zoneGuard: true,
            SettingsKey.trackCountdown: true,
            SettingsKey.lapFeedback: false,
            SettingsKey.haptics: true,
            SettingsKey.runZone: RunZoneTarget.off.rawValue
        ])
    }

    private static func bool(_ key: String, fallback: Bool) -> Bool {
        if let value = UserDefaults.standard.object(forKey: key) as? Bool {
            return value
        }
        return fallback
    }

    private static func double(_ key: String, fallback: Double) -> Double {
        if let value = UserDefaults.standard.object(forKey: key) as? Double {
            return value
        }
        return fallback
    }

    static var mileTime: Double { double(SettingsKey.mileTime, fallback: defaultMileTime) }
    static var goalMile: Double { double(SettingsKey.goalMile, fallback: defaultGoalMile) }
    static var announceMiles: Bool { bool(SettingsKey.announceMiles, fallback: true) }
    static var zoneGuardCues: Bool { bool(SettingsKey.zoneGuard, fallback: true) }
    static var trackCountdown: Bool { bool(SettingsKey.trackCountdown, fallback: true) }
    static var lapFeedback: Bool { bool(SettingsKey.lapFeedback, fallback: false) }
    static var haptics: Bool { bool(SettingsKey.haptics, fallback: true) }

    static var zones: PaceZones { PaceZones.forMile(mileTime) }
}
