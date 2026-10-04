import Foundation
import Observation

/// Live GPS, pace and audio readouts plus an optional log, for the diagnostics panel.
/// The cheap live values always update. The ring log and the per-run export record are only
/// collected while diagnostics are enabled in Settings.
@Observable
@MainActor
final class Diagnostics {
    static let shared = Diagnostics()

    enum Kind: String {
        case fix
        case reject
        case cue
        case state
        case audio
    }

    struct Entry: Identifiable, Equatable {
        let id: Int
        /// Run elapsed seconds, or -1 when no run is going.
        let t: Double
        let kind: Kind
        /// Full line text, starting with its keyword ("fix", "rej", "cue", ...).
        let text: String
    }

    static let maxEntries = 300
    /// Window for the sample rate, in seconds.
    static let rateWindow: Double = 10

    // MARK: Live values

    private(set) var lastAccuracy: Double?
    private(set) var lastSpeedAccuracy: Double?
    private(set) var lastSpeed: Double?
    private(set) var sampleRateHz: Double = 0
    private(set) var lastFixAge: Double?
    private(set) var accepted: Int = 0
    private(set) var rejected: [RejectReason: Int] = [:]
    private(set) var dopplerPace: Double?
    private(set) var windowPace: Double?
    private(set) var cadence: Double?
    private(set) var audioState: String = "idle"
    private(set) var gpsState: GPSState = .off

    // MARK: Log and export record

    /// Newest first, at most `maxEntries`.
    private(set) var entries: [Entry] = []
    /// Number of raw samples in the current run's export record.
    private(set) var recordCount: Int = 0

    @ObservationIgnored private var records: [DiagnosticsRecord] = []
    @ObservationIgnored private var recentArrivals: [Date] = []
    @ObservationIgnored private var lastFixTimestamp: Date?
    @ObservationIgnored private var nextEntryID: Int = 0
    @ObservationIgnored private var clock: Double = -1
    @ObservationIgnored private var runStart: Date?

    private init() {}

    var rejectedTotal: Int {
        return rejected.values.reduce(0, +)
    }

    var isCollecting: Bool {
        return AppSettings.diagnosticsEnabled
    }

    // MARK: Run lifecycle

    /// Clears the per-run counters and export record.
    func beginRun(at date: Date) {
        records = []
        recordCount = 0
        accepted = 0
        rejected = [:]
        dopplerPace = nil
        windowPace = nil
        runStart = date
        clock = 0
    }

    /// Run elapsed seconds for log timestamps; pass -1 when idle.
    func setClock(_ seconds: Double) {
        clock = seconds
    }

    func setCadence(_ value: Double?) {
        cadence = value
    }

    func setGPS(_ state: GPSState) {
        let changedKind = state.name != gpsState.name
        gpsState = state
        guard changedKind else { return }
        switch state {
        case .ready(let accuracy):
            log(.state, "gps ready \(oneDecimal(accuracy))m")
        case .off, .searching, .weak:
            log(.state, "gps \(state.name)")
        }
    }

    func setAudio(_ state: String) {
        guard state != audioState else { return }
        audioState = state
        log(.audio, "audio \(state)")
    }

    // MARK: Samples

    /// Notes any location update (warm-up or run): live accuracy and speed values and the sample rate.
    func noteFix(_ sample: PaceSample) {
        lastAccuracy = sample.horizontalAccuracy >= 0 ? sample.horizontalAccuracy : nil
        lastSpeedAccuracy = sample.speedAccuracy >= 0 ? sample.speedAccuracy : nil
        lastSpeed = sample.speed >= 0 ? sample.speed : nil
        lastFixTimestamp = sample.timestamp
        let now = Date()
        recentArrivals.append(now)
        refresh(now: now)
    }

    /// Refreshes the values that change with time alone. Call on the one-second tick.
    func refresh(now: Date) {
        let cutoff = now.addingTimeInterval(-Diagnostics.rateWindow)
        recentArrivals.removeAll { $0 < cutoff }
        sampleRateHz = Double(recentArrivals.count) / Diagnostics.rateWindow
        if let stamp = lastFixTimestamp {
            lastFixAge = max(0, now.timeIntervalSince(stamp))
        } else {
            lastFixAge = nil
        }
    }

    /// Records what the calculator did with a sample during a run.
    func recordSample(_ sample: PaceSample,
                      outcome: SampleOutcome,
                      distance: Double,
                      windowPace: Double?,
                      dopplerPace: Double?,
                      currentPace: Double?,
                      cadence: Double?,
                      elapsed: Double) {
        switch outcome {
        case .accepted, .anchored:
            accepted += 1
        case .rejected(let reason):
            rejected[reason, default: 0] += 1
        }
        self.windowPace = windowPace
        self.dopplerPace = dopplerPace
        self.cadence = cadence

        guard isCollecting else { return }

        let wasAccepted: Bool
        let reasonText: String
        switch outcome {
        case .accepted:
            wasAccepted = true
            reasonText = "ok"
        case .anchored:
            wasAccepted = true
            reasonText = "anchor"
        case .rejected(let reason):
            wasAccepted = false
            reasonText = reason.rawValue
        }
        records.append(DiagnosticsRecord(t: elapsed,
                                         latitude: sample.latitude,
                                         longitude: sample.longitude,
                                         horizontalAccuracy: sample.horizontalAccuracy,
                                         speed: sample.speed,
                                         speedAccuracy: sample.speedAccuracy,
                                         course: sample.course,
                                         accepted: wasAccepted,
                                         reason: reasonText,
                                         distance: distance,
                                         windowPace: windowPace,
                                         dopplerPace: dopplerPace,
                                         currentPace: currentPace,
                                         cadence: cadence))
        recordCount = records.count

        switch outcome {
        case .accepted:
            log(.fix, "fix \(oneDecimal(sample.horizontalAccuracy))m \(speedText(sample)) ok")
        case .anchored:
            log(.fix, "fix \(oneDecimal(sample.horizontalAccuracy))m anchor")
        case .rejected(let reason):
            // Paused samples would flood the log, so they only go into the export record.
            if reason != .paused {
                log(.reject, rejectText(reason, sample: sample))
            }
        }
    }

    // MARK: Log

    func log(_ kind: Kind, _ text: String) {
        guard isCollecting else { return }
        let entry = Entry(id: nextEntryID, t: clock, kind: kind, text: text)
        nextEntryID += 1
        entries.insert(entry, at: 0)
        if entries.count > Diagnostics.maxEntries {
            entries.removeLast(entries.count - Diagnostics.maxEntries)
        }
    }

    /// Logs a spoken cue with what triggered it, e.g. `cue "slow down" 21s under 7:58`.
    func logCue(_ spoken: String, reason: String?) {
        var text = "cue \"" + spoken.lowercased() + "\""
        if let reason = reason, !reason.isEmpty {
            text += " " + reason
        }
        log(.cue, text)
    }

    // MARK: Export

    /// Writes the current run's record to a temporary CSV file. Nil when there is no record.
    func exportCSV() -> URL? {
        guard !records.isEmpty else { return nil }
        let name = DiagnosticsCSV.fileName(for: runStart ?? Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try DiagnosticsCSV.document(records).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: Text helpers

    private func oneDecimal(_ value: Double) -> String {
        return String(format: "%.1f", value)
    }

    private func speedText(_ sample: PaceSample) -> String {
        guard sample.speed >= 0 else { return "--" }
        return String(format: "%.2f", sample.speed) + "m/s"
    }

    private func rejectText(_ reason: RejectReason, sample: PaceSample) -> String {
        switch reason {
        case .accuracy:
            if sample.horizontalAccuracy < 0 {
                return "rej h.acc invalid"
            }
            let limit = Int(PaceCalculator.maxAccuracy)
            return "rej h.acc \(Int(sample.horizontalAccuracy.rounded()))m > \(limit)m"
        case .paused:
            return "rej paused"
        case .beforeStart:
            return "rej before start"
        case .outOfOrder:
            return "rej out of order"
        case .jump:
            return "rej jump"
        }
    }
}
