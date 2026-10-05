import SwiftUI

/// Every plan week grouped by phase. Tap a week for its sessions.
@MainActor
struct PlanOverviewView: View {
    let onClose: () -> Void

    @State private var detailWeek: Int? = nil

    private static let phaseNames: [String] = [
        "build running legs",
        "aerobic power",
        "mile-specific",
        "sharpen and race"
    ]

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    private var store: PlanStore {
        return PlanStore.shared
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "plan", right: "\(store.plan?.weeks.count ?? 0) weeks")
            if let week = detailWeek {
                PlanWeekDetailView(week: week, onBack: { detailWeek = nil })
            } else {
                overview
            }
        }
        .instrumentScreen()
    }

    // MARK: Overview

    @ViewBuilder
    private var overview: some View {
        if let schedule = store.schedule {
            VStack(spacing: 0) {
                backBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ReadoutRow(key: "race",
                                   value: PlanFormat.dayLabel(offset: schedule.raceDayOffset, start: store.startDate))
                        ForEach(phases(schedule), id: \.self) { phase in
                            phaseSection(schedule, phase)
                        }
                    }
                    .padding(.horizontal, Theme.s3)
                    .padding(.bottom, Theme.s3)
                }
            }
        } else {
            Text("plan file missing.")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.dim)
                .padding(Theme.s3)
            Spacer(minLength: 0)
        }
    }

    private var backBar: some View {
        HStack {
            BracketButton(title: "close", minHeight: 44, fullWidth: false) {
                onClose()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.s3)
        .padding(.top, Theme.s2)
    }

    /// The phase numbers the plan's weeks use, in order.
    private func phases(_ schedule: PlanSchedule) -> [Int] {
        return Array(Set(schedule.plan.weeks.map { $0.phase })).sorted()
    }

    private func phaseTitle(_ phase: Int) -> String {
        let names = PlanOverviewView.phaseNames
        let name = (phase >= 1 && phase <= names.count) ? names[phase - 1] : ""
        return "phase \(phase)  " + name
    }

    /// "weeks 15-24", read from the plan's weeks; empty when the phase has none.
    private func phaseRange(_ weeks: [PlanWeek]) -> String {
        let numbers = weeks.map { $0.week }
        guard let first = numbers.min(), let last = numbers.max() else { return "" }
        return first == last ? "week \(first)" : "weeks \(first)-\(last)"
    }

    private func phaseSection(_ schedule: PlanSchedule, _ phase: Int) -> some View {
        let weeks = schedule.plan.weeks.filter { $0.phase == phase }
        let current = schedule.currentWeek(today: store.todayOffset)
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(phaseTitle(phase))
            Text(phaseRange(weeks))
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .padding(.vertical, Theme.s1)
            ForEach(weeks, id: \.week) { week in
                weekRow(schedule, week, current: current)
            }
        }
    }

    private func tagText(_ week: PlanWeek) -> String {
        var tags: [String] = []
        if week.recovery {
            tags.append("rec")
        }
        if week.timeTrial {
            tags.append("tt")
        }
        if week.race {
            tags.append("race")
        }
        return tags.joined(separator: " ")
    }

    private func weekRow(_ schedule: PlanSchedule, _ week: PlanWeek, current: Int) -> some View {
        let isCurrent = week.week == current
        let isPast = week.week < current
        let textColor: Color = isCurrent ? Theme.onSignal : (isPast ? Theme.dim : Theme.fg)
        let date = PlanFormat.shortDate(offset: schedule.startOffset(ofWeek: week.week), start: store.startDate)
        return Button {
            detailWeek = week.week
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: Theme.s2) {
                    Text(String(format: "wk %02d", week.week))
                    Text(date)
                    Spacer(minLength: 0)
                    Text(PlanFormat.miles(week.miles) + " mi")
                    Text(tagText(week))
                        .font(Theme.mono(.micro))
                        .frame(width: 44, alignment: .trailing)
                }
                .font(Theme.mono(.body))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.vertical, Theme.s2)
                .padding(.horizontal, isCurrent ? Theme.s2 : 0)
                .background(isCurrent ? Theme.plan : Color.clear)
                DashedRule()
            }
        }
        .buttonStyle(InstrumentButtonStyle())
    }
}

/// One plan week: its sessions with date and status.
@MainActor
struct PlanWeekDetailView: View {
    let week: Int
    let onBack: () -> Void

    private var store: PlanStore {
        return PlanStore.shared
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                BracketButton(title: "back", minHeight: 44, fullWidth: false) {
                    onBack()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.top, Theme.s2)
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let schedule = store.schedule {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(schedule)
                    ForEach(sessionIndices(schedule), id: \.self) { index in
                        sessionRow(schedule, index)
                    }
                }
                .padding(.horizontal, Theme.s3)
                .padding(.bottom, Theme.s3)
            }
        } else {
            Text("plan file missing.")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.dim)
                .padding(Theme.s3)
            Spacer(minLength: 0)
        }
    }

    private func sessionIndices(_ schedule: PlanSchedule) -> [Int] {
        return schedule.plan.sessions.indices.filter { schedule.plan.sessions[$0].week == week }
    }

    @ViewBuilder
    private func header(_ schedule: PlanSchedule) -> some View {
        SectionHeader("week \(week)")
        if let planWeek = schedule.plan.weeks.first(where: { $0.week == week }) {
            ReadoutRow(key: "miles", value: PlanFormat.miles(planWeek.miles) + " mi")
            ReadoutRow(key: "phase", value: "\(planWeek.phase)")
            if planWeek.recovery {
                ReadoutRow(key: "recovery", value: "week")
            }
            if planWeek.timeTrial {
                ReadoutRow(key: "time trial", value: "this week")
            }
            if planWeek.race {
                ReadoutRow(key: "race", value: "this week")
            }
        }
        SectionHeader("sessions")
    }

    private func statusText(_ schedule: PlanSchedule, _ index: Int) -> String {
        switch schedule.status(index) {
        case .some(.done):
            return "done"
        case .some(.skipped):
            return "skipped"
        case .none:
            let day = schedule.dayOffset(index)
            if day < store.todayOffset { return "missed" }
            if day == store.todayOffset { return "today" }
            return ""
        }
    }

    private func sessionRow(_ schedule: PlanSchedule, _ index: Int) -> some View {
        let session = schedule.plan.sessions[index]
        let status = statusText(schedule, index)
        var detail = status
        if let note = session.note, !note.isEmpty {
            detail = status.isEmpty ? note : note + " \u{00B7} " + status
        }
        return VStack(alignment: .leading, spacing: 0) {
            ReadoutRow(key: PlanFormat.dayLabel(offset: schedule.dayOffset(index), start: store.startDate),
                       value: session.title,
                       ruled: false,
                       leaders: false)
            if !detail.isEmpty {
                Text(detail)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, Theme.s2)
            }
            DashedRule()
        }
    }
}
