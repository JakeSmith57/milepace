import SwiftUI
import CoreLocation

/// Where a made loop starts.
enum LoopStart: String, Hashable {
    case home
    case here
}

/// Make a loop: pick a distance and a start, and three loops come back as map cards to save or use. Shown
/// as a sheet from the routes screen. MapKit is asked for the paths, so it needs the network.
@MainActor
struct MakeLoopView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationTracker.self) private var tracker

    /// The distance in half miles (2 is 1.0 mi, 20 is 10.0 mi).
    @State private var halfMiles: Int
    @State private var start: LoopStart = .home
    @State private var viaParks: Bool = false
    @State private var maker = RouteMaker()
    /// The `SavedRoute` id of each candidate (by heading) that was saved.
    @State private var savedIds: [Int: String] = [:]
    @State private var note: String? = nil

    init() {
        _halfMiles = State(initialValue: MakeLoopView.defaultHalfMiles())
    }

    /// Today's planned run in half miles, else 3 mi.
    private static func defaultHalfMiles() -> Int {
        let store = PlanStore.shared
        guard let schedule = store.schedule else { return 6 }
        for index in schedule.todays(today: store.todayOffset) {
            let session = schedule.plan.sessions[index]
            if session.isRunTabSession, let miles = session.miles, miles > 0 {
                return min(20, max(2, Int((miles * 2).rounded())))
            }
        }
        return 6
    }

    private var startOptions: [Choice<LoopStart>] {
        return [Choice(.home, "home"), Choice(.here, "here")]
    }

    private var targetMeters: Double {
        return Double(halfMiles) / 2 * metersPerMile
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace",
                       center: "make a loop",
                       right: "",
                       accessory: StatusAccessory(title: "close", action: { dismiss() }))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s2) {
                    controls
                    makeButton
                    messages
                    cards
                }
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, Theme.s3)
            }
        }
        .instrumentScreen()
        .onDisappear {
            maker.cancel()
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            StepperRow(title: "distance",
                       value: $halfMiles,
                       range: 2...20,
                       format: { String(format: "%.1f mi", Double($0) / 2) })
            ChoiceRow(label: "start", options: startOptions, selection: $start)
            CheckRow(title: "via parks", isOn: $viaParks)
        }
    }

    private var makeButton: some View {
        BracketButton(title: maker.isMaking ? maker.progressText : "make",
                      style: .signal,
                      isEnabled: !maker.isMaking) {
            make()
        }
        .padding(.top, Theme.s2)
    }

    @ViewBuilder
    private var messages: some View {
        if let text = maker.errorText ?? note {
            Text(text)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
        } else if maker.candidates.isEmpty && !maker.isMaking {
            Text("makes three loops of about that distance, heading different ways, with apple maps walking paths. needs the network.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cards: some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            ForEach(maker.candidates) { candidate in
                LoopCard(candidate: candidate,
                         isSaved: savedIds[candidate.id] != nil,
                         onSave: { _ = save(candidate) },
                         onUse: { use(candidate) })
            }
        }
    }

    // MARK: Actions

    /// The start point: nil means home (the maker finds it), "here" needs a location.
    private func startPoint() -> GeoPoint?? {
        switch start {
        case .home:
            return .some(nil)
        case .here:
            if let coordinate = tracker.lastCoordinate {
                return .some(GeoPoint(lat: coordinate.latitude, lon: coordinate.longitude))
            }
            if let location = CLLocationManager().location {
                return .some(GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude))
            }
            return nil
        }
    }

    private func make() {
        guard let point = startPoint() else {
            note = "no location yet. allow location, stand outside for a moment (the run screen finds you), or start from home."
            return
        }
        note = nil
        savedIds = [:]
        maker.make(start: point, targetMeters: targetMeters, viaParks: viaParks)
    }

    private func save(_ candidate: LoopCandidate) -> String? {
        if let id = savedIds[candidate.id] {
            return id
        }
        let id = "gen-" + UUID().uuidString
        let saved = RouteResolver.shared.upsert(id: id,
                                                name: candidate.name,
                                                kind: .generated,
                                                points: candidate.points,
                                                stops: candidate.stops,
                                                notes: "made with make a loop")
        guard saved else {
            note = "couldn't save the loop."
            return nil
        }
        savedIds[candidate.id] = id
        return id
    }

    private func use(_ candidate: LoopCandidate) {
        guard let id = save(candidate) else { return }
        PlanStore.shared.selectedRouteId = id
        note = "set for your next outdoor run."
    }
}

/// One made loop: the map, its distance and time at easy pace, and what to do with it.
private struct LoopCard: View {
    let candidate: LoopCandidate
    let isSaved: Bool
    let onSave: () -> Void
    let onUse: () -> Void

    private var easyPace: Double {
        return RouteFormat.middle(of: AppSettings.zones.easy)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            Text(candidate.name)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
            RouteMapView(points: candidate.points, height: 180)
            ReadoutRow(key: "distance",
                       value: RouteFormat.distanceText(meters: candidate.meters, shape: .loop),
                       keyWidth: 10)
            ReadoutRow(key: "est. time",
                       value: RouteFormat.timeText(meters: candidate.meters, secondsPerMile: easyPace),
                       keyWidth: 10)
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.s2) {
            BracketButton(title: isSaved ? "saved" : "save", minHeight: 48, isEnabled: !isSaved) {
                onSave()
            }
            BracketButton(title: "use", minHeight: 48, action: onUse)
        }
    }
}
