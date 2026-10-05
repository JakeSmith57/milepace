import Foundation
import AVFoundation

/// What the shared audio session should look like for a given mix of clients. Pure, so it can be tested.
struct AudioSessionPlan: Equatable {
    enum Action: Equatable {
        /// Nobody needs the session.
        case deactivate
        /// Keep it active with the settings below.
        case activate
    }

    let action: Action
    /// Spoken-audio mode (`.voicePrompt`) when true, `.default` otherwise.
    let voicePromptMode: Bool
    /// Lower other apps' audio while speaking.
    let duck: Bool

    /// While the metronome plays, speech mixes in without ducking and the category and options never
    /// change under the running engine, so other apps' audio is never left ducked. Without it, speech
    /// ducks other audio for as long as it lasts.
    static func make(speechCount: Int, metronomeCount: Int) -> AudioSessionPlan {
        if metronomeCount > 0 {
            return AudioSessionPlan(action: .activate, voicePromptMode: false, duck: false)
        }
        if speechCount > 0 {
            return AudioSessionPlan(action: .activate, voicePromptMode: true, duck: true)
        }
        return AudioSessionPlan(action: .deactivate, voicePromptMode: false, duck: false)
    }
}

/// Owns the shared audio session so speech and the metronome do not deactivate each other.
/// Each client counts itself in and out; the session is configured from the combined counts.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    /// The session is released this long after the last client finishes, so back-to-back utterances do
    /// not toggle it, and once more after `retryDelaySeconds` if releasing it fails.
    static let deactivateDelaySeconds: Double = 0.5
    static let retryDelaySeconds: Double = 1.0

    private var speechCount = 0
    private var metronomeCount = 0
    private var applied: AudioSessionPlan?
    private var deactivation: Task<Void, Never>?

    private init() {}

    func beginSpeech() {
        speechCount += 1
        apply()
    }

    func endSpeech() {
        speechCount = max(0, speechCount - 1)
        apply()
    }

    func beginMetronome() {
        metronomeCount += 1
        apply()
    }

    func endMetronome() {
        metronomeCount = max(0, metronomeCount - 1)
        apply()
    }

    /// "idle", "speech", "metronome" or "speech+metronome".
    var stateText: String {
        if speechCount > 0 && metronomeCount > 0 { return "speech+metronome" }
        if speechCount > 0 { return "speech" }
        if metronomeCount > 0 { return "metronome" }
        return "idle"
    }

    private func apply() {
        Diagnostics.shared.setAudio(stateText)
        let plan = AudioSessionPlan.make(speechCount: speechCount, metronomeCount: metronomeCount)
        switch plan.action {
        case .deactivate:
            scheduleDeactivation()
        case .activate:
            cancelDeactivation()
            activate(plan)
        }
    }

    private func cancelDeactivation() {
        deactivation?.cancel()
        deactivation = nil
    }

    private func activate(_ plan: AudioSessionPlan) {
        // Nothing to do while the session already looks like this; in particular the category is not
        // touched when speech starts or ends under a running metronome.
        if applied == plan { return }
        let session = AVAudioSession.sharedInstance()
        let mode: AVAudioSession.Mode = plan.voicePromptMode ? .voicePrompt : .default
        let options: AVAudioSession.CategoryOptions = plan.duck
            ? [.mixWithOthers, .duckOthers]
            : [.mixWithOthers]
        do {
            try session.setCategory(.playback, mode: mode, options: options)
            try session.setActive(true)
            applied = plan
        } catch {
            applied = nil
            Diagnostics.shared.log(.audio, "session activate failed: \(error.localizedDescription)")
        }
    }

    private func scheduleDeactivation() {
        cancelDeactivation()
        deactivation = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(AudioSessionCoordinator.deactivateDelaySeconds * 1_000_000_000))
            } catch {
                return
            }
            self?.deactivateIfIdle(retry: true)
        }
    }

    private func deactivateIfIdle(retry: Bool) {
        guard speechCount == 0, metronomeCount == 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            applied = nil
            deactivation = nil
            Diagnostics.shared.log(.audio, "session released")
        } catch {
            Diagnostics.shared.log(.audio, "session release failed: \(error.localizedDescription)")
            guard retry else {
                deactivation = nil
                return
            }
            deactivation = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(AudioSessionCoordinator.retryDelaySeconds * 1_000_000_000))
                } catch {
                    return
                }
                self?.deactivateIfIdle(retry: false)
            }
        }
    }
}
