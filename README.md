# MilePace

A small native iOS app (SwiftUI, iOS 17+) for training from a 6:52 mile toward a 5:30 mile.

- **Run**: live GPS pace, average pace, distance and mile splits, with optional voice cues and a pace guard (Easy or Threshold). Hold the End button for one second to finish.
- **Track**: tap-per-lap workout timer with target splits from your current training zones, rest countdown, and a results table.
- **History**: weekly mileage chart (Monday to Sunday, last 10 weeks), saved runs and workouts, and manual mileage entry for treadmill or watch runs.
- **Settings**: current and goal mile time, zone preview, voice and haptic toggles.

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
- Tracking pace uses a 30 second window and needs about 25 m of movement before it shows a number, so the first few seconds read `--:--`.
