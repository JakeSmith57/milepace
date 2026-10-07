import SwiftUI

/// The route a run is following, as the run screen needs it: loaded once when the run starts.
struct FollowedRoute: Equatable {
    let id: String
    let points: [GeoPoint]
    let meters: Double
}

/// The data view's "route 1.2 / 3.1 mi" row. It keeps how far along the route the last fix was and moves
/// that forward as fixes arrive (`RouteGeometry.progress`: an out-and-back or a loop never jumps back to
/// the first pass). When the view is rebuilt, for example after a switch to the map and back, it replays
/// the whole run so far.
struct RouteFollowRow: View {
    let followed: FollowedRoute
    let liveRoute: [RoutePoint]

    @State private var along: Double? = nil
    @State private var processed: Int = 0

    var body: some View {
        ReadoutRow(key: "route", value: RouteFormat.followText(along: along, total: followed.meters))
            .onAppear {
                advance()
            }
            .onChange(of: liveRoute.count) { _, _ in
                advance()
            }
    }

    private func advance() {
        if liveRoute.count < processed {
            processed = 0
            along = nil
        }
        guard liveRoute.count > processed else { return }
        let fresh = liveRoute[processed...].map { point in
            GeoPoint(lat: point.lat, lon: point.lon)
        }
        along = RouteGeometry.follow(track: fresh, on: followed.points, startingAlong: along)
        processed = liveRoute.count
    }
}
