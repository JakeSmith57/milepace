# MilePace — iOS app build plan

Native iOS app (SwiftUI, iOS 17+) for one runner training from a 6:52 mile to a 5:30 mile.
Two jobs: (1) live GPS pace on road/treadmill-free runs, (2) a tap-per-lap track workout timer
with target splits. Plus history and weekly mileage. Single user, no accounts, no network.

The implementer CANNOT compile here (Linux, no Xcode). So: write conservative, idiomatic
SwiftUI/Swift 5.9 that compiles on Xcode 15/16 without warnings-as-errors issues. Avoid
experimental APIs, macros other than SwiftData `@Model` and `@Observable`, and anything iOS 18-only.
CI on GitHub Actions is the compile check.

## Tooling and repo layout

Use XcodeGen (`project.yml`) — do NOT hand-write a `.xcodeproj`.

```
milepace/
  PLAN.md                      (this file)
  README.md                    (setup, build, install, TestFlight)
  project.yml                  (XcodeGen)
  .gitignore                   (*.xcodeproj, build/, DerivedData, .DS_Store, *.ipa)
  MilePace/
    App/MilePaceApp.swift      (@main, SwiftData modelContainer for RunRecord + WorkoutRecord)
    App/ContentView.swift      (TabView: Run, Track, History, Settings)
    Models/PaceZones.swift     (pure logic, no UIKit)
    Models/Formatting.swift    (pure logic)
    Models/WorkoutPresets.swift
    Models/TrackWorkout.swift  (pure session state machine, testable)
    Models/Records.swift       (SwiftData @Model RunRecord, WorkoutRecord)
    Models/Settings.swift      (@AppStorage keys wrapper)
    Services/LocationTracker.swift
    Services/PaceCalculator.swift (pure: rolling pace from samples, testable)
    Services/Coach.swift       (AVSpeechSynthesizer + haptics)
    Views/RunView.swift
    Views/TrackSetupView.swift
    Views/TrackSessionView.swift
    Views/HistoryView.swift
    Views/SettingsView.swift
    Views/Components.swift     (big metric tile, etc.)
    Resources/Info.plist
    Resources/Assets.xcassets/ (Contents.json, AppIcon.appiconset/Contents.json with a single
                                1024 universal slot and no image, AccentColor.colorset)
  MilePaceTests/
    PaceZonesTests.swift
    FormattingTests.swift
    PaceCalculatorTests.swift
    TrackWorkoutTests.swift
  .github/workflows/build.yml
  .github/workflows/testflight.yml
  scripts/ExportOptions.plist
```

### project.yml essentials
- name MilePace; options.bundleIdPrefix `com.example` but bundle id driven by setting
  `PRODUCT_BUNDLE_IDENTIFIER: $(BUNDLE_ID)` with default `BUNDLE_ID: com.example.milepace`
  so CI can override; deploymentTarget iOS 17.0; Swift 5.9 (`SWIFT_VERSION: 5.0` is fine).
- App target: sources `MilePace`, `INFOPLIST_FILE: MilePace/Resources/Info.plist`,
  `GENERATE_INFOPLIST_FILE: NO`, `TARGETED_DEVICE_FAMILY: 1`, `CODE_SIGN_STYLE: Automatic`,
  `DEVELOPMENT_TEAM: $(TEAM_ID)` (default empty), `MARKETING_VERSION: 1.0`,
  `CURRENT_PROJECT_VERSION: 1`, `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
- Unit test target MilePaceTests (bundle.unit-test) depending on app; scheme MilePace with
  test target included.

### Info.plist
Standard keys (CFBundle* using $(…) build vars, UILaunchScreen empty dict, supported orientation
portrait), plus:
- NSLocationWhenInUseUsageDescription: "MilePace uses your location to measure pace and distance during runs."
- NSLocationAlwaysAndWhenInUseUsageDescription: same idea, mention keeping tracking when the screen is locked.
- UIBackgroundModes: [location, audio]
- ITSAppUsesNonExemptEncryption: false (avoids TestFlight export-compliance prompt)

## Domain logic (pure, unit-tested)

### Formatting
- `formatPace(secondsPerMile: Double?) -> String` → "7:05" ("--:--" for nil/inf/<=0/>30 min).
- `formatDuration(_ seconds: Double) -> String` → "M:SS" under an hour, "H:MM:SS" otherwise;
  `formatSplit(_ seconds:)` → "82.4" under 60s, else "1:22.4".
- `formatMiles(_ meters:)` → "3.12". Constants: metersPerMile = 1609.344.
- `parseTime("6:52") -> Double?` accepts "m:ss", "ss", "m:ss.s".

### PaceZones
Training paces come from the user's latest mile time via Jack Daniels VDOT, implemented as a table
with linear interpolation on mile time. Anchor rows (seconds per MILE unless noted):

| Mile | Easy lo–hi | T | I | R per 400 |
|------|-----------|---|---|-----------|
| 412 (6:52) | 575–630 | 478–483 | 438–443 | 102–104 |
| 395 (6:35) | 540–595 | 455–460 | 418–423 | 97–99 |
| 365 (6:05) | 510–565 | 423–428 | 389–394 | 90–92 |
| 345 (5:45) | 485–535 | 402–407 | 370–375 | 85–87 |
| 330 (5:30) | 465–515 | 388–393 | 357–362 | 82–83 |

Clamp outside 330…420. Expose `struct PaceZones { easy: ClosedRange<Double>; threshold; interval; rep400: ClosedRange<Double>; }`
and `static func forMile(_ seconds: Double) -> PaceZones`. Helper `targetSeconds(distanceMeters:, zone:)`
→ midpoint of zone scaled to distance (R scales from per-400; others from per-mile).
Goal pace constant: 330 s/mile (82.5 s/400).

### PaceCalculator (rolling pace)
Input: location samples (timestamp, coordinate, horizontalAccuracy, speed). Keep only accuracy ≤ 20 m
and timestamps increasing. Distance accumulates from consecutive accepted points (skip jumps implying
> 9 m/s). `currentPace` = time/distance over the trailing 30 s window (needs ≥ 25 m in window else nil),
lightly smoothed (EMA α 0.3). `averagePace` = elapsed moving time / total distance. Support pause:
samples while paused ignored and pause time excluded. Make it a plain struct taking a lightweight
`Sample` type (not CLLocation) so tests run without CoreLocation fixtures. Auto-lap: emit a split each
time cumulative distance crosses a whole mile.

### TrackWorkout (state machine)
`struct WorkoutSpec { name; reps: Int; repDistance: Int (meters: 200,300,400,600,800,1000,1200,1609);
targetRepSeconds: Double; restSeconds: Int; sets: Int = 1; setRestSeconds: Int = 0 }`
Derived: lapsPerRep = max(1, repDistance / 400) for ≥400, else 1 (a 200/300 rep is one tap);
for 1609 use 4 laps (last lap 409 m — treat as 400 for targets). Target per lap = proportional.
States: `.ready, .running(rep, lap), .resting(untilDate), .setRest, .finished`.
Events: `start(now)`, `lapTap(now)`, `restDone(now)`/time-based check `tick(now)`, `skipRest(now)`,
`undoLastTap()`. Records every lap split and rep total; computes delta vs target (+slow / −fast).
Rest end does NOT auto-start the next rep; it alerts and waits for tap "GO" (runner starts on own cue).

### WorkoutPresets
From the training plan (target derived from current zones unless fixed):
- 6×200 @ R (200 jog → rest 75s), 8×200 @ R, 10×200 @ goal 41s (rest 75s), 12×200 @ goal 41s
- 6×400 @ R (rest 2:30), 8×400 @ R (rest 2:00)
- 4×400 @ 82s full rest 3:00; 2 sets 4×400 @ 83s (60s, 5:00 between); 4 sets 2×400 @ 84s (60s, 4:00)
- 3×600 @ 2:05 (rest 5:00)
- 5×800 @ I (rest 2:00), 6×800 @ I
- 5×1000 @ I (rest 2:30), 6×1000 @ I
- 4×1200 @ I (rest 3:00), 5×1200 @ I
- Mile time trial: 1 rep 1609, target = latest mile goal the user sets (default goal 330)
- Custom (builder)

## Services

### LocationTracker (@Observable, @MainActor)
CLLocationManager: activityType .fitness, desiredAccuracy kCLLocationAccuracyBest, distanceFilter
kCLDistanceFilterNone, pausesLocationUpdatesAutomatically false, allowsBackgroundLocationUpdates true
(set ONLY after authorization and only while a run is active), showsBackgroundLocationIndicator true.
Request whenInUse first; that's enough for background updates when started in foreground with the
background mode. Expose authorization status, start/pause/resume/stop, feeds PaceCalculator, publishes
distance, elapsed, currentPace, averagePace, splits. Elapsed driven by a 1 s Timer using dates (not
counting ticks). Handle denied auth with a clear message + button to open Settings.

### Coach
AVSpeechSynthesizer + AVAudioSession(.playback, mode .voicePrompt, options [.duckOthers,
.mixWithOthers]); activate before speaking, deactivate after (notifyOthersOnDeactivation).
Announcements (each toggleable in Settings):
- each mile: "Mile 2. Split 9 minutes 41. Average 9 41."
- zone guard for runs: user picks target zone (None/Easy/Threshold); if current pace is outside zone
  for 20 s continuous, say "Easy up" / "Pick it up", at most once per 60 s.
- track: rest countdown "10 seconds", "Go when ready"; lap feedback optional "On pace / 2 seconds slow".
Haptics: UINotificationFeedbackGenerator for lap tap and rest end.

## Screens

Design: dark-friendly, system colors, huge monospaced digits (`.monospacedDigit()`, SF Rounded),
readable mid-run. Accent: orange.

1. **Run** — idle: zone picker (None/Easy/Threshold with range shown), Start button; permission
   prompt state. Active: big current pace, then average pace, distance, time; mile splits list;
   Pause/Resume, and long-press (1 s) to End (prevents pocket taps). On end → summary sheet with
   Save/Discard; save to RunRecord (date, distance m, duration s, avg pace, splits [Double], notes).
2. **Track** — preset list grouped (Short reps / 400s / Long reps / Time trial) showing computed
   target per rep and per 400 from current zones; tap → setup sheet to edit reps/target/rest → Start.
   Session view: screen stays awake (`UIApplication.shared.isIdleTimerDisabled = true` while active).
   Top: workout name, Rep x/y, Lap a/b. Center: running clock for the current rep, target for this lap,
   last split with colored delta (green fast/on, red slow; ±1.0 s counts as on pace). Bottom: a huge
   full-width LAP button (≥ 40% of screen height). During rest: countdown ring + "GO" button, plus
   "Skip rest". Undo last tap via small button. End → results table (each rep, splits, delta, average)
   and Save to WorkoutRecord (date, name, spec JSON, rep times [Double], lap splits [[Double]]).
3. **History** — Swift Charts bar chart of weekly miles (Mon–Sun weeks, last 10 weeks, runs only,
   plus a manual "add miles" entry for treadmill/watch runs saved as RunRecord with no splits).
   List sections: Runs, Workouts; swipe to delete; detail views.
4. **Settings** — current mile time (default 6:52, text field m:ss, validated), goal mile (5:30),
   zone table preview, voice toggles, units fixed to miles.

## Tests (XCTest, logic only)
- Formatting round-trips and edge cases.
- PaceZones: exact anchor rows; interpolation midpoint (e.g. 380 s lies between 6:35 and 6:05 rows);
  clamping.
- PaceCalculator: synthetic straight-line samples at 4 m/s → pace ≈ 402 s/mi; inaccurate samples
  ignored; teleport rejected; pause excluded; mile split emitted at 1609 m.
- TrackWorkout: 2×800 with 2 laps each: taps produce 4 lap splits, 2 rep times, rest state between,
  finished after last; undo works; deltas sign correct.

## CI

### .github/workflows/build.yml (on push, pull_request, workflow_dispatch)
runs-on: macos-15. Steps: checkout; `brew install xcodegen`; `xcodegen generate`;
select latest Xcode (`sudo xcode-select -s /Applications/Xcode_16.*.app` — glob safely, or use
`maxim-lobanov/setup-xcode@v1` with `latest-stable`); pick an available iPhone simulator
dynamically (`xcrun simctl list devices available -j` + small python/jq to choose first iPhone)
rather than hardcoding a device name; `xcodebuild test -scheme MilePace -destination "id=$SIM_ID"
CODE_SIGNING_ALLOWED=NO`. Upload xcresult on failure.

### .github/workflows/testflight.yml (workflow_dispatch only)
Uses App Store Connect API key + automatic cloud signing (no p12 juggling):
secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (contents), `TEAM_ID`, `BUNDLE_ID`.
Steps: checkout, xcodegen, write key to `$RUNNER_TEMP/AuthKey.p8`; set CURRENT_PROJECT_VERSION to
`${{ github.run_number }}`; `xcodebuild archive -scheme MilePace -destination "generic/platform=iOS"
-archivePath build/MilePace.xcarchive DEVELOPMENT_TEAM=$TEAM_ID BUNDLE_ID=$BUNDLE_ID
-allowProvisioningUpdates -authenticationKeyPath … -authenticationKeyID … -authenticationKeyIssuerID …`;
then `xcodebuild -exportArchive -exportOptionsPlist scripts/ExportOptions.plist` (method
app-store-connect, destination upload, signingStyle automatic, teamID substituted at runtime) with the
same auth flags. README explains: create the app record in App Store Connect with the same bundle id,
API key needs Admin or App Manager role (Admin needed for cloud-managed certificates).

## README
Three install paths, short and concrete: (A) Xcode on the Mac: `brew install xcodegen`,
`xcodegen generate`, open, set Team, run on phone (enable Developer Mode on iPhone).
(B) GitHub Actions build check. (C) TestFlight via the workflow + secrets list.
Field notes: allow location "While Using" (background works via the blue indicator), keep the phone
on the body consistently, GPS pace is noisy on tracks — use Track mode on the track.

## Done criteria for the implementer
All files above exist; no placeholders/TODO stubs in shipped code; every Swift file self-consistent
(types referenced exist, imports present); tests reference real APIs; YAML valid
(`python3 -c "import yaml…"` check); Info.plist and ExportOptions.plist valid (`plutil` unavailable —
use python plistlib). Report a file list and any assumptions.
