import Foundation
import AVFoundation
import Observation

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
            Task { @MainActor in
                self?.handleInterruption(rawType: rawType)
            }
        }
        observers = [configObserver, interruptionObserver]
    }

    // MARK: Control

    func start() {
        guard !isRunning else { return }
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

    private func handleInterruption(rawType: UInt?) {
        guard let rawType = rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        switch type {
        case .began:
            // The system stops the engine; `isRunning` stays true so the click resumes afterwards.
            break
        case .ended:
            if isRunning {
                restart()
            }
        @unknown default:
            break
        }
    }
}
