import SwiftUI
import UserNotifications

@MainActor
struct SettingsView: View {
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile
    @AppStorage(SettingsKey.announceMiles) private var announceMiles: Bool = true
    @AppStorage(SettingsKey.zoneGuard) private var zoneGuardCues: Bool = true
    @AppStorage(SettingsKey.trackCountdown) private var trackCountdown: Bool = true
    @AppStorage(SettingsKey.lapFeedback) private var lapFeedback: Bool = false
    @AppStorage(SettingsKey.haptics) private var haptics: Bool = true
    @AppStorage(SettingsKey.cueInterval) private var cueInterval: CueInterval = .half
    @AppStorage(SettingsKey.voiceEnabled) private var voiceEnabled: Bool = true
    @AppStorage(SettingsKey.autoPause) private var autoPause: Bool = true
    @AppStorage(SettingsKey.homeAddress) private var homeAddress: String = RouteHome.defaultAddress
    @AppStorage(SettingsKey.offRouteCue) private var offRouteCue: Bool = true
    @AppStorage(SettingsKey.metronomeEnabled) private var metronomeEnabled: Bool = false
    @AppStorage(SettingsKey.metronomeBPM) private var metronomeBPM: Int = AppSettings.defaultMetronomeBPM
    @AppStorage(SettingsKey.metronomeVolume) private var metronomeVolume: Double = AppSettings.defaultMetronomeVolume
    @AppStorage(SettingsKey.displayMode) private var displayMode: DisplayMode = .system
    @AppStorage(SettingsKey.diagnostics) private var diagnosticsEnabled: Bool = false
    @AppStorage(SettingsKey.remindersEnabled) private var remindersEnabled: Bool = true
    @AppStorage(SettingsKey.reminderMorning) private var reminderMorning: Bool = true
    @AppStorage(SettingsKey.reminderEvening) private var reminderEvening: Bool = true
    @AppStorage(SettingsKey.reminderTimeTrial) private var reminderTimeTrial: Bool = true
    @AppStorage(SettingsKey.reminderWeekly) private var reminderWeekly: Bool = true
    @AppStorage(SettingsKey.paceWindow) private var paceWindow: Double = AppSettings.defaultPaceWindow
    @AppStorage(SettingsKey.voiceIdentifier) private var voiceIdentifier: String = ""
    @AppStorage(SettingsKey.reminderMorningMinutes) private var morningMinutes: Int = ReminderSettings.defaultMorningMinutes
    @AppStorage(SettingsKey.reminderEveningMinutes) private var eveningMinutes: Int = ReminderSettings.defaultEveningMinutes

    @State private var mileText: String = ""
    @State private var goalText: String = ""
    @State private var mileInvalid: Bool = false
    @State private var goalInvalid: Bool = false
    @State private var confirmReset: Bool = false
    @State private var planStart: Date = PlanStore.shared.realStartDate
    @State private var confirmEndTest: Bool = false
    @State private var endTestFailed: Bool = false
    @State private var showVoicePicker: Bool = false
    @State private var homeText: String = ""
    @State private var voiceOptions: [VoiceOption] = []

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    /// The pace window as whole seconds, for the stepper.
    private var paceWindowSeconds: Binding<Int> {
        return Binding(get: { Int(paceWindow.rounded()) },
                       set: { paceWindow = Double($0) })
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

    private var reminderSettings: ReminderSettings {
        return ReminderSettings(enabled: remindersEnabled,
                                morning: reminderMorning,
                                evening: reminderEvening,
                                timeTrial: reminderTimeTrial,
                                weekly: reminderWeekly,
                                morningMinutes: morningMinutes,
                                eveningMinutes: eveningMinutes)
    }

    private func paceRange(_ range: ClosedRange<Double>) -> String {
        return ReadoutFormat.paceRange(range) + " /mi"
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace",
                       center: "set",
                       right: "v1.15",
                       accessory: StatusAccessory(title: "today", action: { PlanStore.shared.goHome() }))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    mileTimes
                    trainingZones
                    planSection
                    testWeekSection
                    remindersSection
                    runAndRoutes
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
            homeText = RouteHome.address
            planStart = PlanStore.shared.realStartDate
            Reminders.shared.refreshAuthorization()
        }
        .onChange(of: reminderSettings) { _, _ in
            Reminders.shared.reschedule()
        }
        .onChange(of: planStart) { _, newValue in
            let day = PlanCalendar.local.startOfDay(for: newValue)
            if day != PlanStore.shared.realStartDate {
                PlanStore.shared.setStartDate(day)
            }
        }
        .onChange(of: mileText) { _, newValue in
            if newValue != formatDuration(mileTime) {
                mileInvalid = false
            }
        }
        .onChange(of: goalText) { _, newValue in
            if newValue != formatDuration(goalMile) {
                goalInvalid = false
            }
        }
        .onChange(of: mileTime) { _, newValue in
            syncMileText(newValue)
        }
        .onChange(of: metronomeVolume) { _, newValue in
            Metronome.shared.setVolume(Float(newValue))
        }
        .onChange(of: voiceEnabled) { _, enabled in
            // Turning the voice off cuts off what is being said. The click is never touched here.
            if !enabled {
                Coach.shared.stopSpeaking()
            }
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
                     note: mileInvalid ? InputParsing.mileTimeNote : nil,
                     onCommit: { commitMile() })
            FieldRow(key: "goal",
                     placeholder: "m:ss",
                     text: $goalText,
                     note: goalInvalid ? InputParsing.mileTimeNote : nil,
                     onCommit: { commitGoal() })
            note("training zones come from your current mile. type 645 for 6:45. units are miles.")
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

    /// Takes the typed current mile time when the field is submitted or left. A time that is not 5:00 to
    /// 8:30 keeps the old value and shows the note.
    private func commitMile() {
        if let value = InputParsing.validMileTime(mileText) {
            mileTime = value
            mileInvalid = false
        } else {
            mileInvalid = true
        }
        mileText = formatDuration(mileTime)
    }

    private func commitGoal() {
        if let value = InputParsing.validMileTime(goalText) {
            goalMile = value
            goalInvalid = false
        } else {
            goalInvalid = true
        }
        goalText = formatDuration(goalMile)
    }

    /// Keeps the text box in step when the mile time changes elsewhere, such as after a time trial.
    private func syncMileText(_ value: Double) {
        if let typed = InputParsing.mileTime(mileText), abs(typed - value) < 0.5 {
            return
        }
        mileText = formatDuration(value)
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("plan")
            planStartRow
            raceRow
            note("plan weeks run monday to sunday. pick a monday so they match the calendar.")
            resetControls
                .padding(.top, Theme.s3)
        }
    }

    /// The race day the plan currently ends on, from the plan file and the start date above. Not shown
    /// during the test week, when the plan in use is the test plan.
    @ViewBuilder
    private var raceRow: some View {
        if !PlanStore.shared.isTestWeek, let schedule = PlanStore.shared.schedule {
            ReadoutRow(key: "race",
                       value: PlanFormat.dayLabel(offset: schedule.raceDayOffset,
                                                  start: PlanStore.shared.startDate))
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

    // MARK: Test week

    /// Offered before the real plan starts; while it is on, shows its dates and how to end it.
    @ViewBuilder
    private var testWeekSection: some View {
        let store = PlanStore.shared
        if store.isTestWeek {
            testWeekOn(store)
        } else if store.canStartTestWeek {
            testWeekOff
        }
    }

    private var testWeekOff: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("test week")
            note("try the plan this week. test runs and progress are deleted when the test ends or the real plan starts. settings you change, like mile time or voices, are real and stay.")
            BracketButton(title: "start test week", style: .plan) {
                PlanStore.shared.startTestWeek()
            }
            .padding(.top, Theme.s3)
        }
    }

    private func testWeekOn(_ store: PlanStore) -> some View {
        let busy = store.runInProgress || store.trackInProgress
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("test week")
            Text("test week: " + store.testWeekRangeText)
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
                .padding(.top, Theme.s2)
            note(busy ? "finish the run or workout first, then end the test week." : "ending deletes the test runs, workouts and progress. settings stay.")
            if endTestFailed {
                note("could not end the test week. try again.")
            }
            endTestControls(busy: busy)
                .padding(.top, Theme.s3)
        }
    }

    @ViewBuilder
    private func endTestControls(busy: Bool) -> some View {
        if confirmEndTest {
            VStack(spacing: Theme.s2) {
                BracketButton(title: "yes, end and delete test data", style: .inverted, isEnabled: !busy) {
                    endTestWeek()
                }
                BracketButton(title: "cancel") {
                    confirmEndTest = false
                }
            }
        } else {
            BracketButton(title: "end test week", isEnabled: !busy) {
                confirmEndTest = true
            }
        }
    }

    private func endTestWeek() {
        endTestFailed = !PlanStore.shared.endTestWeek()
        confirmEndTest = false
    }

    // MARK: Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("reminders")
            CheckRow(title: "reminders", isOn: $remindersEnabled)
            reminderOptions
                .disabled(!remindersEnabled)
                .opacity(remindersEnabled ? 1 : 0.35)
            ReadoutRow(key: "scheduled", value: String(Reminders.shared.pendingCount))
            permissionRow
            BracketButton(title: "send a test") {
                Reminders.shared.sendTest()
            }
            .padding(.top, Theme.s3)
            note("reminders are local notifications for the next two weeks of the plan. they are rebuilt whenever the plan changes.")
        }
    }

    private var reminderOptions: some View {
        VStack(alignment: .leading, spacing: 0) {
            CheckRow(title: "morning: today's session", isOn: $reminderMorning)
            CheckRow(title: "evening nudge if not logged", isOn: $reminderEvening)
            CheckRow(title: "day before time trials", isOn: $reminderTimeTrial)
            CheckRow(title: "sunday summary", isOn: $reminderWeekly)
            timeRow("morning", minutes: $morningMinutes)
            timeRow("evening", minutes: $eveningMinutes)
        }
    }

    private func timeRow(_ key: String, minutes: Binding<Int>) -> some View {
        let picked = Binding<Date>(get: { ReminderFormat.date(minutes: minutes.wrappedValue) },
                                   set: { minutes.wrappedValue = ReminderFormat.minutes(of: $0) })
        return VStack(spacing: 0) {
            HStack(spacing: Theme.s2) {
                Text(ReadoutFormat.leader(key, width: 12))
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
                DatePicker(key + " time", selection: picked, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Theme.fg)
            }
            .padding(.vertical, Theme.s1)
            DashedRule()
        }
    }

    @ViewBuilder
    private var permissionRow: some View {
        if Reminders.shared.authorizationKnown {
            switch Reminders.shared.authorization {
            case .notDetermined:
                BracketButton(title: "allow notifications") {
                    Reminders.shared.requestPermission()
                }
                .padding(.top, Theme.s3)
            case .denied:
                note("notifications are off for milepace in ios settings.")
            default:
                EmptyView()
            }
        }
    }

    private var runSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("run")
            CheckRow(title: "auto-pause", isOn: $autoPause)
            note("pauses when you stop (lights, traffic) and resumes when you run again. never during reps or recoveries, never on the treadmill.")
        }
    }

    // MARK: Routes

    /// One child of the screen's stack (a view builder takes at most 10).
    private var runAndRoutes: some View {
        VStack(alignment: .leading, spacing: 0) {
            runSection
            routesSection
        }
    }

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("routes")
            FieldRow(key: "home",
                     placeholder: "street, city",
                     text: $homeText,
                     keyboard: .default,
                     fieldWidth: 220,
                     onCommit: { commitHome() })
            BracketButton(title: "reset", minHeight: 44, fullWidth: false, size: .micro) {
                resetHome()
            }
            .padding(.top, Theme.s2)
            CheckRow(title: "off-route cue", isOn: $offRouteCue)
                .padding(.top, Theme.s2)
            note("says \"Off route.\" once when you stay more than 40 m from the route you follow for 20 seconds. needs the voice switch. never on the treadmill.")
            note("routes start here. after a new address, tap [ resolve all ] on the routes screen to find them again (needs the network).")
        }
    }

    /// Takes the typed home address when the field is submitted or left; an empty one goes back to the default.
    private func commitHome() {
        let trimmed = homeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            resetHome()
            return
        }
        if trimmed != homeAddress {
            homeAddress = trimmed
        }
        homeText = trimmed
    }

    private func resetHome() {
        homeAddress = RouteHome.defaultAddress
        homeText = RouteHome.defaultAddress
    }

    private var voiceAndFeedback: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("voice and feedback")
            CheckRow(title: "voice", isOn: $voiceEnabled)
            if !voiceEnabled {
                note("voice is off. haptics still work. also mutes the track countdown and lap feedback.")
            }
            voiceRow
            ChoiceRow(label: "pace cues every", options: cueOptions, selection: $cueInterval)
            CheckRow(title: "announce each mile", isOn: $announceMiles)
            CheckRow(title: "pace guard cues", isOn: $zoneGuardCues)
            StepperRow(title: "target window",
                       value: paceWindowSeconds,
                       range: Int(AppSettings.paceWindowRange.lowerBound)...Int(AppSettings.paceWindowRange.upperBound),
                       format: { "\u{00B1}\($0) s/mi" })
            note("how far off target before you hear speed up / slow down. wider = fewer cues.")
            CheckRow(title: "haptics", isOn: $haptics)
            note("mile announcements are skipped during reps and recoveries, and with 1 mi pace cues on.")
        }
    }

    /// The chosen voice (or "default"); opens the picker. Set is not inside a navigation stack, so the
    /// picker is a sheet.
    private var voiceRow: some View {
        return Button {
            showVoicePicker = true
        } label: {
            ReadoutRow(key: "voice", value: voiceRowValue + " >")
        }
        .buttonStyle(InstrumentButtonStyle())
        .onAppear {
            voiceOptions = Coach.availableVoices()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                voiceOptions = Coach.availableVoices()
            }
        }
        .sheet(isPresented: $showVoicePicker, onDismiss: {
            voiceOptions = Coach.availableVoices()
        }) {
            VoicePickerView()
        }
    }

    private var voiceRowValue: String {
        if let chosen = VoiceCatalog.resolve(identifier: voiceIdentifier, available: voiceOptions) {
            return VoiceCatalog.label(chosen)
        }
        return "default"
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
            CheckRow(title: "click", isOn: $metronomeEnabled)
            note("the click is separate from the voice. here it sets the default for the next run; during a run, use [ click on ] on the run screen.")
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
