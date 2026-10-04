import Foundation
import AVFoundation
import UIKit

/// Decides when to cue the runner that pace has drifted outside a target zone.
/// Pace must be outside the zone for 20 s continuously; cues are at most once per 60 s.
struct ZoneGuard {
    enum Cue: Equatable {
        case easyUp
        case pickItUp
    }

    static let outsideSecondsRequired: Double = 20
    static let minSecondsBetweenCues: Double = 60

    private var outsideSince: Date?
    private var outsideCue: Cue?
    private var lastCue: Date?

    init() {}

    mutating func reset() {
        outsideSince = nil
        outsideCue = nil
        lastCue = nil
    }

    /// `zone` is a seconds-per-mile range. Too fast (below the lower bound) cues "Easy up";
    /// too slow (above the upper bound) cues "Pick it up".
    mutating func update(pace: Double?, zone: ClosedRange<Double>?, now: Date) -> Cue? {
        guard let zone = zone, let pace = pace else {
            outsideSince = nil
            outsideCue = nil
            return nil
        }

        let cue: Cue
        if pace < zone.lowerBound {
            cue = .easyUp
        } else if pace > zone.upperBound {
            cue = .pickItUp
        } else {
            outsideSince = nil
            outsideCue = nil
            return nil
        }

        if outsideCue != cue || outsideSince == nil {
            outsideCue = cue
            outsideSince = now
            return nil
        }

        guard let since = outsideSince,
              now.timeIntervalSince(since) >= ZoneGuard.outsideSecondsRequired else {
            return nil
        }
        if let last = lastCue, now.timeIntervalSince(last) < ZoneGuard.minSecondsBetweenCues {
            return nil
        }
        lastCue = now
        return cue
    }
}

/// Voice announcements and haptics.
@MainActor
final class Coach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Coach(synthesizer: AVSpeechSynthesizer())

    private let synthesizer: AVSpeechSynthesizer
    private var pendingUtterances = 0
    private var zoneGuard = ZoneGuard()

    private init(synthesizer: AVSpeechSynthesizer) {
        self.synthesizer = synthesizer
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Run announcements

    func announceMile(_ mile: Int, split: Double, average: Double?) {
        guard AppSettings.announceMiles else { return }
        var text = "Mile \(mile). Split \(spokenMinutesSeconds(split))."
        if let average = average {
            text += " Average \(spokenCompact(average))."
        }
        speak(text)
    }

    func resetZoneGuard() {
        zoneGuard.reset()
    }

    func evaluateZone(pace: Double?, zone: ClosedRange<Double>?, now: Date = Date()) {
        guard AppSettings.zoneGuardCues else { return }
        guard let cue = zoneGuard.update(pace: pace, zone: zone, now: now) else { return }
        switch cue {
        case .easyUp: speak("Easy up")
        case .pickItUp: speak("Pick it up")
        }
    }

    // MARK: Track announcements

    func announceRestCountdown(seconds: Int) {
        guard AppSettings.trackCountdown else { return }
        speak(seconds == 1 ? "1 second" : "\(seconds) seconds")
    }

    func announceGo() {
        guard AppSettings.trackCountdown else { return }
        speak("Go when ready")
    }

    func announceLap(delta: Double) {
        guard AppSettings.lapFeedback else { return }
        switch SplitVerdict.verdict(delta: delta) {
        case .onPace:
            speak("On pace")
        case .fast, .slow:
            let whole = max(1, Int(abs(delta).rounded()))
            let unit = whole == 1 ? "second" : "seconds"
            let direction = delta < 0 ? "fast" : "slow"
            speak("\(whole) \(unit) \(direction)")
        }
    }

    // MARK: Haptics

    func lapHaptic() {
        guard AppSettings.haptics else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    func restEndHaptic() {
        guard AppSettings.haptics else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    // MARK: Speech

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true)
        } catch {
            // Speak anyway; the system may still route audio.
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        pendingUtterances += 1
        synthesizer.speak(utterance)
    }

    private func utteranceEnded() {
        pendingUtterances = max(0, pendingUtterances - 1)
        if pendingUtterances == 0 {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.utteranceEnded()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.utteranceEnded()
        }
    }
}
