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
    @AppStorage(SettingsKey.displayMode) private var displayMode: DisplayMode = .system
    @AppStorage(SettingsKey.diagnostics) private var diagnosticsEnabled: Bool = false

    @State private var mileText: String = ""
    @State private var goalText: String = ""
    @State private var mileInvalid: Bool = false
    @State private var goalInvalid: Bool = false

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    private var cueOptions: [Choice<CueInterval>] {
        return CueInterval.allCases.map { Choice($0, $0.title.lowercased()) }
    }

    private var displayOptions: [Choice<DisplayMode>] {
        return DisplayMode.allCases.map { Choice($0, $0.title) }
    }

    /// Volume as a whole percent, for the stepper.
    private var volumePercent: Binding<Int> {
        return Binding(get: { Int((metronomeVolume * 100).rounded()) },
                       set: { metronomeVolume = Double($0) / 100 })
    }

    private func paceRange(_ range: ClosedRange<Double>) -> String {
        return ReadoutFormat.paceRange(range) + " /mi"
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "set", right: "v1.2")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mileTimes
                    trainingZones
                    voiceAndFeedback
                    trackOptions
                    metronome
                    display
                }
                .padding(.horizontal, Theme.s3)
                .padding(.bottom, Theme.s4)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .instrumentScreen()
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
        .onChange(of: goalText) { _, newValue in
            if let value = parseTime(newValue), AppSettings.validMileRange.contains(value) {
                goalMile = value
                goalInvalid = false
            } else {
                goalInvalid = true
            }
        }
        .onChange(of: metronomeVolume) { _, newValue in
            Metronome.shared.setVolume(Float(newValue))
        }
    }

    // MARK: Sections

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.dim)
            .padding(.top, Theme.s2)
    }

    private var mileTimes: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("mile times")
            FieldRow(key: "current",
                     placeholder: "m:ss",
                     text: $mileText,
                     note: mileInvalid ? "use m:ss, 4:00 to 12:00" : nil)
            FieldRow(key: "goal",
                     placeholder: "m:ss",
                     text: $goalText,
                     note: goalInvalid ? "use m:ss, 4:00 to 12:00" : nil)
            note("training zones come from your current mile. units are miles.")
        }
    }

    private var trainingZones: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("training zones")
            ReadoutRow(key: "easy", value: paceRange(zones.easy), keyWidth: 10)
            ReadoutRow(key: "threshold", value: paceRange(zones.threshold), keyWidth: 10)
            ReadoutRow(key: "interval", value: paceRange(zones.interval), keyWidth: 10)
            ReadoutRow(key: "rep /400m",
                       value: formatSplit(zones.rep400.lowerBound) + "\u{2013}" + formatSplit(zones.rep400.upperBound),
                       keyWidth: 10)
            ReadoutRow(key: "goal", value: formatPace(secondsPerMile: goalMile) + " /mi", keyWidth: 10)
        }
    }

    private var voiceAndFeedback: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("voice and feedback")
            ChoiceRow(label: "pace cues every", options: cueOptions, selection: $cueInterval)
            CheckRow(title: "announce each mile", isOn: $announceMiles)
                .disabled(cueInterval != .off)
                .opacity(cueInterval == .off ? 1 : 0.35)
            CheckRow(title: "pace guard cues", isOn: $zoneGuardCues)
            CheckRow(title: "haptics", isOn: $haptics)
        }
    }

    private var trackOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("track")
            CheckRow(title: "rest countdown", isOn: $trackCountdown)
            CheckRow(title: "lap feedback", isOn: $lapFeedback)
        }
    }

    private var metronome: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("metronome")
            StepperRow(title: "tempo spm",
                       value: $metronomeBPM,
                       range: ClickTrack.bpmRange,
                       step: 2)
            StepperRow(title: "volume",
                       value: volumePercent,
                       range: 10...100,
                       step: 10,
                       format: { "\($0)%" })
            note("a slightly quicker, shorter stride reduces impact per step. raise cadence gradually, about 5% at a time.")
        }
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("display")
            ChoiceRow(label: "appearance", options: displayOptions, selection: $displayMode)
            CheckRow(title: "diagnostics", isOn: $diagnosticsEnabled)
            note("diagnostics adds a [ diag ] button to the run screen and keeps a log of gps fixes, pace and voice cues.")
        }
    }
}
