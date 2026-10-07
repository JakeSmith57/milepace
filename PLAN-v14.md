# MilePace v1.14: auto-pause, treadmill mode, mile progress, effort and foot check

Builds on v1.13 (`main`, compiles and passes CI). Same constraints: Swift 5 mode, iOS 17, Xcode 16 CI,
no local compiler, Instrument design system, XcodeGen folder globs. `MARKETING_VERSION: "1.14"`;
Settings status text "v1.14". **Do not regress** v1.13 routines, v1.12 hold-to-end / hold-to-skip,
v1.11 rep time-left cues and spoken pause/resume (`Coach.announcePause`), v1.10 export and voice/click
switches, v1.9 Today-only navigation, v1.8 metronome-follows-pause.

The runner has no Apple Watch. He runs roads now, a treadmill in winter, track for workouts. He had a
tibial sesamoid fracture years ago, hence the foot check.

Implemented in two passes: **Part A** (sections 1–2) then **Part B** (sections 3–5). Each pass
self-reviews and leaves the tree compiling-clean.

---------------------------------------------------------------------------------------------------
## Part A

## 1. Auto-pause / auto-resume (outdoor runs only)
- Setting `SettingsKey.autoPause = "autoPause"`, default `true`; `AppSettings.autoPause`. Settings,
  "voice and feedback" section is wrong place — put a `CheckRow(title: "auto-pause", ...)` in a
  small new section "run" right above "voice and feedback", with note: "pauses when you stop (lights,
  traffic) and resumes when you run again. never during reps or recoveries, never on the treadmill."
- Pure detector `Models/AutoPause.swift`:
  ```swift
  struct AutoPauseDetector: Equatable {
      static let stopSpeed = 0.8      // m/s (~33:30/mi): below this counts as stopped
      static let goSpeed = 1.6        // m/s (~16:45/mi): at or above this counts as moving
      static let stopSeconds = 5.0    // stopped this long → pause
      static let goSamples = 2        // consecutive moving samples → resume
      static let maxSpeedAccuracy = 1.5   // ignore samples with speedAccuracy < 0 or above this
      enum Event: Equatable { case pause, resume }
      /// `paused` is whether the run is currently auto-paused (the caller owns phase).
      mutating func update(speed: Double, speedAccuracy: Double, at time: Date, paused: Bool) -> Event?
      mutating func reset()
  }
  ```
  Invalid samples (speed < 0, accuracy invalid/too large) are ignored entirely (they neither start
  nor break a stop window, and reset the consecutive-go count). Stop window: first valid slow sample
  time; any valid sample ≥ stopSpeed (while not paused) clears it. Emits `.pause` once when a valid
  slow sample arrives ≥ stopSeconds after the window start. While `paused`, count consecutive valid
  samples ≥ goSpeed; emit `.resume` at goSamples; a valid slower sample resets the count.
- `LocationTracker`:
  - `private(set) var autoPaused = false` (observable). `pause()` / `resume()` keep their behavior for
    manual use; add `private func autoPauseNow()` / `autoResumeNow()` which call the same internals
    and set/clear `autoPaused`, log "state auto-pause"/"state auto-resume", and call
    `Coach.shared.announcePause(paused:)` (respects the voice switch). A **manual** pause clears
    `autoPaused` and the detector never auto-resumes a manual pause. A manual resume while auto-paused
    just resumes (clears `autoPaused`).
  - Feed the detector in `handle(_:)` from each incoming `PaceSample` while `phase == .running` (not
    yet auto-paused) **and** while `phase == .paused && autoPaused` (fixes still arrive while paused;
    today they are logged as rejected). Use the sample's Doppler speed and speed accuracy (check
    `PaceSample` field names; if it lacks speedAccuracy, add it from `CLLocation.speedAccuracy` where
    samples are built).
  - Eligible only when: `AppSettings.autoPause`, not treadmill (section 2), and no road workout is in
    a rep or recovery phase (check `RoadWorkoutSession` phase names: allowed only in warmup / cooldown /
    no workout). If a workout enters a rep while auto-paused (can't really happen since the runner
    must tap start reps, but guard anyway), auto-resume immediately.
  - Reset the detector on start, manual pause/resume, stop, reset.
- RunView: when `tracker.autoPaused`, the pause button area shows "auto-paused" (the existing resume
  button still works); the big readout status says "auto-paused" instead of "paused" wherever the
  paused state is labeled. The metronome already follows `tracker.phase` (v1.8) — confirm the
  `.onChange(of: tracker.phase)` path covers auto pause/resume (it should, phase changes).
- Run draft / crash recovery: no change (pausing is just phase).
- Tests `AutoPauseTests`: steady running never pauses; 4 s slow doesn't pause, 5 s does (once);
  invalid samples ignored (don't pause on GPS garbage, don't resume on it); resume needs 2 consecutive
  fast samples; slow sample between resets; reset() clears.

## 2. Treadmill mode
- Setting `SettingsKey.runSurface = "runSurface"` with `enum RunSurface: String { case outdoor,
  treadmill }`, default outdoor. On the run screen idle setup, a ChoiceRow "surface"
  [outdoor | treadmill] above the existing mode controls. Persisted.
- Treadmill runs:
  - Need no location permission and no GPS: `LocationTracker.start()` takes the surface into account
    (e.g. `start(surface: RunSurface)` or a property set before start; keep `start()` source-compatible
    for existing callers by defaulting to outdoor). Treadmill: skip the authorization guard and never
    call `startUpdatingLocation` (stop a GPS warm-up if one is running); clock, pause/resume, cadence
    and metronome work as usual; distance stays 0 during the run unless the pedometer gives a distance
    (if `CadenceTracker`/CMPedometer can provide `distance` cheaply, expose `estimatedDistance` and show
    it as "≈ 2.31 mi" with a "pedometer" label; otherwise show only time). No pace guard, no distance
    cues, no mile splits, no map, no auto-pause. GPS status UI hidden.
  - Voice: every 5 minutes say "<N> minutes." (+ " Cadence <spm>." when known). Workout events
    (rep/rest/time-left cues) still speak.
  - Guided road workouts: only time-based specs (`length: .time`) are offered on treadmill; distance
    reps are hidden with a micro note "distance reps need gps; use a timed workout or the track."
    If the selected workout is distance-based when switching to treadmill, fall back to free mode.
  - **Treadmill speed helper**: on the idle setup and the running screen, show the target pace as
    treadmill speed: mph = 3600 / paceSecondsPerMile, 1 decimal ("8:00/mi = 7.5 mph"). For a free run
    with zone easy/threshold show the zone range as mph range; during a guided workout show the rep
    target as mph during reps and the easy range otherwise. Note once in setup: "set 1% incline to
    match outdoor effort." Pure helper `TreadmillSpeed.mph(pace:)`, `.paceText(mph:)` in Models, tested.
  - End of a treadmill run: the summary sheet shows a distance field "treadmill distance (mi)",
    prefilled with the pedometer estimate if any, else empty; saving requires a value > 0 (or allow
    0 → saves time only; prefer require > 0 with inline hint). Average pace is computed from it.
  - `RunRecord` gets `var isTreadmill: Bool = false` (SwiftData lightweight migration: default value,
    like `isTest`). Log row shows "treadmill" tag; run detail hides the map. Export (ProgressExport)
    lists "treadmill" for those runs (add `isTreadmill` to `ExportRun`, default false).
  - Plan reconciliation / weekly miles: treadmill runs count like any run.
  - Run draft (crash recovery) must carry the surface so a recovered treadmill run asks for distance
    (add a defaulted field to `RunDraft`, decoding old drafts as outdoor).
- Tests: `TreadmillSpeedTests` (8:00 → 7.5 mph, 6:00 → 10.0, round-trip text), filter of time-based
  workouts, draft decoding without the new field.

---------------------------------------------------------------------------------------------------
## Part B

## 3. Effort and foot check after every run and track workout
- `RunRecord` and `WorkoutRecord` get `var effort: Int = 0` (0 = not set, 1–10) and
  `var footPain: Int = -1` (−1 = not set, 0–10). Defaults so SwiftData migrates.
- The run summary sheet (before save) and the track results screen (before save) get two compact
  rows: "effort" — a row of 10 small tappable numbers 1…10 (selected = inverted), and "big toe /
  foot pain" — 0…10 the same way, with 0 labeled "none". Both optional; saving without them is fine.
  Build one reusable `Views/ScaleRow.swift` (`ScaleRow(title:, range:, selection: Binding<Int>,
  unsetValue:)`), keep it small.
- If foot pain ≥ 4 is chosen: an inline micro note under the row: "take the next day easy or off. if
  it still hurts after 2 days or gets worse, get it checked." (No blocking.)
- Run/workout detail screens in Log show the two values and allow editing them with the same rows.
- Log rows: append " · rpe 7" and " · foot 3" when set (foot only when ≥ 1).
- Today: if the most recent run or workout in the last 3 days had foot pain ≥ 4, show a small plan-
  colored card above today's session: "foot pain <n> on <day>. go easy today; skip if it still
  hurts." No other behavior change.
- Export: add effort and foot to runs and track workouts (`ExportRun`/`ExportWorkout` fields with
  defaults; print "rpe 7, foot 0" or omit when unset). Add a "## Foot" section listing every entry
  with foot ≥ 1 (date, value, run/workout), or "no foot pain logged".

## 4. Mile progress (Log screen)
- Pure `Models/MileProgress.swift`:
  ```swift
  struct MileResult: Equatable { let date: Date; let seconds: Double; let source: Source
      enum Source: Equatable { case trackTimeTrial, race, gpsBest } }
  enum MileProgress {
      /// Fastest continuous 1609 m inside a run's route (RoutePoint has moving time `t` and cumulative
      /// distance `d`). Two-pointer sliding window over points; interpolate the start so the window is
      /// exactly 1609 m. Ignores windows that span a `segmentStart` pause boundary? No — `t` is moving
      /// time so pauses are excluded already; just use t/d. nil when the route covers < 1609 m.
      static func fastestMile(route: [RoutePoint]) -> Double?
      /// Fastest continuous distance generally (400, 800, 1609, 3218, 5000).
      static func fastest(distance: Double, route: [RoutePoint]) -> Double?
      /// Track results: a WorkoutRecord-like input whose spec is a single 1609 m rep (the "mile-tt"
      /// preset or any reps*sets == 1 at 1609 m) → its rep time.
      static func trackMile(repDistance: Int, totalReps: Int, repTimes: [Double]) -> Double?
      /// Best per distance across inputs; track reps count for 400/800/1609 exactly at that distance.
      static func bests(...) -> [(distance: Double, seconds: Double, date: Date)]
  }
  ```
  Use plain inputs (no SwiftData) for testability. Exclude test-week records.
- Log screen, top of the list (above the weekly chart): `SectionHeader("mile")`, then a Swift Charts
  chart (`import Charts`; iOS 16+ available) ~180 pt tall in the Instrument style (mono axis labels,
  1 pt lines, black/white, the electric blue only for the actual results):
  - y axis: mile time m:ss, **faster at the top** (reverse the scale), domain from goal − 10 s to the
    slower of 7:10 or the slowest point + 10 s.
  - Goal line: horizontal dashed RuleMark at `AppSettings.goalMile` labeled "goal 5:30".
  - Plan line: the plan's time trial and race sessions' `targetSeconds` at their scheduled dates, as a
    thin dashed line with small hollow points ("plan"). (Real plan, not test plan.)
  - Results: track time trials / races as filled blue points (connected by a line); GPS-run fastest
    miles only when that run is within 15 s of the latest track result or faster than it (otherwise
    they're easy-run noise) as small hollow squares.
  - Empty state (no results yet): show plan line + goal + "first time trial: <date>".
- Under the chart, a compact readout list "bests": 400 m, 800 m, 1 mi, 2 mi, 5 km — each best time
  with date (from track reps where the rep distance matches exactly, and GPS routes); "—" when none.
- Under that, one line: "latest mile 6:52 · goal 5:30 · 1:22 to go". Latest = most recent track
  time trial/race mile, else the mile time setting.
- When a new GPS best mile is set at the end of a run (faster than every earlier best and faster than
  the mile time setting), the run summary shows "new best mile in a run: 6:41". It never changes the
  training paces by itself (only track time trials offer new paces, as today).
- Export: add a "## Mile progress" section: latest, goal, bests table, and each time trial vs plan
  target.

## 5. Tests (Part B)
- `MileProgressTests`: sliding window on a synthetic route (constant pace → exact; a fast middle
  section found; < 1 mile → nil; interpolation correctness within 0.5 s), trackMile detection,
  bests merge picks the fastest and keeps its date, GPS noise filter rule.
- `ScaleRow` has no logic worth testing; foot-warning "last 3 days ≥ 4" rule as a pure helper with
  tests (`FootCheck.warning(entries:now:) -> (value: Int, date: Date)?`).
- Export tests updated for new fields/sections. Keep all existing tests passing.

## Done criteria (each pass)
Self-review all edited files (exact signatures, MainActor, SwiftData defaults, view body sizes,
Charts API: `Chart { LineMark/PointMark/RuleMark }`, `.chartYScale(domain:)` with reversed domain or
`.chartYScale(domain: .automatic(reversed: true))` — pick an API that exists in iOS 17 SDK and say
which). Append to HANDOFF.md (append only) and README field notes. Report files, deviations,
least-confident spots. Don't commit.
