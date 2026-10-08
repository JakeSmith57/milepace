# MilePace v1.16: track assist — voice coaching, plain targets, GPS auto-lap

Builds on v1.15 (`main`, compiles and passes CI). Same constraints: Swift 5 mode, iOS 17, Xcode 16
CI, no local compiler, Instrument design, XcodeGen globs. `MARKETING_VERSION: "1.16"`; Settings status
"v1.16". **Do not regress** v1.15 routes, v1.14 (auto-pause, treadmill, mile progress, effort/foot),
v1.13 routines, v1.12 holds, v1.11 cues, v1.10 export/voice switch, v1.9 nav, v1.8 metronome pause.

Runner feedback from his first lap-timer session (4 × 200 test): "I go 200 m then click lap myself,
what is the 55.5 target, is it time? Can we have voice cues, can the phone measure distance or tell
me how many laps to go? Too much is manual, not enough assistance and auto."

## 1. Plain language on the track screens (TrackSetupView + TrackSessionView)
- Every target shows units and meaning: "55.5 s" → **"target 55.5 s per 200 m"**; lap targets
  "lap 1 target 1:44.0". Never a bare number.
- Distance in laps of a 400 m track, pure helper `TrackLaps.describe(meters:) -> String`:
  200 → "half a lap", 300 → "¾ of a lap", 400 → "1 lap", 600 → "1½ laps", 800 → "2 laps",
  1000 → "2½ laps", 1200 → "3 laps", 1609 → "4 laps + 9 m". Shown under the rep distance on setup and
  on the session header ("rep 2 of 4 · 200 m · half a lap").
- Where to start: setup shows one micro line per distance: 200 → "start anywhere; finish half a lap
  later (directly across the track)"; 400+ → "start and finish at the same line". Lane note: "run in
  lane 1 (inside); lane 2 adds ~7 m per lap."
- The ready screen explains in 2 short lines: "tap [ start ] (or let the countdown run) to begin rep 1.
  the phone ends each rep for you by gps, or tap [ lap ] at the line for an exact time."
- Results table headers spelled out: "rep · time · target · ±".

## 2. Voice coaching (default on)
- Defaults change: `trackCountdown` true (already), `lapFeedback` default **true** for new and existing
  users who never touched it (register-defaults change is enough since it was never explicitly set
  for most; do not overwrite an explicit stored false — `UserDefaults.object(forKey:) == nil` check).
- New Coach lines (all through `speak`, respecting the voice switch; reasons for diagnostics):
  - Before each rep (on start / when rest ends): "Rep 2 of 4. 200 meters. Target 55 seconds." then
    the existing 3-2-1 "Go". Target spoken as whole seconds when ≥ 60 → "1 minute 44".
  - Halfway cue for reps ≥ 400 m (GPS mode only, section 3): "Halfway. 52. On pace." / "2 seconds
    fast." / "3 seconds slow." (on pace = within ±1 s of the pro-rated target).
  - "100 to go." in GPS mode at rep distance − 100 m for reps ≥ 300 m (once).
  - Rep done: "55.8. Half a second slow." / "54.1. 1 second fast." / "On target." (±0.5 s); then
    "Rest 60 seconds." For the last rep: "Last rep done. Average 55.2." and nothing about rest.
  - Rest: "30 seconds." when rest ≥ 60, "10 seconds." always, then the existing countdown + go.
  - Before the final rep: "Last one."
- Delta wording helper (pure, tested): `TrackSpeech.delta(_ seconds: Double) -> String`
  ("On target." / "Half a second fast." / "1 second slow." / "2.3 seconds fast." — one decimal above 1 s
  only when not a whole number; "half a second" for 0.5±0.05).
- Existing per-lap feedback (`announceLap(delta:)`) stays for multi-lap reps but uses the same wording.

## 3. GPS auto-lap (default on, outdoor track only)
- New `@MainActor @Observable` service `Services/TrackGPS.swift` (separate from LocationTracker, which
  belongs to road runs): owns its own `CLLocationManager` (best accuracy, background allowed while a
  session runs), feeds samples into a fresh `PaceCalculator` (reuse its filtering; check its API) and
  exposes `repDistance` (meters since the current rep started, calibrated) and `gpsState`.
- Calibration: GPS on a track typically misreads distance by a few percent. Before the first rep the
  ready screen offers `[ calibrate: run 1 lap ]` (optional, recommended): runner jogs one lap in lane 1,
  tapping `[ lap ]` at start and finish; factor = 400 / measured, clamped 0.85…1.15, stored per track
  (UserDefaults key "trackCalibration" with date). Without calibration use factor 1.0 and say "auto-lap
  is approximate (±2 s on 200 m)". Re-calibration offered if older than 60 days.
- During a rep: when calibrated `repDistance >= rep distance` → end the rep automatically exactly as a
  final lap tap would, timestamped by interpolation between the two GPS samples straddling the
  distance (not the moment the sample arrived). Intermediate lap boundaries (every 400 m) likewise.
  A manual `[ lap ]` tap always wins: it ends the lap/rep immediately and the GPS distance resets.
  Guard: no auto-finish before 60 % of the target time has elapsed (protects against GPS jumps) and
  only with `horizontalAccuracy <= 15` on the deciding samples; otherwise wait for a tap and say once
  "GPS weak, tap at the line."
- Rest and setRest: GPS distance ignored. Resting doesn't need movement.
- Treadmill or `[ gps auto-lap ]` off (setup toggle, persisted `trackAutoLap`, default true): pure
  tap mode as today.
- The session screen shows live "128 m · 72 to go" during a rep (GPS mode), else "tap at the line".
- Results mark auto-ended reps with a small "gps" tag and manual ones nothing; times saved the same.
- Location permission: reuse the app's existing authorization; if not authorized, auto-lap row shows
  "allow location for auto-lap" and the session works in tap mode.
- Background: allowsBackgroundLocationUpdates true only while the session is live; stop updates on
  finish/close.

## 4. Auto-start (less tapping)
- Setup toggle "auto-start reps" (default on): after `[ start ]` on the ready screen, a 10 s spoken
  countdown starts rep 1 ("Rep 1 of 4 ... 3, 2, 1, go"). Between reps the rest ends with the countdown
  and the next rep starts by itself (already the case if the timer drives it — verify; if a tap is
  currently required to start reps after rest, make it automatic when this toggle is on).

## 5. Tests
`TrackLapsTests` (descriptions), `TrackSpeechTests` (delta wording, target wording, rep intro text,
halfway verdict), `TrackAutoLapTests` on a pure helper `TrackAutoLap` (crossing interpolation between
two samples, 60 % time guard, accuracy guard, calibration factor clamp). Keep all existing tests.

## Done criteria
Grep every API (TrackWorkout state machine, TrackSessionView tap handling and drafts, Coach, PaceCalculator,
CLLocationManager on iOS 17); MainActor; small view bodies; drafts (TrackSessionDraft) keep working —
add an `autoEnded` per-rep flag only if needed, with defaults for old drafts. Append HANDOFF.md
section and README note. Don't commit.
