import Foundation

/// Pure sample generation for the cadence metronome.
enum ClickTrack {
    static let bpmRange: ClosedRange<Int> = 140...200

    static let clickSeconds: Double = 0.025
    static let clickFrequency: Double = 1800
    /// Decay time constant of the click envelope in seconds.
    static let decaySeconds: Double = 0.005
    static let amplitude: Double = 0.8

    /// One beat of mono Float samples: a 25 ms click (1,800 Hz sine, exponential decay) then silence.
    /// The length is exactly one beat at the given tempo.
    static func beatSamples(bpm: Int, sampleRate: Double) -> [Float] {
        guard bpm > 0, sampleRate.isFinite, sampleRate > 0 else { return [] }
        let total = Int((sampleRate * 60 / Double(bpm)).rounded())
        let clickLength = min(total, Int((sampleRate * clickSeconds).rounded()))
        var samples = [Float](repeating: 0, count: total)
        for index in 0..<clickLength {
            let time = Double(index) / sampleRate
            let envelope = exp(-time / decaySeconds)
            let value = amplitude * envelope * sin(2 * Double.pi * clickFrequency * time)
            samples[index] = Float(value)
        }
        return samples
    }

    /// Suggested tempo for a measured cadence: 5% above it, rounded to an even number and clamped.
    static func suggestedBPM(averageCadence: Double) -> Int {
        guard averageCadence.isFinite, averageCadence > 0 else { return bpmRange.lowerBound }
        let target = averageCadence * 1.05
        let even = Int((target / 2).rounded()) * 2
        return min(max(even, bpmRange.lowerBound), bpmRange.upperBound)
    }
}
