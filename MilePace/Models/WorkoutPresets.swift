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
    /// The runner's goal mile time, for the whole mile.
    case goalMile
    /// The runner's goal mile pace over the rep distance: a quarter of the goal mile per 400 m.
    case goalPace
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

    /// The spec to set up from the track screen. The mile time trial aims for the session's goal time when
    /// the plan sends one (`planTarget`), and otherwise for the runner's current mile time.
    func startSpec(zones: PaceZones, goalMile: Double, mileTime: Double, planTarget: Double? = nil) -> WorkoutSpec {
        var result = spec(zones: zones, goalMile: goalMile)
        if id == PlanSchedule.mileTrialPresetId {
            if let target = planTarget, target > 0 {
                result.targetRepSeconds = target
            } else if mileTime.isFinite, mileTime > 0 {
                result.targetRepSeconds = (mileTime * 10).rounded() / 10
            }
        }
        return result
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
        case .goalPace:
            seconds = goalMile / 4 * Double(repDistance) / 400
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
    /// Id of the short workout the test week uses.
    static let testPresetId = "4x200-test"

    static let all: [WorkoutPreset] = [
        // Short reps
        WorkoutPreset(id: "6x200-r", name: "6 × 200 @ R", group: .shortReps, reps: 6, repDistance: 200,
                      targetKind: .zone(.repetition), restSeconds: 75),
        WorkoutPreset(id: "8x200-r", name: "8 × 200 @ R", group: .shortReps, reps: 8, repDistance: 200,
                      targetKind: .zone(.repetition), restSeconds: 75),
        WorkoutPreset(id: "10x200-goal", name: "10 × 200 @ goal", group: .shortReps, reps: 10, repDistance: 200,
                      targetKind: .goalPace, restSeconds: 75),
        WorkoutPreset(id: "12x200-goal", name: "12 × 200 @ goal", group: .shortReps, reps: 12, repDistance: 200,
                      targetKind: .goalPace, restSeconds: 75),
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
                      targetKind: .goalPace, restSeconds: 180),
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
                      targetKind: .goalMile, restSeconds: 0),

        // Test week
        WorkoutPreset(id: testPresetId, name: "4 \u{00D7} 200 (test)", group: .shortReps, reps: 4, repDistance: 200,
                      targetKind: .zone(.repetition), restSeconds: 60)
    ]

    /// Goal pace per 400 m for a goal mile time ("goal 82.5/400").
    static func goalPer400(goalMile: Double) -> Double {
        return goalMile / 4
    }

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

/// How the setup sheet keeps its numbers in step when one of them changes.
enum WorkoutEditing {
    /// The rep target after the rep distance changes from `old` to `new`, keeping the same pace.
    static func rescaledTarget(_ seconds: Double, fromDistance old: Int, toDistance new: Int) -> Double {
        guard old > 0, new > 0, seconds.isFinite else { return seconds }
        return seconds * Double(new) / Double(old)
    }

    /// Rest between sets once there is more than one set: at least twice the rest between reps.
    static func setRest(current: Int, repRest: Int, sets: Int) -> Int {
        guard sets > 1 else { return current }
        return max(current, 2 * repRest)
    }
}
