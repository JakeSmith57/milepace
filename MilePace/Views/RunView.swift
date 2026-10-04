import SwiftUI
import SwiftData
import UIKit
import CoreLocation

@MainActor
struct RunView: View {
    @Environment(LocationTracker.self) private var tracker
    @Environment(\.modelContext) private var modelContext

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.runZone) private var zoneChoice: RunZoneTarget = .off

    @State private var summary: RunSummary?

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    private var guardRange: ClosedRange<Double>? {
        return zoneChoice.range(in: zones)
    }

    var body: some View {
        NavigationStack {
            Group {
                if tracker.phase == .idle {
                    idleView
                } else {
                    activeView
                }
            }
            .navigationTitle("Run")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $summary) { item in
            RunSummaryView(summary: item,
                           onSave: { notes in save(item, notes: notes) },
                           onDiscard: { discard() })
        }
    }

    // MARK: Idle

    private var zoneDescription: String {
        guard let range = guardRange else {
            return "No pace cues. Mile splits are still announced if enabled."
        }
        return "\(zoneChoice.title) zone: \(formatPace(secondsPerMile: range.lowerBound)) to \(formatPace(secondsPerMile: range.upperBound)) per mile"
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.run")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pace guard")
                    .font(.headline)
                Picker("Zone", selection: $zoneChoice) {
                    ForEach(RunZoneTarget.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                Text(zoneDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            permissionOrStart

            if let message = tracker.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var permissionOrStart: some View {
        if tracker.authorization == .notDetermined {
            VStack(spacing: 8) {
                Text("MilePace needs your location to measure pace and distance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                FilledActionButton(title: "Allow Location Access") {
                    tracker.requestAuthorization()
                }
            }
        } else if tracker.isDenied {
            VStack(spacing: 8) {
                Text("Location access is off. Turn on While Using the App for MilePace in Settings to track runs.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                FilledActionButton(title: "Open Settings") {
                    openSystemSettings()
                }
            }
        } else {
            FilledActionButton(title: "Start Run", height: 80) {
                startRun()
            }
        }
    }

    // MARK: Active

    private var paceColor: Color {
        guard let range = guardRange, let pace = tracker.currentPace else { return .primary }
        return range.contains(pace) ? .primary : .red
    }

    private var activeView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    if tracker.phase == .paused {
                        Text("PAUSED")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                    BigMetricTile(title: "Current pace",
                                  value: formatPace(secondsPerMile: tracker.currentPace),
                                  unit: "/mi",
                                  valueSize: 96,
                                  valueColor: paceColor)
                    HStack(spacing: 12) {
                        BigMetricTile(title: "Average",
                                      value: formatPace(secondsPerMile: tracker.averagePace),
                                      unit: "/mi",
                                      valueSize: 40)
                        BigMetricTile(title: "Distance",
                                      value: formatMiles(tracker.distanceMeters),
                                      unit: "mi",
                                      valueSize: 40)
                    }
                    BigMetricTile(title: "Time",
                                  value: formatDuration(tracker.elapsed),
                                  valueSize: 48)
                    splitsSection
                }
                .padding()
            }

            VStack(spacing: 10) {
                if tracker.phase == .paused {
                    FilledActionButton(title: "Resume", color: .green) {
                        tracker.resume()
                    }
                } else {
                    FilledActionButton(title: "Pause", color: .orange) {
                        tracker.pause()
                    }
                }
                HoldToEndButton(title: "Hold to End") {
                    endRun()
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var splitsSection: some View {
        if !tracker.splits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mile splits")
                    .font(.headline)
                ForEach(Array(tracker.splits.enumerated()), id: \.offset) { item in
                    HStack {
                        Text("Mile \(item.offset + 1)")
                        Spacer()
                        Text(formatDuration(item.element))
                            .font(.roundedDigits(20, weight: .semibold))
                    }
                    Divider()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Actions

    private func startRun() {
        let range = guardRange
        Coach.shared.resetZoneGuard()
        tracker.onMile = { mile, split, average in
            Coach.shared.announceMile(mile, split: split, average: average)
        }
        tracker.onTick = { pace in
            Coach.shared.evaluateZone(pace: pace, zone: range)
        }
        tracker.start()
    }

    private func endRun() {
        summary = tracker.stop()
        tracker.onMile = nil
        tracker.onTick = nil
    }

    private func save(_ item: RunSummary, notes: String) {
        let record = RunRecord(date: item.date,
                               distanceMeters: item.distanceMeters,
                               durationSeconds: item.durationSeconds,
                               averagePace: item.averagePace,
                               splits: item.splits,
                               notes: notes)
        modelContext.insert(record)
        summary = nil
        tracker.reset()
    }

    private func discard() {
        summary = nil
        tracker.reset()
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct RunSummaryView: View {
    let summary: RunSummary
    let onSave: (String) -> Void
    let onDiscard: () -> Void

    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Run") {
                    row("Distance", "\(formatMiles(summary.distanceMeters)) mi")
                    row("Time", formatDuration(summary.durationSeconds))
                    row("Average pace", "\(formatPace(secondsPerMile: summary.averagePace)) /mi")
                }
                if !summary.splits.isEmpty {
                    Section("Mile splits") {
                        ForEach(Array(summary.splits.enumerated()), id: \.offset) { item in
                            row("Mile \(item.offset + 1)", formatDuration(item.element))
                        }
                    }
                }
                Section("Notes") {
                    TextField("How did it feel?", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    Button("Save Run") {
                        onSave(notes)
                    }
                    .fontWeight(.semibold)
                    Button("Discard", role: .destructive) {
                        onDiscard()
                    }
                }
            }
            .navigationTitle("Run Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded).monospacedDigit())
        }
    }
}
