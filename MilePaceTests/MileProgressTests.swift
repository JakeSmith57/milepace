import XCTest
@testable import MilePace

/// The fastest-mile window over a GPS route, track mile detection, the bests merge, the GPS noise rule, the
/// chart snapshot and the new-best rule (v1.14 part B).
final class MileProgressTests: XCTestCase {
    private let day: TimeInterval = 86400

    private func date(_ days: Int) -> Date {
        return Date(timeIntervalSince1970: 1_790_000_000 + Double(days) * day)
    }

    /// A route with a point every `spacing` meters. `secondsPerMeter` gives the pace of each stretch from its
    /// start distance (meters), so `[(0, 0.3), (1000, 0.2)]` is slow for 1000 m and quicker after.
    private func route(length: Double,
                       spacing: Double = 10,
                       stretches: [(from: Double, secondsPerMeter: Double)]) -> [RoutePoint] {
        var points: [RoutePoint] = [RoutePoint(lat: 0, lon: 0, t: 0, d: 0, segmentStart: true)]
        var distance = 0.0
        var time = 0.0
        while distance < length {
            let pace = stretches.last(where: { $0.from <= distance })?.secondsPerMeter ?? stretches[0].secondsPerMeter
            let step = min(spacing, length - distance)
            distance += step
            time += step * pace
            points.append(RoutePoint(lat: 0, lon: distance * 0.00001, t: time, d: distance))
        }
        return points
    }

    // MARK: Sliding window

    func testConstantPaceGivesTheExactMile() throws {
        // 6:00 per mile for 3000 m.
        let perMeter = 360.0 / metersPerMile
        let points = route(length: 3000, stretches: [(0, perMeter)])
        let mile = try XCTUnwrap(MileProgress.fastestMile(route: points))
        XCTAssertEqual(mile, 1609 * perMeter, accuracy: 0.05)
    }

    func testFastMiddleSectionIsFound() throws {
        // 8:00/mi for 1000 m, 5:00/mi for 1700 m, 8:00/mi for 1000 m.
        let slow = 480.0 / metersPerMile
        let fast = 300.0 / metersPerMile
        let points = route(length: 3700, stretches: [(0, slow), (1000, fast), (2700, slow)])
        let mile = try XCTUnwrap(MileProgress.fastestMile(route: points))
        XCTAssertEqual(mile, 1609 * fast, accuracy: 0.5)
        // Well under an 8:00 mile.
        XCTAssertLessThan(mile, 1609 * slow - 60)
    }

    func testRouteShorterThanAMileHasNoMile() {
        let points = route(length: 1500, stretches: [(0, 0.25)])
        XCTAssertNil(MileProgress.fastestMile(route: points))
        XCTAssertNil(MileProgress.fastestMile(route: []))
        XCTAssertNil(MileProgress.fastestMile(route: Array(points.prefix(1))))
    }

    func testStartIsInterpolatedBetweenSparsePoints() throws {
        // Two points 2000 m apart: the window starts inside the only segment.
        let points = [RoutePoint(lat: 0, lon: 0, t: 0, d: 0, segmentStart: true),
                      RoutePoint(lat: 0, lon: 0.02, t: 400, d: 2000)]
        let mile = try XCTUnwrap(MileProgress.fastestMile(route: points))
        XCTAssertEqual(mile, 321.8, accuracy: 0.01)
    }

    func testWindowStartingOnAPointIsFound() throws {
        // Fast only between 500 m and 2109 m: the best window starts exactly on a point (500 m), and its
        // end falls between two points.
        let slow = 0.3
        let fast = 0.2
        let points = [RoutePoint(lat: 0, lon: 0, t: 0, d: 0, segmentStart: true),
                      RoutePoint(lat: 0, lon: 0, t: 500 * slow, d: 500),
                      RoutePoint(lat: 0, lon: 0, t: 500 * slow + 1700 * fast, d: 2200),
                      RoutePoint(lat: 0, lon: 0, t: 500 * slow + 1700 * fast + 1000 * slow, d: 3200)]
        let mile = try XCTUnwrap(MileProgress.fastestMile(route: points))
        XCTAssertEqual(mile, 1609 * fast, accuracy: 0.01)
    }

    func testOtherDistances() throws {
        let perMeter = 0.25
        let points = route(length: 6000, stretches: [(0, perMeter)])
        XCTAssertEqual(try XCTUnwrap(MileProgress.fastest(distance: 400, route: points)), 100, accuracy: 0.05)
        XCTAssertEqual(try XCTUnwrap(MileProgress.fastest(distance: 5000, route: points)), 1250, accuracy: 0.05)
        XCTAssertNil(MileProgress.fastest(distance: 5000, route: route(length: 4000, stretches: [(0, perMeter)])))
        XCTAssertNil(MileProgress.fastest(distance: 0, route: points))
    }

    func testImpossibleSpeedsAreIgnored() {
        // 2000 m in 100 s is 20 m/s: GPS garbage, not a time.
        let points = route(length: 2000, stretches: [(0, 0.05)])
        XCTAssertNil(MileProgress.fastestMile(route: points))
    }

    func testGapInMovingTimeNeverMakesAWindowFaster() throws {
        // A GPS gap adds time but no distance (a re-anchor): the window across it is slow, the rest is steady.
        let perMeter = 0.25
        var points = route(length: 1000, stretches: [(0, perMeter)])
        let last = try XCTUnwrap(points.last)
        points.append(RoutePoint(lat: 0, lon: 0.01, t: last.t + 120, d: last.d, segmentStart: true))
        var distance = last.d
        var time = last.t + 120
        while distance < 3000 {
            distance += 10
            time += 10 * perMeter
            points.append(RoutePoint(lat: 0, lon: 0.01 + distance * 0.00001, t: time, d: distance))
        }
        let mile = try XCTUnwrap(MileProgress.fastestMile(route: points))
        XCTAssertEqual(mile, 1609 * perMeter, accuracy: 0.05)
    }

    func testGPSBestsCoverOnlyTheDistancesTheRouteReaches() {
        let points = route(length: 2500, stretches: [(0, 0.25)])
        let bests = MileProgress.gpsBests(date: date(0), route: points)
        XCTAssertEqual(bests.map { $0.distance }, [400, 800, 1609])
        XCTAssertTrue(bests.allSatisfy { $0.date == date(0) })
    }

    // MARK: Track workouts

    func testTrackMileNeedsASingleMileRep() {
        XCTAssertEqual(MileProgress.trackMile(repDistance: 1609, totalReps: 1, repTimes: [391.2]), 391.2)
        XCTAssertNil(MileProgress.trackMile(repDistance: 1609, totalReps: 2, repTimes: [391.2, 395]))
        XCTAssertNil(MileProgress.trackMile(repDistance: 1609, totalReps: 1, repTimes: []))
        XCTAssertNil(MileProgress.trackMile(repDistance: 800, totalReps: 1, repTimes: [170]))
        XCTAssertNil(MileProgress.trackMile(repDistance: 1609, totalReps: 1, repTimes: [0]))
    }

    func testTrackRepsCountAtTheirExactDistanceOnly() throws {
        let rep400 = MileProgress.trackBests(date: date(0), repDistance: 400, repTimes: [90, 88.4, 91])
        XCTAssertEqual(rep400.count, 1)
        XCTAssertEqual(rep400[0].distance, 400)
        XCTAssertEqual(rep400[0].seconds, 88.4)
        XCTAssertTrue(MileProgress.trackBests(date: date(0), repDistance: 1000, repTimes: [200]).isEmpty)
        XCTAssertTrue(MileProgress.trackBests(date: date(0), repDistance: 400, repTimes: []).isEmpty)
    }

    // MARK: Bests

    func testBestsPickTheFastestAndKeepItsDate() throws {
        let candidates = [DistanceBest(distance: 1609, seconds: 400, date: date(0)),
                          DistanceBest(distance: 1609, seconds: 391.2, date: date(7)),
                          DistanceBest(distance: 1609, seconds: 395, date: date(14)),
                          DistanceBest(distance: 400, seconds: 88.4, date: date(3)),
                          DistanceBest(distance: 1000, seconds: 200, date: date(3))]
        let merged = MileProgress.bests(candidates)
        XCTAssertEqual(merged.map { $0.distance }, [400, 1609])
        let mile = try XCTUnwrap(merged.last)
        XCTAssertEqual(mile.seconds, 391.2)
        XCTAssertEqual(mile.date, date(7))
    }

    func testBestsTieKeepsTheEarlierDate() throws {
        let merged = MileProgress.bests([DistanceBest(distance: 800, seconds: 170, date: date(9)),
                                         DistanceBest(distance: 800, seconds: 170, date: date(2))])
        XCTAssertEqual(try XCTUnwrap(merged.first).date, date(2))
    }

    func testBestsOfNothingIsEmpty() {
        XCTAssertTrue(MileProgress.bests([]).isEmpty)
    }

    // MARK: Noise rule

    func testGPSMilesCloseToTheLatestResultAreChartWorthy() {
        XCTAssertTrue(MileProgress.isChartWorthy(gpsMile: 380, reference: 392))
        XCTAssertTrue(MileProgress.isChartWorthy(gpsMile: 392, reference: 392))
        XCTAssertTrue(MileProgress.isChartWorthy(gpsMile: 407, reference: 392))
        XCTAssertFalse(MileProgress.isChartWorthy(gpsMile: 407.5, reference: 392))
        XCTAssertFalse(MileProgress.isChartWorthy(gpsMile: 480, reference: 392))
    }

    // MARK: Snapshot

    private func trial(_ time: Double, day days: Int, race: Bool = false, test: Bool = false) -> MileTrackInput {
        return MileTrackInput(date: date(days), repDistance: 1609, totalReps: 1, repTimes: [time], isRace: race, isTest: test)
    }

    func testSnapshotKeepsTrackResultsAndFiltersGPSNoise() throws {
        let tracks = [trial(400, day: 0), trial(392, day: 30), trial(380, day: 60, test: true)]
        let gps = [DistanceBest(distance: 1609, seconds: 410, date: date(10)),   // 18 s off 392: noise, but 10 days before
                   DistanceBest(distance: 1609, seconds: 405, date: date(35)),   // within 15 s of 392
                   DistanceBest(distance: 1609, seconds: 385, date: date(40)),   // faster than 392
                   DistanceBest(distance: 800, seconds: 170, date: date(40))]
        let snapshot = MileProgress.snapshot(tracks: tracks, gps: gps, plan: [], goal: 330, mileTime: 412)
        XCTAssertEqual(snapshot.results.map { $0.seconds }, [400, 392])
        XCTAssertEqual(snapshot.results.map { $0.source }, [.trackTimeTrial, .trackTimeTrial])
        XCTAssertEqual(snapshot.gpsPoints.map { $0.seconds }, [405, 385])
        XCTAssertEqual(snapshot.latest, 392)
        XCTAssertEqual(snapshot.latestDate, date(30))
        XCTAssertEqual(snapshot.toGo, 62, accuracy: 1e-9)
        // The best mile is the GPS 385; the 800 m comes from GPS too.
        XCTAssertEqual(snapshot.bests.map { $0.distance }, [800, 1609])
        XCTAssertEqual(snapshot.bests.last?.seconds, 385)
    }

    func testRaceResultIsMarkedAsARace() {
        let snapshot = MileProgress.snapshot(tracks: [trial(335, day: 5, race: true)], gps: [], plan: [], goal: 330, mileTime: 412)
        XCTAssertEqual(snapshot.results.first?.source, .race)
    }

    func testWithoutTrackResultsTheMileSettingIsTheLatest() {
        let gps = [DistanceBest(distance: 1609, seconds: 425, date: date(1)),
                   DistanceBest(distance: 1609, seconds: 440, date: date(2))]
        let snapshot = MileProgress.snapshot(tracks: [], gps: gps, plan: [], goal: 330, mileTime: 412)
        XCTAssertTrue(snapshot.results.isEmpty)
        XCTAssertNil(snapshot.latestDate)
        XCTAssertEqual(snapshot.latest, 412)
        XCTAssertEqual(snapshot.toGo, 82, accuracy: 1e-9)
        XCTAssertEqual(snapshot.gpsPoints.map { $0.seconds }, [425])
    }

    func testGoalReachedHasNothingToGo() {
        let snapshot = MileProgress.snapshot(tracks: [trial(328, day: 1)], gps: [], plan: [], goal: 330, mileTime: 412)
        XCTAssertEqual(snapshot.toGo, 0)
        XCTAssertTrue(MileProgress.summaryLine(latest: 328, goal: 330).hasSuffix("goal reached"))
    }

    func testSummaryLine() {
        XCTAssertEqual(MileProgress.summaryLine(latest: 412, goal: 330),
                       "latest mile 6:52 \u{00B7} goal 5:30 \u{00B7} 1:22 to go")
    }

    func testPlanPointsAreSortedByDate() {
        let plan = [PlanMilePoint(date: date(20), seconds: 330), PlanMilePoint(date: date(5), seconds: 395)]
        let snapshot = MileProgress.snapshot(tracks: [], gps: [], plan: plan, goal: 330, mileTime: 412)
        XCTAssertEqual(snapshot.plan.map { $0.seconds }, [395, 330])
    }

    // MARK: Axis

    func testAxisSpansGoalMinusTenToSevenTen() {
        let domain = MileProgress.yDomain(goal: 330, points: [395, 412])
        XCTAssertEqual(domain.lowerBound, 320)
        XCTAssertEqual(domain.upperBound, 430)
    }

    func testAxisGrowsForASlowerPoint() {
        let domain = MileProgress.yDomain(goal: 330, points: [395, 500])
        XCTAssertEqual(domain.upperBound, 510)
        XCTAssertEqual(MileProgress.yDomain(goal: 330, points: []).upperBound, 430)
    }

    // MARK: New best in a run

    func testNewBestMileMustBeatEarlierBestsAndTheSetting() {
        XCTAssertEqual(MileProgress.newBestMile(current: 401, previousBest: 410, mileTime: 412), 401)
        // Not faster than an earlier best.
        XCTAssertNil(MileProgress.newBestMile(current: 405, previousBest: 400, mileTime: 412))
        // Not faster than the mile time setting.
        XCTAssertNil(MileProgress.newBestMile(current: 415, previousBest: nil, mileTime: 412))
        // The first mile ever, faster than the setting.
        XCTAssertEqual(MileProgress.newBestMile(current: 400, previousBest: nil, mileTime: 412), 400)
        XCTAssertNil(MileProgress.newBestMile(current: nil, previousBest: nil, mileTime: 412))
    }

    func testLabels() {
        XCTAssertEqual(MileProgress.bestDistances.map { MileProgress.distanceLabel($0) },
                       ["400 m", "800 m", "1 mi", "2 mi", "5 km"])
        XCTAssertEqual(MileProgress.timeText(88.44, distance: 400), "1:28.4")
        XCTAssertEqual(MileProgress.timeText(391.9, distance: 1609), "6:31")
    }
}

/// Foot pain warning on Today, and the effort and foot wording.
final class FootCheckTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 86400

    private func entry(_ value: Int, daysAgo: Double, test: Bool = false) -> FootEntry {
        return FootEntry(date: now.addingTimeInterval(-daysAgo * day), value: value, isTest: test)
    }

    func testPainOfFourInTheLastThreeDaysWarns() throws {
        let warning = try XCTUnwrap(FootCheck.warning(entries: [entry(4, daysAgo: 2)], now: now))
        XCTAssertEqual(warning.value, 4)
        XCTAssertEqual(warning.date, now.addingTimeInterval(-2 * day))
    }

    func testPainOfThreeDoesNotWarn() {
        XCTAssertNil(FootCheck.warning(entries: [entry(3, daysAgo: 1)], now: now))
    }

    func testOldPainDoesNotWarn() {
        XCTAssertNil(FootCheck.warning(entries: [entry(8, daysAgo: 3.5)], now: now))
        XCTAssertNotNil(FootCheck.warning(entries: [entry(8, daysAgo: 3)], now: now))
    }

    func testTheMostRecentRatingDecides() throws {
        // A sore run, then an easier one: no warning.
        XCTAssertNil(FootCheck.warning(entries: [entry(6, daysAgo: 2), entry(1, daysAgo: 1)], now: now))
        // An easier run, then a sore one: the sore one warns, whatever the order of the list.
        let warning = try XCTUnwrap(FootCheck.warning(entries: [entry(6, daysAgo: 0.5), entry(1, daysAgo: 2)], now: now))
        XCTAssertEqual(warning.value, 6)
    }

    func testUnratedEntriesAreSkipped() throws {
        let entries = [entry(5, daysAgo: 2), entry(-1, daysAgo: 1)]
        XCTAssertEqual(try XCTUnwrap(FootCheck.warning(entries: entries, now: now)).value, 5)
        XCTAssertNil(FootCheck.warning(entries: [entry(-1, daysAgo: 1)], now: now))
        XCTAssertNil(FootCheck.warning(entries: [], now: now))
    }

    func testTestEntriesAndFutureDatesAreIgnored() {
        XCTAssertNil(FootCheck.warning(entries: [entry(9, daysAgo: 1, test: true)], now: now))
        XCTAssertNil(FootCheck.warning(entries: [entry(9, daysAgo: -1)], now: now))
    }

    func testCardText() {
        XCTAssertEqual(FootCheck.cardText(value: 5, day: "tue oct 20"),
                       "foot pain 5 on tue oct 20. go easy today; skip if it still hurts.")
    }

    func testLogSuffix() {
        XCTAssertEqual(FeelText.logSuffix(effort: 7, footPain: 3), " \u{00B7} rpe 7 \u{00B7} foot 3")
        XCTAssertEqual(FeelText.logSuffix(effort: 7, footPain: 0), " \u{00B7} rpe 7")
        XCTAssertEqual(FeelText.logSuffix(effort: 0, footPain: 2), " \u{00B7} foot 2")
        XCTAssertEqual(FeelText.logSuffix(effort: 0, footPain: -1), "")
    }

    func testExportText() {
        XCTAssertEqual(FeelText.exportText(effort: 7, footPain: 0), "rpe 7, foot 0")
        XCTAssertEqual(FeelText.exportText(effort: 0, footPain: 3), "foot 3")
        XCTAssertEqual(FeelText.exportText(effort: 5, footPain: -1), "rpe 5")
        XCTAssertNil(FeelText.exportText(effort: 0, footPain: -1))
    }
}
