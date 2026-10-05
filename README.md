# MilePace

A small native iOS app (SwiftUI, iOS 17+) for training from a 6:52 mile toward a 5:30 mile.

- **Today**: the built-in 48-week plan. Shows today's session with its target paces and a `[ start ]` button that sets up the run or track tab, a missed-session card, the week at a glance, and the full plan.
- **Run**: live GPS pace (instant Doppler pace plus a 30 second average), distance and mile splits, with optional voice cues and a pace guard (Easy or Threshold). Hold the "hold to end" bar for one second to finish.
- **Track**: tap-per-lap workout timer with target splits from your current training zones, rest countdown, and a results table.
- **Log**: weekly mileage chart (Monday to Sunday, last 10 weeks), saved runs and workouts, and manual mileage entry for treadmill or watch runs.
- **Set**: current and goal mile time, zone preview, plan start date and reset, voice and haptic toggles, light or dark display, and a diagnostics switch.

The look is "Instrument": the Departure Mono pixel typeface (MIT, in `MilePace/Resources/Fonts/`), pure black and white, and one electric blue used only as a fill. Design tokens live in `MilePace/Design/Theme.swift` and the components in `MilePace/Design/`. The reference mockups are in `design-mockups.png`.

Single user, no accounts, no network. Data is stored on the device with SwiftData.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); there is no checked-in `.xcodeproj`.

## A. Build and run with Xcode on a Mac

1. `brew install xcodegen`
2. `xcodegen generate`
3. `open MilePace.xcodeproj`
4. Select the MilePace target, open Signing & Capabilities, and choose your Team. Change the bundle id if `com.example.milepace` is taken (or build with `BUNDLE_ID=com.yourname.milepace`).
5. On your iPhone, turn on Developer Mode (Settings, Privacy & Security, Developer Mode), connect it, pick it as the run destination, and press Run.

Run the unit tests with Cmd+U.

## B. GitHub Actions build check

`.github/workflows/build.yml` runs on every push, pull request, and manual dispatch. It installs XcodeGen, generates the project, picks an available iPhone simulator, and runs `xcodebuild test` with code signing disabled. The `.xcresult` bundle is uploaded if the run fails.

## C. TestFlight from GitHub Actions

`.github/workflows/testflight.yml` (manual dispatch only) archives the app and uploads it to App Store Connect using an API key and cloud-managed signing, so no certificates or profiles are stored in the repo.

Before the first run:

1. In App Store Connect, create an app record with the same bundle id you will use.
2. Create an App Store Connect API key (Users and Access, Integrations). It needs the Admin role, or App Manager at minimum; Admin is needed for cloud-managed distribution certificates. Download the `.p8` file.
3. Add the repository secrets:
   - `ASC_KEY_ID`: the key id.
   - `ASC_ISSUER_ID`: the issuer id shown above the keys list.
   - `ASC_KEY_P8`: the full contents of the `.p8` file, including the BEGIN and END lines.
   - `TEAM_ID`: your 10-character Apple developer team id.
   - `BUNDLE_ID`: the bundle id, for example `com.yourname.milepace`.
4. Run the "TestFlight" workflow from the Actions tab. The build number is the workflow run number. The build appears in TestFlight after Apple finishes processing it.

## Field notes

- Allow location **While Using the App**. Tracking continues with the screen locked because the app declares the location background mode; the blue status indicator shows it is active.
- Carry the phone in the same place every run (armband or the same pocket). GPS pace is smoother and more comparable that way.
- GPS pace is noisy on a 400 m track because of the tight turns and short distances. Use Track mode on the track and tap a lap each time you cross the line.
- In Track mode the rest timer does not start the next rep for you. When the rest ends you get a vibration and a voice cue; tap GO when you actually start running.
- The 30 second window pace needs about 25 m of movement before it shows a number. The big pace number uses Doppler speed when the phone reports it (see Pace below), so it appears sooner; otherwise the first seconds read `--:--`.
- Road workouts: pick Workout mode on the Run tab, warm up, then tap Start Reps. Reps, recoveries and cool-down are coached by voice, with pace verdicts against the rep target (threshold, interval or goal pace). Skip ends a rep or recovery early. Pace cues (quarter, half or full mile) are held back during reps and recoveries.
- Metronome: the cadence click plays through the speaker or headphones, keeps going with the screen locked, and mixes with music and voice cues. Cadence comes from the phone's pedometer, so carry the phone on your body. After two minutes, "Set to my cadence +5%" sets the click a little above your average; raise cadence gradually.
- Run maps: each saved run keeps its route and shows it on a map colored by pace against that run's average (blue faster, white or black steady, grey slower) with mile markers. Runs saved before v1.1 have no map.
- GPS warm-up: while the Run tab is showing and nothing is recording, the status line reads `gps searching` with a blinking cursor, then `gps 4m` once the fix is within 10 m. Wait for that before tapping start so distance begins where you stand. Warm-up stops by itself after 3 minutes, when you leave the Run tab, or when the app goes to the background, to save battery. It does not use the background location mode.
- Pace: the big number follows your Doppler speed (smoothed over about 4 seconds), so it appears within a few seconds of moving and a change of pace mostly shows in about 5 seconds. If the phone reports no usable speed it falls back to the 30 second window. Voice cues say "Slow down" and "Speed up".
- Diagnostics: turn on `diagnostics` in Set and the Run tab gets a `[ diag ]` button. The panel shows live GPS accuracy, speed accuracy, sample rate, fix age, accepted and rejected fixes, Doppler pace, 30 second pace, cadence and audio state, plus a log of fixes, rejections, voice cues (with what triggered them), state changes and metronome events. `[ export run log ]` shares a CSV of every raw sample from the last run (`milepace-run-YYYYMMDD-HHmm.csv`). The log and CSV are only collected while diagnostics are on.
- Today tab: the plan is `MilePace/Resources/plan.json` (48 weeks, starts Mon 2026-10-12; change the start date in Set). Purple means scheduled or from the plan; blue still means on target right now. `[ start ]` opens the matching run or track setup and remembers the session; saving that run or workout marks it done. Runs and workouts logged on a session's day also mark it done, so manual miles count.
- Missed days: the oldest missed session appears at the top as an inverted card. `[ do it today ]` moves that session and every later one back by the days missed (the card says where the race lands); `[ skip ]` drops just that session. One missed session is shown at a time, oldest first. Nothing is ever rescheduled automatically.
- Time trials: saving a mile time trial offers to retune the training paces to that time (only for believable miles, 4:00 to 12:00). `[ keep ]` leaves the current mile time alone.
- Sessions without a preset (the week-47 sharpener) show their note, and `[ open track ]` opens the custom builder.
- Set, plan: `[ reset plan progress ]` clears done, skipped and pushed-back sessions after a second tap.
- Reminders (v1.4): local notifications only, no server and no extra capability. The app keeps the next 14 days scheduled (at most 60) and rebuilds them whenever the plan, your settings or your logged runs change, and each time the app opens. Default times are a morning note at 8:00 am with today's session, an evening nudge at 5:00 pm if it is not logged, a "tomorrow" note at 6:00 pm before each time trial and the race, and a Sunday 6:00 pm weekly summary. Rest days get nothing. The morning note also mentions the oldest missed session. Pushing the plan back moves the reminders with it.
- The morning and evening notifications have `[ mark done ]` and `[ skip ]` actions on the lock screen (pull down or long-press); tapping the notification itself opens the today tab. While the app is open only the time trial and weekly notes show a banner.
- Set, reminders: master switch, one switch per kind, the two times, how many are scheduled, and `[ send a test ]` (a notification five seconds later; lock the phone or leave the app to see it as it would arrive). The today tab shows a card asking to turn reminders on until you answer the iOS prompt, and a link to iOS Settings if you said no.
