import Foundation

enum PresetGroup: String, CaseIterable, Identifiable {
    case shortReps = "Short reps"
    case fourHundreds = "400s"
    case longReps = "Long reps"
    case timeTrial = "Time trial"

    var id: String { rawValue }
    var title: String { rawValue }
}

/// How a preset's per-rep target is chosen.
enum PresetTarget: Equatable {
    /// Derived from the runner's current zones.
    case zone(PaceZoneKind)
    /// A fixed rep time in seconds.
    case fixed(Double)
    /// The runner's goal mile time.
    case goalMile
}

struct WorkoutPreset: Identifiable, Equatable {
    let id: String
    let name: String
    let group: PresetGroup
    let reps: Int
    let repDistance: Int
    let targetKind: PresetTarget
    let restSeconds: Int
    let sets: Int
    let setRestSeconds: Int

    init(id: String,
         name: String,
         group: PresetGroup,
         reps: Int,
         repDistance: Int,
         targetKind: PresetTarget,
         restSeconds: Int,
         sets: Int = 1,
         setRestSeconds: Int = 0) {
        self.id = id
        self.name = name
        self.group = group
        self.reps = reps
        self.repDistance = repDistance
        self.targetKind = targetKind
        self.restSeconds = restSeconds
        self.sets = sets
        self.setRestSeconds = setRestSeconds
    }

    /// Builds a concrete spec using the runner's current zones and goal mile.
    func spec(zones: PaceZones, goalMile: Double) -> WorkoutSpec {
        let seconds: Double
        switch targetKind {
        case .zone(let kind):
            seconds = zones.targetSeconds(distanceMeters: Double(repDistance), zone: kind)
        case .fixed(let value):
            seconds = value
        case .goalMile:
            seconds = goalMile
        }
        let rounded = (seconds * 10).rounded() / 10
        return WorkoutSpec(name: name,
                           reps: reps,
                           repDistance: repDistance,
                           targetRepSeconds: rounded,
                           restSeconds: restSeconds,
                           sets: sets,
                           setRestSeconds: setRestSeconds)
    }
}

enum WorkoutPresets {
    static let all: [WorkoutPreset] = [
        // Short reps
        WorkoutPreset(id: "6x200-r", name: "6 × 200 @ R", group: .shortReps, reps: 6, repDistance: 200,
                      targetKind: .zone(.repetition), restSeconds: 75),
        WorkoutPreset(id: "8x200-r", name: "8 × 200 @ R", group: .shortReps, reps: 8, repDistance: 200,
                      targetKind: .zone(.repetition), restSeconds: 75),
        WorkoutPreset(id: "10x200-goal", name: "10 × 200 @ goal 41s", group: .shortReps, reps: 10, repDistance: 200,
                      targetKind: .fixed(41), restSeconds: 75),
        WorkoutPreset(id: "12x200-goal", name: "12 × 200 @ goal 41s", group: .shortReps, reps: 12, repDistance: 200,
                      targetKind: .fixed(41), restSeconds: 75),
        WorkoutPreset(id: "10x200-r", name: "10 × 200 @ R", group: .shortReps, reps: 10, repDistance: 200,
                      targetKind: .zone(.repetition), restSeconds: 75),
        WorkoutPreset(id: "3s-3x300-r", name: "3 sets × 3 × 300 @ R", group: .shortReps, reps: 3, repDistance: 300,
                      targetKind: .zone(.repetition), restSeconds: 30, sets: 3, setRestSeconds: 240),

        // 400s
        WorkoutPreset(id: "6x400-r", name: "6 × 400 @ R", group: .fourHundreds, reps: 6, repDistance: 400,
                      targetKind: .zone(.repetition), restSeconds: 150),
        WorkoutPreset(id: "8x400-r", name: "8 × 400 @ R", group: .fourHundreds, reps: 8, repDistance: 400,
                      targetKind: .zone(.repetition), restSeconds: 120),
        WorkoutPreset(id: "4x400-82", name: "4 × 400 @ 82s", group: .fourHundreds, reps: 4, repDistance: 400,
                      targetKind: .fixed(82), restSeconds: 180),
        WorkoutPreset(id: "3x400-goal", name: "3 × 400 @ goal", group: .fourHundreds, reps: 3, repDistance: 400,
                      targetKind: .fixed(PaceZones.goalPer400), restSeconds: 180),
        WorkoutPreset(id: "6x400-82", name: "6 × 400 @ 82s", group: .fourHundreds, reps: 6, repDistance: 400,
                      targetKind: .fixed(82.5), restSeconds: 120),
        WorkoutPreset(id: "2s-4x400-83", name: "2 sets × 4 × 400 @ 83s", group: .fourHundreds, reps: 4, repDistance: 400,
                      targetKind: .fixed(83), restSeconds: 60, sets: 2, setRestSeconds: 300),
        WorkoutPreset(id: "4s-2x400-84", name: "4 sets × 2 × 400 @ 84s", group: .fourHundreds, reps: 2, repDistance: 400,
                      targetKind: .fixed(84), restSeconds: 60, sets: 4, setRestSeconds: 240),

        // Long reps
        WorkoutPreset(id: "3x600-125", name: "3 × 600 @ 2:05", group: .longReps, reps: 3, repDistance: 600,
                      targetKind: .fixed(125), restSeconds: 300),
        WorkoutPreset(id: "3x800-i", name: "3 × 800 @ I", group: .longReps, reps: 3, repDistance: 800,
                      targetKind: .zone(.interval), restSeconds: 120),
        WorkoutPreset(id: "5x800-i", name: "5 × 800 @ I", group: .longReps, reps: 5, repDistance: 800,
                      targetKind: .zone(.interval), restSeconds: 120),
        WorkoutPreset(id: "6x800-i", name: "6 × 800 @ I", group: .longReps, reps: 6, repDistance: 800,
                      targetKind: .zone(.interval), restSeconds: 120),
        WorkoutPreset(id: "4x1000-i", name: "4 × 1000 @ I", group: .longReps, reps: 4, repDistance: 1000,
                      targetKind: .zone(.interval), restSeconds: 150),
        WorkoutPreset(id: "5x1000-i", name: "5 × 1000 @ I", group: .longReps, reps: 5, repDistance: 1000,
                      targetKind: .zone(.interval), restSeconds: 150),
        WorkoutPreset(id: "6x1000-i", name: "6 × 1000 @ I", group: .longReps, reps: 6, repDistance: 1000,
                      targetKind: .zone(.interval), restSeconds: 150),
        WorkoutPreset(id: "1x1200-412", name: "1200 @ 4:12", group: .longReps, reps: 1, repDistance: 1200,
                      targetKind: .fixed(252), restSeconds: 0),
        WorkoutPreset(id: "4x1200-i", name: "4 × 1200 @ I", group: .longReps, reps: 4, repDistance: 1200,
                      targetKind: .zone(.interval), restSeconds: 180),
        WorkoutPreset(id: "5x1200-i", name: "5 × 1200 @ I", group: .longReps, reps: 5, repDistance: 1200,
                      targetKind: .zone(.interval), restSeconds: 180),

        // Time trial
        WorkoutPreset(id: "mile-tt", name: "Mile time trial", group: .timeTrial, reps: 1, repDistance: 1609,
                      targetKind: .goalMile, restSeconds: 0)
    ]

    static func presets(in group: PresetGroup) -> [WorkoutPreset] {
        return all.filter { $0.group == group }
    }

    /// Starting point for the custom builder: 6 × 400 at R with 2:00 rest.
    static func customSpec(zones: PaceZones) -> WorkoutSpec {
        return WorkoutSpec(name: "Custom workout",
                           reps: 6,
                           repDistance: 400,
                           targetRepSeconds: (zones.targetSeconds(distanceMeters: 400, zone: .repetition) * 10).rounded() / 10,
                           restSeconds: 120)
    }
}
