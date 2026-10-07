import SwiftUI

/// The micro line under Today's start row: "where: mccarren park track >". A tap opens that route's detail
/// sheet, or the routes screen when the recommendation has no route to open (such as "any 4 mi route").
/// Drawn on the purple session card, so it uses the on-signal color.
@MainActor
struct TodayWhereLine: View {
    let pick: RouteRecommendation.Pick

    @State private var sheet: RouteRef? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open()
            } label: {
                Text("where: " + pick.label + " >")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.onSignal)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(InstrumentButtonStyle())
            noteLine
        }
        .sheet(item: $sheet) { ref in
            RouteDetailView(routeId: ref.id)
        }
    }

    @ViewBuilder
    private var noteLine: some View {
        if let note = pick.note {
            Text(note)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.onSignal)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func open() {
        if let id = pick.routeId {
            sheet = RouteRef(id: id)
        } else {
            PlanStore.shared.open(.routes)
        }
    }
}
