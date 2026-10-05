import Foundation

/// One speech voice, without any AVFoundation types so the list logic can be tested.
struct VoiceOption: Equatable, Identifiable {
    /// The voice identifier.
    let id: String
    let name: String
    /// BCP 47 language, such as "en-US".
    let language: String
    /// 1 default, 2 enhanced, 3 premium.
    let quality: Int
}

enum VoiceCatalog {
    /// Parts of an identifier that mark Apple's novelty and Eloquence voices (Bells, Zarvox, Flo, ...).
    private static let noveltyMarkers = ["speech.synthesis.voice.", "eloquence"]

    private static func isNovelty(_ option: VoiceOption) -> Bool {
        let id = option.id.lowercased()
        return noveltyMarkers.contains { id.contains($0) }
    }

    /// English voices only (language starts with "en"), novelty voices removed, sorted by quality
    /// (best first), then en-US first, then name. One entry per identifier.
    static func options(from all: [VoiceOption]) -> [VoiceOption] {
        var seen = Set<String>()
        var kept: [VoiceOption] = []
        for option in all {
            guard option.language.hasPrefix("en"), !isNovelty(option) else { continue }
            if seen.insert(option.id).inserted {
                kept.append(option)
            }
        }
        return kept.sorted { lhs, rhs in
            if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
            let lhsUS = lhs.language == "en-US"
            let rhsUS = rhs.language == "en-US"
            if lhsUS != rhsUS { return lhsUS }
            let lhsName = lhs.name.lowercased()
            let rhsName = rhs.name.lowercased()
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.id < rhs.id
        }
    }

    /// "ava  premium  us": lowercase name, the quality word for enhanced and premium voices only, then
    /// the region.
    static func label(_ v: VoiceOption) -> String {
        var parts: [String] = [v.name.lowercased()]
        switch v.quality {
        case 2: parts.append("enhanced")
        case 3: parts.append("premium")
        default: break
        }
        let region = regionCode(v.language)
        if !region.isEmpty {
            parts.append(region)
        }
        return parts.joined(separator: "  ")
    }

    /// The voice the stored identifier names, or nil (use the default voice) when it is empty or not available.
    static func resolve(identifier: String, available: [VoiceOption]) -> VoiceOption? {
        guard !identifier.isEmpty else { return nil }
        return available.first { $0.id == identifier }
    }

    /// "en-US" gives "us", "en-GB" gives "uk"; other regions are lowercased as they are.
    static func regionCode(_ language: String) -> String {
        let pieces = language.split(whereSeparator: { $0 == "-" || $0 == "_" })
        guard pieces.count >= 2, let last = pieces.last else { return "" }
        let region = String(last).lowercased()
        switch region {
        case "gb": return "uk"
        default: return region
        }
    }
}
