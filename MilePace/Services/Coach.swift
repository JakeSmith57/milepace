import Foundation
import AVFoundation
import UIKit

/// Decides when to cue the runner that pace has drifted outside a target zone.
/// By default pace must be outside the zone for 20 s continuously and cues are at most once per 60 s.
struct ZoneGuard {
    enum Cue: Equatable {
        case easyUp
        case pickItUp
    }

    /// What the runner hears for a cue.
    static func spokenText(for cue: Cue) -> String {
        switch cue {
        case .easyUp: return "Slow down"
        case .pickItUp: return "Speed up"
        }
    }

    static let outsideSecondsRequired: Double = 20
    static let minSecondsBetweenCues: Double = 60

    private let requiredSeconds: Double
    private let cueGapSeconds: Double
    private var outsideSince: Date?
    private var outsideCue: Cue?
    private var lastCue: Date?

    init(outsideSecondsRequired: Double = ZoneGuard.outsideSecondsRequired,
         minSecondsBetweenCues: Double = ZoneGuard.minSecondsBetweenCues) {
        self.requiredSeconds = outsideSecondsRequired
        self.cueGapSeconds = minSecondsBetweenCues
    }

    mutating func reset() {
        outsideSince = nil
        outsideCue = nil
        lastCue = nil
    }

    /// How long pace has been outside the zone, or nil when it is inside (or unknown).
    func secondsOutside(at now: Date) -> Double? {
        guard let since = outsideSince else { return nil }
        return max(0, now.timeIntervalSince(since))
    }

    /// `zone` is a seconds-per-mile range. Too fast (below the lower bound) cues "Slow down";
    /// too slow (above the upper bound) cues "Speed up".
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
              now.timeIntervalSince(since) >= requiredSeconds else {
            return nil
        }
        if let last = lastCue, now.timeIntervalSince(last) < cueGapSeconds {
            return nil
        }
        lastCue = now
        return cue
    }
}

/// Whether the whole-mile announcement ("Mile 2. Split ...") is spoken.
enum MileAnnouncement {
    /// Never while a workout rep or recovery is running, never when the "announce each mile" setting is
    /// off, and never with 1 mi pace cues on, because those cues replace it.
    static func shouldAnnounce(interval: CueInterval, announceSetting: Bool, suppressed: Bool) -> Bool {
        if suppressed || !announceSetting { return false }
        switch interval {
        case .off, .quarter, .half: return true
        case .mile: return false
        }
    }
}

/// Voice announcements and haptics.
@MainActor
final class Coach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = Coach(synthesizer: AVSpeechSynthesizer())

    private let synthesizer: AVSpeechSynthesizer
    private var pendingUtterances = 0
    private var zoneGuard = ZoneGuard()
    /// Tighter timings used while a workout rep is running.
    private var repGuard = ZoneGuard(outsideSecondsRequired: 12, minSecondsBetweenCues: 30)

    private init(synthesizer: AVSpeechSynthesizer) {
        self.synthesizer = synthesizer
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Run announcements

    /// `suppressed` is true while a guided workout is in a rep or recovery, so nothing talks over it.
    func announceMile(_ mile: Int, split: Double, average: Double?, suppressed: Bool = false) {
        guard MileAnnouncement.shouldAnnounce(interval: AppSettings.cueInterval,
                                              announceSetting: AppSettings.announceMiles,
                                              suppressed: suppressed) else { return }
        var text = "Mile \(mile). Split \(spokenMinutesSeconds(split))."
        if let average = average {
            text += " Average \(spokenCompact(average))."
        }
        speak(text, reason: "mile \(mile)")
    }

    func resetZoneGuard() {
        zoneGuard.reset()
    }

    func evaluateZone(pace: Double?, zone: ClosedRange<Double>?, now: Date = Date()) {
        guard AppSettings.zoneGuardCues else { return }
        guard let cue = zoneGuard.update(pace: pace, zone: zone, now: now), let range = zone else { return }
        let reason = zoneReason(cue: cue, zone: range, seconds: zoneGuard.secondsOutside(at: now))
        speak(ZoneGuard.spokenText(for: cue), reason: reason)
    }

    /// "21s under 7:58" or "21s over 8:03": how long pace was outside and which bound it crossed.
    private func zoneReason(cue: ZoneGuard.Cue, zone: ClosedRange<Double>, seconds: Double?) -> String {
        let whole = Int((seconds ?? 0).rounded())
        switch cue {
        case .easyUp:
            return "\(whole)s under \(formatPace(secondsPerMile: zone.lowerBound))"
        case .pickItUp:
            return "\(whole)s over \(formatPace(secondsPerMile: zone.upperBound))"
        }
    }

    /// Short pace cue at each quarter, half or full mile. Whole-mile cues for quarter and half
    /// intervals are left to `announceMile`, which also gives the split and average.
    func announceDistanceCue(_ cue: DistanceCue, interval: CueInterval, zone: ClosedRange<Double>?) {
        guard let perMile = interval.cuesPerMile else { return }
        if interval != .mile && cue.index % perMile == 0 { return }
        var text = "\(interval.spokenName) \(cue.index). Pace \(spokenCompact(cue.paceSecondsPerMile))."
        if let zone = zone {
            text += " " + ZoneVerdict.phrase(pace: cue.paceSecondsPerMile, zone: zone)
        }
        speak(text, reason: "pace \(formatPace(secondsPerMile: cue.paceSecondsPerMile))")
    }

    // MARK: Workout announcements

    func resetRepGuard() {
        repGuard.reset()
    }

    /// Pace-guard cue against a rep's target range, with tighter timings than a free run.
    func evaluateRepZone(pace: Double?, zone: ClosedRange<Double>?, now: Date = Date()) {
        guard AppSettings.zoneGuardCues else { return }
        guard let cue = repGuard.update(pace: pace, zone: zone, now: now), let range = zone else { return }
        let reason = zoneReason(cue: cue, zone: range, seconds: repGuard.secondsOutside(at: now))
        speak(ZoneGuard.spokenText(for: cue), reason: reason)
    }

    func announceWorkoutEvent(_ event: RoadWorkoutSession.Event, spec: RoadWorkoutSpec, repRange: ClosedRange<Double>) {
        switch event {
        case .repStarted(let number, let total):
            repGuard.reset()
            lapHaptic()
            if total > 1 {
                speak("Go. Rep \(number) of \(total). \(spec.spokenLength) at \(spec.target.spokenName).")
            } else {
                speak("Go. \(spec.spokenLength) at \(spec.target.spokenName).")
            }
        case .halfway:
            speak("Halfway.")
        case .repEnded(let number, let avgPace):
            restEndHaptic()
            var text = "Rep \(number) done."
            if let pace = avgPace {
                text += " Average \(spokenCompact(pace)). " + ZoneVerdict.phrase(pace: pace, zone: repRange)
            }
            speak(text)
        case .recoveryCountdown(let seconds):
            if seconds <= 3 {
                speak("3, 2, 1")
            } else {
                speak("\(seconds) seconds")
            }
        case .workoutComplete:
            speak("Workout complete. Cool down easy.")
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

    /// A light tap for a lap press that was ignored because it came too soon.
    func tooSoonHaptic() {
        guard AppSettings.haptics else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
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

    /// English voices the runner can pick, as plain values: every installed voice mapped, personal
    /// voices left out, then filtered and ordered by `VoiceCatalog`.
    static func availableVoices() -> [VoiceOption] {
        var all: [VoiceOption] = []
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            if voice.voiceTraits.contains(.isPersonalVoice) { continue }
            let quality: Int
            switch voice.quality {
            case .enhanced: quality = 2
            case .premium: quality = 3
            default: quality = 1
            }
            all.append(VoiceOption(id: voice.identifier,
                                   name: voice.name,
                                   language: voice.language,
                                   quality: quality))
        }
        return VoiceCatalog.options(from: all)
    }

    /// Says a sample cue in the given voice ("" is the default voice), cutting off anything being said.
    func preview(identifier: String) {
        stopSpeaking()
        speak("Mile 1. Split 7 minutes 2. Speed up.", reason: "preview", voiceIdentifier: identifier, force: true)
    }

    /// The voice for an identifier from Set; the system en-US voice when it is empty or no longer installed.
    private func voice(for identifier: String) -> AVSpeechSynthesisVoice? {
        if !identifier.isEmpty, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    /// `voiceIdentifier` overrides the stored choice (the preview in the voice picker). With the voice
    /// switch off nothing is said, but the cue is still logged so the run log shows what would have been
    /// said; `force` (previews) speaks anyway.
    private func speak(_ text: String, reason: String? = nil, voiceIdentifier: String? = nil, force: Bool = false) {
        if !force && !AppSettings.voiceEnabled {
            Diagnostics.shared.logCue(text, reason: reason.map { $0 + " (voice off)" } ?? "(voice off)")
            return
        }
        Diagnostics.shared.logCue(text, reason: reason)
        AudioSessionCoordinator.shared.beginSpeech()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: voiceIdentifier ?? AppSettings.voiceIdentifier)
        utterance.rate = Float(AppSettings.voiceRate)
        pendingUtterances += 1
        synthesizer.speak(utterance)
    }

    private func utteranceEnded() {
        pendingUtterances = max(0, pendingUtterances - 1)
        AudioSessionCoordinator.shared.endSpeech()
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
