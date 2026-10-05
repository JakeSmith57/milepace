import Foundation

/// A run in progress, written to disk every 30 seconds of moving time so a crash, a kill or a dead
/// battery never loses it.
struct RunDraft: Codable, Equatable {
    var start: Date
    var distanceMeters: Double
    /// Moving time in seconds (pauses excluded).
    var movingSeconds: Double
    var splits: [Double]
    var route: [RoutePoint]
    /// Steps counted outside pauses.
    var cadenceSteps: Int
    /// Name of the guided workout; empty for a free run.
    var workoutName: String

    /// Seconds per mile, 0 with under 10 m covered (the same rule a finished run uses).
    var averagePace: Double {
        guard distanceMeters >= 10, movingSeconds > 0 else { return 0 }
        return movingSeconds / distanceMeters * metersPerMile
    }

    /// Steps per minute, 0 when there is not enough data.
    var averageCadence: Double {
        return CadenceMath.averageSPM(totalSteps: cadenceSteps, pausedSteps: 0, movingSeconds: movingSeconds) ?? 0
    }

    /// "unfinished run from 6:42 am: 2.41 mi, 18:52".
    func summaryText(calendar: Calendar = PlanCalendar.local) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        let clock = formatter.string(from: start).lowercased()
        return "unfinished run from " + clock + ": " + formatMiles(distanceMeters) + " mi, " + formatDuration(movingSeconds)
    }

    /// The run as it will be saved.
    func makeRecord() -> RunRecord {
        return RunRecord(date: start,
                         distanceMeters: distanceMeters,
                         durationSeconds: movingSeconds,
                         averagePace: averagePace,
                         splits: splits,
                         notes: "",
                         route: route,
                         averageCadence: averageCadence,
                         workoutName: workoutName)
    }

    func encoded() -> Data? {
        return try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> RunDraft? {
        return try? JSONDecoder().decode(RunDraft.self, from: data)
    }
}

/// Where the draft lives: `Application Support/run-draft.json`, written atomically. All access goes
/// through one serial queue, so a clear can never be overtaken by an older write.
enum RunDraftStore {
    private static let queue = DispatchQueue(label: "milepace.run-draft")

    static let fileName = "run-draft.json"

    static var url: URL? {
        let manager = FileManager.default
        guard let base = try? manager.url(for: .applicationSupportDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: nil,
                                          create: true) else {
            return nil
        }
        return base.appendingPathComponent(fileName)
    }

    /// Writes `draft` in the background.
    static func save(_ draft: RunDraft) {
        guard let data = draft.encoded(), let target = url else { return }
        queue.async {
            try? data.write(to: target, options: .atomic)
        }
    }

    /// The saved draft, if there is one that reads back.
    static func load() -> RunDraft? {
        guard let target = url else { return nil }
        return queue.sync {
            guard let data = try? Data(contentsOf: target) else { return nil }
            return RunDraft.decode(data)
        }
    }

    /// Deletes the draft file.
    static func clear() {
        guard let target = url else { return }
        queue.async {
            try? FileManager.default.removeItem(at: target)
        }
    }
}
