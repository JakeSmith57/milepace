import SwiftUI
import SwiftData

/// Where to run: the curated routes near home, with their distance once resolved. Opened from Today and
/// from the run screen's route row; a row opens the route as a sheet. Resolving uses the network, the
/// result is kept on the device.
@MainActor
struct RoutesView: View {
    @AppStorage(SettingsKey.homeAddress) private var homeAddress: String = RouteHome.defaultAddress

    @Query private var saved: [SavedRoute]

    @State private var selected: RouteRef? = nil

    private var catalog: RouteCatalog? {
        return RouteCatalogLoader.bundled
    }

    private var resolver: RouteResolver {
        return RouteResolver.shared
    }

    /// "17 Monitor St": the street part of the saved home address.
    private var homeShort: String {
        let trimmed = homeAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return RouteFormat.shortAddress(trimmed.isEmpty ? RouteHome.defaultAddress : trimmed)
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace",
                       center: "routes",
                       right: "",
                       accessory: StatusAccessory(title: "today", action: { PlanStore.shared.goHome() }))
            ScrollView {
                content
            }
        }
        .instrumentScreen()
        .sheet(item: $selected) { ref in
            RouteDetailView(routeId: ref.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let catalog = catalog {
            VStack(alignment: .leading, spacing: 0) {
                Text("from " + homeShort)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, Theme.s2)
                nearHome(catalog)
                resolveArea(catalog)
                Text("the network is used only to resolve a route. resolved routes are saved on this phone and work without it.")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.s3)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.bottom, Theme.s4)
        } else {
            Text("routes file missing.")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.dim)
                .padding(Theme.s3)
        }
    }

    private func nearHome(_ catalog: RouteCatalog) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("near home")
            ForEach(catalog.routes) { route in
                row(route)
            }
        }
    }

    private func savedRoute(_ id: String) -> SavedRoute? {
        return saved.first { $0.id == id }
    }

    private func row(_ route: CuratedRoute) -> some View {
        let found = savedRoute(route.id)
        let meters = found?.distanceMeters ?? 0
        return Button {
            selected = RouteRef(id: route.id)
        } label: {
            RouteRowLabel(name: route.name,
                          distance: RouteFormat.distanceText(meters: meters, shape: route.shape),
                          tags: route.tags.joined(separator: " \u{00B7} "),
                          error: resolver.errors[route.id],
                          busy: resolver.busyIds.contains(route.id))
        }
        .buttonStyle(InstrumentButtonStyle())
    }

    // MARK: Resolve all

    /// True when every route has a saved path that is not stale.
    private func allFresh(_ catalog: RouteCatalog) -> Bool {
        for route in catalog.routes {
            guard let found = savedRoute(route.id), !resolver.isStale(found) else {
                return false
            }
        }
        return true
    }

    @ViewBuilder
    private func resolveArea(_ catalog: RouteCatalog) -> some View {
        if resolver.isBatchRunning {
            Text("resolving \(resolver.batchDone) / \(resolver.batchTotal)")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .padding(.top, Theme.s3)
        } else {
            BracketButton(title: allFresh(catalog) ? "refresh all" : "resolve all") {
                let force = allFresh(catalog)
                Task {
                    await RouteResolver.shared.resolveAll(catalog: catalog, force: force)
                }
            }
            .padding(.top, Theme.s3)
        }
    }
}

/// One row of the routes list: name and distance, the tags under them, and the error if it failed.
private struct RouteRowLabel: View {
    let name: String
    let distance: String
    let tags: String
    let error: String?
    let busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
                Text(name)
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.fg)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(busy ? "..." : distance)
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            Text(tags)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
            errorLine
            DashedRule()
                .padding(.top, Theme.s1)
        }
        .padding(.top, Theme.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var errorLine: some View {
        if let message = error {
            Text(message)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
