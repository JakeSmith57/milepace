import Foundation

/// Text helpers for the instrument-style readouts. Pure Foundation so they can be unit tested.
enum ReadoutFormat {
    /// Key followed by a space and dot leaders, padded to `width` characters in total:
    /// `leader("avg", width: 12)` is `"avg ........"`. A key too long to fit is cut with an ellipsis.
    static func leader(_ key: String, width: Int = 12) -> String {
        let room = max(2, width) - 1
        if key.count > room {
            return String(key.prefix(room - 1)) + "\u{2026}" + " "
        }
        let dots = room - key.count
        return key + " " + String(repeating: ".", count: dots)
    }

    /// Signed delta with one decimal and a real minus sign: "+1.6", "\u{2212}0.6", "0.0".
    static func signedDelta(_ seconds: Double) -> String {
        return formatDelta(seconds).replacingOccurrences(of: "-", with: "\u{2212}")
    }

    /// "+1.6 slow", "\u{2212}0.6 fast" or "on pace", using the same 1.0 s band as `SplitVerdict`.
    static func deltaWords(_ seconds: Double) -> String {
        switch SplitVerdict.verdict(delta: seconds) {
        case .onPace: return "on pace"
        case .slow: return signedDelta(seconds) + " slow"
        case .fast: return signedDelta(seconds) + " fast"
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()

    /// "sat oct 17".
    static func day(_ date: Date) -> String {
        return dayFormatter.string(from: date).lowercased()
    }

    /// "7:58\u{2013}8:03" for a seconds-per-mile range.
    static func paceRange(_ range: ClosedRange<Double>) -> String {
        return formatPace(secondsPerMile: range.lowerBound) + "\u{2013}" + formatPace(secondsPerMile: range.upperBound)
    }

    /// Log timestamp "03:11.8" from run seconds; "--:--.-" when no run is going (negative).
    static func stamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--.-" }
        let tenths = Int((seconds * 10).rounded(.down))
        let minutes = tenths / 600
        let rest = tenths % 600
        return String(format: "%02d:%02d.%d", minutes, rest / 10, rest % 10)
    }
}

/// Which of the pace meter's cells holds the current pace.
enum PaceMeterModel {
    static let defaultCells = 8

    /// The two cells that stand for the target zone (3 and 4 of 8).
    static func zoneCells(cells: Int = PaceMeterModel.defaultCells) -> ClosedRange<Int> {
        let count = max(2, cells)
        return (count / 2 - 1)...(count / 2)
    }

    /// Zero-based cell for `pace` (seconds per mile). Lower seconds is faster, so faster paces map to
    /// the left. Each of the two zone cells covers half of the zone width, and each outside cell
    /// covers the same width again. Paces beyond the ends clamp to the first or last cell.
    static func cell(pace: Double, zone: ClosedRange<Double>, cells: Int = PaceMeterModel.defaultCells) -> Int {
        let count = max(2, cells)
        let band = zoneCells(cells: count)
        guard pace.isFinite else { return band.lowerBound }

        let width = zone.upperBound - zone.lowerBound
        let cellWidth = max(width / 2, 0.5)

        if pace < zone.lowerBound {
            let ratio = min((zone.lowerBound - pace) / cellWidth, Double(count))
            let steps = Int(ratio.rounded(.up))
            return max(0, band.lowerBound - steps)
        }
        if pace > zone.upperBound {
            let ratio = min((pace - zone.upperBound) / cellWidth, Double(count))
            let steps = Int(ratio.rounded(.up))
            return min(count - 1, band.upperBound + steps)
        }
        let middle = zone.lowerBound + width / 2
        return pace < middle ? band.lowerBound : band.upperBound
    }
}

/// GPS quality as shown in the status line.
enum GPSState: Equatable {
    case off
    case searching
    /// A fix exists but is not good enough yet. Accuracy in meters.
    case weak(Double)
    /// Accurate and fresh. Accuracy in meters.
    case ready(Double)

    static let readyAccuracy: Double = 10
    static let readyAge: Double = 3
    /// A fix older than this counts as no fix at all.
    static let staleAge: Double = 10

    /// `accuracy` is the horizontal accuracy of the latest fix and `age` how old it is in seconds.
    /// Both nil (or a negative accuracy, or a stale fix) means still searching.
    static func evaluate(accuracy: Double?, age: Double?) -> GPSState {
        guard let accuracy = accuracy, let age = age, accuracy >= 0, age <= staleAge else {
            return .searching
        }
        if accuracy <= readyAccuracy && age <= readyAge {
            return .ready(accuracy)
        }
        return .weak(accuracy)
    }

    var isReady: Bool {
        switch self {
        case .ready: return true
        case .off, .searching, .weak: return false
        }
    }

    var isSearching: Bool {
        switch self {
        case .searching: return true
        case .off, .weak, .ready: return false
        }
    }

    /// Short name of the case, for logs.
    var name: String {
        switch self {
        case .off: return "off"
        case .searching: return "searching"
        case .weak: return "weak"
        case .ready: return "ready"
        }
    }

    /// "gps off", "gps searching", "gps 27m weak", "gps 4m".
    var label: String {
        switch self {
        case .off: return "gps off"
        case .searching: return "gps searching"
        case .weak(let accuracy): return "gps \(Int(accuracy.rounded()))m weak"
        case .ready(let accuracy): return "gps \(Int(accuracy.rounded()))m"
        }
    }
}

/// One raw GPS sample with what the calculator made of it, for the run log export.
struct DiagnosticsRecord: Equatable {
    var t: Double
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var speed: Double
    var speedAccuracy: Double
    var course: Double
    var accepted: Bool
    var reason: String
    var distance: Double
    var windowPace: Double?
    var dopplerPace: Double?
    var currentPace: Double?
    var cadence: Double?
}

/// CSV formatting for the run log export.
enum DiagnosticsCSV {
    static let header = "t,lat,lon,hAcc,speed,speedAcc,course,accepted,reason,distance,windowPace,dopplerPace,currentPace,cadence"

    private static func optional(_ value: Double?, _ format: String) -> String {
        guard let value = value, value.isFinite else { return "" }
        return String(format: format, value)
    }

    static func row(_ record: DiagnosticsRecord) -> String {
        let fields: [String] = [
            String(format: "%.1f", record.t),
            String(format: "%.6f", record.latitude),
            String(format: "%.6f", record.longitude),
            String(format: "%.1f", record.horizontalAccuracy),
            String(format: "%.2f", record.speed),
            String(format: "%.2f", record.speedAccuracy),
            String(format: "%.0f", record.course),
            record.accepted ? "1" : "0",
            record.reason,
            String(format: "%.1f", record.distance),
            optional(record.windowPace, "%.1f"),
            optional(record.dopplerPace, "%.1f"),
            optional(record.currentPace, "%.1f"),
            optional(record.cadence, "%.0f")
        ]
        return fields.joined(separator: ",")
    }

    static func document(_ records: [DiagnosticsRecord]) -> String {
        var lines: [String] = [header]
        for record in records {
            lines.append(row(record))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "milepace-run-YYYYMMDD-HHmm.csv".
    static func fileName(for date: Date, timeZone: TimeZone = TimeZone.current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "milepace-run-" + formatter.string(from: date) + ".csv"
    }
}
