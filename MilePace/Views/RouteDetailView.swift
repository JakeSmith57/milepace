import SwiftUI
import SwiftData
import MapKit
import CoreLocation

/// Which route a sheet shows. `Identifiable` so it can drive `.sheet(item:)`.
struct RouteRef: Identifiable, Equatable {
    let id: String
}

/// One route: the map, distance and an easy-pace time, the notes, and what to do with it. Shown as a sheet.
@MainActor
struct RouteDetailView: View {
    let routeId: String

    @Environment(\.dismiss) private var dismiss
    @Query private var saved: [SavedRoute]

    private var resolver: RouteResolver {
        return RouteResolver.shared
    }

    private var store: PlanStore {
        return PlanStore.shared
    }

    private var curated: CuratedRoute? {
        return RouteCatalogLoader.bundled?.route(id: routeId)
    }

    private var savedRoute: SavedRoute? {
        return saved.first { $0.id == routeId }
    }

    private var title: String {
        return curated?.name ?? savedRoute?.name ?? "route"
    }

    private var shape: RouteShape {
        return curated?.shape ?? .loop
    }

    private var isSelected: Bool {
        return store.selectedRouteId == routeId
    }

    private var isBusy: Bool {
        return resolver.busyIds.contains(routeId)
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace",
                       center: title,
                       right: "",
                       accessory: StatusAccessory(title: "close", action: { dismiss() }))
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.s3) {
                    mapBlock
                    infoRows
                    notesText
                    errorText
                    buttons
                }
                .padding(.horizontal, Theme.s3)
                .padding(.vertical, Theme.s3)
            }
        }
        .instrumentScreen()
    }

    // MARK: Content

    @ViewBuilder
    private var mapBlock: some View {
        if let route = savedRoute, route.pointsData.isEmpty == false {
            RouteMapView(points: route.points)
        } else {
            Text("not resolved yet. [ resolve ] finds the path with apple maps (needs the network once).")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var infoRows: some View {
        if let route = savedRoute, route.distanceMeters > 0 {
            VStack(alignment: .leading, spacing: 0) {
                ReadoutRow(key: "distance",
                           value: RouteFormat.distanceText(meters: route.distanceMeters, shape: shape),
                           keyWidth: 10)
                ReadoutRow(key: "est. time",
                           value: RouteFormat.timeText(meters: route.distanceMeters, secondsPerMile: easyPace),
                           keyWidth: 10)
                ReadoutRow(key: "easy pace",
                           value: formatPace(secondsPerMile: easyPace) + " /mi",
                           keyWidth: 10)
            }
        }
    }

    /// The middle of the easy zone, in seconds per mile.
    private var easyPace: Double {
        return RouteFormat.middle(of: AppSettings.zones.easy)
    }

    private var notes: String {
        return curated?.notes ?? savedRoute?.notes ?? ""
    }

    @ViewBuilder
    private var notesText: some View {
        if !notes.isEmpty {
            Text(notes)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var errorText: some View {
        if let message = resolver.errors[routeId] {
            Text(message)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Buttons

    private var hasPath: Bool {
        return savedRoute?.pointsData.isEmpty == false
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            BracketButton(title: isSelected ? "stop using this route" : "use for today's run",
                          style: isSelected ? .plain : .signal,
                          isEnabled: hasPath) {
                toggleUse()
            }
            if isSelected {
                Text("set for your next outdoor run. the run screen shows it, and the map draws it.")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BracketButton(title: "open in maps", isEnabled: hasPath) {
                openInMaps()
            }
            refreshButton
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        if let route = curated {
            BracketButton(title: isBusy ? "resolving..." : (hasPath ? "refresh" : "resolve"),
                          isEnabled: !isBusy) {
                Task {
                    await RouteResolver.shared.ensureResolved(route, force: true)
                }
            }
        }
    }

    // MARK: Actions

    private func toggleUse() {
        if isSelected {
            store.selectedRouteId = nil
        } else {
            store.selectedRouteId = routeId
        }
    }

    /// Apple Maps with walking directions to the route's first stop (the track, for the track route).
    private func openInMaps() {
        guard let route = savedRoute, let stop = resolver.firstStop(of: route) else { return }
        let coordinate = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lon)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = title
        _ = item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
