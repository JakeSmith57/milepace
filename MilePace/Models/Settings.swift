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
    static let cueInterval = "cueInterval"
    static let runMode = "runMode"
    static let roadWorkoutName = "roadWorkoutName"
    static let metronomeEnabled = "metronomeEnabled"
    static let metronomeBPM = "metronomeBPM"
    static let metronomeVolume = "metronomeVolume"
    static let displayMode = "displayMode"
    static let diagnostics = "diagnosticsEnabled"
    static let remindersEnabled = "remindersEnabled"
    static let reminderMorning = "reminderMorning"
    static let reminderEvening = "reminderEvening"
    static let reminderTimeTrial = "reminderTimeTrial"
    static let reminderWeekly = "reminderWeekly"
    static let reminderMorningMinutes = "reminderMorningMinutes"
    static let reminderEveningMinutes = "reminderEveningMinutes"
}

/// Light, dark or follow the system.
enum DisplayMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "system"
        case .dark: return "dark"
        case .light: return "light"
        }
    }
}

/// What the run screen is set up to do.
enum RunMode: String, CaseIterable, Identifiable {
    case free
    case workout

    var id: String { rawValue }

    var title: String {
        switch self {
        case .free: return "Free run"
        case .workout: return "Workout"
        }
    }
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
    static let defaultMetronomeBPM: Int = 166
    static let defaultMetronomeVolume: Double = 0.6

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.mileTime: defaultMileTime,
            SettingsKey.goalMile: defaultGoalMile,
            SettingsKey.announceMiles: true,
            SettingsKey.zoneGuard: true,
            SettingsKey.trackCountdown: true,
            SettingsKey.lapFeedback: false,
            SettingsKey.haptics: true,
            SettingsKey.runZone: RunZoneTarget.off.rawValue,
            SettingsKey.cueInterval: CueInterval.half.rawValue,
            SettingsKey.runMode: RunMode.free.rawValue,
            SettingsKey.metronomeEnabled: false,
            SettingsKey.metronomeBPM: defaultMetronomeBPM,
            SettingsKey.metronomeVolume: defaultMetronomeVolume,
            SettingsKey.displayMode: DisplayMode.system.rawValue,
            SettingsKey.diagnostics: false,
            SettingsKey.remindersEnabled: true,
            SettingsKey.reminderMorning: true,
            SettingsKey.reminderEvening: true,
            SettingsKey.reminderTimeTrial: true,
            SettingsKey.reminderWeekly: true,
            SettingsKey.reminderMorningMinutes: ReminderSettings.defaultMorningMinutes,
            SettingsKey.reminderEveningMinutes: ReminderSettings.defaultEveningMinutes
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

    private static func int(_ key: String, fallback: Int) -> Int {
        if let value = UserDefaults.standard.object(forKey: key) as? Int {
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
    static var diagnosticsEnabled: Bool { bool(SettingsKey.diagnostics, fallback: false) }

    static var cueInterval: CueInterval {
        if let raw = UserDefaults.standard.string(forKey: SettingsKey.cueInterval),
           let value = CueInterval(rawValue: raw) {
            return value
        }
        return .half
    }

    static var metronomeBPM: Int {
        if let value = UserDefaults.standard.object(forKey: SettingsKey.metronomeBPM) as? Int {
            return min(max(value, ClickTrack.bpmRange.lowerBound), ClickTrack.bpmRange.upperBound)
        }
        return defaultMetronomeBPM
    }

    static var metronomeVolume: Double {
        return min(max(double(SettingsKey.metronomeVolume, fallback: defaultMetronomeVolume), 0.1), 1.0)
    }

    static var reminderSettings: ReminderSettings {
        return ReminderSettings(
            enabled: bool(SettingsKey.remindersEnabled, fallback: true),
            morning: bool(SettingsKey.reminderMorning, fallback: true),
            evening: bool(SettingsKey.reminderEvening, fallback: true),
            timeTrial: bool(SettingsKey.reminderTimeTrial, fallback: true),
            weekly: bool(SettingsKey.reminderWeekly, fallback: true),
            morningMinutes: int(SettingsKey.reminderMorningMinutes, fallback: ReminderSettings.defaultMorningMinutes),
            eveningMinutes: int(SettingsKey.reminderEveningMinutes, fallback: ReminderSettings.defaultEveningMinutes)
        )
    }

    static var zones: PaceZones { PaceZones.forMile(mileTime) }
}
