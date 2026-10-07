import SwiftUI
import SwiftData

/// The "yours" part of the routes screen: routes found from two or more of your saved GPS runs. The grouping
/// runs in the background (`YourRoutes`) on plain values taken from the runs here.
@MainActor
struct YourRoutesSection: View {
    @Query private var runs: [RunRecord]

    /// The route being renamed and the text typed so far.
    @State private var renamingKey: String? = nil
    @State private var draft: String = ""

    private var service: YourRoutes {
        return YourRoutes.shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("yours")
            content
        }
        .onAppear {
            refresh()
        }
        .onChange(of: runs.count) { _, _ in
            refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if service.routes.isEmpty {
            Text(service.isComputing ? "looking for routes you repeat..." : "run the same route twice and it shows up here.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.s2)
        } else {
            ForEach(service.routes) { route in
                YourRouteRow(route: route,
                             name: service.displayName(route),
                             isRenaming: renamingKey == route.key,
                             draft: $draft,
                             onUse: { service.use(route) },
                             onRename: { startRename(route) },
                             onDone: { finishRename(route) })
            }
        }
    }

    /// Plain values for the background grouping: outdoor GPS runs of the real plan with a saved path.
    private func refresh() {
        var inputs: [RunPathInput] = []
        for run in runs where !run.isTest && !run.isTreadmill && !run.routeData.isEmpty {
            inputs.append(RunPathInput(id: String(Int(run.date.timeIntervalSince1970)),
                                       date: run.date,
                                       seconds: run.durationSeconds,
                                       meters: run.distanceMeters,
                                       routeData: run.routeData))
        }
        service.refresh(inputs: inputs)
    }

    private func startRename(_ route: YourRoute) {
        draft = service.displayName(route)
        renamingKey = route.key
    }

    private func finishRename(_ route: YourRoute) {
        RouteNameStore.set(draft, for: route.key)
        renamingKey = nil
        // A route already chosen for the next run keeps its saved name in step.
        if PlanStore.shared.selectedRouteId == YourRoutes.savedId(for: route) {
            service.use(route)
        }
    }
}

/// One route found from runs: name, how often and how fast, and `[ use ]` / `[ rename ]`.
private struct YourRouteRow: View {
    let route: YourRoute
    let name: String
    let isRenaming: Bool
    @Binding var draft: String
    let onUse: () -> Void
    let onRename: () -> Void
    let onDone: () -> Void

    private var details: String {
        var parts: [String] = ["\(route.count) runs"]
        if route.bestSeconds > 0 {
            parts.append("best " + formatDuration(route.bestSeconds))
        }
        parts.append("last " + ReadoutFormat.day(route.lastDate))
        return parts.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            Text(name)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.s2)
            Text(details)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
            if isRenaming {
                renameField
            } else {
                buttons
            }
            DashedRule()
        }
    }

    private var buttons: some View {
        HStack(spacing: Theme.s3) {
            TextBracketButton(title: "use", action: onUse)
            TextBracketButton(title: "rename", action: onRename)
            Spacer(minLength: 0)
        }
    }

    private var renameField: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            BoxedField(placeholder: "name", text: $draft, lines: 1...2)
            HStack(spacing: Theme.s3) {
                TextBracketButton(title: "done", action: onDone)
                Spacer(minLength: 0)
            }
        }
    }
}
