import SwiftUI
import SwiftData
import UIKit
import UserNotifications

/// The home screen: what to do today, what was missed, and the week at a glance. Run, track, log and
/// set open from here.
@MainActor
struct TodayView: View {
    /// True while the today screen is showing. All screens stay alive, so this drives the reload of
    /// unfinished work when the runner comes back.
    let isActive: Bool

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile
    @AppStorage(SettingsKey.paceWindow) private var paceWindow: Double = AppSettings.defaultPaceWindow
    @AppStorage(SettingsKey.runZone) private var runZone: RunZoneTarget = .off
    @AppStorage(SettingsKey.reminderMorningMinutes) private var morningMinutes: Int = ReminderSettings.defaultMorningMinutes
    @AppStorage(SettingsKey.reminderEveningMinutes) private var eveningMinutes: Int = ReminderSettings.defaultEveningMinutes

    @Query private var runs: [RunRecord]
    @Query private var workouts: [WorkoutRecord]

    @Environment(\.scenePhase) private var scenePhase

    @State private var showOverview: Bool = false
    /// A run found on disk that was never finished, offered on top of the screen.
    @State private var runDraft: RunDraft? = nil
    /// A track session found on disk that was never saved, offered the same way.
    @State private var trackDraft: TrackSessionDraft? = nil
    /// A routine opened from the session card, shown as a sheet.
    @State private var routineSheet: Routine? = nil

    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(isActive: Bool) {
        self.isActive = isActive
    }

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
        .sheet(item: $routineSheet) { routine in
            RoutineDetailView(routine: routine)
        }
        .onAppear {
            store.refresh()
            reconcile()
            syncReminders(refreshPermission: true)
            reloadDrafts()
        }
        .onChange(of: isActive) { _, active in
            if active {
                reloadDrafts()
            }
        }
        .onChange(of: runs.count) { old, new in
            // Fewer runs than before: one was deleted, and the sessions it had marked done are re-checked.
            reconcile(removed: new < old)
            syncReminders(refreshPermission: false)
        }
        .onChange(of: workouts.count) { old, new in
            reconcile(removed: new < old)
            syncReminders(refreshPermission: false)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.refresh()
                reconcile()
                syncReminders(refreshPermission: true)
                reloadDrafts()
            }
        }
        .onChange(of: paceInputs) { _, _ in
            Reminders.shared.reschedule()
        }
        .onReceive(ticker) { _ in
            store.refresh()
        }
    }

    /// The settings the reminder text is built from; any change rebuilds the reminders.
    private var paceInputs: [Double] {
        return [mileTime, goalMile, paceWindow]
    }

    /// The saved runs this plan counts: test runs during the test week, the others otherwise.
    private var loggedRuns: [LoggedRun] {
        return TestRecordFilter.runs(runs.map { LoggedRun(record: $0) }, testWeek: store.isTestWeek)
    }

    private var loggedWorkouts: [LoggedWorkout] {
        return TestRecordFilter.workouts(workouts.map { LoggedWorkout(record: $0) }, testWeek: store.isTestWeek)
    }

    private func reconcile(removed: Bool = false) {
        store.reconcile(runs: loggedRuns, workouts: loggedWorkouts, activitiesRemoved: removed)
    }

    /// Asks for a fresh reminder schedule; `Reminders` reads the saved runs and workouts itself.
    private func syncReminders(refreshPermission: Bool) {
        if refreshPermission {
            Reminders.shared.refreshAuthorization()
        }
        Reminders.shared.reschedule()
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

    /// "[ log ]" and "[ set ]" open those screens.
    private var screenAccessories: [StatusAccessory] {
        return [StatusAccessory(title: "log", action: { store.open(.log) }),
                StatusAccessory(title: "set", action: { store.open(.set) })]
    }

    private var statusLine: some View {
        let texts = statusTexts
        return StatusLine(left: "milepace",
                          center: texts.center,
                          right: texts.right,
                          accessories: screenAccessories,
                          tag: store.isTestWeek ? "test" : "")
    }

    // MARK: Content

    private var content: some View {
        return VStack(alignment: .leading, spacing: Theme.s3) {
            unfinishedCards
            planContent
            otherSection
        }
        .padding(.horizontal, Theme.s3)
        .padding(.vertical, Theme.s3)
    }

    @ViewBuilder
    private var planContent: some View {
        if let schedule = store.schedule {
            planColumn(schedule)
        } else {
            Text("plan file missing.")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.dim)
        }
    }

    private func planColumn(_ schedule: PlanSchedule) -> some View {
        VStack(alignment: .leading, spacing: Theme.s3) {
            missedSection(schedule)
            todaySection(schedule)
            doctorNote
            weekSection(schedule)
            remindersCard
            BracketButton(title: "full plan") {
                showOverview = true
            }
        }
    }

    // MARK: Unfinished work

    /// Reads the run and track drafts from disk. Nothing is offered while that kind of session is being
    /// recorded: its own checkpoint is on disk then, and it is not unfinished.
    private func reloadDrafts() {
        let run: RunDraft? = store.runInProgress ? nil : RunDraftStore.load()
        if run != runDraft {
            runDraft = run
        }
        let track: TrackSessionDraft? = store.trackInProgress ? nil : TrackSessionStore.load()
        if track != trackDraft {
            trackDraft = track
        }
    }

    @ViewBuilder
    private var unfinishedCards: some View {
        if let draft = runDraft {
            unfinishedCard(text: draft.summaryText(), screen: .run)
        }
        if let draft = trackDraft {
            unfinishedCard(text: trackDraftText(draft), screen: .track)
        }
    }

    private func trackDraftText(_ draft: TrackSessionDraft) -> String {
        let prefix = draft.isFinished ? "unsaved track workout: " : "unfinished track workout: "
        return prefix + draft.workout.spec.name
    }

    /// An inverted card; "[ open ]" goes to the screen that holds the save or discard choice.
    private func unfinishedCard(text: String, screen: AppTab) -> some View {
        return VStack(alignment: .leading, spacing: Theme.s2) {
            Text(text)
                .font(Theme.mono(.body))
                .fixedSize(horizontal: false, vertical: true)
            BracketButton(title: "open", style: .outlineOnInverted, minHeight: 48) {
                store.open(screen)
            }
        }
        .foregroundStyle(Theme.bg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s3)
        .background(Theme.fg)
    }

    // MARK: Other

    private var otherSection: some View {
        return VStack(alignment: .leading, spacing: Theme.s2) {
            SectionHeader("other")
            HStack(spacing: Theme.s2) {
                BracketButton(title: "free run") {
                    startFreeRun()
                }
                BracketButton(title: "track workout") {
                    openTrackList()
                }
            }
            BracketButton(title: "routines") {
                store.open(.routines)
            }
        }
    }

    /// A run that belongs to no plan session: the run screen opens in free mode with the pace guard as
    /// it was left.
    private func startFreeRun() {
        store.discardActive()
        store.pendingRoute = PlanRoute.freeRun(zone: runZone)
        store.open(.run)
    }

    /// The track screen's preset list, with no plan session attached.
    private func openTrackList() {
        store.discardActive()
        store.open(.track)
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

    private func missedCard(_ schedule: PlanSchedule, _ index: Int) -> some View {
        let session = schedule.plan.sessions[index]
        let result = schedule.pushingBack(missed: index, today: today)
        return VStack(alignment: .leading, spacing: Theme.s2) {
            micro("missed " + dayLabel(schedule.dayOffset(index)))
            Text(session.title)
                .font(Theme.mono(.body))
                .fixedSize(horizontal: false, vertical: true)
            missedButtons(schedule, index, result)
            missedNote(schedule, index, result)
        }
        .foregroundStyle(Theme.bg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s3)
        .background(Theme.fg)
    }

    /// The day a dry run moved the missed session to; nil when it would be skipped or left alone.
    private func moveTarget(_ schedule: PlanSchedule, _ index: Int, _ result: PushBackResult) -> Int? {
        guard !result.dropped.contains(index), result.progress != schedule.progress else { return nil }
        let moved = PlanSchedule(plan: schedule.plan,
                                 progress: result.progress,
                                 startWeekday: schedule.startWeekday)
        return moved.dayOffset(index)
    }

    private func missedButtons(_ schedule: PlanSchedule, _ index: Int, _ result: PushBackResult) -> some View {
        return HStack(spacing: Theme.s2) {
            if let target = moveTarget(schedule, index, result) {
                BracketButton(title: PlanText.moveTitle(day: target, today: today, label: dayLabel(target)),
                              style: .plan,
                              minHeight: 48) {
                    store.doItToday(missed: index)
                }
            }
            BracketButton(title: "skip", style: .outlineOnInverted, minHeight: 48) {
                store.skip(index)
            }
        }
        .padding(.top, Theme.s1)
    }

    @ViewBuilder
    private func missedNote(_ schedule: PlanSchedule, _ index: Int, _ result: PushBackResult) -> some View {
        if result.dropped.contains(index) {
            micro(PlanText.noRoomNote)
        } else if let target = moveTarget(schedule, index, result) {
            micro(PlanText.pushNote(moved: result.moved.count,
                                    dropped: result.dropped.map { droppedItem(schedule, $0) },
                                    targetLabel: target == today ? nil : dayLabel(target)))
        }
    }

    /// "the 2 mi easy on fri" for a session the push would skip.
    private func droppedItem(_ schedule: PlanSchedule, _ index: Int) -> String {
        let date = PlanCalendar.date(forOffset: schedule.dayOffset(index), start: store.startDate)
        let short = String(PlanFormat.weekdayName(date).prefix(3))
        return PlanText.droppedItem(title: schedule.plan.sessions[index].title, dayShort: short)
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
            micro(store.isTestWeek ? "today  test week" : "today")
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
            routineLinks(session)
        }
        .foregroundStyle(Theme.onSignal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.s3)
        .background(Theme.plan)
    }

    /// "[ warm-up ]" and, for workouts, "[ cool-down ]": opens the matching routine as a sheet.
    @ViewBuilder
    private func routineLinks(_ session: PlanSession) -> some View {
        let ids = RoutineSuggestion.ids(for: session.kind)
        let library = RoutineLoader.bundled
        let before = library?.routine(id: ids.before)
        let after = ids.after.flatMap { library?.routine(id: $0) }
        if before != nil || after != nil {
            HStack(spacing: Theme.s3) {
                if let routine = before {
                    TextBracketButton(title: "warm-up", color: Theme.onSignal) {
                        routineSheet = routine
                    }
                }
                if let routine = after {
                    TextBracketButton(title: "cool-down", color: Theme.onSignal) {
                        routineSheet = routine
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func startTitle(_ session: PlanSession) -> String {
        switch session.kind {
        case .track:
            return trackSpec(session) == nil ? "open track" : "start"
        case .easy, .long, .road, .timeTrial, .race, .other:
            return "start"
        }
    }

    private func trackSpec(_ session: PlanSession) -> WorkoutSpec? {
        return PlanText.trackSpec(for: session, zones: zones, goalMile: goalMile)
    }

    private func detailLines(_ session: PlanSession) -> some View {
        let lines = PlanText.lines(for: session, zones: zones, goalMile: goalMile, window: paceWindow)
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
            testWeekOffer
        }
    }

    /// Before the plan starts: try the whole app for a week, with nothing carried into the real plan.
    @ViewBuilder
    private var testWeekOffer: some View {
        if store.canStartTestWeek {
            BracketButton(title: "start a test week") {
                store.startTestWeek()
            }
            .padding(.top, Theme.s2)
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
            heading(store.isTestWeek ? "test week complete" : "plan complete")
            bodyText(store.isTestWeek ? "end it in set to delete the test data." : "the race is behind you.")
        }
    }

    // MARK: Reminders

    @ViewBuilder
    private var remindersCard: some View {
        if Reminders.shared.authorizationKnown {
            switch Reminders.shared.authorization {
            case .notDetermined:
                reminderPrompt
            case .denied:
                reminderDenied
            default:
                EmptyView()
            }
        }
    }

    private var reminderPrompt: some View {
        let morning = ReminderFormat.clock(morningMinutes)
        let evening = ReminderFormat.clock(eveningMinutes)
        return outlined {
            Text("reminders")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
            Text("a note at \(morning) with today's session, and a nudge at \(evening) if it isn't logged.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            BracketButton(title: "turn on reminders", style: .plan) {
                Reminders.shared.requestPermission()
            }
        }
    }

    private var reminderDenied: some View {
        return outlined {
            Text("reminders are off in ios settings")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
                .fixedSize(horizontal: false, vertical: true)
            BracketButton(title: "open settings") {
                openSystemSettings()
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
            weekSummary(schedule)
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

    /// The calendar Monday-to-Sunday week holding today: its planned week and the miles logged in it
    /// (runs, plus track workouts estimated with a warm-up and cool-down). Nil before the plan
    /// starts and after the race.
    private func thisWeek(_ schedule: PlanSchedule) -> PlanWeekMiles? {
        guard today >= 0, today <= schedule.raceDayOffset else { return nil }
        let milesByDay = PlanActivities.milesByDay(runs: loggedRuns,
                                                   workouts: loggedWorkouts,
                                                   start: store.startDate)
        return schedule.weekMiles(containing: today, milesByDay: milesByDay)
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
    private func weekSummary(_ schedule: PlanSchedule) -> some View {
        if let summary = thisWeek(schedule), let planWeek = summary.planWeek {
            let logged = String(format: "%.1f", summary.logged)
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
