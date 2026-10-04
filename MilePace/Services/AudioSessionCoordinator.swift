import Foundation
import AVFoundation

/// Owns the shared audio session so speech and the metronome do not deactivate each other.
/// Each client counts itself in and out; the session is configured from the combined counts.
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private var speechCount = 0
    private var metronomeCount = 0

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
        let session = AVAudioSession.sharedInstance()
        do {
            if speechCount == 0 && metronomeCount == 0 {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
            let mode: AVAudioSession.Mode = metronomeCount == 0 ? .voicePrompt : .default
            let options: AVAudioSession.CategoryOptions = speechCount > 0
                ? [.mixWithOthers, .duckOthers]
                : [.mixWithOthers]
            try session.setCategory(.playback, mode: mode, options: options)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("AudioSessionCoordinator: \(error)")
            #endif
        }
    }
}
