# MilePace v1.10: progress export for review, separate voice and click switches

Builds on v1.9 (`main`, compiles and passes CI). Same constraints: Swift 5 mode, iOS 17, Xcode 16 CI,
no local compiler, Instrument design system, XcodeGen folder globs (new files need no registration).
`MARKETING_VERSION: "1.10"`; SettingsView status right text "v1.10". **Do not regress v1.9** (Today as
the only home screen, `[ today ]` accessories, routing guards, metronome pause, voice picker, drafts,
test week, reminders).

The runner wants to (a) export everything the app knows about his training as one file and attach it
to a chat with his coach (Claude), who reviews progress and updates the plan; (b) mute the voice and
the metronome click independently, including mid-run.

## 1. Voice master switch
- New setting `SettingsKey.voiceEnabled = "voiceEnabled"`, default `true` (register it),
  `AppSettings.voiceEnabled`.
- `Coach.speak` returns early (no audio session work, no utterance) when `!AppSettings.voiceEnabled`,
  **except** previews: give `speak` a parameter `force: Bool = false`; `preview(identifier:)` passes
  `true` so picking a voice still plays a sample. Still log the cue to Diagnostics with reason suffix
  " (voice off)" when skipped, so the run log shows what would have been said. Haptics are unaffected.
- When the switch turns off mid-utterance, stop current speech: in the places that flip it (below), call
  `Coach.shared.stopSpeaking()` after setting it to false.
- Settings → "voice and feedback": first row `CheckRow(title: "voice", isOn: $voiceEnabled)`. When off,
  the rows below (voice picker, cue interval, announce, pace guard, window) stay visible but add a
  micro note under the switch: "voice is off. haptics still work." Track section's rest countdown /
  lap feedback rows unchanged (they are silenced by the master switch too; add to the note:
  "also mutes the track countdown and lap feedback.").
- Metronome stays fully independent: the voice switch never touches `Metronome`, and the click switch
  never touches `Coach`.

## 2. Click switch in Settings
- Settings → "metronome" section gets `CheckRow(title: "click", isOn: $metronomeEnabled)` first
  (same `SettingsKey.metronomeEnabled` the run screen's setup row already uses, so both stay in sync).
  Changing it in Settings while no run is active only changes the default for the next run. If a run
  is active (`PlanStore.shared.runInProgress`) do not try to start/stop audio from Settings; Settings
  can't be reached mid-run anyway (v1.9 routing), so just document that.

## 3. Mid-run controls
- RunView, while `tracker.phase` is `.running` or `.paused`: a row of two `BracketButton`s side by
  side directly above the existing pause/resume + end controls (match their width rules; minHeight
  44, `.micro` size if that is how secondary buttons are styled there):
  - `[ voice on ]` / `[ voice off ]` → toggles `voiceEnabled` (persisted, same setting as Settings);
    turning off calls `Coach.shared.stopSpeaking()`.
  - `[ click on ]` / `[ click off ]` → calls the existing `toggleMetronome()` (which already handles
    the paused/suspended cases from v1.8). The title reflects the real audible state:
    "on" when `metronome.isRunning || metronome.isSuspended`, else "off".
  Keep the existing tap-on-cadence-row toggle too.
  Make sure `toggleMetronome()` also writes `metronomeEnabled` consistently (check: if it currently
  only starts/stops audio, set `metronomeEnabled` to the new state as well so the next run remembers).
- TrackSessionView (the live lap timer): add the same `[ voice on/off ]` button where it fits without
  crowding the lap button (e.g. as a StatusAccessory "voice"/"mute" in its StatusLine, or a small
  button in the header). No click there (track has no metronome).
- Accessibility labels: "voice on, double tap to mute" etc.

## 4. Progress export
### 4a. Pure builder — `Models/ProgressExport.swift`
No SwiftData / SwiftUI types in its API, so it is unit-testable. Inputs as plain structs:
```swift
struct ExportRun: Equatable { let date: Date; let distanceMeters: Double; let durationSeconds: Double
    let averagePace: Double; let splits: [Double]; let averageCadence: Double; let workoutName: String
    let notes: String; let hasRoute: Bool }
struct ExportWorkout: Equatable { let date: Date; let name: String; let spec: WorkoutSpec?
    let repTimes: [Double]; let lapSplits: [[Double]] }
struct ExportSettings: Equatable { let mileTime: Double; let goalMile: Double; let paceWindow: Double
    let metronomeBPM: Int; let metronomeEnabled: Bool; let voiceEnabled: Bool; let cueInterval: String }
struct ExportInput {
    let generatedAt: Date; let appVersion: String
    let plan: PlanFile?; let startYMD: String; let progress: PlanProgress; let schedule: PlanSchedule?
    let todayOffset: Int
    let settings: ExportSettings; let zones: PaceZones
    let runs: [ExportRun]; let workouts: [ExportWorkout]
}
enum ProgressExport {
    static func markdown(_ input: ExportInput, calendar: Calendar = PlanCalendar.local) -> String
    static func fileName(for date: Date) -> String   // "milepace-progress-2026-10-06.md"
}
```
Use the existing formatters (`ReadoutFormat`, `PlanFormat`, pace/time formatting helpers) — grep
for them; don't invent new formatting rules. Times as m:ss, paces as m:ss/mi, distances in miles
with 2 decimals, dates as yyyy-MM-dd (EEE).

Markdown content, in this order (plain, compact, meant for an AI coach and a human to read):
1. `# MilePace progress export` then lines: generated (date + time), app version, plan name +
   version, plan start date, race date, today's plan week number / total weeks and phase, and a line
   "test week active (test data excluded)" when applicable.
2. `## Settings`: current mile time, goal mile, pace zones (each zone's range as pace), pace window,
   metronome tempo + on/off, voice on/off, cue interval.
3. `## Sessions` — one markdown table for every plan session from week 1 through the end of the week
   after today's week (not the whole future plan): date (after shifts/moves, i.e. the schedule's
   actual day), week, kind, title, planned miles, target (targetSeconds as m:ss when present),
   status: `done`, `done (auto)` when in `progress.autoDone`, `skipped`, `missed` (past, no status),
   `today`, `planned`. Then a line listing shifts ("moved session X by N days") if any, and day
   overrides if any.
4. `## Weekly mileage` — table per plan week through today's week: week, phase, planned miles
   (`PlanWeek.miles`), actual miles (from runs, using the same day-bucketing the app already uses —
   reuse `PlanActivity`/`WeeklyMiles` helpers rather than re-deriving), sessions done / planned.
5. `## Runs` — newest first, every non-test run: date, distance, time, avg pace, avg cadence (or "—"),
   workout name or "free", mile splits list ("7:02, 6:58, …"), notes if non-empty, "manual" when no
   splits and no route.
6. `## Track workouts` — newest first: date, name, spec in words ("6 × 400 m @ 1:28, rest 90 s",
   include sets/set rest when sets > 1), each rep time with its delta vs target ("1:27 (−1)"), average
   rep vs target, and lap splits per rep when a rep has more than one lap.
7. `## Time trials and races` — for each plan session of kind timeTrial/race that is done, the matching
   workout (same calendar day, track workout or run) result vs `targetSeconds`. If none, "none yet".
8. A final short line: "Totals: N runs, X mi; M track workouts; since <first activity date>."

Exclude test-week data (`isTest`). If the test week is active, export the **real** plan/progress, not
the test plan: add read-only accessors on `PlanStore` (`exportPlan`, `exportStartYMD`,
`exportProgress`, plus a schedule built from them) that always return the real ones.

### 4b. UI
- Log screen (HistoryView): add `[ export ]` as a StatusAccessory after `[ today ]`. Tapping builds
  the input on the main actor from the `@Query` results + `PlanStore` + `AppSettings`, writes the
  markdown to `FileManager.default.temporaryDirectory/<fileName>` (overwrite), and presents the system
  share sheet for that file URL. Use whichever share mechanism already works in this codebase
  (DiagnosticsPanel uses `ShareLink(item: url)` with a precomputed URL; for a tap-to-build flow, a
  `.sheet` wrapping `UIActivityViewController` via `UIViewControllerRepresentable` is fine — keep it
  tiny, in `Views/ShareSheet.swift`). On failure to write, show the existing inline error style with
  "couldn't make the export file."
- Add a micro note at the top of the Log list (one line, only when there is at least one run or
  workout): "[ export ] makes a file to send to your coach." Keep it subtle.
- Today: nothing new.

## 5. Tests
- `ProgressExportTests`: fixed calendar (UTC or the test's PlanCalendar) and a tiny hand-built
  PlanFile (2 weeks, a few sessions incl. a timeTrial with targetSeconds), progress with one done,
  one autoDone, one skipped; two runs (one with splits, one manual) and one track workout with lap
  splits. Assert: section headers present in order; statuses rendered (`done (auto)`, `skipped`,
  `missed`); rep delta formatting with minus sign; sessions table stops after the week following
  today; test runs excluded (builder input already filtered — test that the caller-side filter helper
  is used, or put an `isTest` flag on ExportRun and filter in the builder; choose one and test it);
  file name format.
- `VoiceSwitch`-level logic is trivial; add one pure test if you extract any helper (e.g. a
  `MidRunAudioLabels` helper for the on/off titles). Keep all existing tests passing.

## Done criteria
Self-review all edited files (exact signatures, MainActor isolation for anything touching PlanStore,
SwiftData model access on main, view body sizes, `Transferable`/UIKit imports). Append one short
"v1.10" section to HANDOFF.md (re-read from disk first, append only). README field note. Report
files, deviations, least-confident spots. Don't commit.
