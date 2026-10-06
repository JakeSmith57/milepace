import Foundation

/// Titles and spoken labels of the mid-run voice and click switches. Pure, so they can be tested.
enum MidRunAudioLabels {
    /// "voice on" or "voice off": the state the voice is in now.
    static func voiceTitle(on: Bool) -> String {
        return on ? "voice on" : "voice off"
    }

    /// "click on" or "click off": whether the click is audible now (or held back by a pause).
    static func clickTitle(on: Bool) -> String {
        return on ? "click on" : "click off"
    }

    static func voiceAccessibility(on: Bool) -> String {
        return on ? "voice on, double tap to mute" : "voice off, double tap to unmute"
    }

    static func clickAccessibility(on: Bool) -> String {
        return on ? "click on, double tap to turn off" : "click off, double tap to turn on"
    }
}
