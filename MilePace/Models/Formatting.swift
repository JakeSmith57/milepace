import Foundation

/// Meters in one statute mile.
let metersPerMile: Double = 1609.344

/// "7:05" for a pace in seconds per mile. Returns "--:--" for nil, non-finite,
/// non-positive or slower-than-30-minute values.
func formatPace(secondsPerMile: Double?) -> String {
    guard let value = secondsPerMile, value.isFinite, value > 0, value <= 1800 else {
        return "--:--"
    }
    let total = Int(value.rounded())
    return String(format: "%d:%02d", total / 60, total % 60)
}

/// "M:SS" under an hour, "H:MM:SS" otherwise. Fractions are truncated (clock style).
func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let total = Int(max(0, seconds).rounded(.down))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}

/// "82.4" under 60 seconds, otherwise "1:22.4". Rounded to tenths.
func formatSplit(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0.0" }
    let tenths = (max(0, seconds) * 10).rounded() / 10
    if tenths < 60 {
        return String(format: "%.1f", tenths)
    }
    let minutes = Int(tenths / 60)
    let remainder = tenths - Double(minutes) * 60
    return String(format: "%d:%04.1f", minutes, remainder)
}

/// "3.12" for a distance in meters, expressed in miles.
func formatMiles(_ meters: Double) -> String {
    guard meters.isFinite else { return "0.00" }
    return String(format: "%.2f", max(0, meters) / metersPerMile)
}

/// Signed delta with one decimal: "+1.2", "-0.8", "0.0".
func formatDelta(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0.0" }
    let rounded = (seconds * 10).rounded() / 10
    if rounded == 0 { return "0.0" }
    return String(format: "%+.1f", rounded)
}

/// Parses "m:ss", "ss", "m:ss.s" (and "h:mm:ss"). Returns nil for anything malformed.
func parseTime(_ text: String) -> Double? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let allowed = CharacterSet(charactersIn: "0123456789.:")
    guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }

    let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { String($0) }
    guard parts.count >= 1, parts.count <= 3 else { return nil }

    var total = 0.0
    for (index, part) in parts.enumerated() {
        guard !part.isEmpty else { return nil }
        let isLast = index == parts.count - 1
        if isLast {
            guard let value = Double(part), value.isFinite, value >= 0 else { return nil }
            if parts.count > 1 && value >= 60 { return nil }
            total = total * 60 + value
        } else {
            guard !part.contains("."), let whole = Int(part), whole >= 0 else { return nil }
            if index > 0 && whole >= 60 { return nil }
            total = total * 60 + Double(whole)
        }
    }
    return total
}

/// "9 minutes 41" for speech.
func spokenMinutesSeconds(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0 seconds" }
    let total = Int(seconds.rounded())
    let minutes = total / 60
    let secs = total % 60
    if minutes == 0 {
        return secs == 1 ? "1 second" : "\(secs) seconds"
    }
    var text = minutes == 1 ? "1 minute" : "\(minutes) minutes"
    if secs > 0 {
        text += secs < 10 ? " oh \(secs)" : " \(secs)"
    }
    return text
}

/// "9 41" for speech (compact pace form).
func spokenCompact(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0" }
    let total = Int(seconds.rounded())
    let minutes = total / 60
    let secs = total % 60
    if secs == 0 { return "\(minutes)" }
    return secs < 10 ? "\(minutes) oh \(secs)" : "\(minutes) \(secs)"
}
