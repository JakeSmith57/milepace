import SwiftUI
import SwiftData
import Charts

struct WeekBucket: Identifiable, Equatable {
    let weekStart: Date
    let label: String
    let miles: Double

    var id: Date { weekStart }
}

enum WeeklyMiles {
    /// Miles per Monday-to-Sunday week for the last `weeks` weeks, oldest first.
    static func buckets(runs: [(date: Date, meters: Double)],
                        weeks: Int = 10,
                        now: Date = Date()) -> [WeekBucket] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "M/d"

        var result: [WeekBucket] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { continue }
            var meters = 0.0
            for run in runs where run.date >= start && run.date < end {
                meters += run.meters
            }
            result.append(WeekBucket(weekStart: start,
                                     label: formatter.string(from: start),
                                     miles: meters / metersPerMile))
        }
        return result
    }
}

@MainActor
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunRecord.date, order: .reverse) private var runs: [RunRecord]
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var workouts: [WorkoutRecord]

    @State private var showingAdd = false

    private var buckets: [WeekBucket] {
        let pairs = runs.map { (date: $0.date, meters: $0.distanceMeters) }
        return WeeklyMiles.buckets(runs: pairs)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Weekly miles") {
                    Chart(buckets) { bucket in
                        BarMark(x: .value("Week of", bucket.label),
                                y: .value("Miles", bucket.miles))
                            .foregroundStyle(Color.orange)
                    }
                    .chartYAxisLabel("Miles")
                    .frame(height: 180)
                    .padding(.vertical, 8)
                }

                Section("Runs") {
                    if runs.isEmpty {
                        Text("No runs yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(runs) { run in
                        NavigationLink {
                            RunDetailView(run: run)
                        } label: {
                            runRow(run)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(runs[index])
                        }
                    }
                }

                Section("Workouts") {
                    if workouts.isEmpty {
                        Text("No workouts yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            workoutRow(workout)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(workouts[index])
                        }
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add miles", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddMilesView()
            }
        }
    }

    private func runRow(_ run: RunRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(run.date, style: .date)
                    .font(.headline)
                Spacer()
                Text("\(formatMiles(run.distanceMeters)) mi")
                    .font(.system(.headline, design: .rounded).monospacedDigit())
            }
            Text("\(formatDuration(run.durationSeconds))  ·  \(formatPace(secondsPerMile: run.averagePace)) /mi")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func workoutRow(_ workout: WorkoutRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(workout.name)
                .font(.headline)
            HStack {
                Text(workout.date, style: .date)
                Text("·")
                Text("\(workout.repTimes.count) reps")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

/// Manual entry for treadmill or watch runs. Saved as a run with no splits.
struct AddMilesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var date: Date = Date()
    @State private var milesText: String = ""
    @State private var durationText: String = ""

    private var parsedMiles: Double? {
        let cleaned = milesText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value > 0, value < 200 else { return nil }
        return value
    }

    /// Nil means invalid; 0 means not provided.
    private var parsedDuration: Double? {
        let trimmed = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        return parseTime(trimmed)
    }

    private var canSave: Bool {
        return parsedMiles != nil && parsedDuration != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: [.date])
                TextField("Miles", text: $milesText)
                    .keyboardType(.decimalPad)
                TextField("Time (optional, m:ss or h:mm:ss)", text: $durationText)
                    .keyboardType(.numbersAndPunctuation)
            }
            .navigationTitle("Add Miles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let miles = parsedMiles, let duration = parsedDuration else { return }
        let meters = miles * metersPerMile
        let pace = duration > 0 ? duration / meters * metersPerMile : 0
        let record = RunRecord(date: date,
                               distanceMeters: meters,
                               durationSeconds: duration,
                               averagePace: pace,
                               splits: [],
                               notes: "")
        modelContext.insert(record)
        dismiss()
    }
}

struct RunDetailView: View {
    @Bindable var run: RunRecord

    var body: some View {
        Form {
            Section {
                detailRow("Date", Text(run.date, style: .date))
                detailRow("Distance", Text("\(formatMiles(run.distanceMeters)) mi"))
                if run.durationSeconds > 0 {
                    detailRow("Time", Text(formatDuration(run.durationSeconds)))
                }
                detailRow("Average pace", Text("\(formatPace(secondsPerMile: run.averagePace)) /mi"))
            }
            if !run.splits.isEmpty {
                Section("Mile splits") {
                    ForEach(Array(run.splits.enumerated()), id: \.offset) { item in
                        detailRow("Mile \(item.offset + 1)", Text(formatDuration(item.element)))
                    }
                }
            }
            Section("Notes") {
                TextField("Notes", text: $run.notes, axis: .vertical)
                    .lineLimit(1...6)
            }
        }
        .navigationTitle("Run")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(_ title: String, _ value: Text) -> some View {
        HStack {
            Text(title)
            Spacer()
            value
                .font(.system(.body, design: .rounded).monospacedDigit())
        }
    }
}

struct WorkoutDetailView: View {
    let workout: WorkoutRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(workout.name)
                    .font(.title2.weight(.bold))
                Text(workout.date, style: .date)
                    .foregroundStyle(.secondary)
                if let spec = workout.spec {
                    WorkoutResultsTable(spec: spec,
                                        repTimes: workout.repTimes,
                                        lapSplits: workout.lapSplits)
                } else {
                    Text("Workout details are unavailable.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
    }
}
