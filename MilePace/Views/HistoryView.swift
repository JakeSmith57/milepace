import SwiftUI
import SwiftData
import Charts

@MainActor
struct HistoryView: View {
    @Query(sort: \RunRecord.date, order: .reverse) private var runs: [RunRecord]
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var workouts: [WorkoutRecord]

    @State private var showingAdd = false
    /// The export file waiting in the share sheet.
    @State private var shareFile: ShareFile?
    @State private var exportFailed = false

    /// The same Monday-to-Sunday weekly miles as the today screen: runs plus estimated track workouts.
    private var buckets: [WeekBucket] {
        return WeeklyMiles.buckets(runs: runs.map { LoggedRun(record: $0) },
                                   workouts: workouts.map { LoggedWorkout(record: $0) })
    }

    private var thisWeek: WeekBucket? {
        return buckets.last
    }

    private var thisWeekMiles: Double {
        return thisWeek?.miles ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StatusLine(left: "milepace",
                           center: "week of " + (thisWeek?.label ?? "--"),
                           right: String(format: "%.1f", thisWeekMiles) + " mi",
                           accessory: StatusAccessory(title: "today", action: { PlanStore.shared.goHome() }),
                           accessories: [exportAccessory],
                           tag: PlanStore.shared.isTestWeek ? "test" : "")
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        exportNote
                        HeroReadout(label: "this week",
                                    value: String(format: "%.1f", thisWeekMiles),
                                    unit: "mi",
                                    size: .hero)
                            .padding(.top, Theme.s3)
                        weeklyChart
                        runsSection
                        workoutsSection
                        BracketButton(title: "add miles") {
                            showingAdd = true
                        }
                        .padding(.top, Theme.s4)
                        .padding(.bottom, Theme.s3)
                    }
                    .padding(.horizontal, Theme.s3)
                }
            }
            .instrumentScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingAdd) {
                AddMilesView()
            }
            .sheet(item: $shareFile) { file in
                ShareSheet(url: file.url)
            }
        }
    }

    // MARK: Export

    private var exportAccessory: StatusAccessory {
        return StatusAccessory(title: "export", action: { exportProgress() })
    }

    /// One quiet line saying what [ export ] does, or that it failed.
    @ViewBuilder
    private var exportNote: some View {
        if exportFailed {
            Text("couldn't make the export file.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.fg)
                .padding(.top, Theme.s2)
        } else if !runs.isEmpty || !workouts.isEmpty {
            Text("[ export ] makes a file to send to your coach.")
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.dim)
                .padding(.top, Theme.s2)
        }
    }

    private var exportRuns: [ExportRun] {
        return runs.map { run in
            ExportRun(date: run.date,
                      distanceMeters: run.distanceMeters,
                      durationSeconds: run.durationSeconds,
                      averagePace: run.averagePace,
                      splits: run.splits,
                      averageCadence: run.averageCadence,
                      workoutName: run.workoutName,
                      notes: run.notes,
                      hasRoute: !run.routeData.isEmpty,
                      isTest: run.isTest,
                      isTreadmill: run.isTreadmill)
        }
    }

    private var exportWorkouts: [ExportWorkout] {
        return workouts.map { workout in
            ExportWorkout(date: workout.date,
                          name: workout.name,
                          spec: workout.spec,
                          repTimes: workout.repTimes,
                          lapSplits: workout.lapSplits,
                          isTest: workout.isTest)
        }
    }

    private var exportSettings: ExportSettings {
        return ExportSettings(mileTime: AppSettings.mileTime,
                              goalMile: AppSettings.goalMile,
                              paceWindow: AppSettings.paceWindow,
                              metronomeBPM: AppSettings.metronomeBPM,
                              metronomeEnabled: AppSettings.metronomeEnabled,
                              voiceEnabled: AppSettings.voiceEnabled,
                              cueInterval: AppSettings.cueInterval.title)
    }

    private func makeExportInput(now: Date) -> ExportInput {
        let store = PlanStore.shared
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.10"
        return ExportInput(generatedAt: now,
                           appVersion: version,
                           plan: store.exportPlan,
                           startYMD: store.exportStartYMD,
                           progress: store.exportProgress,
                           schedule: store.exportSchedule,
                           todayOffset: store.exportTodayOffset,
                           settings: exportSettings,
                           zones: AppSettings.zones,
                           runs: exportRuns,
                           workouts: exportWorkouts,
                           testWeekActive: store.isTestWeek)
    }

    /// Writes the progress file to the temporary folder and offers it in the share sheet.
    private func exportProgress() {
        let now = Date()
        let text = ProgressExport.markdown(makeExportInput(now: now))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(ProgressExport.fileName(for: now))
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportFailed = false
            shareFile = ShareFile(url: url)
        } catch {
            Diagnostics.shared.log(.state, "progress export failed: \(error.localizedDescription)")
            exportFailed = true
        }
    }

    // MARK: Chart

    private var weeklyChart: some View {
        let current = thisWeek?.weekStart
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("weekly miles")
            Chart(buckets) { bucket in
                BarMark(x: .value("Week of", bucket.label),
                        y: .value("Miles", bucket.miles))
                    .foregroundStyle(bucket.weekStart == current ? Theme.signal : Theme.fg)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            axisText(label)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let miles = value.as(Double.self) {
                            axisText(String(format: "%.0f", miles))
                        }
                    }
                }
            }
            .frame(height: 160)
            .padding(.top, Theme.s3)
        }
    }

    private func axisText(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.dim)
    }

    // MARK: Lists

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("runs")
            if runs.isEmpty {
                emptyNote("no runs yet.")
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(runs) { run in
                    NavigationLink {
                        RunDetailView(run: run)
                    } label: {
                        runRow(run)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var workoutsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("workouts")
            if workouts.isEmpty {
                emptyNote("no workouts yet.")
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(workouts) { workout in
                    NavigationLink {
                        WorkoutDetailView(workout: workout)
                    } label: {
                        workoutRow(workout)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(.body))
            .foregroundStyle(Theme.dim)
            .padding(.vertical, Theme.s2)
    }

    private func runRow(_ run: RunRecord) -> some View {
        let time = run.durationSeconds > 0 ? formatDuration(run.durationSeconds) : "--"
        return VStack(alignment: .leading, spacing: 0) {
            runTags(run)
            ReadoutRow(key: ReadoutFormat.day(run.date),
                       value: formatMiles(run.distanceMeters) + "  " + time)
        }
    }

    /// "test" and "treadmill" labels above a log row.
    @ViewBuilder
    private func runTags(_ run: RunRecord) -> some View {
        if run.isTest || run.isTreadmill {
            HStack(spacing: Theme.s1) {
                if run.isTest {
                    PlanTag(text: "test")
                }
                if run.isTreadmill {
                    PlanTag(text: "treadmill")
                }
            }
            .padding(.top, Theme.s1)
        }
    }

    private func workoutRow(_ workout: WorkoutRecord) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            ReadoutRow(key: ReadoutFormat.day(workout.date),
                       value: "\(workout.repTimes.count) reps",
                       ruled: false)
            HStack(spacing: Theme.s2) {
                Text(workout.name)
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                if workout.isTest {
                    PlanTag(text: "test")
                }
            }
            .padding(.bottom, Theme.s2)
            DashedRule()
        }
    }
}

/// Manual entry for treadmill or watch runs. Saved as a run with no splits.
struct AddMilesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var daysAgo: Int = 0
    @State private var milesText: String = ""
    @State private var durationText: String = ""

    /// Noon of the day `days` ago, so an entry made in the small hours still lands on that day.
    private func date(daysAgo days: Int) -> Date {
        let calendar = PlanCalendar.local
        let day = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private var parsedMiles: Double? {
        return InputParsing.addedMiles(milesText)
    }

    private var trimmedDuration: String {
        return durationText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Nil means invalid; 0 means not provided. A bare number is minutes. With miles entered, the
    /// pace has to be between 4:00 and 20:00 per mile.
    private var parsedDuration: Double? {
        if trimmedDuration.isEmpty { return 0 }
        guard let seconds = InputParsing.addedDuration(trimmedDuration) else { return nil }
        if let miles = parsedMiles, !InputParsing.isPlausiblePace(seconds: seconds, miles: miles) {
            return nil
        }
        return seconds
    }

    private var canSave: Bool {
        return parsedMiles != nil && parsedDuration != nil
    }

    private var milesNote: String? {
        if milesText.isEmpty || parsedMiles != nil { return nil }
        return "enter miles like 3.1"
    }

    private var durationNote: String? {
        if trimmedDuration.isEmpty || parsedDuration != nil { return nil }
        if InputParsing.addedDuration(trimmedDuration) == nil {
            return "minutes like 45, or 32:10, or 1:05:00"
        }
        return "that works out outside 4:00 to 20:00 per mile"
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "add miles", right: "")
            HStack {
                BracketButton(title: "cancel", minHeight: 44, fullWidth: false) {
                    dismiss()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.top, Theme.s2)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader("manual run")
                    StepperRow(title: "date",
                               value: $daysAgo,
                               range: 0...365,
                               format: { days in ReadoutFormat.day(date(daysAgo: days)) },
                               keyWidth: 5)
                    FieldRow(key: "miles",
                             placeholder: "0.0",
                             text: $milesText,
                             note: milesNote,
                             keyboard: .decimalPad)
                    FieldRow(key: "time",
                             placeholder: "min or m:ss",
                             text: $durationText,
                             note: durationNote,
                             keyboard: .numbersAndPunctuation)
                    Text("time is optional. a bare number is minutes.")
                        .font(Theme.mono(.micro))
                        .foregroundStyle(Theme.dim)
                        .padding(.top, Theme.s2)
                    BracketButton(title: "save", style: .signal, minHeight: 72, isEnabled: canSave) {
                        save()
                    }
                    .padding(.top, Theme.s4)
                }
                .padding(.horizontal, Theme.s3)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .instrumentScreen()
    }

    private func save() {
        guard let miles = parsedMiles, let duration = parsedDuration else { return }
        let meters = miles * metersPerMile
        let pace = duration > 0 ? duration / meters * metersPerMile : 0
        let record = RunRecord(date: date(daysAgo: daysAgo),
                               distanceMeters: meters,
                               durationSeconds: duration,
                               averagePace: pace,
                               splits: [],
                               notes: "",
                               isTest: PlanStore.shared.isTestWeek)
        modelContext.insert(record)
        try? modelContext.save()
        dismiss()
    }
}

/// Full-width two-step delete: the first tap arms it, the second confirms.
struct ConfirmDeleteButton: View {
    let title: String
    let onConfirm: () -> Void

    @State private var armed: Bool = false

    init(title: String, onConfirm: @escaping () -> Void) {
        self.title = title
        self.onConfirm = onConfirm
    }

    var body: some View {
        let style: BracketStyle = armed ? .inverted : .plain
        return BracketButton(title: armed ? "tap again to delete" : title, style: style) {
            if armed {
                onConfirm()
            } else {
                armed = true
            }
        }
    }
}

struct RunDetailView: View {
    @Bindable var run: RunRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var route: [RoutePoint] = []
    /// Set just before deleting so the body stops reading the model.
    @State private var removed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if removed {
                Color.clear
            } else {
                content
            }
        }
        .instrumentScreen()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            route = run.route
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "run", right: ReadoutFormat.day(run.date))
            backBar
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if route.count >= 2 && !run.isTreadmill {
                        RunMapView(route: route, averagePace: run.averagePace)
                            .padding(.top, Theme.s2)
                    }
                    numbers
                    splitsBlock
                    SectionHeader("notes")
                    BoxedField(placeholder: "notes", text: $run.notes, lines: 1...6)
                        .padding(.top, Theme.s2)
                    ConfirmDeleteButton(title: "delete run") {
                        delete()
                    }
                    .padding(.top, Theme.s4)
                    .padding(.bottom, Theme.s3)
                }
                .padding(.horizontal, Theme.s3)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var backBar: some View {
        HStack {
            BracketButton(title: "back", minHeight: 44, fullWidth: false) {
                dismiss()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.s3)
        .padding(.top, Theme.s2)
    }

    private var numbers: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("run")
            if run.isTreadmill {
                ReadoutRow(key: "surface", value: "treadmill")
            }
            ReadoutRow(key: "dist", value: formatMiles(run.distanceMeters) + " mi")
            if run.durationSeconds > 0 {
                ReadoutRow(key: "time", value: formatDuration(run.durationSeconds))
            }
            ReadoutRow(key: "avg /mi", value: formatPace(secondsPerMile: run.averagePace))
            if run.averageCadence > 0 {
                ReadoutRow(key: "cadence", value: "\(Int(run.averageCadence.rounded())) spm")
            }
        }
    }

    @ViewBuilder
    private var splitsBlock: some View {
        if !run.splits.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("mile splits")
                Tape(rows: splitRows)
                    .padding(.top, Theme.s2)
            }
        }
    }

    private var splitRows: [TapeRow] {
        var rows: [TapeRow] = []
        for (index, split) in run.splits.enumerated() {
            rows.append(TapeRow(id: index + 1, key: "\(index + 1)", value: formatDuration(split)))
        }
        return rows
    }

    private func delete() {
        removed = true
        modelContext.delete(run)
        dismiss()
    }
}

struct WorkoutDetailView: View {
    let workout: WorkoutRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Set just before deleting so the body stops reading the model.
    @State private var removed: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if removed {
                Color.clear
            } else {
                content
            }
        }
        .instrumentScreen()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var content: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "workout", right: ReadoutFormat.day(workout.date))
            HStack {
                BracketButton(title: "back", minHeight: 44, fullWidth: false) {
                    dismiss()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.s3)
            .padding(.top, Theme.s2)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(workout.name)
                    if let spec = workout.spec {
                        WorkoutResultsTable(spec: spec,
                                            repTimes: workout.repTimes,
                                            lapSplits: workout.lapSplits)
                            .padding(.top, Theme.s2)
                    } else {
                        Text("workout details are unavailable.")
                            .font(Theme.mono(.body))
                            .foregroundStyle(Theme.dim)
                            .padding(.top, Theme.s2)
                    }
                    ConfirmDeleteButton(title: "delete workout") {
                        delete()
                    }
                    .padding(.top, Theme.s4)
                    .padding(.bottom, Theme.s3)
                }
                .padding(.horizontal, Theme.s3)
            }
        }
    }

    private func delete() {
        removed = true
        modelContext.delete(workout)
        dismiss()
    }
}
