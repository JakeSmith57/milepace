import SwiftUI

/// A dim one-line note in the track screens.
struct TrackMicroLine: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Setup: the rep distance in laps, where to start, which lane.
struct TrackSetupNotes: View {
    let distance: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s1) {
            TrackMicroLine("\(distance) m = " + TrackLaps.describe(meters: distance))
            TrackMicroLine(TrackLaps.startNote(meters: distance))
            TrackMicroLine(TrackLaps.laneNote)
        }
        .padding(.top, Theme.s2)
    }
}

/// Setup: the two assist switches (also kept in Set through the same settings keys).
struct TrackAssistSetupSection: View {
    @AppStorage(SettingsKey.trackAutoLap) private var autoLap: Bool = true
    @AppStorage(SettingsKey.trackAutoStart) private var autoStart: Bool = true
    @Environment(LocationTracker.self) private var tracker

    private var autoLapNote: String {
        if AppSettings.runSurface == .treadmill {
            return "treadmill: no gps, tap [ lap ] at each rep end."
        }
        if tracker.isDenied {
            return "allow location for auto-lap. until then tap [ lap ] at the line."
        }
        return "the phone ends each rep by gps. a tap on [ lap ] always counts first."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("assist")
            CheckRow(title: "gps auto-lap", isOn: $autoLap, ruled: false)
            TrackMicroLine(autoLapNote)
                .padding(.bottom, Theme.s2)
            DashedRule()
            CheckRow(title: "auto-start reps", isOn: $autoStart, ruled: false)
            TrackMicroLine("10 s countdown into rep 1, then each rep starts by itself when the rest ends.")
                .padding(.bottom, Theme.s2)
        }
    }
}

/// Ready screen: how a rep starts and ends, the GPS state and the optional calibration lap.
struct TrackReadyPanel: View {
    let assist: TrackAssist
    let now: Date

    private var startLine: String {
        if AppSettings.trackAutoStart {
            return "tap [ start ] (or let the countdown run) to begin rep 1."
        }
        return "tap [ start ] to begin rep 1."
    }

    private var endLine: String {
        if assist.gpsEnabled {
            return "the phone ends each rep for you by gps, or tap [ lap ] at the line for an exact time."
        }
        return "tap [ lap ] at the line to end each rep."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            TrackMicroLine(startLine)
            TrackMicroLine(endLine)
            if assist.gpsEnabled {
                TrackGPSStatusLine(assist: assist, now: now)
                TrackCalibrationBlock(assist: assist, now: now)
            }
        }
    }
}

/// "gps ready" and what is wrong when it is not.
struct TrackGPSStatusLine: View {
    let assist: TrackAssist
    let now: Date

    private var text: String {
        switch assist.gps.status(now: now) {
        case .ready:
            return "gps ready (\u{00B1}\(Int(max(0, assist.gps.accuracy).rounded())) m)"
        case .searching:
            return "gps: finding signal. wait a moment on the track."
        case .weak:
            return "gps weak here. you may need to tap at the line."
        case .denied:
            return "allow location for auto-lap. rep ends by tap until then."
        case .needsPermission:
            return "allow location when asked, for auto-lap."
        case .off:
            return "gps off"
        }
    }

    var body: some View {
        TrackMicroLine(text)
    }
}

/// Calibration: status line and the one-lap measurement.
struct TrackCalibrationBlock: View {
    let assist: TrackAssist
    let now: Date

    private var statusText: String {
        guard let saved = assist.calibration else {
            return "not calibrated: auto-lap is approximate (\u{00B1}2 s on 200 m)."
        }
        let factor = String(format: "%.3f", saved.factor)
        let day = ReadoutFormat.day(saved.date)
        if saved.isStale(now: now) {
            return "calibration x\(factor) (\(day)) is over 60 days old. do it again?"
        }
        return "calibrated x\(factor) (\(day))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.s2) {
            switch assist.calibrationStep {
            case .idle:
                TrackMicroLine(statusText)
                BracketButton(title: "calibrate: run 1 lap", minHeight: 44, fullWidth: false, size: .micro) {
                    assist.beginCalibration()
                }
            case .armed:
                TrackMicroLine("jog one lap in lane 1. tap at the start line, run a full lap, tap at the same line.")
                HStack(spacing: Theme.s2) {
                    BracketButton(title: "at the start line", minHeight: 44, fullWidth: false, size: .micro) {
                        assist.markCalibrationStart()
                    }
                    BracketButton(title: "cancel", minHeight: 44, fullWidth: false, size: .micro) {
                        assist.cancelCalibration()
                    }
                }
            case .measuring:
                TrackMicroLine("measuring: \(Int(assist.calibrationMeasured.rounded())) m. tap at the line after one full lap.")
                HStack(spacing: Theme.s2) {
                    BracketButton(title: "at the finish line", minHeight: 44, fullWidth: false, size: .micro) {
                        assist.markCalibrationFinish(now: Date())
                    }
                    BracketButton(title: "cancel", minHeight: 44, fullWidth: false, size: .micro) {
                        assist.cancelCalibration()
                    }
                }
            case .done(let measured, let factor):
                TrackMicroLine("the phone measured \(Int(measured.rounded())) m for 400 m. saved x" + String(format: "%.3f", factor) + ".")
                BracketButton(title: "ok", minHeight: 44, fullWidth: false, size: .micro) {
                    assist.cancelCalibration()
                }
            case .failed:
                TrackMicroLine("that was too short to be a lap. try again.")
                BracketButton(title: "try again", minHeight: 44, fullWidth: false, size: .micro) {
                    assist.beginCalibration()
                }
            }
        }
    }
}

/// During a rep: "128 m · 72 to go" by GPS, otherwise "tap at the line".
struct TrackLiveGPSLine: View {
    let assist: TrackAssist
    let repDistance: Int
    let now: Date

    private var text: String {
        guard assist.gpsEnabled, let meters = assist.gps.repMeters else {
            return "tap at the line"
        }
        switch assist.gps.status(now: now) {
        case .ready:
            let done = max(0, Int(meters.rounded()))
            let left = max(0, repDistance - done)
            return "\(done) m \u{00B7} \(left) to go"
        case .weak:
            return "gps weak, tap at the line"
        case .searching, .denied, .needsPermission, .off:
            return "tap at the line"
        }
    }

    var body: some View {
        Text(text)
            .font(Theme.mono(.body))
            .foregroundStyle(Theme.fg)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The lower area while the spoken countdown into rep 1 runs.
struct TrackCountdownArea: View {
    let remaining: Double
    let onStartNow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Theme.s2) {
            Text("\(Int(remaining.rounded(.up)))")
                .font(Theme.mono(.giant))
                .foregroundStyle(Theme.bg)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.fg)
            HStack(spacing: Theme.s2) {
                BracketButton(title: "start now", style: .signal, minHeight: 56, action: onStartNow)
                BracketButton(title: "cancel", minHeight: 56, action: onCancel)
            }
        }
        .padding(.horizontal, Theme.s3)
        .padding(.bottom, Theme.s2)
    }
}
