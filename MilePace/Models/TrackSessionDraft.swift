import Foundation

/// A track session in progress, saved on every tap and when the app goes to the background, so a
/// killed app does not lose the reps already timed.
struct TrackSessionDraft: Codable, Equatable {
    /// A draft older than this is forgotten.
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

    /// The saved draft when it is fresh; an old or unreadable one is removed and nil is returned.
    static func load(now: Date = Date(), defaults: UserDefaults = UserDefaults.standard) -> TrackSessionDraft? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let draft = try? JSONDecoder().decode(TrackSessionDraft.self, from: data),
              draft.isFresh(now: now) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return draft
    }

    static func clear(defaults: UserDefaults = UserDefaults.standard) {
        defaults.removeObject(forKey: key)
    }
}
