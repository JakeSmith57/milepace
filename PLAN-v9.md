# MilePace v1.7: test week (practice run of the plan before it starts)

Builds on v1.6 (`main`, compiles and passes CI). Same constraints: Swift 5 mode, iOS 17, Xcode 16 CI,
no local compiler, Instrument design system. `MARKETING_VERSION: "1.7"`. **Do not regress v1.6.**

The runner wants to try the whole app this week (before the real plan starts Mon Oct 12, 2026) as if
the plan had started, without any of that data carrying into the real plan.

## 1. What the test week is
- A synthetic one-week plan built in code (not plan.json): `TestWeek.plan(startingOn day: Date) -> PlanFile`
  in `MilePace/Models/TestWeek.swift` (pure). `version` = 1000 (distinct from the real plan's), name
  "test week". It covers the calendar Mon–Sun week containing the start day; sessions on days before the
  start day are omitted. Sessions (weekday → session), all short and gentle so they can be done easy or
  even walked; titles end with nothing special, the UI adds the "test" tag:
  - Mon: easy, 1.0 mi, "1 mi easy", note "test the run screen, voice cues and map."
  - Tue: road, preset "2 × 2 min threshold (test)", note "test a guided workout. jog it if you like."
  - Thu: track, preset "4x200-test", note "test the lap timer. walking is fine."
  - Fri: easy, 1.5 mi, "1.5 mi easy + metronome", note "turn on the metronome."
  - Sat: timeTrial, preset "mile-tt", targetSeconds = current mile setting, title "practice time trial",
    note "optional. test the time trial flow; jog it."
  - Wed, Sun: rest. One `PlanWeek` (week 1, miles = sum of easy miles + 1, phase 1).
  If the start day is late in the week (Sat/Sun) and fewer than 2 sessions remain, include the *next*
  calendar week instead only if it ends before the real plan start; otherwise just what remains.
- New presets: road `RoadWorkoutSpec(name: "2 × 2 min threshold (test)", reps: 2, length: .time(seconds: 120),
  target: .threshold, recoverySeconds: 60)` appended to `RoadWorkoutPresets.all`; track
  `WorkoutPreset(id: "4x200-test", name: "4 × 200 (test)", group: .shortReps, reps: 4, repDistance: 200, …R target…, rest 60)`.
  Existing tests that assert preset counts must be updated (say which).

## 2. Turning it on and off
- Only offered while today is before the real plan start. Settings → section "test week":
  - Off: micro note "try the plan this week. test runs and progress are deleted when the test ends or
    the real plan starts." + `[ start test week ]` (plan fill).
  - On: "test week: oct 5 – oct 11" + `[ end test week ]` (two-tap confirm `[ yes, end and delete test data ]`).
- Today tab before the plan start (countdown screen) also shows `[ start a test week ]` (plain).
- State: `@AppStorage("testWeekStart")` = "yyyy-MM-dd" or "" (off). `TestWeekStore`/`PlanStore`:
  `isTestWeek: Bool`. While on, `PlanStore` uses the test `PlanFile`, a separate progress key
  `testPlanProgress`, and everything downstream (today tab, week strip, missed card, push back,
  reconcile, reminders, plan overview, track/run plan bars) works exactly as with the real plan.
- **Auto end**: when `todayOffset` (03:00 boundary) reaches the real plan's start day, or the test
  week's Sunday has passed, the test week ends automatically on next refresh/launch (same cleanup
  as manual end). Never end during an active run or track session; defer to after it.

## 3. Keeping test data separate
- `RunRecord.isTest: Bool = false`, `WorkoutRecord.isTest: Bool = false` (declaration defaults for
  SwiftData migration). Every record created while the test week is on gets `isTest = true` (run save on
  stop, run draft recovery, track save, finished-track-draft auto-save, manual "add miles"). RunDraft and
  TrackSessionDraft carry `isTest` too (Codable default false).
- While the test week is on, test records appear normally (log, weekly miles, maps) so the runner can
  test those screens, with a small "test" tag on log rows.
- **Cleanup on end**: delete all `isTest == true` RunRecords and WorkoutRecords, `try save()`; delete
  `testPlanProgress`; clear `testWeekStart`; clear any run/track draft marked `isTest`; reset
  `activeSessionIndex`; reschedule reminders (removes test `plan.*` notifications and delivered ones).
  The real `planProgress` key is never read or written while the test week is on.
- Settings changes (mile time, pace window, voices, metronome) are real settings and persist (say so
  in the note). Exception: the time-trial "update paces?" sheet during the test week shows
  "practice: paces not changed" and only offers `[ ok ]`.
- Real-plan reconcile must ignore `isTest` records (they're deleted anyway, but filter defensively),
  and test-week reconcile only considers `isTest` records.

## 4. UI marking
- While on: status lines on today/run/track show a plan-filled tag "test" (micro) in the right slot or
  next to the left label; the today block's micro header reads "today  test week".
- Reminders during the test week prefix titles with "test: ".

## 5. Tests
- `TestWeekTests`: Monday start → 5 sessions on Mon/Tue/Thu/Fri/Sat; Thursday start → Thu/Fri/Sat only;
  time trial target equals the passed mile time; presets referenced exist; version ≠ real version.
- PlanStore-level pure logic (put it in a pure helper `TestWeekLifecycle`): `shouldAutoEnd(today:testStart:realStart:)`
  true on/after the real start day and after the test Sunday, false during; deferred when a session is active.
- Record filtering helper: given records with isTest flags, real-plan activities exclude tests,
  test-week activities include only tests.
- Update preset count assertions as needed.

## Done criteria
Self-review all edited files (exact signatures, MainActor, SwiftData defaults, Codable defaults,
exhaustive switches). Keep HANDOFF.md edits to appending one short "v1.7" section (re-read the file
from disk first, append only; don't rewrite it). README field note. Report files, test changes,
deviations, least-confident spots. Don't commit.
