import SwiftUI

/// The route a run is following, as the run screen needs it: loaded once when the run starts.
struct FollowedRoute: Equatable {
    let id: String
    let points: [GeoPoint]
    let meters: Double
}

/// The data view's "route 1.2 / 3.1 mi" row. The progress itself lives in `RouteFollowState`, which
/// `RouteFollowMonitor` keeps up to date whichever view (data or map) is showing.
struct RouteFollowRow: View {
    let state: RouteFollowState
    let total: Double

    var body: some View {
        ReadoutRow(key: "route", value: RouteFormat.followText(along: state.along, total: total))
    }
}

/// An invisible view that moves the run along the followed route as saved fixes arrive, and says
/// "Off route." once per excursion (through `Coach`, so the voice switch applies; the setting `off-route
/// cue` turns it off). Only shown for an outdoor run that follows a route.
struct RouteFollowMonitor: View {
    let state: RouteFollowState
    let followed: FollowedRoute
    let liveRoute: [RoutePoint]

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                update()
            }
            .onChange(of: liveRoute.count) { _, _ in
                update()
            }
    }

    private func update() {
        let events = state.advance(liveRoute: liveRoute, on: followed.points)
        // Only the latest event matters: a catch-up after a gap must not announce an old excursion.
        if events.last == .off && AppSettings.offRouteCue {
            Coach.shared.announceOffRoute()
        }
    }
}
