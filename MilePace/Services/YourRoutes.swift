import Foundation
import Observation

/// The routes found from the runner's saved GPS runs (two or more runs on the same path). The grouping runs
/// on a background thread on plain values (`RunPathInput`), and the result is kept in memory until the runs
/// change, so opening the routes screen again costs nothing.
@Observable
@MainActor
final class YourRoutes {
    static let shared = YourRoutes()

    private(set) var routes: [YourRoute] = []
    private(set) var isComputing: Bool = false

    @ObservationIgnored private var computedSignature: String? = nil
    @ObservationIgnored private var pendingSignature: String? = nil

    private init() {}

    /// A short fingerprint of the runs: how many, and when they were made.
    nonisolated static func signature(_ inputs: [RunPathInput]) -> String {
        var total = 0
        for input in inputs {
            total += Int(input.date.timeIntervalSince1970)
        }
        return "\(inputs.count)-\(total)"
    }

    /// Groups the runs unless that was done for these very runs already.
    func refresh(inputs: [RunPathInput]) {
        let signature = YourRoutes.signature(inputs)
        guard signature != computedSignature, signature != pendingSignature else { return }
        pendingSignature = signature
        isComputing = true
        let home = RouteHome.point
        Task {
            let found = await Task.detached(priority: .utility) { () -> [YourRoute] in
                return RouteMatching.groups(from: inputs, home: home)
            }.value
            // A newer set of runs started meanwhile: that result will replace this one.
            guard self.pendingSignature == signature else { return }
            self.routes = found
            self.computedSignature = signature
            self.pendingSignature = nil
            self.isComputing = false
        }
    }

    /// The name shown for a route: the one the runner typed, else the default.
    func displayName(_ route: YourRoute) -> String {
        return RouteNameStore.name(for: route.key) ?? route.defaultName
    }

    /// The id of the `SavedRoute` that holds a route's path.
    static func savedId(for route: YourRoute) -> String {
        return "learned-" + route.key
    }

    /// Saves the route's latest path as a `SavedRoute` and chooses it for the next outdoor run.
    func use(_ route: YourRoute) {
        let id = YourRoutes.savedId(for: route)
        let saved = RouteResolver.shared.upsert(id: id,
                                                name: displayName(route),
                                                kind: .learned,
                                                points: route.points,
                                                stops: [],
                                                notes: "from \(route.count) of your runs")
        if saved {
            PlanStore.shared.selectedRouteId = id
        }
    }
}
