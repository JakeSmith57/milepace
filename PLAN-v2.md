# MilePace v1.1: pace coaching, cadence metronome, run maps

This builds on the shipped v1.0 (see `PLAN.md`, `HANDOFF.md`, `.github/copilot-instructions.md`).
v1.0 compiles and passes CI. **Do not regress it.** Same constraints as before: Swift 5 language mode,
iOS 17 deployment target, Xcode 16 on CI, no compiler available locally, so write conservative code
and self-review hard. Keep existing public APIs and tests working; extend, don't rewrite.

Set `MARKETING_VERSION: "1.1"` in `project.yml`.

---

## Feature 1: Voice pace coaching

### 1a. Distance cues (quarter / half / full mile)

New pure file `MilePace/Models/DistanceCues.swift`:

```swift
enum CueInterval: String, CaseIterable, Identifiable { case off, quarter, half, mile
  var meters: Double? // nil for .off; quarter = metersPerMile/4, etc.
  var title: String   // "Off", "¼ mi", "½ mi", "1 mi"
  var spokenName: String // "Quarter", "Half", "Mile" }

struct DistanceCueTracker {
  init(intervalMeters: Double)
  /// Feed cumulative distance and moving elapsed time; returns cues for every interval boundary
  /// crossed since the last call (linear interpolation of the crossing time between calls).
  mutating func update(distance: Double, elapsed: Double) -> [DistanceCue]
}
struct DistanceCue: Equatable { let index: Int; let splitSeconds: Double; let paceSecondsPerMile: Double }
```

- `index` is 1-based. `paceSecondsPerMile = splitSeconds / intervalMeters * metersPerMile`.
- First call just anchors (distance 0 → no cue). Multiple boundaries crossed in one call each get a cue.

Wiring (in `LocationTracker`): keep a `DistanceCueTracker?` created in `start()` from
`AppSettings.cueInterval` (nil when `.off`). After each `handle(samples)` batch call
`update(distance: calculator.totalDistance, elapsed: calculator.elapsed(at: lastSampleTimestamp))`
and forward each cue through a new `@ObservationIgnored var onDistanceCue: (@MainActor (DistanceCue) -> Void)?`.
Use the sample's own timestamp, not `Date()`.

Speech (`Coach.announceDistanceCue(_:interval:zone:)`):
- If the interval is `.mile`: do NOT also speak the existing mile announcement twice. Rule: when
  `cueInterval == .mile`, distance cues replace `announceMile`; when `cueInterval` is quarter/half,
  on cues whose cumulative distance lands on a whole mile, speak the existing mile announcement
  instead of the short cue. When `.off`, keep v1.0 behavior (`announceMiles` setting controls mile cues).
- Short cue text: "Quarter 3. Pace 7 05." then, if a target zone is active, append
  "On target." / "4 seconds fast." / "6 seconds slow." comparing pace to the zone (fast if below
  lowerBound, slow if above upperBound, delta to the nearest bound, whole seconds, min 1).
- Spoken numbers use existing `spokenCompact`.

### 1b. Guided road workouts

New pure file `MilePace/Models/RoadWorkout.swift`.

```swift
enum RepLength: Codable, Equatable { case time(seconds: Int), distance(meters: Double) }
enum RepTarget: String, Codable, CaseIterable { case threshold, interval, goal }
  // pace range: threshold → zones.threshold, interval → zones.interval,
  // goal → (AppSettings.goalMile - 3)...(AppSettings.goalMile + 3)
struct RoadWorkoutSpec: Codable, Equatable, Identifiable, Hashable {
  var id: String { name }; var name: String; var reps: Int; var length: RepLength
  var target: RepTarget; var recoverySeconds: Int }
enum RoadWorkoutPresets { static let all: [RoadWorkoutSpec] }
```

Presets (all target `.threshold` unless noted), matching the training plan:
3×5 min (2:00 rec), 4×5 min (2:00), 4×6 min (2:00), 3×8 min (2:00), 2×10 min (2:00), 3×10 min (2:00),
2×12 min (2:00), 2×15 min (3:00), 4×5 min (1:00), 1×15 min tempo (0), 1×20 min tempo (0),
1×25 min tempo (0), 3×1 mi (1:00, distance 1609.344), 3×1.5 mi (2:00, distance 2414.016).
Names like "3 × 10 min threshold", "20 min tempo", "3 × 1 mi threshold".

Session state machine (pure, testable), `struct RoadWorkoutSession`:

```swift
enum Phase: Equatable { case warmup, rep(Int), recovery(Int), cooldown }  // rep/recovery are 1-based
enum Event: Equatable {
  case repStarted(Int, total: Int)
  case halfway(Int)                      // once per rep, at 50% of time or distance
  case repEnded(Int, avgPace: Double?)   // avg pace over the rep (sec/mi) from distance/time deltas
  case recoveryCountdown(Int)            // fires once each at 10, 3 seconds remaining
  case workoutComplete
}
init(spec: RoadWorkoutSpec)
private(set) var phase: Phase
mutating func startReps(elapsed: Double, distance: Double) -> [Event]    // warmup → rep 1
mutating func skip(elapsed: Double, distance: Double) -> [Event]         // ends current rep/recovery early
mutating func update(elapsed: Double, distance: Double) -> [Event]       // call each tick and after samples
func remaining(elapsed: Double, distance: Double) -> (seconds: Double?, meters: Double?)
```

Rules: warmup lasts until `startReps`. Rep ends at its time/distance; then recovery (if
`recoverySeconds > 0` and not the last rep) else next rep or cooldown. After the last rep →
`.workoutComplete`, phase `.cooldown`, run continues normally until the user ends it. Recovery always
by time. `update` must be idempotent if called twice with the same values and must emit each event once.
`elapsed` is moving time (pauses excluded), so pausing freezes the workout naturally.

Coaching during a workout (in `Coach`):
- `repStarted`: "Go. Rep 2 of 4. 6 minutes at threshold." / "… 1 mile at threshold."
- `halfway`: "Halfway."
- `repEnded`: "Rep 2 done. Average 7 05." + zone verdict as in 1a (vs the rep's target range).
- `recoveryCountdown`: "10 seconds" / "3, 2, 1" (speak "3, 2, 1" at the 3-second event).
- `workoutComplete`: "Workout complete. Cool down easy."
- While in a rep, run the existing `ZoneGuard` against the rep target range, but with tighter timings:
  make `ZoneGuard` configurable via `init(outsideSecondsRequired: Double = 20, minSecondsBetweenCues: Double = 60)`
  (keep the static defaults for existing tests) and use 12 s / 30 s during reps. During warmup,
  recovery and cooldown, no zone cues. Reset the guard at each rep start.
- Distance cues (1a) are suppressed during a rep when the rep is ≤ 2 minutes from ending (avoid talking
  over the rep-end cue); simplest acceptable rule: suppress distance cues entirely while a workout
  session exists and phase is `.rep` or `.recovery`.

`LocationTracker` gets `@ObservationIgnored`-free observable state for the UI:
`private(set) var workout: RoadWorkoutSession?` and methods `beginWorkout(_ spec:)` (called before
`start()`), `startReps()`, `skipPhase()`. It runs `workout.update` on each 1-second tick and after each
sample batch, forwarding events through `@ObservationIgnored var onWorkoutEvent: (@MainActor (RoadWorkoutSession.Event) -> Void)?`.
Clear `workout` in `stop()`/`reset()`. `RunSummary` gets `workoutName: String?`.

UI (`RunView` idle screen): add a segmented "Mode" picker: **Free run** | **Workout**.
- Free run: existing pace-guard picker (None/Easy/Threshold).
- Workout: a list/menu of `RoadWorkoutPresets.all`, each showing name and target pace range
  ("7:58–8:03 /mi"). Selected workout persists in `@AppStorage("roadWorkoutName")`.

Active screen when a workout exists: a banner card above the pace tile showing phase title
("Warm-up", "Rep 2 of 4", "Recovery", "Cool-down"), a large countdown (time remaining `M:SS`, or
distance remaining `0.62 mi`), and the target range during reps. The current-pace color uses the
rep target during reps. Buttons inside the banner: during warm-up a big green **Start Reps**; during
rep/recovery a small **Skip**. Keep Pause / Hold-to-End as they are.

### 1c. Settings
Add to Settings "Voice and feedback": `Picker("Pace cues every", selection: $cueInterval)` over
`CueInterval` (default `.half`). Keep "Announce each mile" (applies only when cue interval is Off).

---

## Feature 2: Cadence + metronome

### 2a. Cadence measurement
New `MilePace/Services/CadenceTracker.swift`, `@Observable @MainActor final class CadenceTracker`
wrapping `CMPedometer`:
- `static var isAvailable: Bool { CMPedometer.isCadenceAvailable() && CMPedometer.isStepCountingAvailable() }`
- `start(at:)`, `stop()`, published `currentSPM: Double?` (from `currentCadence` steps/s × 60; nil if
  missing) and `steps: Int`. Pedometer handler runs off-main: capture plain values, then
  `Task { @MainActor in ... }`.
- `averageSPM(movingSeconds:) -> Double?` = steps / movingSeconds × 60 when movingSeconds ≥ 60.
- Info.plist: add `NSMotionUsageDescription` = "MilePace uses motion data to measure your running cadence (steps per minute)."
- Owned by `LocationTracker` (create in init, start/stop alongside the run, pause does not stop it).
  Expose `cadence` on the tracker so views read `tracker.cadence.currentSPM`. `RunSummary` gets
  `averageCadence: Double?`.

Run screen: a "Cadence" `BigMetricTile` next to Time showing `"172"` with unit `"spm"` (or `"--"`).

### 2b. Shared audio session
New `MilePace/Services/AudioSessionCoordinator.swift`, `@MainActor final class AudioSessionCoordinator`
singleton. Coach currently configures and deactivates the session itself; that would kill a running
metronome. Replace it with reference counting:
- `beginSpeech()` / `endSpeech()`, `beginMetronome()` / `endMetronome()`.
- Whenever counts change, apply: category `.playback`; mode `.voicePrompt` if metronome count == 0
  else `.default`; options `[.mixWithOthers, .duckOthers]` while speech count > 0, else `[.mixWithOthers]`;
  `setActive(true)` when any count > 0; when both reach 0, `setActive(false, options: .notifyOthersOnDeactivation)`.
  Wrap calls in `do/catch` and ignore errors (log with `print` only in DEBUG).
- Coach: `speak` → `beginSpeech()`; utterance finished/cancelled → `endSpeech()` (keep its pending counter logic but delegate the session work).

### 2c. Metronome
New pure file `MilePace/Models/ClickTrack.swift`:
```swift
enum ClickTrack {
  static let bpmRange: ClosedRange<Int> = 140...200
  /// One beat of mono Float samples: a 25 ms click (1,800 Hz sine, exponential decay) then silence.
  static func beatSamples(bpm: Int, sampleRate: Double) -> [Float]
}
```
Length must equal `Int((sampleRate * 60 / Double(bpm)).rounded())`; peak amplitude ≤ 0.9; everything
after the click is exactly 0.

New `MilePace/Services/Metronome.swift`, `@Observable @MainActor final class Metronome` singleton:
- `AVAudioEngine` + `AVAudioPlayerNode`; format = mainMixer output sample rate, 1 channel. Build an
  `AVAudioPCMBuffer` from `ClickTrack.beatSamples`, `scheduleBuffer(buffer, at: nil, options: .loops)`.
- `private(set) var isRunning`, `var bpm: Int` (didSet restarts if running), `var volume: Float` (0.1–1.0, sets `player.volume`).
- `start()`: `AudioSessionCoordinator.shared.beginMetronome()`, attach/connect once, `engine.start()`, schedule, `play()`.
- `stop()`: stop player + engine, `endMetronome()`.
- Observe `.AVAudioEngineConfigurationChange` and `AVAudioSession.interruptionNotification` (ended →
  restart if it was running). Use `NotificationCenter` closure observers; hop to MainActor.
- Background playback works via the existing `audio` background mode.

UI: On the Run idle screen, a "Metronome" row: toggle, BPM stepper (step 2, within `ClickTrack.bpmRange`),
showing "166 spm". Settings section "Metronome": default BPM (`@AppStorage("metronomeBPM")`, default 166),
volume slider (`@AppStorage("metronomeVolume")`, default 0.6). On the active run screen show a small
metronome chip ("♩ 166") that toggles it on/off and a **"Set to my cadence +5%"** button that appears
once the run has ≥ 2 minutes and a cadence average: sets BPM to `round(avg × 1.05)` rounded to the
nearest even number and clamped to the range. Metronome starts with the run if the toggle is on, and
stops when the run ends.

Note in the UI footer (Settings → Metronome): "A slightly quicker, shorter stride reduces impact per
step. Raise cadence gradually, about 5% at a time."

---

## Feature 3: Run maps

### 3a. Recording the route
Extend `PaceCalculator` (pure) with `private(set) var route: [RoutePoint]`:
```swift
struct RoutePoint: Codable, Equatable { var lat: Double; var lon: Double; var t: Double /*moving elapsed s*/; var d: Double /*cumulative m*/ }
```
- Append the first accepted anchor sample, then any accepted sample that is ≥ 10 m (cumulative
  distance) past the last stored point. On re-anchor after a long jump, append the new anchor too and
  start a new segment: add `var segmentStart: Bool` defaulting to false (true for the first point and
  for each re-anchor / resume after pause).
- `resume(at:)` marks the next appended point `segmentStart = true`.
- Must not change any existing behavior/outputs of the calculator.

`RunSummary` gets `route: [RoutePoint]`. `RunRecord` gets `var routeData: Data = Data()` and
`var averageCadence: Double = 0` (**defaults in the declaration** so SwiftData lightweight migration
works for existing stores), a computed `route: [RoutePoint]` (JSON decode, `[]` on failure), and the
initializer gains optional `route: [RoutePoint] = []`, `averageCadence: Double = 0` params.
`RunRecord(... )` call sites (RunView.save, manual add) keep compiling.

### 3b. Pace coloring (pure)
New `MilePace/Models/RouteSegments.swift`:
```swift
enum PaceBand: Int, CaseIterable { case faster, steady, slower }   // relative to the run average
struct ColoredSegment: Identifiable { let id: Int; let band: PaceBand; let points: [RoutePoint] }
enum RouteSegments {
  /// Splits the route into runs of consecutive points with the same band. Each point's pace is
  /// computed over the surrounding ±2 points (time delta / distance delta × metersPerMile).
  /// faster: pace < average − 10 s; slower: pace > average + 10 s; else steady.
  /// Adjacent segments share their boundary point so the line is continuous. A point with
  /// segmentStart == true always begins a new segment and is not joined to the previous one.
  static func colored(_ route: [RoutePoint], averagePace: Double) -> [ColoredSegment]
  static func mileMarkers(_ route: [RoutePoint]) -> [(mile: Int, point: RoutePoint)]  // first point at/after each whole mile
}
```

### 3c. Map view
New `MilePace/Views/RunMapView.swift` using the iOS 17 SwiftUI MapKit API:
```swift
Map(initialPosition: .automatic) {
  ForEach(segments) { seg in MapPolyline(coordinates: seg.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) })
                               .stroke(color(seg.band), lineWidth: 5) }
  Marker("Start", systemImage: "flag", coordinate: start).tint(.green)
  Marker("Finish", systemImage: "flag.checkered", coordinate: end).tint(.red)
  ForEach(mile markers) { Annotation("", coordinate: …) { Text("\(mile)").font(.caption2.bold()).padding(4).background(.orange, in: Circle()).foregroundStyle(.white) } }
}
.mapStyle(.standard(elevation: .flat))
```
Colors: faster `.green`, steady `.orange`, slower `.blue`. Below the map a one-line legend.
Shown (height ~260, rounded corners) at the top of `RunSummaryView` and `RunDetailView` when the route
has ≥ 2 points; otherwise nothing. RunDetailView also shows average cadence when > 0.
No live map during the run.

---

## Tests (add; keep all existing tests passing)
- `DistanceCuesTests`: quarter-mile cues at 4 m/s fire at the right indices with ≈ correct splits;
  multiple boundaries in one update; `.off` has nil meters.
- `RoadWorkoutTests`: 2 × 60 s reps with 30 s recovery driven by `update` every second → exact event
  sequence (repStarted 1, halfway 1, repEnded 1, countdown 10, countdown 3, repStarted 2, halfway 2,
  repEnded 2, workoutComplete); distance-based rep ends on distance; `skip` ends a rep early; calling
  `update` twice with the same values emits nothing new; no recovery after the last rep.
- `ClickTrackTests`: length for 166 bpm @ 48 kHz; tail zeros; peak ≤ 0.9; non-silent click.
- `RouteTests`: route downsampling at ≥ 10 m; segmentStart on resume; `RouteSegments.colored` bands
  on a synthetic route with a fast middle section; boundary sharing; mile markers.
- `ZoneGuard` custom timings.

## Done criteria
- All new and existing files compile-checked by careful review (types, imports: CoreMotion, MapKit,
  AVFoundation; MainActor hops; exhaustive switches; Codable conformance; `Hashable` where used in
  `ForEach`/`Picker` tags).
- Info.plist validated with plistlib; project.yml still valid YAML; no `.xcodeproj` committed.
- Update `README.md` "Field notes" with 3 bullets (workouts, metronome, maps) and `HANDOFF.md`
  with a short "v1.1" section listing new files.
- Report: file list, deviations, least-confident spots.
