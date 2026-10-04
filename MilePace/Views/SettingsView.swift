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
    @State private var confirmReset: Bool = false
    @State private var planStart: Date = PlanStore.shared.startDate

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
            StatusLine(left: "milepace", center: "set", right: "v1.3")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mileTimes
                    trainingZones
                    planSection
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
            planStart = PlanStore.shared.startDate
        }
        .onChange(of: planStart) { _, newValue in
            let day = PlanCalendar.local.startOfDay(for: newValue)
            if day != PlanStore.shared.startDate {
                PlanStore.shared.setStartDate(day)
            }
        }
        .onChange(of: mileText) { _, newValue in
            if let value = parseTime(newValue), AppSettings.validMileRange.contains(value) {
                mileTime = value
                mileInvalid = false
            } else {
                mileInvalid = true
            }
        }
        .onChange(of: mileTime) { _, newValue in
            syncMileText(newValue)
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

    /// Keeps the text box in step when the mile time changes elsewhere, such as after a time trial.
    private func syncMileText(_ value: Double) {
        if let typed = parseTime(mileText), abs(typed - value) < 0.5 {
            return
        }
        mileText = formatDuration(value)
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("plan")
            planStartRow
            note("plan weeks start on this date. pick a monday.")
            resetControls
                .padding(.top, Theme.s3)
        }
    }

    private var planStartRow: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.s2) {
                Text(ReadoutFormat.leader("start", width: 12))
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                DatePicker("plan start", selection: $planStart, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Theme.fg)
            }
            .padding(.vertical, Theme.s1)
            DashedRule()
        }
    }

    @ViewBuilder
    private var resetControls: some View {
        if confirmReset {
            HStack(spacing: Theme.s2) {
                BracketButton(title: "yes, reset", style: .inverted) {
                    PlanStore.shared.resetProgress()
                    confirmReset = false
                }
                BracketButton(title: "cancel") {
                    confirmReset = false
                }
            }
        } else {
            BracketButton(title: "reset plan progress") {
                confirmReset = true
            }
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
