# MilePace v1.13: routines (warm-ups, drills, cool-downs, stretches, strength)

Builds on v1.10 (`main`, compiles and passes CI). Same constraints: Swift 5 mode, iOS 17, Xcode 16 CI,
no local compiler, Instrument design system, XcodeGen folder globs. `MARKETING_VERSION: "1.13"`;
Settings status text "v1.13". **Do not regress v1.10** (export, voice/click switches) or v1.9
(Today as only home screen, `[ today ]` accessories, routing guards).

Content is already written: `MilePace/Resources/routines.json` (don't change its text; fix only JSON
errors if any). Confirm it gets bundled the same way `plan.json` does (check project.yml resources).

## 1. Model — `Models/Routines.swift` (pure)
```swift
struct RoutineExercise: Codable, Equatable, Identifiable {
    let name: String; let dose: String; let how: String; let video: String?
    var id: String { name }
    var videoURL: URL? { video.flatMap(URL.init(string:)) }
    /// true for a YouTube search link (results?search_query=), false for a single video.
    var isSearchLink: Bool
}
enum RoutineGroup: String, Codable, CaseIterable { case warmup, cooldown, strength
    var title: String  // "warm-up", "cool-down", "strength and mobility" }
struct Routine: Codable, Equatable, Identifiable {
    let id: String; let group: RoutineGroup; let title: String; let minutes: Int
    let when: String; let why: String; let exercises: [RoutineExercise] }
struct RoutineLibrary: Codable, Equatable { let version: Int; let routines: [Routine]
    func routine(id: String) -> Routine?
    func routines(in group: RoutineGroup) -> [Routine] }   // file order
enum RoutineLoader { static func load(bundle: Bundle) -> RoutineLibrary?   // like PlanLoader
                     static func decode(_ data: Data) -> RoutineLibrary? }
enum RoutineSuggestion {
    /// Which routines go with a plan session: (before, after).
    /// easy/long/other → ("warmup-easy", nil); road/track/timeTrial/race → ("warmup-workout", "cooldown").
    static func ids(for kind: SessionKind) -> (before: String, after: String?)
}
```
Ids must exist in the JSON (test it).

## 2. Screens
- `AppTab` gains `case routines` (screen enum; add to ContentView's layer stack like `.log`, using the
  same `TabLayer` modifier; `ScreenRouting.resolve` unchanged and still forces run/track during
  recordings — add a test that `.routines` is overridden while a run is in progress).
- `Views/RoutinesView.swift` — the library: StatusLine left "milepace", center "routines", accessory
  `[ today ]` → `store.goHome()`. Scroll content: for each `RoutineGroup` a `SectionHeader(group.title)`
  then one row per routine: `ReadoutRow(key: routine.title, value: "\(minutes) min >")` as a button
  pushing the detail as a `.sheet` (Today/Log aren't in a NavigationStack; check and match how
  Settings presents VoicePickerView). Under the list one micro note: "videos open in youtube. links
  marked 'search' show a few options to pick from."
- `Views/RoutineDetailView.swift` (sheet): StatusLine center = routine title, accessory `[ close ]`.
  Micro text block with `when` and `why`. Then each exercise as a block: name (body mono), dose
  (right-aligned readout style, like ReadoutRow value), `how` (micro, wraps), and when there is a URL a
  small `BracketButton(title: isSearchLink ? "videos" : "video", minHeight: 44, fullWidth: false,
  size: .micro)` that opens the URL with `@Environment(\.openURL)` (YouTube app opens if installed).
  Tapping an exercise row toggles a check mark (a simple `[x]`/`[ ]` prefix in the name), state only
  in `@State` (resets when the sheet closes) — it's a follow-along checklist, nothing saved.
  A `[ reset ]` BracketButton at the bottom clears the checks when any are checked.
  Keep the view body small (split rows into subviews).

## 3. Entry points
- Today, "other" section: add a third button `[ routines ]` → `store.open(.routines)` (layout: if
  three side by side gets cramped, put `[ routines ]` full width on its own row below the two).
- Today's session card (the planned session for today, not done yet): below the start/mark done/skip
  controls, a single micro line of two small text buttons, using the existing `TextBracketButton`
  style the card already uses: `warm-up` and, when the suggestion has one, `cool-down`. Each opens
  `RoutineDetailView` for `RoutineSuggestion.ids(for: session.kind)` as a sheet directly from Today.
  Don't show it on rest days or for a done/skipped session.
- Run screen idle setup and track setup screens: nothing new (keep them uncluttered).

## 4. Tests
- `RoutinesTests`: the bundled-style JSON decodes (load it from the app bundle via
  `Bundle(for:)`/`Bundle.main` as existing PlanLoader tests do — check how plan.json is loaded in tests;
  if tests can't reach the app bundle, read the file via `#file`-relative path the same way, or decode
  a small inline sample and separately assert the shipped file decodes if possible); every routine has
  ≥1 exercise; ids unique; every `RoutineSuggestion` id for every `SessionKind` exists in the library;
  `isSearchLink` true for a `results?search_query=` URL and false for a `watch?v=` URL; every
  non-nil video string parses as a URL with host containing "youtube.com".
- ScreenRouting test for `.routines` as above. Keep all existing tests passing.

## Done criteria
Self-review all edited files (exact component signatures — grep `TextBracketButton`, `BracketButton`,
`ReadoutRow`, `StatusLine`, `SectionHeader`; MainActor; view body sizes; `openURL` usage). Append a
short "v1.13" section to HANDOFF.md (append only) and a README field note. Bump MARKETING_VERSION.
Report files, deviations, least-confident spots. Don't commit.
