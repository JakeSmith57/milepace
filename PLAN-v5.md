# MilePace v1.4: plan reminders (local notifications)

Builds on v1.3 (`PLAN-v4.md`). v1.3 compiles and passes CI. **Do not regress it.** Same constraints:
Swift 5 mode, iOS 17, Xcode 16 CI, no local compiler, Instrument design system for UI.
Set `MARKETING_VERSION: "1.4"`.

Use **local** notifications (`UserNotifications`, `UNCalendarNotificationTrigger`). No server, no APNs,
no entitlement or capability changes. The app schedules a rolling window of reminders from the plan
and rebuilds it whenever anything changes.

## 1. Reminders
All text lowercase, like the app. Times are user settings.

| id prefix | when | condition | title | body |
|---|---|---|---|---|
| `plan.morning.<day>` | each day with an unstatused session, at morning time (default **08:00**) | morning on | `today: <session title>` | kind-specific detail line (same as the today block: e.g. "conversational, 9:35–10:30 /mi" / "reps 102–104 s, warm up 1–2 mi first" / "target ≤ 6:35. full warm-up."). If a missed session exists as of scheduling time, append " also missed: <weekday> <title>." |
| `plan.evening.<day>` | same days, at evening time (default **17:00**) | evening on, session not done/skipped | `still on the plan: <title>` | `log it, or open the app to skip or move it.` |
| `plan.tt.<day>` | the day before each `timeTrial` or `race` session, at evening time + 1 hour (default 18:00) | time-trial reminder on | `time trial tomorrow` / `race tomorrow` | `keep today short and easy. target ≤ 6:35.` (race: `goal 5:30. lay out your shoes.`) |
| `plan.week.<day>` | each plan-week's Sunday at 18:00 | weekly summary on | `week <n>: <logged> / <planned> mi` | `next week: <miles> mi<, recovery week><, time trial sat><, race sat>.` |
| `plan.start` | plan start day at morning time, only before the plan starts | morning on | `week 1 starts today` | `three short easy runs this week. see a doctor about your foot before week 5.` |

Rules:
- Window: today through today + 13 days; never schedule anything in the past (compare to `now`).
  Stay under iOS's 64 pending limit (cap at 60; drop the furthest-out first).
- Days use the **shifted** plan schedule (`PlanSchedule.dayOffset`), so pushing back moves reminders.
- Rest days: no morning/evening reminder.
- "logged" miles for the weekly summary = run miles saved in that plan week's 7 calendar days (as of
  scheduling time; rescheduling after every save keeps it current).
- Category `PLAN_SESSION` on morning/evening reminders with two actions: `MARK_DONE` ("mark done")
  and `SKIP` ("skip"); `userInfo["sessionIndex"] = index`.

## 2. Pure planner: `MilePace/Models/ReminderPlanner.swift`
```swift
struct ReminderSettings: Equatable { var enabled: Bool; var morning: Bool; var evening: Bool
  var timeTrial: Bool; var weekly: Bool; var morningMinutes: Int /*480*/; var eveningMinutes: Int /*1020*/ }
struct ReminderSpec: Equatable { let id: String; let dayOffset: Int; let minutes: Int /*since midnight*/
  let title: String; let body: String; let category: String?; let sessionIndex: Int? }
enum ReminderPlanner {
  static func build(schedule: PlanSchedule, todayOffset: Int, nowMinutes: Int, settings: ReminderSettings,
                    loggedMilesByDay: [Int: Double], zones: PaceZones, goalMile: Double,
                    windowDays: Int = 14, cap: Int = 60) -> [ReminderSpec]
}
```
- `nowMinutes` = minutes since local midnight now; skip same-day specs whose minutes ≤ nowMinutes.
- Returns sorted by (dayOffset, minutes). `enabled == false` → `[]`.
- Detail-line text comes from one shared pure helper that the today screen also uses (extract it from
  TodayView into `PlanText.detail(for:zones:goalMile:) -> String` in Models; update TodayView to call it).

## 3. Service: `MilePace/Services/Reminders.swift`
`@MainActor final class Reminders` singleton (+ `NSObject, UNUserNotificationCenterDelegate`):
- `authorization: UNAuthorizationStatus` (observable; refresh on app active).
- `requestPermission()` → `requestAuthorization(options: [.alert, .sound, .badge])`, then reschedule.
- `reschedule()`: if not authorized or plan missing → remove all pending with prefix `plan.` and
  return. Else: build specs via `ReminderPlanner`; `removePendingNotificationRequests(withIdentifiers:)`
  for all current `plan.` ids; add each spec as `UNNotificationRequest` with
  `UNCalendarNotificationTrigger(dateMatching: [year, month, day, hour, minute], repeats: false)` built
  from `PlanCalendar.date(forOffset:start:)`. Debounce: coalesce calls within 1 s (a Task with sleep).
  Log the count to `Diagnostics` ("reminders scheduled 23").
- Register category `PLAN_SESSION` with actions `MARK_DONE` and `SKIP` (no `.foreground` option).
- Delegate (nonisolated methods, hop to MainActor):
  - `willPresent` → present `[.banner, .sound]` only for `plan.tt.` and `plan.week.`; suppress others
    while the app is open.
  - `didReceive`: action `MARK_DONE` → `PlanStore.shared.markDone(index)`; `SKIP` →
    `PlanStore.shared.skip(index)`; default tap → `PlanStore.shared.requestedTab = .today`
    (add that observable property; ContentView switches tabs on change). Always call the completion
    handler.
- Set `UNUserNotificationCenter.current().delegate = Reminders.shared` at launch via a
  `UIApplicationDelegateAdaptor` AppDelegate (`didFinishLaunchingWithOptions`).

Call `Reminders.shared.reschedule()` when: app becomes active (scenePhase), PlanStore progress
changes (done/skip/push back/reset/reconcile), plan start date changes, reminder settings change,
pace settings change (mile time), and after a run or workout is saved or deleted.

## 4. UI
- **Today tab**: if authorization is `.notDetermined`, a bordered card under the week strip:
  "reminders" / "a note at 8:00 am with today's session, and a nudge at 5:00 pm if it isn't logged." /
  "[ turn on reminders ]" (plan fill). If `.denied`: "reminders are off in ios settings" +
  "[ open settings ]". Hidden when authorized.
- **Settings**: section "reminders": CheckRow "reminders" (master), CheckRows "morning: today's
  session", "evening nudge if not logged", "day before time trials", "sunday summary"; ReadoutRows with
  compact `DatePicker(.hourAndMinute)` for morning and evening times (stored as minutes since midnight
  in `@AppStorage` Ints: `reminderMorningMinutes` 480, `reminderEveningMinutes` 1020). A ReadoutRow
  "scheduled" showing the pending count (from `getPendingNotificationRequests`), and "[ send a test ]"
  which schedules a one-off notification 5 s out titled "test: reminders work".
- Settings keys in `SettingsKey`/`AppSettings` with defaults: enabled true, morning true, evening
  true, timeTrial true, weekly true.

## 5. Tests (add; keep everything passing)
`ReminderPlannerTests` with an inline mini plan (reuse the TrainingPlanTests JSON helper style):
- morning + evening for each unstatused session day in the window; none on rest days;
- done/skipped session → no evening (and no morning) reminder;
- same-day reminders earlier than `nowMinutes` are dropped;
- time-trial session at day D → `plan.tt.<D-1>` at evening + 60 min;
- weekly summary title uses logged / planned miles;
- missed session text appended to the next morning body;
- `enabled = false` → empty; cap respected (cap: 3 → 3 earliest);
- a push-back shift moves the reminder days.

## Done criteria
- `import UserNotifications` where used; delegate methods' exact signatures for iOS 17
  (`userNotificationCenter(_:willPresent:withCompletionHandler:)` and
  `userNotificationCenter(_:didReceive:withCompletionHandler:)`, completion handlers called exactly once).
- No new Info.plist keys are required for local notifications; don't add any.
- README field notes + HANDOFF.md v1.4 section.
- Report: files added/changed, deviations, least-confident compile spots.
