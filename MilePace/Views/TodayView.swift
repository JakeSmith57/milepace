import SwiftUI
import SwiftData

/// First tab: what to do today, what was missed, and the week at a glance.
@MainActor
struct TodayView: View {
    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile

    @Query private var runs: [RunRecord]
    @Query private var workouts: [WorkoutRecord]

    @Environment(\.scenePhase) private var scenePhase

    @State private var showOverview: Bool = false

    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var store: PlanStore {
        return PlanStore.shared
    }

    private var today: Int {
        return store.todayOffset
    }

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    private func dayLabel(_ offset: Int) -> String {
        return PlanFormat.dayLabel(offset: offset, start: store.startDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusLine
            ScrollView {
                content
            }
        }
        .instrumentScreen()
        .sheet(isPresented: $showOverview) {
            PlanOverviewView(onClose: { showOverview = false })
        }
        .onAppear {
            store.refresh()
            reconcile()
        }
        .onChange(of: runs.count) { _, _ in
            reconcile()
        }
        .onChange(of: workouts.count) { _, _ in
            reconcile()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refresh()
                reconcile()
            }
        }
        .onReceive(ticker) { _ in
            store.refresh()
        }
    }

    private func reconcile() {
        store.reconcile(runDates: runs.map { $0.date },
                        workoutDates: workouts.map { $0.date })
    }

    // MARK: Status line

    private var statusTexts: (center: String, right: String) {
        guard let schedule = store.schedule else {
            return ("plan", "")
        }
        if today < 0 {
            return ("starts " + PlanFormat.shortDate(offset: 0, start: store.startDate), "")
        }
        if today > schedule.raceDayOffset {
            return ("done", "")
        }
        let week = schedule.currentWeek(today: today)
        var phase = ""
        if let planWeek = schedule.plan.weeks.first(where: { $0.week == week }) {
            phase = "phase \(planWeek.phase)"
        }
        return ("week \(week) / \(schedule.plan.weeks.count)", phase)
    }

    private var statusLine: some View {
        let texts = statusTexts
        return StatusLine(left: "milepace", center: texts.center, right: texts.right)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let schedule = store.schedule {
            planColumn(schedule)
        } else {
            Text("plan file missing.")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.dim)
                .padding(Theme.s3)
        }
    }

    private func planColumn(_ schedule: PlanSchedule) -> some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            missedSection(schedule)
            todaySection(schedule)
            doctorNote
            weekSection(schedule)
            BracketButton(title: "full plan") {
                showOverview = true
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s3)
    }

    private func micro(_ text: String) -> some View {
        return Text(text)
            .font(Theme.mono(.micro))
    }

    @ViewBuilder
    private var doctorNote: some View {
        if today >= 0 && today < 7 {
            Text("see a doctor about your foot before running past week 4.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
        }
    }

    // MARK: Missed

    @ViewBuilder
    private func missedSection(_ schedule: PlanSchedule) -> some View {
        if let index = schedule.firstMissed(today: today) {
            missedCard(schedule, index)
        }
    }

    private func pushNote(_ schedule: PlanSchedule, _ index: Int) -> String {
        let days = max(0, today - schedule.dayOffset(index))
        let pushed = PlanSchedule(plan: schedule.plan,
                                  progress: schedule.pushingBack(missed: index, today: today))
        let race = dayLabel(pushed.raceDayOffset)
        return "doing it today moves the rest of the plan back " + PlanFormat.daysText(days) + ". race moves to " + race + "."
    }

    private func missedCard(_ schedule: PlanSchedule, _ index: Int) -> some View {
        let session = schedule.plan.sessions[index]
        return VStack(alignment: .leading, spacing: Theme.s2) {
            micro("missed " + dayLabel(schedule.dayOffset(index)))
            Text(session.title)
                .font(Theme.mono(.body))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.s2) {
                BracketButton(title: "do it today", style: .plan, minHeight: 48) {
                    store.doItToday(missed: index)
                }
                BracketButton(title: "skip", style: .outlineOnInverted, minHeight: 48) {
                    store.skip(index)
                }
            }
            .padding(.top, Theme.s1)
            micro(pushNote(schedule, index))
        }
        .foregroundStyle(Theme.bg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s3)
        .background(Theme.fg)
    }

    // MARK: Today

    @ViewBuilder
    private func todaySection(_ schedule: PlanSchedule) -> some View {
        if today < 0 {
            preStartBlock(schedule)
        } else if today > schedule.raceDayOffset {
            finishedBlock
        } else {
            todayStack(schedule)
        }
    }

    private func todayStack(_ schedule: PlanSchedule) -> some View {
        let pending = schedule.todays(today: today)
        return VStack(alignment: .leading, spacing: Theme.s3) {
            if pending.isEmpty {
                restBlock(schedule)
            } else {
                ForEach(pending, id: \.self) { index in
                    todayBlock(schedule, index)
                }
            }
        }
    }

    private func todayBlock(_ schedule: PlanSchedule, _ index: Int) -> some View {
        let session = schedule.plan.sessions[index]
        return VStack(alignment: .leading, spacing: Theme.s2) {
            micro("today")
            Text(session.title)
                .font(Theme.mono(.title))
                .fixedSize(horizontal: false, vertical: true)
            detailLines(session)
            BracketButton(title: startTitle(session), style: .inverted) {
                store.start(index)
            }
            .padding(.top, Theme.s2)
            HStack(spacing: Theme.s3) {
                TextBracketButton(title: "mark done", color: Theme.onSignal) {
                    store.markDone(index)
                }
                TextBracketButton(title: "skip", color: Theme.onSignal) {
                    store.skip(index)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Theme.onSignal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s3)
        .background(Theme.plan)
    }

    private func startTitle(_ session: PlanSession) -> String {
        switch session.kind {
        case .track:
            return trackSpec(session) == nil ? "open track" : "start"
        case .easy, .long, .road, .timeTrial, .race, .other:
            return "start"
        }
    }

    private func roadSpec(_ session: PlanSession) -> RoadWorkoutSpec? {
        guard let name = session.preset else { return nil }
        return RoadWorkoutPresets.all.first(where: { $0.name == name })
    }

    private func trackSpec(_ session: PlanSession) -> WorkoutSpec? {
        guard let id = session.preset else { return nil }
        let preset = WorkoutPresets.all.first(where: { $0.id == id })
        return preset?.spec(zones: zones, goalMile: goalMile)
    }

    private func trackLine(_ spec: WorkoutSpec) -> String {
        var text = formatSplit(spec.targetRepSeconds) + " per rep"
        if spec.repDistance != 400 {
            text += " \u{00B7} " + formatSplit(spec.targetPer400) + " per 400"
        }
        return text
    }

    private func detailText(_ session: PlanSession) -> [String] {
        var lines: [String] = []
        switch session.kind {
        case .easy, .long:
            var line = ""
            if let miles = session.miles {
                line = PlanFormat.miles(miles) + " mi, "
            }
            line += "conversational, " + ReadoutFormat.paceRange(zones.easy) + " /mi"
            lines.append(line)
        case .road:
            if let spec = roadSpec(session) {
                let range = spec.target.range(zones: zones, goalMile: goalMile)
                lines.append(spec.target.rawValue + " " + ReadoutFormat.paceRange(range) + " /mi")
            }
        case .track:
            if let spec = trackSpec(session) {
                lines.append(trackLine(spec))
            }
        case .timeTrial, .race:
            lines.append("goal " + formatPace(secondsPerMile: goalMile))
        case .other:
            break
        }
        if let note = session.note, !note.isEmpty {
            lines.append(note)
        }
        return lines
    }

    private func detailLines(_ session: PlanSession) -> some View {
        let lines = detailText(session)
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { item in
                Text(item.element)
                    .font(Theme.mono(.micro))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Rest, before start, after the race

    private func outlined<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        return VStack(alignment: .leading, spacing: Theme.s2) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s3)
        .overlay(Rectangle().strokeBorder(Theme.fg, lineWidth: Theme.rule))
    }

    private func heading(_ text: String) -> some View {
        return Text(text)
            .font(Theme.mono(.title))
            .foregroundStyle(Theme.fg)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bodyText(_ text: String) -> some View {
        return Text(text)
            .font(Theme.mono(.body))
            .foregroundStyle(Theme.dim)
    }

    private func restBlock(_ schedule: PlanSchedule) -> some View {
        let logged = !schedule.indices(onDay: today).isEmpty
        return outlined {
            heading(logged ? "done for today" : "rest or cross-train")
            bodyText(logged ? "today's session is logged." : "tennis or an easy ride is fine.")
            nextLine(schedule)
        }
    }

    @ViewBuilder
    private func nextLine(_ schedule: PlanSchedule) -> some View {
        if let index = schedule.next(after: today) {
            Text("next: " + dayLabel(schedule.dayOffset(index)) + "  " + schedule.plan.sessions[index].title)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
        }
    }

    private func preStartBlock(_ schedule: PlanSchedule) -> some View {
        return outlined {
            heading("plan starts " + dayLabel(0))
            bodyText("in " + PlanFormat.daysText(-today))
            weekOneList(schedule)
        }
    }

    private func weekOneList(_ schedule: PlanSchedule) -> some View {
        let first = schedule.plan.sessions.indices.filter { schedule.plan.sessions[$0].week == 1 }
        return VStack(spacing: 0) {
            ForEach(first, id: \.self) { index in
                ReadoutRow(key: dayLabel(schedule.dayOffset(index)),
                           value: schedule.plan.sessions[index].title,
                           size: .micro)
            }
        }
        .padding(.top, Theme.s2)
    }

    private var finishedBlock: some View {
        return outlined {
            heading("plan complete")
            bodyText("the race is behind you.")
        }
    }

    // MARK: Week strip

    private func weekSection(_ schedule: PlanSchedule) -> some View {
        let start = schedule.stripStart(today: today)
        return VStack(alignment: .leading, spacing: Theme.s2) {
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { column in
                    stripCell(schedule, day: start + column)
                }
            }
            weekSummary(schedule, start: start)
        }
    }

    private func stripCell(_ schedule: PlanSchedule, day: Int) -> some View {
        let cell = schedule.stripCell(day: day, today: today)
        let date = PlanCalendar.date(forOffset: day, start: store.startDate)
        return VStack(spacing: 2) {
            Text(PlanFormat.weekdayLetter(date))
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
            cellBox(cell)
        }
        .frame(maxWidth: .infinity)
    }

    private func cellBox(_ cell: StripCell) -> some View {
        return Text(cell.label)
            .font(Theme.mono(.micro))
            .foregroundStyle(cellText(cell.state))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(cellFill(cell.state))
            .overlay(cellBorder(cell.state))
    }

    private func cellText(_ state: StripState) -> Color {
        switch state {
        case .today: return Theme.onSignal
        case .done: return Theme.bg
        case .rest, .skipped: return Theme.dim
        case .planned, .missed: return Theme.fg
        }
    }

    private func cellFill(_ state: StripState) -> Color {
        switch state {
        case .today: return Theme.plan
        case .done: return Theme.fg
        case .rest, .skipped, .planned, .missed: return Theme.bg
        }
    }

    @ViewBuilder
    private func cellBorder(_ state: StripState) -> some View {
        switch state {
        case .planned, .skipped:
            Rectangle().strokeBorder(Theme.dim, lineWidth: 1)
        case .missed:
            Rectangle().strokeBorder(Theme.fg, lineWidth: Theme.rule)
        case .rest, .today, .done:
            EmptyView()
        }
    }

    // MARK: Week summary

    /// Miles from saved runs in the seven days of the strip.
    private func loggedMiles(start: Int) -> Double {
        let calendar = PlanCalendar.local
        var meters = 0.0
        for run in runs {
            let day = PlanCalendar.dayOffset(of: run.date, start: store.startDate, calendar: calendar)
            if day >= start && day < start + 7 {
                meters += run.distanceMeters
            }
        }
        return meters / metersPerMile
    }

    private func timeTrialTag(_ week: Int, _ schedule: PlanSchedule) -> String {
        for index in schedule.plan.sessions.indices {
            let session = schedule.plan.sessions[index]
            if session.week == week && session.kind == .timeTrial {
                let date = PlanCalendar.date(forOffset: schedule.dayOffset(index), start: store.startDate)
                return "time trial " + PlanFormat.weekdayName(date)
            }
        }
        return "time trial week"
    }

    private func weekTags(_ planWeek: PlanWeek, _ schedule: PlanSchedule) -> [String] {
        var tags: [String] = []
        if planWeek.recovery {
            tags.append("recovery week")
        }
        if planWeek.timeTrial {
            tags.append(timeTrialTag(planWeek.week, schedule))
        }
        if planWeek.race {
            tags.append("race week")
        }
        return tags
    }

    @ViewBuilder
    private func weekSummary(_ schedule: PlanSchedule, start: Int) -> some View {
        let week = schedule.currentWeek(today: today)
        if let planWeek = schedule.plan.weeks.first(where: { $0.week == week }) {
            let logged = String(format: "%.1f", loggedMiles(start: start))
            let tags = weekTags(planWeek, schedule)
            VStack(alignment: .leading, spacing: 2) {
                Text("this week " + logged + " / " + PlanFormat.miles(planWeek.miles) + " mi")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.fg)
                if !tags.isEmpty {
                    Text(tags.joined(separator: " \u{00B7} "))
                        .font(Theme.mono(.micro))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}
