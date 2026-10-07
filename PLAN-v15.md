# MilePace v1.15: routes — where to run today

Builds on v1.14 (`main`, compiles and passes CI). Same constraints: Swift 5 mode, iOS 17, Xcode 16
CI, no local compiler, Instrument design, XcodeGen folder globs. `MARKETING_VERSION: "1.15"`;
Settings status text "v1.15". **Do not regress** v1.14 (auto-pause, treadmill, mile progress, effort/
foot), v1.13 routines, v1.12 holds, v1.11 cues, v1.10 export/voice switches, v1.9 Today-only nav.

Context: from November the runner lives at **17 Monitor St, Brooklyn, NY 11222** (on McGolrick Park's
east side, Greenpoint). McCarren Park's public 400 m track is ~0.6 mi west along Driggs Ave. Like
Strava's suggested routes, but the plan decides: today's session → where to go. No accounts, no
backend. Apple MapKit only: `MKLocalSearch` / `CLGeocoder` to resolve places, `MKDirections`
(`transportType = .walking`) for paths. Network is used only when planning/resolving; resolved
routes are cached in SwiftData, so runs never need the network.

Content is written: `MilePace/Resources/routes.json` (home address + 10 curated routes). Don't change
its wording; fix JSON errors only.

Two passes: **Part A** = sections 1–5, **Part B** = sections 6–8. Each pass must leave the tree
compiling and tests green.

=====================================================================================================
## Part A

## 1. Model (pure, `Models/Routes.swift`)
```swift
struct RouteWaypoint: Codable, Equatable { let query: String; let kind: Kind
    enum Kind: String, Codable { case place, address } }
enum RouteShape: String, Codable { case loop, outAndBack, oneWay, track }
struct CuratedRoute: Codable, Equatable, Identifiable { let id: String; let name: String
    let shape: RouteShape; let start: String /* "home" */; let waypoints: [RouteWaypoint]
    let tags: [String]; let notes: String }
struct RouteCatalog: Codable, Equatable { let version: Int; let home: String; let routes: [CuratedRoute]
    func route(id: String) -> CuratedRoute? }
enum RouteCatalogLoader { static func decode(_ data: Data) -> RouteCatalog?; static func load(bundle:) -> RouteCatalog?
    static let bundled: RouteCatalog? }
/// The order of stops MapKit is asked to connect, from the shape:
/// loop: [start] + wps + [start]; outAndBack: [start] + wps + wps.reversed().dropFirst() + [start];
/// oneWay: [start] + wps; track: [start] + wps (distance shown is "to the track").
enum RouteLegs { static func stops<T>(start: T, waypoints: [T], shape: RouteShape) -> [T] }
```
Geometry helpers (pure, `Models/RouteGeometry.swift`): `struct GeoPoint: Codable, Equatable { lat, lon }`,
haversine `distance(a,b)`, `length(of: [GeoPoint])`, `project(point, onto polyline) -> (alongMeters,
offsetMeters)` (nearest segment, equirectangular local projection is fine at city scale),
`resample(polyline, every: meters)`.

## 2. Resolution service (`Services/RouteResolver.swift`, @MainActor @Observable singleton)
- `home` address: `@AppStorage("homeAddress")`, default from `RouteCatalog.home`. Settings "routes"
  section: a TextField "home" + `[ reset ]` to default.
- `resolve(_ route: CuratedRoute) async throws -> ResolvedRoute`: geocode start (home address via
  `CLGeocoder().geocodeAddressString`) and each waypoint (`.address` → CLGeocoder; `.place` →
  `MKLocalSearch` with `naturalLanguageQuery`, region = 5 km around home, take first result's
  `placemark.coordinate`); build stops with `RouteLegs.stops`; for each consecutive pair request
  `MKDirections` walking, take the first route's `polyline` points (`MKPolyline.points()` +
  `pointCount` → `MKMapPoint.coordinate`), concatenate (drop duplicate joints). Sequential legs, small
  delay (~0.3 s) between requests to stay under MapKit throttling. Errors → a typed error with a
  plain message ("couldn't find 'Kosciuszko Bridge, Brooklyn, NY'", "no walking path found",
  "no network").
- `ResolvedRoute`: id, name, shape, points `[GeoPoint]`, distanceMeters (computed from points),
  stopsResolved `[GeoPoint]`, resolvedAt, homeAddress used.
- Cache: SwiftData `@Model final class SavedRoute` (id String unique-ish, name, kind String
  "curated"/"generated"/"learned", pointsData Data (JSON [GeoPoint]), distanceMeters, notes,
  homeAddress String, createdAt, lastUsedAt Date?). Register the model in the app's ModelContainer
  schema (find where RunRecord/WorkoutRecord are registered). A curated route is re-resolved when the
  home address changed or it's older than 90 days, or on `[ refresh ]`.

## 3. Routes screen (`AppTab.routes`, `Views/RoutesView.swift`)
- Add `AppTab.routes`, a layer in ContentView like `.routines`; `ScreenRouting` unchanged (recording
  still forces run/track) — add a routing test like the routines one.
- StatusLine center "routes", `[ today ]` accessory. Content:
  - "from <home address short>" micro line.
  - SectionHeader("near home"): each curated route as a row: name, distance once resolved
    ("2.4 mi", for track "0.6 mi away") else "—", tags as a micro line. Tap → `RouteDetailView` sheet.
  - `[ resolve all ]` once (resolves sequentially with progress "3 / 10"); routes that fail show
    the error line in the row.
- `RouteDetailView` (sheet): Map (MapKit SwiftUI `Map` with `MapPolyline`, start `Annotation`/`Marker`;
  iOS 17 API — the app already uses MapKit in RunMapView/LiveRunMapView, match its style: flat,
  muted, no POIs), name, distance, estimated time at the runner's easy pace (middle of
  `AppSettings.zones.easy`), notes, and buttons: `[ use for today's run ]` (sets the selected route for
  the next run, section 5), `[ open in maps ]` (MKMapItem.openMaps with walking directions to the
  first waypoint — handy for the track), `[ refresh ]`.
- Entry points: Today "other" section gets `[ routes ]` next to `[ routines ]` (same row, two
  buttons); Run screen idle setup gets a compact "route: none ›" row (outdoor only; hidden on
  treadmill) that opens the routes screen.

## 4. Today recommends where (pure `RouteRecommendation`, tested)
`static func pick(kind: SessionKind, plannedMiles: Double?, isTimedRoadWorkout: Bool, now: Date,
sunset: Date?, resolved: [String: Double] /* id → miles */, catalog: RouteCatalog) -> Pick?` where
`Pick { let routeId: String?; let label: String; let note: String? }`:
- track / timeTrial / race → `mccarren-track`, note "lane 1 = 400 m". If `now` is after sunset (or
  before sunrise): label still the track but note "the track is open dawn to dusk".
- road workout → `mccarren-loop`.
- easy / long / other with planned miles → among resolved routes tagged easy (or long for long runs),
  the one whose distance is closest to planned within ±15 %; loops can be repeated: also consider
  `mcgolrick-loop` × n laps (label "mcgolrick loop × 4 (2.4 mi)") and `mccarren-loop`. If none fits →
  label "make a loop: 4 mi" (Part B; in Part A just "any 4 mi route").
- Sunrise/sunset: compute with a small pure NOAA-style solar calculation for the home coordinate
  (store home lat/lon after geocoding; fall back to 40.73, -73.95 if unknown). Unit-test against a
  known date ± 3 min.
- Today's session card shows one micro line under the start row: "where: mccarren park track ›";
  tap opens that route's detail sheet (or the routes screen when routeId is nil).

## 5. Following a route on the run
- `PlanStore`/`RunView` hold `selectedRouteId: String?` (set by `[ use for today's run ]`, cleared
  after the run is saved/discarded). Today's `[ start ]` pre-selects the recommended route if it has
  a resolved path and the run is outdoor (not track sessions).
- Live map (LiveRunMapView) draws the selected route as a thin dim polyline beneath the live track,
  with a small start marker. Data view adds a readout "route 1.2 / 3.1 mi" using
  `RouteGeometry.project` of the latest coordinate (monotonic: never go backwards by more than 50 m to
  avoid jitter on out-and-backs; prefer the projection nearest to the previous along-distance).
- `RunRecord.routeId: String = ""` saved with the run. Export lists the route name per run.

=====================================================================================================
## Part B

## 6. Make a loop (Strava-like generated routes)
- Pure `RouteGenerator` (tested): `static func waypoints(start: GeoPoint, distanceMeters: Double,
  headingDegrees: Double, radiusFactor: Double = 0.8) -> [GeoPoint]` — circle radius
  r = D/(2π)·radiusFactor, the start lies on the circle at `heading+180°` from the center; 3 waypoints
  at 90°, 180°, 270° around the circle from the start. `static func nextRadiusFactor(current:,
  target:, measured:) -> Double` (proportional rescale, clamped 0.4…1.2).
- Service: for a target distance (default today's planned miles; picker 1…10 mi in 0.5 steps) and
  start (home or current location), build 3 candidates at headings 0°, 120°, 240°; for each, request
  walking legs start→w1→w2→w3→start; rescale up to 3 tries until within ±7 %. Hard cap of 12
  MKDirections requests per candidate; stop early on errors. Optional "via parks": before routing,
  snap the middle waypoint to the nearest MKLocalSearch result with
  `pointOfInterestFilter = MKPointOfInterestFilter(including: [.park])` within r.
- Rank: distance error, then fewer direction changes > 60° per mile (proxy for intersections).
- UI: Routes screen `[ make a loop ]` → sheet with distance stepper, start [home | here], via parks
  toggle, `[ make ]` → 3 map cards with distance/time; `[ save ]` stores a `SavedRoute` kind
  "generated" (name "loop 4.0 mi, north"), `[ use ]` selects it for the run.
- Saved generated routes appear in a "saved" section of the Routes screen with swipe/`[ delete ]`.

## 7. Your routes (learned from saved runs)
- Pure `RouteMatching` (tested): two polylines are "the same route" when starts are within 200 m and
  ≥ 80 % of resampled points (every 50 m) of each lie within 30 m of the other.
- On the Routes screen, section "yours": groups of ≥ 2 matching GPS runs (non-test, outdoor), named
  by default "<distance> from <start area>" (rename via a small text field). Shows count, best time,
  last date; `[ use ]` selects the most recent run's path as the route. Compute off the main thread;
  cache the grouping result in memory until runs change.

## 8. Off-route cue
- Pure `OffRouteDetector` (tested): off when `offsetMeters > 40` for ≥ 20 s (with valid fixes), back on
  when < 25 m; emits `.off` once per excursion, `.back` silently (no speech).
- Voice "Off route." through Coach (respects the voice switch). Setting "off-route cue" (default on)
  in the routes section of Settings. Never during treadmill or when no route is selected.

## Tests
Part A: catalog decodes (shipped file), ids unique, every RouteRecommendation target id exists;
RouteLegs per shape; geometry (haversine within 0.5 %, projection along/offset on a simple L-shaped
polyline); recommendation rules; sunrise/sunset sanity; routing test for `.routes`.
Part B: generator geometry (start on circle, 4 points, radius scaling converges toward target),
matching metric, off-route timing.

## Done criteria (each pass)
Grep every API you use; MapKit SwiftUI on iOS 17 (`Map(position:)`, `MapPolyline(coordinates:)`,
`Marker`, `.mapStyle`), MKDirections async (`try await directions.calculate()`), CLGeocoder async
(`try await geocoder.geocodeAddressString(_:)`), MKLocalSearch async (`try await search.start()`).
SwiftData: new model registered in the container; new properties with defaults. MainActor, small
view bodies. Append to HANDOFF.md and README. Don't commit.
