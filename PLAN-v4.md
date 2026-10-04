# MilePace v1.3: the training plan, built in

Builds on v1.2 (`PLAN.md`, `PLAN-v2.md`, `PLAN-v3.md`). v1.2 compiles and passes CI. **Do not regress it.**
Same constraints: Swift 5 mode, iOS 17, Xcode 16 CI, no local compiler, so write conservative
code and self-review hard. Use the Instrument design system (`MilePace/Design/*`) for every new screen.
Set `MARKETING_VERSION: "1.3"`.

Problem: the app knows the workouts but not the schedule. The runner opens the track tab and doesn't
know what to do today. v1.3 adds the full 48-week plan, a **today** tab, and missed-day handling.

---

## 1. Plan data (already generated, don't hand-edit)

`MilePace/Resources/plan.json` is the full plan:
```json
{ "name": "5:30 mile plan", "startDate": "2026-10-12",
  "weeks":    [ { "week": 1, "miles": 5, "phase": 1, "recovery": false, "timeTrial": false, "race": false }, ... 48 ],
  "sessions": [ { "week": 1, "weekday": 2, "phase": 1, "kind": "easy", "miles": 1.5, "title": "1.5 mi easy", "note": "..." }, ... 219 ] }
```
- `weekday`: 1 = Monday … 7 = Sunday (plan weeks start Monday; Oct 12 2026 is a Monday).
- `kind`: `easy | long | road | track | timeTrial | race`. (`other` may appear in future data; decode
  unknown values as `.other` instead of failing.)
- `road` sessions have `preset` = a `RoadWorkoutSpec.name` from `RoadWorkoutPresets.all` (exact string).
- `track`, `timeTrial`, `race` sessions have `preset` = a `WorkoutPreset.id`. `timeTrial` and `race` use
  `mile-tt` (race target = goal mile 5:30).
- `miles` present for easy/long. `note` optional.
- Sessions are in chronological order; their array index is their stable id.

### New track presets (add to `WorkoutPresets.all`, same style as existing ones)
| id | name | reps × dist | target | rest |
|----|------|-------------|--------|------|
| `10x200-r` | 10 × 200 @ R | 10 × 200 | R scaled | 75 s |
| `3s-3x300-r` | 3 sets × 3 × 300 @ R | sets 3, reps 3 × 300 | R × 0.75 | 30 s, set rest 240 s |
| `3x400-goal` | 3 × 400 @ goal | 3 × 400 | goal (82.5 s) | 180 s |
| `3x800-i` | 3 × 800 @ I | 3 × 800 | I | 120 s |
| `4x1000-i` | 4 × 1000 @ I | 4 × 1000 | I | 150 s |
| `6x400-82` | 6 × 400 @ 82s | 6 × 400 | fixed 82.5 s | 120 s |
| `1x1200-412` | 1200 @ 4:12 | 1 × 1200 | fixed 252 s | 0 |

`sharpener` intentionally has no preset (mixed distances). For any track session whose preset id isn't
found, the today screen shows the note and a "[ open track ]" button that opens the custom builder.

## 2. Model (pure, testable): `MilePace/Models/TrainingPlan.swift`
```swift
struct PlanFile: Codable { let name: String; let startDate: String; let weeks: [PlanWeek]; let sessions: [PlanSession] }
struct PlanWeek: Codable, Equatable { let week: Int; let miles: Double; let phase: Int; let recovery: Bool; let timeTrial: Bool; let race: Bool }
enum SessionKind: String, Codable { case easy, long, road, track, timeTrial, race, other  /* custom init(from:) → .other on unknown */ }
struct PlanSession: Codable, Equatable { let week: Int; let weekday: Int; let phase: Int; let kind: SessionKind
  let title: String; let miles: Double?; let preset: String?; let note: String? }

enum SessionStatus: String, Codable { case done, skipped }
struct PlanShift: Codable, Equatable { let fromIndex: Int; let days: Int }
struct PlanProgress: Codable, Equatable { var shifts: [PlanShift] = []; var statuses: [Int: SessionStatus] = [:] }
// NOTE: [Int: X] encodes as a JSON array of alternating keys/values with JSONEncoder; that's fine as long as
// encode/decode use JSONEncoder/JSONDecoder consistently. Or store statuses as [String: SessionStatus].

struct PlanSchedule {
  let plan: PlanFile; let progress: PlanProgress
  /// Days from plan start (start = 0) for session i: (week-1)*7 + (weekday-1) + sum(days of shifts with fromIndex <= i)
  func dayOffset(_ index: Int) -> Int
  func indices(onDay day: Int) -> [Int]
  func status(_ index: Int) -> SessionStatus?
  /// Oldest session with dayOffset < today and no status. nil if none.
  func firstMissed(today: Int) -> Int?
  /// Sessions scheduled for `today` with no status.
  func todays(today: Int) -> [Int]
  /// Next session strictly after today (any status nil).
  func next(after today: Int) -> Int?
  /// Plan week (1…48) to display for `today`: the week of todays/next session; 0 before start; 48 after the end.
  func currentWeek(today: Int) -> Int
  var raceDayOffset: Int  // dayOffset of the race session
  /// New progress after choosing "do it today" for a missed session: adds PlanShift(fromIndex: missed, days: today - dayOffset(missed)).
  func pushingBack(missed: Int, today: Int) -> PlanProgress
  func skipping(_ index: Int) -> PlanProgress
  func markingDone(_ index: Int) -> PlanProgress
  /// Marks done every unstatused run session whose scheduled day has a logged activity day in `activityDays`.
  func reconciled(activityDays: Set<Int>) -> PlanProgress
}
enum PlanCalendar {  // date ↔ day-offset conversion, Gregorian, local time zone, start of day (DST safe: use Calendar.dateComponents([.day], from:to:) between startOfDay values)
  static func dayOffset(of date: Date, start: Date) -> Int
  static func date(forOffset: Int, start: Date) -> Date
  static func parse(_ ymd: String) -> Date?   // "2026-10-12"
}
```

## 3. Store: `MilePace/Services/PlanStore.swift`
`@Observable @MainActor final class PlanStore` singleton:
- Loads `plan.json` from `Bundle.main` once (fail → `plan = nil`, today screen shows "plan file missing").
- `startDate` from `@AppStorage`-backed UserDefaults key `planStartDate` (default from the file, 2026-10-12).
- `progress: PlanProgress`, persisted as JSON in UserDefaults key `planProgress` on every change.
- `schedule: PlanSchedule?`, `todayOffset` (recomputed on the 1-minute scene/timer refresh and when the
  app becomes active).
- `activeSessionIndex: Int?`: set when a session is started from the today screen. When a run or
  workout is **saved** (RunView.save, track workout save), call `PlanStore.shared.completeActive()`,
  which marks it done and clears it. Discarding clears it without marking.
- `reconcile(runDates: [Date], workoutDates: [Date])`: converts to day offsets and applies
  `reconciled(activityDays:)`. Called by TodayView `.onAppear` and `.onChange` of the record counts
  (use `@Query` in TodayView).
- Routing for "start": `pendingRoute: PlanRoute?` with
  `enum PlanRoute: Equatable { case freeRun(zone: RunZoneTarget), roadWorkout(name: String), track(presetId: String?) }`.
  ContentView observes it: switches the tab (run or track) and the target screen applies it on appear /
  onChange (RunView: sets mode, zone or selected workout; TrackSetupView: opens the setup sheet for that
  preset, or the custom builder when nil/not found), then sets `pendingRoute = nil`.
  easy/long → `.freeRun(zone: .easy)`; road → `.roadWorkout(name:)`; track/timeTrial/race → `.track(presetId:)`.
- `resetProgress()`.

## 4. Color: "plan" purple
Add `Theme.plan` = `#8B1EFF` (both modes), text on it `Theme.onSignal` (white). Meaning: **scheduled /
from the plan**. Blue keeps meaning **on target right now**. Purple is a fill only, never text on bg.
Used for: today's session block, the "[ start ]" button on the today screen, the "[ do it today ]"
button, today's cell in the week strip, "planned" tags on the track tab.

## 5. Today tab (new first tab): `MilePace/Views/TodayView.swift`
TabStrip becomes `today run track log set`; app opens on today.

Layout (top to bottom):
1. `StatusLine("milepace", "week 3 / 48", "phase 1")`; before start: "starts oct 12"; after race: "done".
2. **Missed card** (if `firstMissed`): inverted block (fg fill, bg text):
   "missed tue oct 20" / session title. Buttons: "[ do it today ]" (plan fill) and "[ skip ]" (plain,
   bordered in bg color on the inverted block). Below, micro text:
   "doing it today moves the rest of the plan back 2 days. race moves to sat sep 13."
   One missed session at a time, oldest first.
3. **Today block** (plan fill, onSignal text), one per today session (usually one):
   micro "today", title in `.title` size (wrap allowed), then micro lines: target miles for easy/long
   ("2 mi, conversational, 9:35–10:30 /mi" using current easy zone), for road: target range for the
   rep target, for track: rep target per rep (from the preset's spec), for time trial/race: the note
   plus "goal 5:30". `note` line if present. Buttons inside: "[ start ]" (inverted: fg fill on the
   purple) and "[ mark done ]", "[ skip ]" as small plain text buttons.
   Rest day: bg block with "rest or cross-train" and body text "tennis or an easy ride is fine." and
   "next: thu oct 15  1.5 mi easy".
   Before plan start: "plan starts mon oct 12" + "in 8 days" + the week-1 list. Also on any day of
   week 1, show a micro line: "see a doctor about your foot before running past week 4."
4. **Week strip**: 7 equal cells Mon–Sun; each cell: micro day letter row ("m t w t f s s") and a short
   label ("e2", "lg3", "trk", "rd", "tt", "race", "·" for rest). Today's cell plan-filled; done cells
   show "x" in a fg box (inverted); skipped show "–"; past missed show "!". Under the strip micro text:
   "this week 4.2 / 6 mi" (logged run miles in this plan week's 7 days vs `PlanWeek.miles`), plus
   "recovery week" or "time trial saturday" tags when flagged.
5. "[ full plan ]" BracketButton → `PlanOverviewView`.

## 6. Plan overview: `MilePace/Views/PlanOverviewView.swift`
ScrollView of 48 weeks grouped by phase (SectionHeader "phase 1  build running legs", "phase 2  aerobic
power", "phase 3  mile-specific", "phase 4  sharpen and race"). Each week row:
"wk 03  oct 26  8 mi" with tags "rec" / "tt" / "race"; the current week is plan-filled; past weeks
dim. Tap → week detail: the week's sessions as ReadoutRows (key "tue oct 27", value title, status).
Top shows race day: "race  sat sep 11" (shifted date).

## 7. Track tab ties-in
- If today has a track/timeTrial/race session: a plan-filled banner at the top of TrackSetupView:
  "today: 6 × 400 @ R  [ start ]".
- In the preset list, presets scheduled within the next 14 days get a small plan-filled tag
  "tue oct 20" (the nearest date).
- The run tab: if today's session is easy/long/road, a slim plan-filled bar at the top of the idle run
  screen: "today: 3 × 5 min threshold  [ set up ]" (applies the route).

## 8. Time trial → new paces
When a `mile-tt` workout is saved (TrackSessionView save path), show a confirmation sheet (Instrument
style): "mile 6:31" / "update training paces from 6:52 to 6:31?" "[ update paces ]" (signal) /
"[ keep 6:52 ]". Update writes `SettingsKey.mileTime`. Only offer when the time is within
`AppSettings.validMileRange`.

## 9. Settings
Section "plan": ReadoutRow "start" with a compact `DatePicker` (date only) bound to `planStartDate`;
"[ reset plan progress ]" with a confirmation step ("[ yes, reset ]" appears after the first tap).

---

## Tests (add; keep all existing tests passing)
- `TrainingPlanTests` with an inline mini plan JSON (2 weeks, 5 sessions):
  - decoding; unknown kind decodes as `.other`;
  - `dayOffset` without shifts; `pushingBack` shifts that session and all later ones but not earlier;
    two stacked shifts add up;
  - `firstMissed` ignores done/skipped and future sessions; `todays`; `next(after:)`;
  - `reconciled` marks a session done only when its day has activity, never rest days, never already
    skipped ones;
  - `currentWeek` before start (0), mid plan, after end (48);
  - `PlanCalendar` round-trip across a DST change (e.g. start 2026-10-12, offset 27 → 2026-11-08).
- `BundledPlanTests`: load the real `plan.json` via `Bundle(for: PlanStore.self)` (hosted tests);
  48 weeks; sessions sorted by (week, weekday); every `road` preset name exists in
  `RoadWorkoutPresets.all`; every track/timeTrial/race preset id exists in `WorkoutPresets.all`
  except `sharpener`; exactly one `race` session in week 48.

## Done criteria
- plan.json is in the app bundle (XcodeGen resource), Info.plist unchanged except nothing needed.
- Every new screen uses Instrument components; no SF Symbols, rounded corners, system colors.
- Self-review for compile errors (exact signatures across files, MainActor use, exhaustive switches over
  `SessionKind`, Codable conformance). Validate plan.json parses with python.
- Update README field notes (today tab, missed days) and HANDOFF.md (v1.3 section).
- Report: files added/changed, deviations, least-confident compile spots.
