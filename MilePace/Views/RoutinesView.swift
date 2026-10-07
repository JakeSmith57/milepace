import SwiftUI

/// The routine library: warm-ups, cool-downs and strength work. Opened from Today; a row opens the
/// routine as a sheet (the screens are not inside a navigation stack).
@MainActor
struct RoutinesView: View {
    @State private var selected: Routine? = nil

    private var library: RoutineLibrary? {
        return RoutineLoader.bundled
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace",
                       center: "routines",
                       right: "",
                       accessory: StatusAccessory(title: "today", action: { PlanStore.shared.goHome() }))
            ScrollView {
                content
            }
        }
        .instrumentScreen()
        .sheet(item: $selected) { routine in
            RoutineDetailView(routine: routine)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let library = library {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(RoutineGroup.allCases, id: \.self) { group in
                    groupSection(group, library)
                }
                Text("videos open in youtube. links marked 'search' show a few options to pick from.")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.s3)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.bottom, Theme.s4)
        } else {
            Text("routines file missing.")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.dim)
                .padding(Theme.s3)
        }
    }

    private func groupSection(_ group: RoutineGroup, _ library: RoutineLibrary) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(group.title)
            ForEach(library.routines(in: group)) { routine in
                row(routine)
            }
        }
    }

    private func row(_ routine: Routine) -> some View {
        return Button {
            selected = routine
        } label: {
            ReadoutRow(key: routine.title, value: "\(routine.minutes) min >", leaders: false)
        }
        .buttonStyle(InstrumentButtonStyle())
    }
}
