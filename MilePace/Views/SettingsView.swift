import SwiftUI

@MainActor
struct SettingsView: View {
    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile
    @AppStorage(SettingsKey.announceMiles) private var announceMiles: Bool = true
    @AppStorage(SettingsKey.zoneGuard) private var zoneGuardCues: Bool = true
    @AppStorage(SettingsKey.trackCountdown) private var trackCountdown: Bool = true
    @AppStorage(SettingsKey.lapFeedback) private var lapFeedback: Bool = false
    @AppStorage(SettingsKey.haptics) private var haptics: Bool = true
    @AppStorage(SettingsKey.cueInterval) private var cueInterval: CueInterval = .half
    @AppStorage(SettingsKey.metronomeBPM) private var metronomeBPM: Int = AppSettings.defaultMetronomeBPM
    @AppStorage(SettingsKey.metronomeVolume) private var metronomeVolume: Double = AppSettings.defaultMetronomeVolume

    @State private var mileText: String = ""
    @State private var goalText: String = ""
    @State private var mileInvalid: Bool = false
    @State private var goalInvalid: Bool = false

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    private func paceRange(_ range: ClosedRange<Double>) -> String {
        return "\(formatPace(secondsPerMile: range.lowerBound)) – \(formatPace(secondsPerMile: range.upperBound)) /mi"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    timeField("Current mile", text: $mileText, invalid: mileInvalid)
                    timeField("Goal mile", text: $goalText, invalid: goalInvalid)
                } header: {
                    Text("Mile times")
                } footer: {
                    Text("Format m:ss, between 4:00 and 12:00. Training zones come from your current mile. Units are miles.")
                }

                Section("Training zones") {
                    zoneRow("Easy", paceRange(zones.easy))
                    zoneRow("Threshold", paceRange(zones.threshold))
                    zoneRow("Interval", paceRange(zones.interval))
                    zoneRow("Repetition", "\(formatSplit(zones.rep400.lowerBound)) – \(formatSplit(zones.rep400.upperBound)) /400 m")
                    zoneRow("Goal pace", "\(formatPace(secondsPerMile: goalMile)) /mi")
                }

                Section("Voice and feedback") {
                    Picker("Pace cues every", selection: $cueInterval) {
                        ForEach(CueInterval.allCases) { interval in
                            Text(interval.title).tag(interval)
                        }
                    }
                    Toggle("Announce each mile", isOn: $announceMiles)
                        .disabled(cueInterval != .off)
                    Toggle("Pace guard cues on runs", isOn: $zoneGuardCues)
                    Toggle("Rest countdown on track", isOn: $trackCountdown)
                    Toggle("Lap feedback on track", isOn: $lapFeedback)
                    Toggle("Haptics", isOn: $haptics)
                }

                Section {
                    Stepper(value: $metronomeBPM, in: ClickTrack.bpmRange, step: 2) {
                        Text("Default tempo: \(metronomeBPM) spm")
                    }
                    HStack {
                        Text("Volume")
                        Slider(value: $metronomeVolume, in: 0.1...1.0)
                    }
                } header: {
                    Text("Metronome")
                } footer: {
                    Text("A slightly quicker, shorter stride reduces impact per step. Raise cadence gradually, about 5% at a time.")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                mileText = formatDuration(mileTime)
                goalText = formatDuration(goalMile)
            }
            .onChange(of: mileText) { _, newValue in
                if let value = parseTime(newValue), AppSettings.validMileRange.contains(value) {
                    mileTime = value
                    mileInvalid = false
                } else {
                    mileInvalid = true
                }
            }
            .onChange(of: metronomeVolume) { _, newValue in
                Metronome.shared.setVolume(Float(newValue))
            }
            .onChange(of: goalText) { _, newValue in
                if let value = parseTime(newValue), AppSettings.validMileRange.contains(value) {
                    goalMile = value
                    goalInvalid = false
                } else {
                    goalInvalid = true
                }
            }
        }
    }

    private func timeField(_ title: String, text: Binding<String>, invalid: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("m:ss", text: text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .foregroundStyle(invalid ? Color.red : Color.primary)
        }
    }

    private func zoneRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
