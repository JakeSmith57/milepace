import Foundation

/// What the cadence click does around a pause. Pure, so the decisions can be tested; `Metronome` applies
/// the result to the audio engine.
enum MetronomePauseLogic {
    struct State: Equatable {
        /// The click is audibly playing.
        var running: Bool
        /// The click is held back by a pause and comes back on resume.
        var suspended: Bool
        /// An interruption (call, alarm) stopped the click while it was on, and it is waiting to resume.
        var interruptedWhileRunning: Bool
    }

    /// A pause silences the click. A click that an interruption had already stopped is held back too, so
    /// the interruption ending cannot start it during the pause. Otherwise nothing changes.
    static func onPause(_ s: State) -> State {
        var next = s
        if s.running {
            next.running = false
            next.suspended = true
            next.interruptedWhileRunning = false
        } else if s.interruptedWhileRunning {
            next.suspended = true
            next.interruptedWhileRunning = false
        }
        return next
    }

    /// Resuming starts the click only when the pause held one back.
    static func onResume(_ s: State) -> (State, startAudio: Bool) {
        guard s.suspended else { return (s, false) }
        var next = s
        next.suspended = false
        next.running = true
        return (next, true)
    }

    /// An interruption ended. The click comes back only when it was on before the interruption, the system
    /// says to resume, and no pause is holding it back.
    static func onInterruptionEnded(_ s: State, shouldResume: Bool) -> (State, startAudio: Bool) {
        var next = s
        next.interruptedWhileRunning = false
        if s.suspended || s.running {
            return (next, false)
        }
        if s.interruptedWhileRunning && shouldResume {
            next.running = true
            return (next, true)
        }
        return (next, false)
    }
}
