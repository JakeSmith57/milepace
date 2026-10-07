import SwiftUI
import SwiftData

/// The "saved" part of the routes screen: loops made with `[ make a loop ]` and kept. A row opens the route;
/// `[ delete ]` removes it. Nothing is shown while there are none.
@MainActor
struct SavedRoutesSection: View {
    let onOpen: (String) -> Void

    @Query(sort: \SavedRoute.createdAt, order: .reverse) private var all: [SavedRoute]

    private var generated: [SavedRoute] {
        return all.filter { $0.kind == SavedRouteKind.generated.rawValue }
    }

    var body: some View {
        if !generated.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("saved")
                ForEach(generated) { route in
                    row(route)
                }
            }
        }
    }

    private func row(_ route: SavedRoute) -> some View {
        let id = route.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                onOpen(id)
            } label: {
                ReadoutRow(key: route.name,
                           value: RouteFormat.distanceText(meters: route.distanceMeters, shape: .loop) + " >",
                           ruled: false,
                           leaders: false)
            }
            .buttonStyle(InstrumentButtonStyle())
            HStack(spacing: Theme.s3) {
                TextBracketButton(title: "delete") {
                    RouteResolver.shared.delete(id: id)
                }
                Spacer(minLength: 0)
            }
            DashedRule()
        }
    }
}
