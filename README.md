# MilePace

A small native iOS app (SwiftUI, iOS 17+) for training from a 6:52 mile toward a 5:30 mile.

- **Today**: the built-in 37-week plan (race Monday 2027-06-21). Shows today's session with its target paces and a `[ start ]` button that sets up the run or track screen, a missed-session card, the week at a glance, and the full plan.
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
- Road workouts: pick Workout mode on the run screen, warm up, then tap Start Reps. Reps, recoveries and cool-down are coached by voice, with pace verdicts against the rep target (threshold, interval or goal pace). Skip ends a rep or recovery early. Pace cues (quarter, half or full mile) are held back during reps and recoveries.
- Metronome: the cadence click plays through the speaker or headphones, keeps going with the screen locked, and mixes with music and voice cues. Cadence comes from the phone's pedometer, so carry the phone on your body. After two minutes, "Set to my cadence +5%" sets the click a little above your average; raise cadence gradually.
- Run maps: each saved run keeps its route and shows it on a map colored by pace against that run's average (blue faster, white or black steady, a dashed line for slower) with mile markers. Runs saved before v1.1 have no map.
- GPS warm-up: while the run screen is showing and nothing is recording, the status line reads `gps searching` with a blinking cursor, then `gps 4m` once the fix is within 10 m. Wait for that before tapping start so distance begins where you stand. Warm-up stops by itself after 3 minutes, when you leave the run screen, or when the app goes to the background, to save battery. It does not use the background location mode.
- Pace: the big number follows your Doppler speed (smoothed over about 4 seconds), so it appears within a few seconds of moving and a change of pace mostly shows in about 5 seconds. If the phone reports no usable speed it falls back to the 30 second window. Voice cues say "Slow down" and "Speed up".
- Live map (v1.5): during a run the status line has `[ map ]` next to `[ diag ]`; tap it to swap the big pace and readout list for a map with your route so far (blue line, one piece per pause or GPS gap), a start square, mile markers and a blue square for you, over a compact strip with pace, the pace meter, distance, time and cadence. The map follows you until you pan or zoom, then `[ follow ]` appears at its top right to snap back. `[ data ]` returns to the data view. Your choice is remembered. Both views run the same run (voice cues, metronome, workouts, pause and end are unchanged). Map view uses more battery; the data view or a locked screen is cheapest.
- Diagnostics: turn on `diagnostics` in Set and the run screen gets a `[ diag ]` button. The panel shows live GPS accuracy, speed accuracy, sample rate, fix age, accepted and rejected fixes, Doppler pace, 30 second pace, cadence and audio state, plus a log of fixes, rejections, voice cues (with what triggered them), state changes and metronome events. `[ export run log ]` shares a CSV of every raw sample from the last run (`milepace-run-YYYYMMDD-HHmm.csv`). The log and CSV are only collected while diagnostics are on.
- Today screen: the plan is `MilePace/Resources/plan.json` (37 weeks, starts Mon 2026-10-12, race Mon 2027-06-21; change the start date in Set). The plan has nothing on Wednesdays or Sundays, and a time trial or the race shows its own goal ("target <= 6:35", "goal 5:30"). Purple means scheduled or from the plan; blue still means on target right now. `[ start ]` opens the matching run or track setup and remembers the session; saving that run or workout marks it done. Runs and workouts logged on a session's day also mark it done when they are the right kind: an easy or long run needs at least half its miles (all free runs of that day added up), a road session needs that guided workout, a track session needs a track workout and a time trial needs the mile time trial. A run that starts before 3:00 am counts for the day before. Manual miles count as free runs.
- Missed days: a session stays on offer for two days; the oldest missed one appears at the top as an inverted card, and anything older is skipped by itself. `[ do it today ]` puts that session on today (or the next open day this week, since Wednesdays and Sundays are closed) and re-places the unfinished sessions of the same Monday-to-Sunday week around it, each keeping its day when it still fits. What does not fit is skipped, lowest priority first (time trial and race, track, road, long, easy): the card says how many sessions move and which ones are skipped. Later weeks, finished sessions and the race never move, and two hard sessions (road, track, time trial, race) never end up on neighbouring days. If the week has no day left for the missed session itself, it is skipped. `[ skip ]` drops just that session. Nothing is ever rescheduled automatically.
- Time trials: saving a mile time trial offers to retune the training paces to that time (only for believable miles, 5:00 to 8:30). `[ keep ]` leaves the current mile time alone.
- Sessions without a known preset show their note, and `[ open track ]` opens the custom builder.
- Set, plan: `[ reset plan progress ]` clears done, skipped and pushed-back sessions after a second tap.
- Reminders (v1.4): local notifications only, no server and no extra capability. The app keeps the next 14 days scheduled (at most 60) and rebuilds them whenever the plan, your settings or your logged runs change, and each time the app opens. Default times are a morning note at 8:00 am with today's session, an evening nudge at 5:00 pm if it is not logged, a "tomorrow" note at 6:00 pm before each time trial and the race, and a Sunday 6:00 pm weekly summary. Rest days get nothing. The morning note also mentions the oldest missed session. Pushing the plan back moves the reminders with it.
- The morning and evening notifications have `[ mark done ]` and `[ skip ]` actions on the lock screen (pull down or long-press); tapping the notification itself opens the app on Today. While the app is open only the time trial and weekly notes show a banner.
- Set, reminders: master switch, one switch per kind, the two times, how many are scheduled, and `[ send a test ]` (a notification five seconds later; lock the phone or leave the app to see it as it would arrive). Today shows a card asking to turn reminders on until you answer the iOS prompt, and a link to iOS Settings if you said no.
- Never lose a run (v1.6): stopping a run saves it straight away and then shows the summary; `[ save run ]` only adds notes and `[ discard ]` needs a second tap (`[ yes, discard ]`) and also reopens the plan session the run had marked done. While you run, an unfinished-run file is written every 30 seconds of moving time and when the app goes to the background. If the app is killed, Today shows "unfinished run from 6:42 am: 2.41 mi, 18:52" with `[ open ]`, and the run screen then offers `[ save it ]` or `[ discard ]` (two taps). Starting a new run first saves any unfinished one. Track workouts are saved on every tap too: Today shows an `[ open ]` card for it and the track screen offers `[ resume ]` (or `[ open ]` for results that were never saved) for three hours. A rest that ends while the app is in the background sends a "rest over" notification.
- Track taps: a lap tap within 10 seconds of the lap start is ignored ("too soon" on the button and a light tap); `[ undo last tap ]` also works from the results screen and after `[ skip rest ]`.
- Target window (v1.6): Set, voice and feedback, and the run screen's idle list both have "target window" (3 to 15 s/mi, default 8). A pace target narrower than twice that is widened to its middle plus or minus the window for the pace meter, the speed up or slow down cues and the plan text; the wide easy zone is never changed. The pace you see drops to `--:--` when no new GPS or speed reading arrived for 8 seconds.
- Zones now run to a 7:30 mile (slowest anchor row 610 to 675 s easy), and Set accepts 5:00 to 8:30 for the current and goal mile, typed as `m:ss` or as digits (`645` is 6:45). The field is checked when you submit it or leave it, not on each keystroke.
- Metronome: a call, alarm or another app stops the click and the screen says `click off`; it starts again when the interruption ends and asks to resume. Unplugging headphones or losing Bluetooth stops it and turns the switch off, so it never jumps to the speaker.
- Cadence is the pedometer's steps over the whole run minus the steps counted while paused, divided by moving time, worked out when you tap `[ save run ]` so steps taken with the phone locked are included.
- Diagnostics (v1.6): when the run screen is idle the diagnostics panel sits between the setup list and `[ start ]`, so start is always reachable. Set, voice: `announce each mile` is always honoured (mile announcements are skipped during reps and recoveries, and with 1 mi pace cues on).
- Weekly miles: Today, Log and the Sunday reminder add up the same Monday-to-Sunday miles (runs as recorded, track workouts estimated as rep distance plus 2 mi of warm-up and cool-down).
- Add miles (Log): a time with no colon is minutes (`45`); with miles entered the pace must work out between 4:00 and 20:00 per mile.
- Test week (v1.7): before the real plan starts, Set (and the countdown on Today) offers `[ start test week ]`: a gentle one-week plan (easy runs, a 2 x 2 min road workout, 4 x 200 on the track, a practice time trial) to try every screen. Test runs and workouts are tagged "test" in Log and are deleted, with the test progress, when you end it (`[ end test week ]`, two taps) or the real plan starts (also after the test Sunday); it never ends during a run. Reminders say "test:". The practice time trial never offers new paces. Settings you change stay.
- Metronome and pause (v1.8): pausing a run silences the click and the cadence row reads `paused`; resuming brings it back. Tapping the cadence row while paused only sets or clears that hold (no sound until you resume). A call that ends during a pause does not restart the click.
- Voice (v1.8): Set, voice and feedback, `voice` opens a list of the English voices on the phone (best quality first) and a speed choice (slower, normal, faster). Tapping a voice or a speed plays a sample. For better voices, download an enhanced or premium English voice in iOS Settings, Accessibility, Spoken Content, Voices, then come back; the list refreshes. A voice that is later deleted falls back to the default.
- One home screen (v1.9): there is no tab bar. Today is the home screen; `[ log ]` and `[ set ]` in its status line, and `[ free run ]` and `[ track workout ]` in its **other** section at the bottom, open the other screens, and each of those has a `[ today ]` button first in its status line. The run screen shows it only while nothing is recording and no summary is up, and a recording is never left: back-to-Today requests (including a tapped reminder) are ignored during a run or track session. Closing the run summary (save or discard) or a finished track workout goes back to Today. Today shows an inverted card with `[ open ]` for an unfinished run or track workout found on disk.
