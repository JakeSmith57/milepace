import Foundation

/// The training zones a target can be derived from.
enum PaceZoneKind: String, CaseIterable, Equatable {
    case easy
    case threshold
    case interval
    case repetition
}

/// Jack Daniels style training paces derived from a current mile time.
/// Easy / threshold / interval ranges are seconds per mile; `rep400` is seconds per 400 m.
struct PaceZones: Equatable {
    var easy: ClosedRange<Double>
    var threshold: ClosedRange<Double>
    var interval: ClosedRange<Double>
    var rep400: ClosedRange<Double>

    static let goalMileSeconds: Double = 330
    static let goalPer400: Double = 82.5
    static let minMileSeconds: Double = 330
    static let maxMileSeconds: Double = 450
    /// The mile time used when the input is not a number.
    static let fallbackMileSeconds: Double = 412

    /// Narrowest half-width a pace target may have, in seconds per mile (`AppSettings.paceWindow`
    /// chooses the value actually used).
    static let defaultWindow: Double = 8
    static let windowRange: ClosedRange<Double> = 3...15

    private struct Row {
        let mile: Double
        let easyLo: Double
        let easyHi: Double
        let thresholdLo: Double
        let thresholdHi: Double
        let intervalLo: Double
        let intervalHi: Double
        let repLo: Double
        let repHi: Double
    }

    /// Anchor rows, slowest first.
    private static let rows: [Row] = [
        Row(mile: 450, easyLo: 610, easyHi: 675, thresholdLo: 512, thresholdHi: 518,
            intervalLo: 470, intervalHi: 476, repLo: 110, repHi: 112),
        Row(mile: 412, easyLo: 575, easyHi: 630, thresholdLo: 478, thresholdHi: 483,
            intervalLo: 438, intervalHi: 443, repLo: 102, repHi: 104),
        Row(mile: 395, easyLo: 540, easyHi: 595, thresholdLo: 455, thresholdHi: 460,
            intervalLo: 418, intervalHi: 423, repLo: 97, repHi: 99),
        Row(mile: 365, easyLo: 510, easyHi: 565, thresholdLo: 423, thresholdHi: 428,
            intervalLo: 389, intervalHi: 394, repLo: 90, repHi: 92),
        Row(mile: 345, easyLo: 485, easyHi: 535, thresholdLo: 402, thresholdHi: 407,
            intervalLo: 370, intervalHi: 375, repLo: 85, repHi: 87),
        Row(mile: 330, easyLo: 465, easyHi: 515, thresholdLo: 388, thresholdHi: 393,
            intervalLo: 357, intervalHi: 362, repLo: 82, repHi: 83)
    ]

    private static func lerp(_ low: Double, _ high: Double, _ t: Double) -> Double {
        return low + t * (high - low)
    }

    private static func zones(from row: Row) -> PaceZones {
        return PaceZones(
            easy: row.easyLo...row.easyHi,
            threshold: row.thresholdLo...row.thresholdHi,
            interval: row.intervalLo...row.intervalHi,
            rep400: row.repLo...row.repHi
        )
    }

    /// Zones for a mile time in seconds. Input is clamped to 330...450 (7:30, the slowest anchor row);
    /// anything that is not a number is treated as 412.
    static func forMile(_ seconds: Double) -> PaceZones {
        let raw = seconds.isFinite ? seconds : fallbackMileSeconds
        let mile = min(max(raw, minMileSeconds), maxMileSeconds)

        if mile >= rows[0].mile {
            return zones(from: rows[0])
        }
        for index in 0..<(rows.count - 1) {
            let slow = rows[index]
            let fast = rows[index + 1]
            if mile >= fast.mile {
                let t = (mile - fast.mile) / (slow.mile - fast.mile)
                return PaceZones(
                    easy: lerp(fast.easyLo, slow.easyLo, t)...lerp(fast.easyHi, slow.easyHi, t),
                    threshold: lerp(fast.thresholdLo, slow.thresholdLo, t)...lerp(fast.thresholdHi, slow.thresholdHi, t),
                    interval: lerp(fast.intervalLo, slow.intervalLo, t)...lerp(fast.intervalHi, slow.intervalHi, t),
                    rep400: lerp(fast.repLo, slow.repLo, t)...lerp(fast.repHi, slow.repHi, t)
                )
            }
        }
        return zones(from: rows[rows.count - 1])
    }

    /// `range` made at least `window` seconds either side of its middle: a range whose half-width is
    /// under `window` becomes `mid - window ... mid + window`, a wider one is returned as it is. Cues, the
    /// pace meter and the on-target checks use this, so a 5-second-wide threshold range does not nag.
    static func guardRange(_ range: ClosedRange<Double>, window: Double) -> ClosedRange<Double> {
        let width = max(0, window)
        let half = (range.upperBound - range.lowerBound) / 2
        guard half < width else { return range }
        let mid = (range.lowerBound + range.upperBound) / 2
        return (mid - width)...(mid + width)
    }

    /// `guardRange` with the window from the settings.
    static func guardRange(_ range: ClosedRange<Double>) -> ClosedRange<Double> {
        return guardRange(range, window: AppSettings.paceWindow)
    }

    /// The range for a zone. For `.repetition` the range is per 400 m, otherwise per mile.
    func range(for kind: PaceZoneKind) -> ClosedRange<Double> {
        switch kind {
        case .easy: return easy
        case .threshold: return threshold
        case .interval: return interval
        case .repetition: return rep400
        }
    }

    /// Midpoint of the zone scaled to the given distance. Repetition scales from per-400,
    /// everything else from per-mile.
    func targetSeconds(distanceMeters: Double, zone: PaceZoneKind) -> Double {
        let range = self.range(for: zone)
        let midpoint = (range.lowerBound + range.upperBound) / 2
        switch zone {
        case .repetition:
            return midpoint * distanceMeters / 400.0
        case .easy, .threshold, .interval:
            return midpoint * distanceMeters / metersPerMile
        }
    }
}
