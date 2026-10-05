import SwiftUI

/// Identifiable wrapper so a spec can drive `sheet(item:)` and `fullScreenCover(item:)`.
struct SetupItem: Identifiable {
    let id = UUID()
    var spec: WorkoutSpec
}

/// Identifiable wrapper for resuming a saved session in `fullScreenCover(item:)`.
struct ResumeItem: Identifiable {
    let id = UUID()
    let draft: TrackSessionDraft
}

/// Track tab: preset list, with a setup sheet that leads into the session.
@MainActor
struct TrackSetupView: View {
    /// True while the Track tab is the selected tab. Plan routes are applied only then.
    let isActive: Bool

    @AppStorage(SettingsKey.mileTime) private var mileTime: Double = AppSettings.defaultMileTime
    @AppStorage(SettingsKey.goalMile) private var goalMile: Double = AppSettings.defaultGoalMile

    @State private var editing: SetupItem?
    @State private var savedDraft: TrackSessionDraft?
    @State private var resuming: ResumeItem?
    @State private var confirmDiscardDraft: Bool = false

    init(isActive: Bool) {
        self.isActive = isActive
    }

    private var zones: PaceZones {
        return PaceZones.forMile(mileTime)
    }

    private var store: PlanStore {
        return PlanStore.shared
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "track", right: goalHeader)
            planBanner
            resumeCard
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PresetGroup.allCases) { group in
                        groupSection(group)
                    }
                    SectionHeader("custom")
                    BracketButton(title: "custom workout") {
                        editing = SetupItem(spec: WorkoutPresets.customSpec(zones: zones))
                    }
                    .padding(.top, Theme.s3)
                    .padding(.bottom, Theme.s3)
                }
                .padding(.horizontal, Theme.s3)
            }
        }
        .instrumentScreen()
        .sheet(item: $editing, onDismiss: {
            // Leaving the setup sheet, or finishing from it, ends the plan session hand-off.
            store.discardActive()
            reloadDraft()
        }) { item in
            WorkoutEditorView(spec: item.spec)
        }
        .fullScreenCover(item: $resuming) { item in
            TrackSessionView(spec: item.draft.workout.spec, restored: item.draft) {
                resuming = nil
                reloadDraft()
            }
        }
        .onAppear {
            reloadDraft()
            applyPendingRoute()
        }
        .onChange(of: isActive) { _, active in
            if active {
                reloadDraft()
                applyPendingRoute()
            } else if editing == nil {
                // Left the track tab without starting: forget the session the route opened.
                store.discardActive()
            }
        }
        .onChange(of: PlanStore.shared.pendingRoute) { _, _ in
            applyPendingRoute()
        }
    }

    /// "goal 82.5/400", from the goal mile setting.
    private var goalHeader: String {
        return "goal " + formatSplit(WorkoutPresets.goalPer400(goalMile: goalMile)) + "/400"
    }

    // MARK: Saved session

    private func reloadDraft() {
        let draft = TrackSessionStore.load()
        if draft != savedDraft {
            savedDraft = draft
        }
        if draft == nil {
            confirmDiscardDraft = false
        }
    }

    /// A session that was running when the app was closed or killed, offered for three hours.
    @ViewBuilder
    private var resumeCard: some View {
        if let draft = savedDraft {
            VStack(alignment: .leading, spacing: Theme.s2) {
                Text(draft.title)
                    .font(Theme.mono(.body))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.s2) {
                    BracketButton(title: draft.actionTitle, style: .outlineOnInverted, minHeight: 48) {
                        resuming = ResumeItem(draft: draft)
                    }
                    BracketButton(title: confirmDiscardDraft ? "yes, discard" : "discard",
                                  style: .outlineOnInverted,
                                  minHeight: 48) {
                        discardDraft()
                    }
                }
            }
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.s3)
            .background(Theme.fg)
        }
    }

    private func discardDraft() {
        if confirmDiscardDraft {
            TrackSessionStore.clear()
            confirmDiscardDraft = false
            reloadDraft()
        } else {
            confirmDiscardDraft = true
        }
    }

    // MARK: Plan

    /// Today's unfinished track session from the plan, if any.
    private var todayTrackIndex: Int? {
        guard let schedule = store.schedule else { return nil }
        return schedule.todays(today: store.todayOffset).first(where: { schedule.plan.sessions[$0].isTrackSession })
    }

    @ViewBuilder
    private var planBanner: some View {
        if let index = todayTrackIndex, let schedule = store.schedule {
            PlanBar(text: "today: " + schedule.plan.sessions[index].title, actionTitle: "start") {
                store.markActive(index)
                let session = schedule.plan.sessions[index]
                openTrack(session.preset, targetSeconds: session.targetSeconds)
            }
        }
    }

    /// Opens the setup sheet for a preset id, or the custom builder when there is no such preset.
    /// A plan time trial or race brings its own goal time; started from the track tab the mile time
    /// trial aims for the current mile time.
    private func openTrack(_ presetId: String?, targetSeconds: Double? = nil) {
        if let id = presetId, let preset = WorkoutPresets.all.first(where: { $0.id == id }) {
            editing = SetupItem(spec: startSpec(preset, planTarget: targetSeconds))
        } else {
            editing = SetupItem(spec: WorkoutPresets.customSpec(zones: zones))
        }
    }

    private func applyPendingRoute() {
        guard isActive, let route = store.pendingRoute else { return }
        guard case .track(let presetId, let targetSeconds) = route else { return }
        store.pendingRoute = nil
        openTrack(presetId, targetSeconds: targetSeconds)
    }

    /// "today" or "tue oct 20" for a preset scheduled in the next 14 days.
    private func planTag(for preset: WorkoutPreset) -> String? {
        guard let schedule = store.schedule else { return nil }
        let today = store.todayOffset
        guard let day = schedule.nearestDay(forPreset: preset.id, today: today, within: 14) else { return nil }
        if day == today {
            return "today"
        }
        return PlanFormat.dayLabel(offset: day, start: store.startDate)
    }

    private func groupSection(_ group: PresetGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(group.title.lowercased())
            ForEach(WorkoutPresets.presets(in: group)) { preset in
                presetButton(preset)
            }
        }
    }

    private func startSpec(_ preset: WorkoutPreset, planTarget: Double?) -> WorkoutSpec {
        return preset.startSpec(zones: zones, goalMile: goalMile, mileTime: mileTime, planTarget: planTarget)
    }

    private func presetButton(_ preset: WorkoutPreset) -> some View {
        let spec = startSpec(preset, planTarget: nil)
        return Button {
            editing = SetupItem(spec: spec)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ReadoutRow(key: preset.name,
                           value: formatSplit(spec.targetRepSeconds),
                           ruled: false,
                           leaders: false)
                HStack(spacing: Theme.s2) {
                    Text(summaryLine(for: spec))
                        .font(Theme.mono(.micro))
                        .foregroundStyle(Theme.dim)
                    Spacer(minLength: 0)
                    planTagView(for: preset)
                }
                .padding(.bottom, Theme.s2)
                DashedRule()
            }
        }
        .buttonStyle(InstrumentButtonStyle())
    }

    @ViewBuilder
    private func planTagView(for preset: WorkoutPreset) -> some View {
        if let tag = planTag(for: preset) {
            PlanTag(text: tag)
        }
    }

    private func summaryLine(for spec: WorkoutSpec) -> String {
        var text = "per rep"
        if spec.repDistance != 400 {
            text += " \u{00B7} " + formatSplit(spec.targetPer400) + " per 400"
        }
        if spec.totalReps > 1 {
            text += " \u{00B7} rest " + formatDuration(Double(spec.restSeconds))
        }
        return text
    }
}

/// Setup sheet: edit reps, distance, target and rest, then start the session.
@MainActor
struct WorkoutEditorView: View {
    static let distances: [Int] = [200, 300, 400, 600, 800, 1000, 1200, 1609]

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var reps: Int
    @State private var distance: Int
    @State private var targetText: String
    @State private var restSeconds: Int
    @State private var sets: Int
    @State private var setRestSeconds: Int
    @State private var session: SetupItem?

    init(spec: WorkoutSpec) {
        _name = State(initialValue: spec.name)
        _reps = State(initialValue: spec.reps)
        _distance = State(initialValue: spec.repDistance)
        _targetText = State(initialValue: formatSplit(spec.targetRepSeconds))
        _restSeconds = State(initialValue: spec.restSeconds)
        _sets = State(initialValue: spec.sets)
        _setRestSeconds = State(initialValue: spec.setRestSeconds)
    }

    private var parsedTarget: Double? {
        guard let value = parseTime(targetText), value >= 10, value <= 3600 else { return nil }
        return value
    }

    private var currentSpec: WorkoutSpec? {
        guard let target = parsedTarget else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutSpec(name: trimmed.isEmpty ? "Workout" : trimmed,
                           reps: reps,
                           repDistance: distance,
                           targetRepSeconds: target,
                           restSeconds: restSeconds,
                           sets: sets,
                           setRestSeconds: setRestSeconds)
    }

    private var distanceOptions: [Int] {
        var options = WorkoutEditorView.distances
        if !options.contains(distance) {
            options.append(distance)
            options.sort()
        }
        return options
    }

    /// The rep distance as an index into `distanceOptions`, so a stepper can walk the list.
    private var distanceIndex: Binding<Int> {
        return Binding(get: { distanceOptions.firstIndex(of: distance) ?? 0 },
                       set: { newIndex in
                           let options = distanceOptions
                           guard !options.isEmpty else { return }
                           distance = options[min(max(newIndex, 0), options.count - 1)]
                       })
    }

    private func distanceText(_ index: Int) -> String {
        let options = distanceOptions
        guard index >= 0, index < options.count else { return "--" }
        return "\(options[index]) m"
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "setup", right: "")
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
                    workoutSection
                    targetSection
                    restSection
                    BracketButton(title: "start workout",
                                  style: .signal,
                                  minHeight: 80,
                                  isEnabled: currentSpec != nil) {
                        if let spec = currentSpec {
                            session = SetupItem(spec: spec)
                        }
                    }
                    .padding(.top, Theme.s4)
                    .padding(.bottom, Theme.s3)
                }
                .padding(.horizontal, Theme.s3)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .instrumentScreen()
        .onChange(of: distance) { old, new in
            rescaleTarget(from: old, to: new)
        }
        .onChange(of: sets) { _, newSets in
            setRestSeconds = WorkoutEditing.setRest(current: setRestSeconds, repRest: restSeconds, sets: newSets)
        }
        .fullScreenCover(item: $session) { item in
            TrackSessionView(spec: item.spec) {
                session = nil
                dismiss()
            }
        }
    }

    /// Keeps the same pace when the rep distance changes: 82 s for 400 m becomes 164 s for 800 m.
    private func rescaleTarget(from old: Int, to new: Int) {
        guard let target = parsedTarget else { return }
        let scaled = WorkoutEditing.rescaledTarget(target, fromDistance: old, toDistance: new)
        targetText = formatSplit(scaled)
    }

    private var workoutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("workout")
            FieldRow(key: "name",
                     placeholder: "workout",
                     text: $name,
                     keyboard: .default,
                     fieldWidth: 200)
            StepperRow(title: "reps", value: $reps, range: 1...30)
            StepperRow(title: "rep dist",
                       value: distanceIndex,
                       range: 0...(distanceOptions.count - 1),
                       format: { index in distanceText(index) })
            StepperRow(title: "sets", value: $sets, range: 1...8)
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("target")
            FieldRow(key: "per rep",
                     placeholder: "m:ss.s",
                     text: $targetText,
                     note: currentSpec == nil ? "enter a time like 82.5 or 2:05" : nil)
            if let spec = currentSpec {
                Text(formatSplit(spec.targetPer400) + " per 400 m")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.dim)
                    .padding(.top, Theme.s2)
                if spec.lapsPerRep > 1 {
                    Text("\(spec.lapsPerRep) lap taps per rep")
                        .font(Theme.mono(.micro))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("rest")
            StepperRow(title: "btw reps",
                       value: $restSeconds,
                       range: 0...900,
                       step: 5,
                       format: { formatDuration(Double($0)) })
            if sets > 1 {
                StepperRow(title: "btw sets",
                           value: $setRestSeconds,
                           range: 0...900,
                           step: 15,
                           format: { formatDuration(Double($0)) })
            }
        }
    }
}
