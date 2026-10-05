import Foundation

/// Pure parsing and validation for the text fields on the settings and add-miles screens.
enum InputParsing {
    /// Mile and goal times: 5:00 to 8:30.
    static let mileTimeRange: ClosedRange<Double> = AppSettings.validMileRange
    /// The pace an added run may work out to: 4:00 to 20:00 per mile.
    static let addedPaceRange: ClosedRange<Double> = 240...1200

    /// Note shown under a mile time field that was rejected.
    static let mileTimeNote = "use m:ss, 5:00 to 8:30"

    private static func isDigits(_ text: String) -> Bool {
        return !text.isEmpty && text.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    /// A time as typed. A bare 3 or 4 digit number is m:ss ("645" is 6:45, "1005" is 10:05) when its
    /// last two digits are under 60. Anything else goes through `parseTime`. No range check.
    static func mileTime(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isDigits(trimmed), trimmed.count >= 3, trimmed.count <= 4, let number = Int(trimmed) {
            let minutes = number / 100
            let seconds = number % 100
            if seconds < 60 {
                return Double(minutes * 60 + seconds)
            }
        }
        return parseTime(trimmed)
    }

    /// `mileTime` that must also be inside `mileTimeRange`; nil otherwise.
    static func validMileTime(_ text: String) -> Double? {
        guard let value = mileTime(text), mileTimeRange.contains(value) else { return nil }
        return value
    }

    /// The time of an added run. A bare number is minutes ("45" is 45:00, "32.5" is 32:30); "m:ss" and
    /// "h:mm:ss" are read as written. Nil when it is malformed or zero.
    static func addedDuration(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(":") {
            let allowed = CharacterSet(charactersIn: "0123456789.")
            guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }),
                  let minutes = Double(trimmed), minutes.isFinite, minutes > 0 else {
                return nil
            }
            return minutes * 60
        }
        guard let seconds = parseTime(trimmed), seconds > 0 else { return nil }
        return seconds
    }

    /// Whether `seconds` over `miles` is a believable pace for a run (4:00 to 20:00 per mile).
    static func isPlausiblePace(seconds: Double, miles: Double) -> Bool {
        guard seconds.isFinite, miles.isFinite, miles > 0 else { return false }
        return addedPaceRange.contains(seconds / miles)
    }

    /// Miles as typed ("3.1", "3,1"); nil unless between 0 and 200.
    static func addedMiles(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(cleaned), value.isFinite, value > 0, value < 200 else { return nil }
        return value
    }
}
