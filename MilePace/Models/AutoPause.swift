import Foundation

/// Decides when an outdoor run should pause by itself (the runner stopped at a light) and resume (the
/// runner is running again), from the GPS Doppler speed. Pure: the caller owns the run phase and says
/// whether it is currently auto-paused.
struct AutoPauseDetector: Equatable {
    /// Below this speed (m/s, about 33:30 per mile) the runner counts as stopped.
    static let stopSpeed = 0.8
    /// At or above this speed (m/s, about 16:45 per mile) the runner counts as moving.
    static let goSpeed = 1.6
    /// Stopped for this many seconds: pause.
    static let stopSeconds = 5.0
    /// This many valid moving samples in a row: resume.
    static let goSamples = 2
    /// A sample whose speed accuracy is negative (unknown) or above this (m/s) is ignored.
    static let maxSpeedAccuracy = 1.5

    enum Event: Equatable {
        case pause
        case resume
    }

    /// When the current stopped stretch began (first valid slow sample), while not paused.
    private var stopStart: Date?
    /// Consecutive valid moving samples while paused.
    private var goCount = 0

    /// Feeds one sample. `paused` is whether the run is currently auto-paused. Returns `.pause` once when
    /// a valid slow sample arrives `stopSeconds` or more after the first one of the stretch, `.resume`
    /// after `goSamples` valid fast samples in a row while paused. Invalid samples change nothing,
    /// except that they break a run of moving samples.
    mutating func update(speed: Double, speedAccuracy: Double, at time: Date, paused: Bool) -> Event? {
        guard speed.isFinite, speed >= 0,
              speedAccuracy.isFinite, speedAccuracy >= 0,
              speedAccuracy <= AutoPauseDetector.maxSpeedAccuracy else {
            goCount = 0
            return nil
        }
        if paused {
            stopStart = nil
            if speed >= AutoPauseDetector.goSpeed {
                goCount += 1
                if goCount >= AutoPauseDetector.goSamples {
                    goCount = 0
                    return .resume
                }
            } else {
                goCount = 0
            }
            return nil
        }
        goCount = 0
        if speed >= AutoPauseDetector.stopSpeed {
            stopStart = nil
            return nil
        }
        guard let began = stopStart else {
            stopStart = time
            return nil
        }
        if time.timeIntervalSince(began) >= AutoPauseDetector.stopSeconds {
            stopStart = nil
            return .pause
        }
        return nil
    }

    mutating func reset() {
        stopStart = nil
        goCount = 0
    }
}
