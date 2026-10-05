# MilePace v1.5: live map toggle during a run

Builds on v1.4. v1.4 compiles and passes CI. **Do not regress it.** Same constraints (Swift 5 mode,
iOS 17, Xcode 16 CI, no local compiler, Instrument design system). Set `MARKETING_VERSION: "1.5"`.

Goal: like Strava, while recording a run you can flip between the **data** view (today's run screen)
and a **map** view showing where you are and the route so far.

## 1. Live route data
- `LocationTracker` publishes `private(set) var liveRoute: [RoutePoint] = []`, updated after each
  sample batch only when `calculator.route.count` changed (avoid needless view updates). Cleared on
  start/reset. It's the same downsampled (≥ 10 m) route that gets saved.
- Also publish `private(set) var lastCoordinate: CLLocationCoordinate2D?` (latest accepted fix) for the
  "you are here" marker; `CLLocationCoordinate2D` isn't Equatable, so don't use it in `onChange`.

## 2. Toggle
- On the active run screen, the status line gets a second accessory next to "diag": `[ map ]` while
  in data view, `[ data ]` while in map view. (Extend `StatusLine`/`StatusAccessory` to accept an
  array of accessories if it only takes one; keep existing call sites compiling.)
- Choice persists in `@AppStorage("runViewMode")` ("data" | "map"), default "data".
- The run continues identically in both views (voice cues, metronome, workout engine): the toggle
  is presentation only.

## 3. Map view (`MilePace/Views/LiveRunMapView.swift`)
Layout top to bottom, all inside the existing active-run container:
1. StatusLine (unchanged) and the workout Banner when a workout is active (unchanged).
2. Map, filling the remaining space above the readout strip:
   - iOS 17 SwiftUI `Map(position: $position) { … }` with
     `.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))`.
   - Route so far: `MapPolyline(coordinates:)` stroked `Theme.signal`, lineWidth 6. Respect
     `segmentStart` (pauses / GPS gaps): draw one polyline per contiguous segment.
   - Start: a 12×12 `Theme.fg` square Annotation (with a 2 pt `Theme.bg` border).
   - You: `UserAnnotation()` is acceptable, but prefer an Annotation at `lastCoordinate` drawn as a
     16×16 `Theme.signal` square with a 3 pt `Theme.onSignal` border, so it matches the design.
   - Mile markers: micro text in an inverted box (reuse `RouteSegments.mileMarkers`).
   - Camera: follow mode by default: `position = .userLocation(followsHeading: false, fallback: .automatic)`.
     When the user pans/zooms (detect via `.onMapCameraChange(frequency: .onEnd)` where the change
     wasn't caused by us, or simply when `position.followsUserLocation` becomes false), show a
     `[ follow ]` BracketButton overlaid at the map's top-right that restores follow mode.
     Use `.mapControls { }` (empty) to hide Apple's default controls.
   - Map needs no extra permission (location already granted).
3. **Readout strip** (bg fill, 2 pt fg rule on top), compact so the map gets most of the screen:
   - Row 1: pace in `.title` (33) size with "/mi" unit (dim, micro) on the left; on the right the
     PaceMeter in a compact form (reuse PaceMeter; if it has a fixed height, add a `compact` flag that
     makes cells 22 pt tall and hides the captions). Hidden meter when no zone, as today.
   - Row 2: three equal columns, value body size + micro dim label: dist "2.41 mi", time "18:52",
     cadence "172 spm" (or avg pace when cadence unavailable).
4. The existing controls (start reps / skip, pause/resume, hold to end) stay at the bottom, unchanged.
   The diagnostics panel, when open, overlays the map region the same way it overlays the data view.

## 4. Summary
No change to the post-run summary map (RunMapView) except: none.

## 5. Battery note
Map rendering costs battery only while the screen is on and the map view is showing. Mention it in
the README field notes: "map view uses more battery; the data view or a locked screen is cheapest."

## Tests
- Pure helper `LiveRouteSegments.split(_ route: [RoutePoint]) -> [[RoutePoint]]` (split at
  `segmentStart`, drop segments with < 2 points) in Models with tests: empty, single segment, split on
  resume, one-point segment dropped.

## Done criteria
- No regressions; data view unchanged. Self-review MapKit iOS 17 signatures carefully
  (`Map(position:interactionModes:scope:content:)`, `MapCameraPosition.userLocation(followsHeading:fallback:)`,
  `.onMapCameraChange(frequency:_:)`, `MapPolyline(coordinates:)`, `Annotation(_:coordinate:content:)`).
- README + HANDOFF.md v1.5 notes. Report files changed, deviations, least-confident spots.
