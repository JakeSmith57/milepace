# MilePace v1.9: one home screen (Today), no tab bar

Builds on v1.8 (`main`, compiles and passes CI). Same constraints: Swift 5 mode, iOS 17, Xcode 16 CI,
no local compiler, Instrument design system. `MARKETING_VERSION: "1.9"`; SettingsView status right
text "v1.9". **Do not regress v1.8** (metronome pause, voice picker, test week, drafts, reminders).

The runner decided the app should be just Today. Run, track, log and settings stop being tabs and
become screens opened from Today. Their contents and behavior stay the same.

## 1. Navigation (ContentView)
- Remove the `TabStrip` from the layout (delete the `TabStrip` view; keep `AppTab` as the screen enum,
  rename nothing else, so `requestedTab`, `RunView(isActive:)`, `TrackSetupView(isActive:)` keep working).
- Keep the existing ZStack of live layers (RunView must stay alive during a run). `selection == .today`
  shows Today; any other value shows that screen on top of Today (same `TabLayer` modifier). Remove the
  keyboard show/hide tracking, which only existed for the tab strip.
- Add to `PlanStore` a tiny API used everywhere instead of setting `selection` directly:
  `func open(_ screen: AppTab)` → sets `requestedTab = screen`; `func goHome()` → `requestedTab = .today`.
  ContentView's existing `onChange(of: requestedTab)` applies and clears it. `pendingRoute` handling
  stays as is (still opens .run / .track).
- **Never leave a recording**: `goHome()` / a requested `.today` (e.g. a tapped notification) is
  ignored while `store.runInProgress || store.trackInProgress`; ContentView guards this. A pure helper
  `ScreenRouting.resolve(current: AppTab, requested: AppTab, runInProgress: Bool, trackInProgress: Bool) -> AppTab`
  (in Models) decides: while a run is in progress the result is always `.run`; while a track session
  is in progress it is always `.track` (the session itself is a fullScreenCover there anyway);
  otherwise `requested`. Unit-test it.

## 2. Back to Today
- Run, track setup, log and settings screens get a `[ today ]` accessory first in their StatusLine
  (`StatusAccessory(title: "today") { store.goHome() }`), shown only when leaving is allowed:
  run screen only while `tracker.phase == .idle` and no summary sheet is up; others always.
  Existing accessories ([ diag ], [ map ]/[ data ]) follow it.
- Leaving the idle run or track screen keeps today's existing "forget the session the route opened"
  behavior (driven by `isActive` → false, already implemented).
- **After finishing**: when the run summary sheet closes (save or discard) → `store.goHome()`. When a
  track session's results screen is closed after saving → `store.goHome()` (TrackSetupView's
  fullScreenCover onDismiss / completion closure). Do not go home when the run save failed and the
  draft card is shown (stay on the run screen so the card is visible).

## 3. Today additions
- StatusLine accessories on Today: `[ log ]` → `open(.log)`, `[ set ]` → `open(.set)`. Keep existing
  left/center/right texts and the test tag.
- **Other** section at the bottom of the scroll content, shown always (before plan start, rest days,
  after the plan): `SectionHeader("other")` then two plain BracketButtons side by side:
  `[ free run ]` → clear any active session (`store.discardActive()`), set
  `store.pendingRoute = .freeRun` (check the exact PlanRoute case shape and the RunView apply path so a
  free run starts in free mode) and open `.run`; `[ track workout ]` → `discardActive()` then `open(.track)`
  (the preset list).
- **Unfinished work cards**: run and track drafts used to be visible only on their tabs. On Today, at
  the top of the content, show an inverted card when `RunDraftStore.load() != nil` ("unfinished run
  from <time>") with `[ open ]` → `open(.run)` (the run screen already shows the save/discard card),
  and likewise when `TrackSessionDraftStore.load()` (exact name: check) returns a draft
  ("unfinished track workout") with `[ open ]` → `open(.track)`. Reload these on appear, on scenePhase
  active, and when `requestedTab` returns to `.today`. Respect the test-week filtering the run/track
  screens already apply to drafts (reuse their logic; don't duplicate rules — if the screens filter by
  `isTest`, extract a small shared helper).
- Today's existing "start" button flow is unchanged (it sets pendingRoute; ContentView opens the screen).

## 4. Other places that referenced tabs
- Grep for `TabStrip`, `AppTab`, `requestedTab`, "tab" in user-facing text (notes like "run tab",
  "track tab", reminder bodies, README) and update wording: "run screen", "track screen", or just
  "open the app". Reminder default tap already goes to `.today` — keep.
- Settings test-week section and Today countdown buttons unchanged.

## 5. Tests
- `ScreenRoutingTests`: run in progress forces `.run` for any request; track in progress forces
  `.track`; neither → requested; requested `.today` while idle → `.today`.
- Keep all existing tests passing.

## Done criteria
Self-review all edited files (exact signatures, MainActor, view body sizes). Append one short "v1.9"
section to HANDOFF.md (re-read from disk first, append only). README field note. Report files,
deviations, least-confident spots. Don't commit.
