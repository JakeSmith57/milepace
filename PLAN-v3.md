# MilePace v1.2: instrument design system, faster pace, diagnostics

Builds on v1.1 (`PLAN.md`, `PLAN-v2.md`). v1.1 compiles and passes CI. **Do not regress it.**
Same constraints: Swift 5 mode, iOS 17, Xcode 16 CI, no local compiler, so write conservative
code and self-review hard. Keep existing logic/tests; the UI layer gets restyled, not re-architected.
Set `MARKETING_VERSION: "1.2"`. Reference image: `design-mockups.png` (repo root).

---

## Part A: design system "Instrument"

The app should look like a timing instrument readout: a pixel monospace typeface, pure black and
white, and one electric blue that is only ever used as a **fill**. No SF Symbols, no rounded
corners, no shadows, no system blue, no default List/Form chrome.

### A1. Font
- Add `MilePace/Resources/Fonts/DepartureMono-Regular.otf` (provided in repo root as
  `fonts/DepartureMono-Regular.otf`; move it) and `MilePace/Resources/Fonts/LICENSE-DepartureMono.txt`
  (MIT; copy from `fonts/LICENSE`). Delete the `fonts/` folder after moving.
- Info.plist: `UIAppFonts` = [`DepartureMono-Regular.otf`]. PostScript name: `DepartureMono-Regular`.
- XcodeGen picks up `.otf` under `MilePace/` as a resource automatically; verify `project.yml`
  doesn't exclude it.

### A2. Tokens: `MilePace/Design/Theme.swift`
```swift
enum Theme {
  // Colors (dynamic for light/dark via UIColor { traits in ... })
  static let bg: Color      // dark #000000, light #FFFFFF
  static let fg: Color      // dark #FFFFFF, light #000000
  static let dim: Color     // dark #7D7D7D, light #666666   (secondary text, dashed rules)
  static let signal: Color  // #0A3CFF both modes: FILLS ONLY (never text on bg)
  static let onSignal: Color// #FFFFFF
  // Type scale: Departure Mono is drawn on an 11-unit grid, so sizes are multiples of 11.
  enum Size: CGFloat { case micro = 11, body = 22, title = 33, display = 44, hero = 99, giant = 132 }
  static func mono(_ size: Size) -> Font  // Font.custom("DepartureMono-Regular", fixedSize: size.rawValue)
  // Space
  static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 16, s4: CGFloat = 24
  static let rule: CGFloat = 2          // solid fg rule / border
  static let dash = StrokeStyle(lineWidth: 1, dash: [3, 3])  // dim dashed row separators
}
```
Display preference: `@AppStorage("displayMode")` = system | dark | light, applied with
`.preferredColorScheme` at the root. Root background `Theme.bg.ignoresSafeArea()`; global
`.tint(Theme.signal)`; `.font(Theme.mono(.body))`; `.foregroundStyle(Theme.fg)`.

### A3. Rules of the system
1. **Blue is a fill, never ink.** On-target states, the active workout banner, the LAP button, the
   "rec" tag. Text on blue is `onSignal`.
2. **Off target = inversion + words.** Off-target chips are an `fg` block with `bg` text and an explicit
   word: "+1.6 slow" / "−4 fast". Never rely on color alone.
3. **Labels are lowercase**, sentence fragments: "pace now", "avg", "hold to end". No all-caps, no
   eyebrow labels above everything.
4. **Structure means something.** Solid 2 pt `fg` rule = section boundary. Dashed `dim` rule = row
   boundary in a readout. Brackets `[ ]` = tappable. Nothing decorative.
5. **One loud thing per screen**: the giant pace (Run), the LAP block (Track), the week's miles (Log).
6. **Motion**: only a blinking block cursor in the status line while GPS is searching (static when
   Reduce Motion is on), and the hold-to-end bar filling. Nothing else animates.

### A4. Components: `MilePace/Design/Components+Instrument.swift`
(Replace usages of the old `BigMetricTile`, `FilledActionButton`, `HoldToEndButton`; you may keep the
old types compiling if other code needs them, but no screen should use them.)
- `StatusLine(left:center:right:recording:)`: micro size, one line under the safe area, 2 pt fg rule
  below. When `recording`, right side shows a signal-filled "rec" tag + elapsed.
- `Banner(title:subtitle:trailing:trailingSub:)`: signal fill, body + micro text in onSignal.
- `HeroReadout(label:value:unit:size:)`: micro dim label, value in `.giant` (or `.hero`),
  `minimumScaleFactor(0.5)`, `lineLimit(1)`, tight tracking (−4); unit in body dim, baseline aligned.
- `PaceMeter(pace:zone:)`: 8 equal cells in a row. Cells 3–4 (0-based) represent the zone and are
  signal-filled. Each outside cell spans half the zone width (faster to the left, slower to the right;
  remember lower seconds = faster). The cell containing the current pace shows a fg block (`█`, or a
  fg-filled rect inset 25%); outside cells show a centered dim "·". Clamp to the end cells. Micro dim
  captions under it: "faster" / "on target" / "slower". Hidden when no zone or pace is nil.
- `ReadoutRow(key:value:)`: body size; key in dim padded with dot leaders to a fixed width (12 chars:
  `key + " " + "." * (11 - key.count)`), value right-aligned in fg; dashed dim rule below.
- `BracketButton(title:style:action:)`: text "[ title ]", 2 pt fg border, body size, full width or
  intrinsic. Styles: `.plain` (border), `.signal` (signal fill, no border, onSignal text),
  `.inverted` (fg fill, bg text). Min height 56 for run-screen buttons.
- `HoldBar(title:duration:action:)`: bordered row "hold to end" left; right a 10-char gauge that
  fills from "." to "#" while pressed (driven by a 0…1 progress state with a linear animation), fires
  after `duration` (1 s). Keep the long-press behavior of the current HoldToEndButton.
- `DeltaChip(delta:)`: display size. |delta| ≤ 1.0 → signal fill "on pace"; slower → inverted
  "+1.6 slow"; faster → inverted "−0.6 fast". Use a real minus sign "−".
- `Tape(rows:)`: split list, body size, each row "n ......  97.4 −0.6"; newest last; a dashed fg
  "tear" line at the bottom while live.
- `TabStrip(selection:)`: bottom bar, 2 pt fg rule on top, four equal text cells "run track log set";
  selected = inverted (fg fill, bg text). Height 56 + bottom safe area.
- `CheckRow(title:isOn:)`: "[x] announce each mile" / "[ ] …" (tap toggles). Replaces Toggle.
- `ChoiceRow(options:selection:)`: options laid out inline, selected inverted, others plain text.
  Replaces segmented Pickers.
- `StepperRow(title:value:range:step:format:)`: "cadence ....  [−] 166 [+]".
- `SectionHeader(_ text:)`: body size fg text + 2 pt rule below; top padding s4.

### A5. Screens
- **ContentView**: replace `TabView` with a `ZStack` holding all four screens (keep them alive; show
  the selected one with `.opacity` + `.allowsHitTesting`) plus `TabStrip` at the bottom. Tabs:
  run / track / log / set. Hide all navigation bars (`.toolbar(.hidden, for: .navigationBar)`) and
  use `StatusLine` instead; detail screens pushed in NavigationStack get a top "[ back ]" BracketButton.
- **Run idle**: StatusLine("milepace", gps state, ""). ChoiceRow free run | workout. Free run →
  ChoiceRow for pace guard none | easy | threshold with a ReadoutRow showing the range. Workout →
  list of presets as ReadoutRows (key = name truncated, value = target range), selected inverted.
  Metronome CheckRow + StepperRow. Big `.signal` BracketButton "[ start ]" (min height 80). If GPS
  not ready, the button still works; the status line shows "gps searching" with blinking cursor.
- **Run active**: per the mockup: StatusLine (gps acc, rate, rec + time), Banner when a workout is
  active, HeroReadout pace (.giant), PaceMeter, ReadoutRows avg / dist / time / cadence (cadence
  value shows "172 ♩176" when metronome on; tap the row to toggle metronome), workout "[ start reps ]"
  (signal) / "[ skip ]", "[ pause ]"/"[ resume ]", HoldBar. If diagnostics enabled, a small
  "[ diag ]" BracketButton in the status line area opens the diagnostics panel (Part C).
- **Run summary sheet**: map (if route), ReadoutRows, Tape of splits, notes TextField styled as a
  bordered box, "[ save run ]" signal, "[ discard ]" plain.
- **Track setup & session**: same components; session shows StatusLine, Banner (rep x/y, lap n,
  target, rep clock), HeroReadout "last rep" (.hero), DeltaChip, Tape of reps, and a LAP block:
  signal fill, word "lap" in `.giant`, occupying the lower ~35% of the screen. Rest: the block turns
  inverted and shows the countdown in `.giant`, with "[ go ]" (signal) when the rest is over and
  "[ skip rest ]".
- **Log (History)**: HeroReadout this week's miles (.hero, unit "mi"); weekly chart restyled: bars
  `fg` fill, current week `signal` fill, axis labels micro dim, no gridlines; runs and workouts as
  ReadoutRows (key "sat oct 17", value "2.01  10:12"), "[ add miles ]". Detail screens: map + rows.
- **Set (Settings)**: SectionHeaders + ReadoutRows/CheckRows/ChoiceRows/StepperRows. Add
  "display" ChoiceRow system | dark | light, and a "diagnostics" CheckRow (Part C).
- **Map styling**: `.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))`.
  Band colors: faster = signal, steady = fg, slower = dim. Start/finish markers: tiny squares
  (Annotation with a 10×10 fg/signal Rectangle), mile markers as micro text in an inverted box.

---

## Part B: faster, more responsive pace

### B1. GPS warm-up
`LocationTracker` gains:
```swift
enum GPSState: Equatable { case off, searching, weak(Double), ready(Double) } // accuracy in m
private(set) var gpsState: GPSState
func beginWarmup()   // if authorized and idle: startUpdatingLocation (no background flag)
func endWarmup()     // if idle: stopUpdatingLocation, gpsState = .off
```
- Ready = latest fix horizontalAccuracy ≤ 10 m and ≤ 3 s old; weak = a fix exists but worse; searching
  otherwise. Update on each location and on the 1 s timer (staleness).
- Run tab calls `beginWarmup()` on appear (when idle) and `endWarmup()` on disappear; also end warm-up
  when the scene goes to background while idle (`@Environment(\.scenePhase)` in RunView). Auto-stop
  warm-up after 3 minutes idle to save battery.
- `start()` keeps updates running (no restart) and seeds the calculator with the most recent
  good warm-up fix (≤ 3 s old, accuracy ≤ 20 m), re-stamped at the start time, so distance starts
  from where you are.
- During warm-up, samples must NOT be fed to the run calculator except that seed.

### B2. Doppler (instant) pace
- `PaceSample` gains `speedAccuracy: Double = -1` and `course: Double = -1` (defaulted init params,
  so existing call sites and tests compile). LocationTracker fills them from `CLLocation`.
- `PaceCalculator` gains:
  - `private(set) var dopplerPace: Double?` (sec/mi) and `private(set) var windowPace: Double?`
    (the existing 30 s trailing value).
  - Doppler estimate: for any sample with `speed >= 0`, `speedAccuracy >= 0 && speedAccuracy <= 1.5`,
    and `horizontalAccuracy` in 0...50 (looser than the distance gate), update an exponential
    smoother of speed with time constant τ = 4 s: `α = 1 − exp(−dt/τ)` where dt is seconds since the
    previous Doppler update (first value initializes directly). If smoothed speed < 0.6 m/s →
    `dopplerPace = nil` (standing still). Else `dopplerPace = metersPerMile / smoothedSpeed`.
  - Reset Doppler state on pause/resume/start. Doppler samples ignore the distance gate but still
    respect pause and timestamp ordering.
  - `currentPace` becomes: `dopplerPace` if it was updated within the last 3 s of sample time,
    otherwise the existing `windowPace` behavior. **When samples have speed < 0 (all existing tests),
    behavior must be identical to v1.1.**
- Result: pace shows within a few seconds of moving, and a speed change mostly shows in ~5 s.

### B3. Voice wording
Spoken text for `ZoneGuard` cues: `.easyUp` → "Slow down", `.pickItUp` → "Speed up". Keep the enum
case names (tests use them). Any other place that says "Easy up"/"Pick it up" changes too.

---

## Part C: diagnostics

### C1. Data: `MilePace/Services/Diagnostics.swift`, `@Observable @MainActor final class Diagnostics` singleton
- Live values: `lastAccuracy`, `lastSpeedAccuracy`, `lastSpeed`, `sampleRateHz` (samples in the
  last 10 s ÷ 10), `lastFixAge` (s, refreshed on the 1 s tick), `accepted`, `rejected`
  (`[RejectReason: Int]`), `dopplerPace`, `windowPace`, `cadence`, `audioState` ("idle" / "speech" /
  "metronome" / "speech+metronome", from AudioSessionCoordinator), `gpsState`.
- Ring log: `entries: [Entry]` capped at 300, newest first.
  `Entry { t: Double (run elapsed, or −1 when idle); kind: Kind (.fix, .reject, .cue, .state, .audio); text: String }`.
  Log every accepted fix ("fix 4.1m 3.21m/s ok"), every rejection with reason ("rej acc 27m > 20m"),
  every spoken cue with its trigger ("cue \"slow down\" 21s under 7:58" — Coach passes a reason
  string), state changes (start/pause/resume/stop, warm-up begin/end, gps ready), audio session
  changes, metronome start/stop.
- Per-run full record for export: every raw sample with
  `t, lat, lon, hAcc, speed, speedAcc, course, accepted(0/1), reason, distance, windowPace, dopplerPace, currentPace, cadence`.
  Cleared at run start. `func exportCSV() -> URL?` writes to `FileManager.default.temporaryDirectory`
  as `milepace-run-YYYYMMDD-HHmm.csv`.
- Only collect the ring log and the export record when diagnostics are enabled (`@AppStorage("diagnosticsEnabled")`, default false); the cheap live values can always update.

### C2. Calculator reporting (pure)
`PaceCalculator.add` records `private(set) var lastOutcome: SampleOutcome` where
`enum SampleOutcome: Equatable { case accepted, anchored, rejected(RejectReason) }` and
`enum RejectReason: String, CaseIterable { case paused, accuracy, beforeStart, outOfOrder, jump }`.
No change to return values or other behavior.

### C3. UI: `MilePace/Views/DiagnosticsPanel.swift`
- Per the mockup: bottom panel over the run screen (from just under the PaceMeter to above the
  TabStrip), 2 pt signal rule on top, `bg` fill. Header "diagnostics" + "[ x ]". A two-column grid of
  micro ReadoutRow-style pairs (h.acc, spd.acc, rate, age, accepted, rejected, doppler, 30s avg,
  cadence, audio). Then the log (micro, dim; `cue` and `rej` keywords in fg), scrollable, newest at
  top. "[ export run log ]" uses `ShareLink(item: url)` when a run record exists.
- Shown when the user taps "[ diag ]" on the run screen; stays open while running; does not block the
  pause/end controls (they stay visible below or the panel leaves room for them — put the panel
  between the readout rows and the buttons, and let the readout rows scroll).
- Settings → "diagnostics" CheckRow enables the "[ diag ]" button.

---

## Tests (add; keep all existing tests passing unchanged)
- Doppler: samples with speed 3.5 m/s, speedAccuracy 0.3 → `currentPace ≈ 459.8` within 2 s of the
  first sample; a step to 4.0 m/s reaches ≥ 63 % of the change after 4 s; speed 0.2 → nil;
  speedAccuracy 3.0 ignored (falls back to window pace); speed −1 samples → identical to v1.1.
- `lastOutcome` reasons for accuracy, out-of-order, paused, jump.
- PaceMeter cell mapping as a pure function `PaceMeterModel.cell(pace:zone:cells:) -> Int`
  (put it in Design/ but without SwiftUI imports in the function's file, or in Models/): in-zone →
  3 or 4; much faster → 0; much slower → 7.
- Dot-leader formatting `ReadoutFormat.leader("avg", width: 12) == "avg ........"`.
- Diagnostics CSV header line and one row formatting (pure helper).

## Done criteria
- Every screen uses the Instrument components; grep the Views folder for `Image(systemName`,
  `.cornerRadius`, `RoundedRectangle`, `Color.orange`, `Color.blue`, `Form {`, `List {`, `Toggle(`,
  `.pickerStyle(.segmented)` and remove them from screens (the map's Annotations excepted if needed).
- Info.plist valid (plistlib), project.yml valid (pyyaml); the font file lands in the app bundle.
- Update README field notes (GPS warm-up light, diagnostics) and HANDOFF.md (v1.2 section).
- Report: files added/changed, deviations, least-confident compile spots.
