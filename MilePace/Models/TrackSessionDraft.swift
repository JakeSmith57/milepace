import Foundation

/// A track session in progress, saved on every tap and when the app goes to the background, so a
/// killed app does not lose the reps already timed.
struct TrackSessionDraft: Codable, Equatable {
    /// An unfinished draft older than this is forgotten. A finished one never expires.
    static let maxAgeSeconds: Double = 3 * 3600

    var workout: TrackWorkout
    /// When the first rep started.
    var sessionStart: Date
    /// When this draft was written.
    var savedAt: Date

    /// Still worth offering: written within the last three hours (and not from the future).
    func isFresh(now: Date) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age <= TrackSessionDraft.maxAgeSeconds
    }

    var isFinished: Bool {
        return workout.state == .finished
    }

    /// Whether the store keeps it: a finished workout waits for the runner however long that takes (its
    /// results are real), an unfinished one only while it is fresh.
    func isKept(now: Date) -> Bool {
        return isFinished || isFresh(now: now)
    }

    /// A finished workout with at least one rep timed can be saved as a workout record.
    var hasResults: Bool {
        return isFinished && !workout.repTimes.isEmpty
    }

    /// The workout as it will be saved.
    func makeRecord() -> WorkoutRecord {
        return WorkoutRecord(date: sessionStart,
                             name: workout.spec.name,
                             spec: workout.spec,
                             repTimes: workout.repTimes,
                             lapSplits: workout.lapSplits)
    }

    /// "resume 6 \u{00D7} 400 @ R", or "unsaved results: 6 \u{00D7} 400 @ R" when the workout was already over.
    var title: String {
        return (isFinished ? "unsaved results: " : "resume ") + workout.spec.name
    }

    /// The button that opens it.
    var actionTitle: String {
        return isFinished ? "open" : "resume"
    }
}

/// The track draft in `UserDefaults`, as JSON.
enum TrackSessionStore {
    static let key = "trackSessionDraft"

    static func save(_ draft: TrackSessionDraft, defaults: UserDefaults = UserDefaults.standard) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key)
    }

    /// Whether the session screen writes the draft now: not before the first rep, and not once the
    /// workout is saved or being saved (the finished draft was cleared then and must stay gone).
    static func shouldPersist(started: Bool, state: TrackState, saved: Bool, saving: Bool) -> Bool {
        return started && state != .ready && !saved && !saving
    }

    /// The saved draft when it is kept (finished, or fresh); an old unfinished or unreadable one is
    /// removed and nil is returned.
    static func load(now: Date = Date(), defaults: UserDefaults = UserDefaults.standard) -> TrackSessionDraft? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let draft = try? JSONDecoder().decode(TrackSessionDraft.self, from: data),
              draft.isKept(now: now) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return draft
    }

    static func clear(defaults: UserDefaults = UserDefaults.standard) {
        defaults.removeObject(forKey: key)
    }
}
