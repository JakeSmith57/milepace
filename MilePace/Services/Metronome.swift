import Foundation
import AVFoundation
import Observation

/// Reads of the audio-session notifications that decide what the metronome does. Pure, so they can be tested.
enum AudioSessionEvents {
    /// Whether an interruption-ended notification asks the app to resume playback.
    static func shouldResume(optionsRaw: UInt?) -> Bool {
        guard let raw = optionsRaw else { return false }
        return AVAudioSession.InterruptionOptions(rawValue: raw).contains(.shouldResume)
    }

    /// Whether a route change is the output device going away (headphones unplugged, Bluetooth lost).
    static func isOutputLost(reasonRaw: UInt?) -> Bool {
        guard let raw = reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return false }
        return reason == .oldDeviceUnavailable
    }
}

/// Cadence metronome: loops a one-beat click buffer through an AVAudioEngine.
@Observable
@MainActor
final class Metronome {
    static let shared = Metronome()

    private(set) var isRunning = false
    private(set) var bpm: Int = AppSettings.defaultMetronomeBPM
    private(set) var volume: Float = Float(AppSettings.defaultMetronomeVolume)

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var isGraphAttached = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// True from an interruption that stopped the click until the interruption ends.
    @ObservationIgnored private var wasRunningBeforeInterruption = false

    private init() {
        let center = NotificationCenter.default
        let configObserver = center.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                object: engine,
                                                queue: nil) { @Sendable [weak self] _ in
            Task { @MainActor in
                self?.handleConfigurationChange()
            }
        }
        let interruptionObserver = center.addObserver(forName: AVAudioSession.interruptionNotification,
                                                      object: nil,
                                                      queue: nil) { @Sendable [weak self] notification in
            // Notification is not Sendable: read the plain value here, then hop.
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor in
                self?.handleInterruption(rawType: rawType, rawOptions: rawOptions)
            }
        }
        let routeObserver = center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                               object: nil,
                                               queue: nil) { @Sendable [weak self] notification in
            let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor in
                self?.handleRouteChange(rawReason: rawReason)
            }
        }
        observers = [configObserver, interruptionObserver, routeObserver]
    }

    // MARK: Control

    func start() {
        guard !isRunning else { return }
        wasRunningBeforeInterruption = false
        AudioSessionCoordinator.shared.beginMetronome()
        isRunning = true
        if startEngine() {
            Diagnostics.shared.log(.audio, "metronome start \(bpm)")
        } else {
            isRunning = false
            AudioSessionCoordinator.shared.endMetronome()
        }
    }

    func stop() {
        wasRunningBeforeInterruption = false
        guard isRunning else { return }
        haltEngine()
        isRunning = false
        AudioSessionCoordinator.shared.endMetronome()
        Diagnostics.shared.log(.audio, "metronome stop")
    }

    /// Sets the tempo (clamped to the supported range) and restarts the click if it is playing.
    func setBPM(_ value: Int) {
        let clamped = min(max(value, ClickTrack.bpmRange.lowerBound), ClickTrack.bpmRange.upperBound)
        guard clamped != bpm else { return }
        bpm = clamped
        if isRunning {
            restart()
        }
    }

    /// Sets the click volume (0.1 to 1.0).
    func setVolume(_ value: Float) {
        volume = min(max(value, 0.1), 1.0)
        if isRunning {
            player.volume = volume
        }
    }

    // MARK: Internals

    private func haltEngine() {
        player.stop()
        engine.stop()
    }

    private func restart() {
        haltEngine()
        if !startEngine() {
            isRunning = false
            AudioSessionCoordinator.shared.endMetronome()
        }
    }

    /// Builds the click buffer for the current tempo and starts looping it. Returns false on failure.
    private func startEngine() -> Bool {
        let sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        guard sampleRate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return false
        }

        if !isGraphAttached {
            engine.attach(player)
            isGraphAttached = true
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let samples = ClickTrack.beatSamples(bpm: bpm, sampleRate: sampleRate)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            return false
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in 0..<samples.count {
            channel[index] = samples[index]
        }

        player.volume = volume
        do {
            try engine.start()
        } catch {
            return false
        }
        player.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        player.play()
        return true
    }

    private func handleConfigurationChange() {
        guard isRunning else { return }
        restart()
    }

    /// A call, an alarm or another app took the audio session: the engine is stopped and released at
    /// once, so `isRunning` is false and the screen never shows a click that cannot be heard. When the
    /// interruption ends with "should resume", the click starts again.
    private func handleInterruption(rawType: UInt?, rawOptions: UInt?) {
        guard let rawType = rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            guard isRunning else { return }
            haltEngine()
            isRunning = false
            wasRunningBeforeInterruption = true
            AudioSessionCoordinator.shared.endMetronome()
            Diagnostics.shared.log(.audio, "metronome interrupted")
        case .ended:
            let resume = wasRunningBeforeInterruption && AudioSessionEvents.shouldResume(optionsRaw: rawOptions)
            wasRunningBeforeInterruption = false
            if resume {
                start()
            }
        @unknown default:
            break
        }
    }

    /// Headphones unplugged or the Bluetooth output gone: the click must not jump to the speaker, so it
    /// stops and the run screen's metronome switch goes off.
    private func handleRouteChange(rawReason: UInt?) {
        guard AudioSessionEvents.isOutputLost(reasonRaw: rawReason) else { return }
        guard isRunning else { return }
        stop()
        UserDefaults.standard.set(false, forKey: SettingsKey.metronomeEnabled)
        Diagnostics.shared.log(.audio, "metronome stopped, output lost")
    }
}
