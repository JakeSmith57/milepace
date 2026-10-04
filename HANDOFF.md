# Handoff: get MilePace building and onto TestFlight

## Where things stand
- All source, tests, CI workflows and the README are written (see `PLAN.md` for the spec).
- **The code has never been compiled.** It was written on Linux with no Xcode. Expect some compile
  errors on the first CI run.
- YAML, plists and asset JSON were validated with Python. An app icon is included
  (`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`).

## Task 1: make "Build and Test" pass
Workflow: `.github/workflows/build.yml` (macos-15, latest stable Xcode, XcodeGen, first available
iPhone simulator, `xcodebuild test` with `CODE_SIGNING_ALLOWED=NO`).

Fix compile errors and failing tests with the smallest changes that keep the behavior in `PLAN.md`.
These spots were flagged as most likely to break:
1. `Services/LocationTracker.swift`: `@Observable` + `@MainActor` + `NSObject` subclass with
   `nonisolated` delegate methods; the `@MainActor` closure properties `onMile` and `onTick`.
2. `App/MilePaceApp.swift`: `@State private var tracker = LocationTracker()` in the `App` struct,
   passed with `.environment(tracker)`.
3. `Views/Components.swift`: `HoldToEndButton` uses
   `onLongPressGesture(minimumDuration:maximumDistance:perform:onPressingChanged:)`.
4. `Models/Records.swift`: SwiftData `@Model` classes with `[Double]` properties and computed
   properties that decode JSON.
5. `Views/HistoryView.swift` and `Views/TrackSessionView.swift`: `let` declarations inside
   ViewBuilder closures; `@Query(sort: \RunRecord.date, order: .reverse)`.
6. `project.yml`: the `$(BUNDLE_ID)` / `$(TEAM_ID)` build-setting substitution and the
   `Resources/Info.plist` source exclude.
7. Strict-concurrency warnings: if Xcode 16 escalates any to errors, fix them properly
   (isolation annotations) rather than disabling checking.

Done when the workflow is green and all four test files pass:
`FormattingTests`, `PaceZonesTests`, `PaceCalculatorTests`, `TrackWorkoutTests`.

## Task 2: TestFlight upload
Workflow: `.github/workflows/testflight.yml` (manual dispatch). The owner adds these repository
secrets himself; do not ask for their values in comments:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `TEAM_ID`, `BUNDLE_ID`.

The app record must already exist in App Store Connect with the same bundle ID. The API key has
the Admin role, so cloud-managed signing via `-allowProvisioningUpdates` should work. If the
archive or export step fails, fix the workflow or `scripts/ExportOptions.plist`, not the app code.

Done when the build appears under TestFlight in App Store Connect and the owner can install it as
an internal tester.

## Task 3 (after it runs on a phone): field checks
- Run tab: pace appears within ~30 s of starting, keeps tracking with the screen locked, mile
  voice split plays, hold-to-end works.
- Track tab: target splits match the printed plan (6:52 mile → R 400 ≈ 102–104 s); LAP button is
  easy to hit mid-rep; rest countdown and GO work; results save.
- History: weekly miles chart shows saved and manually added runs.

## v1.1 (see `PLAN-v2.md`)
New files, none of them compiled yet (no Swift toolchain on the authoring machine):
- `Models/DistanceCues.swift`, `Models/RoadWorkout.swift`, `Models/RouteSegments.swift`, `Models/ClickTrack.swift`: pure logic.
- `Services/CadenceTracker.swift` (CMPedometer), `Services/AudioSessionCoordinator.swift` (shared audio session
  counts for speech and metronome), `Services/Metronome.swift` (AVAudioEngine click loop).
- `Views/RunMapView.swift`: iOS 17 MapKit route map.
- Tests: `DistanceCuesTests`, `RoadWorkoutTests`, `ClickTrackTests`, `RouteTests`, `ZoneGuardTests`.
Changed: `LocationTracker`, `Coach`, `PaceCalculator` (route), `Settings`, `Records` (new defaulted SwiftData
fields), `RunView`, `HistoryView`, `SettingsView`, `Info.plist` (motion usage text), `project.yml` (version 1.1).
Most likely to need a compile fix: `Metronome.swift`, `CadenceTracker.swift`, `RunMapView.swift`, `RunView.swift`.

## v1.2 (see `PLAN-v3.md`)
Written on Linux with no Swift toolchain, so **none of it has been compiled**. Expect a few compile fixes on the
first CI run. Build and tests must stay green; v1.1 tests are unchanged.

New files:
- `Design/Theme.swift` (tokens, `Theme.mono`, `instrumentScreen()`), `Design/Components+Instrument.swift`
  (rules, `StatusLine`, `Banner`, `HeroReadout`, `PaceMeter`, `ReadoutRow`, `DeltaChip`, `Tape`, `SectionHeader`),
  `Design/Controls+Instrument.swift` (`BracketButton`, `HoldBar`, `TabStrip`, `CheckRow`, `ChoiceRow`, `StepperRow`,
  `FieldRow`, `BoxedField`).
- `Models/InstrumentFormat.swift`: pure helpers (`ReadoutFormat`, `PaceMeterModel`, `GPSState`, `DiagnosticsCSV`).
- `Services/Diagnostics.swift` (`@Observable @MainActor` singleton) and `Views/DiagnosticsPanel.swift`.
- `Resources/Fonts/DepartureMono-Regular.otf` and `LICENSE-DepartureMono.txt`; `UIAppFonts` in Info.plist.
- Tests: `DopplerPaceTests`, `InstrumentFormatTests`.

Changed: `PaceCalculator` (Doppler pace, `windowPace`, `lastOutcome`; `currentPace` is now computed),
`LocationTracker` (GPS warm-up, `gpsState`, diagnostics hooks), `Coach` (wording, cue reasons), `AudioSessionCoordinator`
and `Metronome` (diagnostics), `Settings` (display mode, diagnostics), every view, `ContentView` (ZStack of live
screens plus `TabStrip`), `project.yml` (version 1.2).

Most likely to need a compile fix: `Design/Controls+Instrument.swift` (`HoldBar` TimelineView, generic `ChoiceRow`),
`Views/HistoryView.swift` (Charts axis closures), `Views/RunMapView.swift` (`mapStyle`), `Design/Theme.swift`
(`UIColor` dynamic provider), `Services/LocationTracker.swift`.

Field checks for v1.2: GPS status line goes `searching` to `4m` on the Run tab before starting; pace shows within a few
seconds of running; "Slow down" / "Speed up" spoken; hold-to-end bar fills and ends the run; LAP block is easy to hit;
light and dark display modes; diagnostics panel stays open mid-run and the CSV exports.
