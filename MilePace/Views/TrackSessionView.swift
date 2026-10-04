import SwiftUI
import SwiftData
import UIKit

@MainActor
struct TrackSessionView: View {
    let onClose: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var workout: TrackWorkout
    @State private var now: Date = Date()
    @State private var lastCountdownSecond: Int = -1
    @State private var confirmEnd: Bool = false

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    init(spec: WorkoutSpec, onClose: @escaping () -> Void) {
        _workout = State(initialValue: TrackWorkout(spec: spec))
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            if workout.state == .finished {
                resultsView
            } else {
                sessionBody
            }
        }
        .onReceive(ticker) { date in
            handleTick(date)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .confirmationDialog("End workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End and see results", role: .destructive) {
                workout.finishEarly()
            }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: Session

    private var progressText: String {
        let total = workout.totalReps
        let spec = workout.spec
        switch workout.state {
        case .ready:
            return "Ready  ·  \(total) reps"
        case .running(let rep, let lap):
            var text = "Rep \(rep)/\(total)"
            if spec.lapsPerRep > 1 {
                text += "  ·  Lap \(lap)/\(spec.lapsPerRep)"
            }
            if spec.sets > 1 {
                text += "  ·  Set \(workout.setNumber(forRep: rep))/\(spec.sets)"
            }
            return text
        case .resting, .setRest:
            return "Resting  ·  next is rep \(workout.completedReps + 1)/\(total)"
        case .finished:
            return "Finished"
        }
    }

    private var sessionBody: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                header
                centerArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomControls
                    .frame(height: proxy.size.height * 0.42)
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.spec.name)
                    .font(.headline)
                Text(progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("End") {
                confirmEnd = true
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    @ViewBuilder
    private var centerArea: some View {
        switch workout.state {
        case .ready:
            VStack(spacing: 8) {
                Text("Tap START when you begin running")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(formatSplit(workout.spec.targetRepSeconds))
                    .font(.roundedDigits(72))
                Text("target per rep")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .running(_, let lap):
            VStack(spacing: 10) {
                Text(formatSplit(workout.repElapsed(at: now)))
                    .font(.roundedDigits(88))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Lap \(lap) target  \(formatSplit(workout.currentLapTarget ?? workout.spec.targetRepSeconds))")
                    .font(.system(.title3, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                lastLapRow
            }
        case .resting, .setRest:
            restRing
        case .finished:
            EmptyView()
        }
    }

    @ViewBuilder
    private var lastLapRow: some View {
        if let last = workout.lastLap {
            let verdict = SplitVerdict.verdict(delta: last.delta)
            HStack(spacing: 10) {
                Text("Last")
                    .foregroundStyle(.secondary)
                Text(formatSplit(last.split))
                    .font(.roundedDigits(32, weight: .semibold))
                Text(formatDelta(last.delta))
                    .font(.roundedDigits(32, weight: .semibold))
                    .foregroundStyle(verdict.color)
            }
        } else {
            Text(" ")
                .font(.roundedDigits(32, weight: .semibold))
        }
    }

    private var restRing: some View {
        let total = max(1, workout.restTotal)
        let remaining = workout.restRemaining(at: now)
        let progress = workout.isRestComplete ? 0 : remaining / total
        return ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: 14)
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 4) {
                if workout.isRestComplete {
                    Text("GO")
                        .font(.roundedDigits(64))
                        .foregroundStyle(.green)
                } else {
                    Text(formatDuration(remaining.rounded(.up)))
                        .font(.roundedDigits(64))
                }
                Text(workout.isRestComplete ? "rest over" : "rest")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 230, height: 230)
    }

    @ViewBuilder
    private var bottomControls: some View {
        VStack(spacing: 10) {
            switch workout.state {
            case .ready:
                bigButton(title: "START", color: .orange) {
                    startWorkout()
                }
            case .running(_, let lap):
                bigButton(title: lap < workout.spec.lapsPerRep ? "LAP" : "FINISH", color: .orange) {
                    tapLap()
                }
            case .resting, .setRest:
                if workout.isRestComplete {
                    bigButton(title: "GO", color: .green) {
                        tapLap()
                    }
                } else {
                    VStack(spacing: 10) {
                        Text("Rest")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
                        Button("Skip rest") {
                            workout.skipRest(now: Date())
                        }
                        .buttonStyle(.bordered)
                    }
                }
            case .finished:
                EmptyView()
            }

            Button {
                workout.undoLastTap()
            } label: {
                Label("Undo last tap", systemImage: "arrow.uturn.backward")
                    .font(.footnote)
            }
            .disabled(!workout.canUndo)
        }
    }

    private func bigButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color, in: RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func startWorkout() {
        workout.start(now: Date())
        Coach.shared.lapHaptic()
    }

    private func tapLap() {
        let outcome = workout.lapTap(now: Date())
        switch outcome {
        case .ignored:
            break
        case .startedRep:
            Coach.shared.lapHaptic()
        case .lapDone(_, let delta, _, _):
            Coach.shared.lapHaptic()
            Coach.shared.announceLap(delta: delta)
        }
    }

    private func handleTick(_ date: Date) {
        now = date
        if workout.tick(now: date) {
            Coach.shared.restEndHaptic()
            Coach.shared.announceGo()
        }
        if workout.isResting && !workout.isRestComplete {
            let seconds = Int(workout.restRemaining(at: date).rounded(.up))
            if seconds == 10 && lastCountdownSecond != 10 {
                Coach.shared.announceRestCountdown(seconds: 10)
            }
            lastCountdownSecond = seconds
        } else {
            lastCountdownSecond = -1
        }
    }

    // MARK: Results

    private var resultsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(workout.spec.name)
                    .font(.title2.weight(.bold))
                Text("Results")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                WorkoutResultsTable(spec: workout.spec,
                                    repTimes: workout.repTimes,
                                    lapSplits: workout.lapSplits)

                VStack(spacing: 10) {
                    FilledActionButton(title: "Save Workout", color: .orange) {
                        saveWorkout()
                    }
                    .disabled(workout.repTimes.isEmpty)
                    .opacity(workout.repTimes.isEmpty ? 0.4 : 1)
                    Button("Discard", role: .destructive) {
                        onClose()
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 8)
            }
            .padding()
        }
    }

    private func saveWorkout() {
        let record = WorkoutRecord(date: Date(),
                                   name: workout.spec.name,
                                   spec: workout.spec,
                                   repTimes: workout.repTimes,
                                   lapSplits: workout.lapSplits)
        modelContext.insert(record)
        onClose()
    }
}
