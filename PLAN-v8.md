# MilePace v1.6 (finish): complete PLAN-v7 + review fixes + pace window setting

Branch `v1.6-wip` contains a partial implementation of `PLAN-v7.md`. **Read PLAN-v7.md in full** — it
is the main spec. Section A (plan data, push back, matching, dates) and parts of B are implemented
in the working tree; sections C, D, E, F and the rest of B are not (LocationTracker, CadenceTracker,
Metronome, Coach, TrackWorkout, PaceZones are unchanged from v1.5). First audit what's done against
PLAN-v7 item by item, then finish everything that's missing, plus the additions below.

The runner confirmed (Oct 5): race **Mon June 21, 2027** (fixed), smart push back as in A2/A3,
count track workouts toward weekly miles (estimated, A7), and the pace changes below.

Constraints unchanged: Swift 5 mode, iOS 17, Xcode 16 CI, no local compiler, Instrument design
system, `MARKETING_VERSION: "1.6"`. The v1.5 build on `main` compiles and passes; this branch has
never been compiled, so treat everything on it as unverified and review it as hard as new code.

## Additions beyond PLAN-v7

### G1. Never lose a run (HIGH)
- **On stop**: `RunView.endRun` inserts the `RunRecord` immediately (with route, cadence, workoutName)
  and calls `try modelContext.save()`, then opens the summary sheet on that saved record. The sheet's
  "[ save run ]" just updates notes and saves; "[ discard ]" requires a confirming second tap
  (`[ yes, discard ]`) and deletes the record. Plan completion happens on stop (it already saved).
- **During the run**: every 30 s of moving time (and on scene phase → background), write a draft
  snapshot `RunDraft { start: Date, distance, moving elapsed, splits, route, cadenceSteps, workoutName }`
  as JSON to `Application Support/run-draft.json` (atomic write). Delete it on stop.
- **On launch**: if a draft exists and no run is active, the run tab shows an inverted block
  "unfinished run from <time>: 2.41 mi, 18:52" with `[ save it ]` (creates a RunRecord from the draft)
  and `[ discard ]` (two-tap). Pure `RunDraft` Codable + tests for encode/decode and record mapping.
- Track workouts: `modelContext.save()` after insert as well (and PLAN-v7 D6 persistence).

### G2. Pace window setting (replaces PLAN-v7 C10's fixed ±5)
- New setting `@AppStorage("paceWindowSeconds")` Double, default **8**, range **3…15**, step 1.
  Meaning: the pace guard/meter/verdict target is at least `mid ± window` s/mi.
- `PaceZones.guardRange(_ r: ClosedRange<Double>, window: Double) -> ClosedRange<Double>`: if the
  range's half-width is < `window`, return `mid − window … mid + window`; otherwise unchanged (so the
  wide easy zone stays as is). Use it everywhere PLAN-v7 C10 says, reading the setting through
  `AppSettings.paceWindow`. Goal ranges become goal ± window.
- Settings → "voice and feedback": a `StepperRow`/slider-style control "target window  ±8 s/mi"
  with `[−]`/`[+]`, plus a micro dim note: "how far off target before you hear speed up / slow down.
  wider = fewer cues." Also expose the same control on the run idle screen under the pace guard
  choice (it's the same setting).
- Tests: guardRange with window 8 on a 5-s-wide range → ±8 around mid; on the easy range → unchanged;
  window 3 → ±3 only when narrower.

### G3. Metronome interruptions
On `AVAudioSession.interruptionNotification` **began**: stop the engine, set `isRunning = false`,
remember `wasRunningBeforeInterruption`, release the session via the coordinator. On **ended** with
`.shouldResume`: restart if it was running. The UI must never show "♩" while silent.

### G4. Diagnostics panel when idle
On the idle run screen the diagnostics panel must not cover `[ start ]`: place it between the setup
controls and the start button (scrollable), or collapse it to a 3-line summary while idle.

### G5. Consistent weekly miles
Log's weekly chart and "this week" header use the same A7 calculation as Today (runs + estimated track
workouts, calendar Mon–Sun). One shared pure function used by Today, Log and the Sunday reminder.

### G6. Time-trial text
`PlanText` for time trials shows the session's `targetSeconds` ("target ≤ 6:35"), and "goal 5:30"
only for the race. Same text in reminders.

### G7. Pace zones for slower times
Extend `PaceZones` beyond the 6:52 anchor by adding a 7:30 (450 s) anchor row: easy 610–675,
threshold 512–518, interval 470–476, rep/400 110–112; clamp range becomes 330…450. Settings valid
mile range per PLAN-v7 E (5:00–8:30). Keep existing PaceZonesTests passing (they test anchors at
412 and below and clamping; if a clamp test asserts 420 → 412 row, update only that assertion and say so).

## Process
1. Audit PLAN-v7 vs code; list done / partial / missing.
2. Implement missing items + G1–G7.
3. Slow self-review of every file changed on this branch vs `main` (`git diff main`), not just your
   edits: exact signatures across files, MainActor isolation, Codable, SwiftData defaults (new
   `RunRecord` properties must have declaration defaults), exhaustive switches, view body size.
4. Hand-trace new tests; python-check plan.json; pyyaml-check project.yml.
5. README + HANDOFF v1.6 notes. Don't touch workflows or AppIcon. Don't commit.
