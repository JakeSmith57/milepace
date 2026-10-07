import Foundation

/// One move in a routine: what to do, how much, how, and an optional YouTube link.
struct RoutineExercise: Codable, Equatable, Identifiable {
    let name: String
    let dose: String
    let how: String
    let video: String?

    /// Names are unique inside a routine (a test checks it).
    var id: String { name }

    var videoURL: URL? {
        return video.flatMap { URL(string: $0) }
    }

    /// True for a YouTube search link (`results?search_query=`), false for a single video.
    var isSearchLink: Bool {
        return video?.contains("results?search_query=") ?? false
    }
}

enum RoutineGroup: String, Codable, CaseIterable {
    case warmup
    case cooldown
    case strength

    var title: String {
        switch self {
        case .warmup: return "warm-up"
        case .cooldown: return "cool-down"
        case .strength: return "strength and mobility"
        }
    }
}

struct Routine: Codable, Equatable, Identifiable {
    let id: String
    let group: RoutineGroup
    let title: String
    let minutes: Int
    let when: String
    let why: String
    let exercises: [RoutineExercise]
}

struct RoutineLibrary: Codable, Equatable {
    let version: Int
    let routines: [Routine]

    func routine(id: String) -> Routine? {
        return routines.first { $0.id == id }
    }

    /// The routines of one group, in file order.
    func routines(in group: RoutineGroup) -> [Routine] {
        return routines.filter { $0.group == group }
    }
}

enum RoutineLoader {
    static func decode(_ data: Data) -> RoutineLibrary? {
        return try? JSONDecoder().decode(RoutineLibrary.self, from: data)
    }

    /// Reads `routines.json` from the bundle; nil when it is missing or does not parse.
    static func load(bundle: Bundle) -> RoutineLibrary? {
        guard let url = bundle.url(forResource: "routines", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decode(data)
    }

    /// The shipped library, read once.
    static let bundled: RoutineLibrary? = RoutineLoader.load(bundle: Bundle.main)
}

enum RoutineSuggestion {
    /// Which routines go with a plan session: (before, after).
    static func ids(for kind: SessionKind) -> (before: String, after: String?) {
        switch kind {
        case .easy, .long, .other:
            return ("warmup-easy", nil)
        case .road, .track, .timeTrial, .race:
            return ("warmup-workout", "cooldown")
        }
    }
}
