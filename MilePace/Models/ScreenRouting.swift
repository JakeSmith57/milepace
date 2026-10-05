import Foundation

/// Which screen the app shows when something asks for one. Pure, so it can be tested.
enum ScreenRouting {
    /// The screen to show after `requested` was asked for while `current` is showing. A recording is never
    /// left: while a run is in progress the answer is always the run screen, and while a track session is
    /// in progress it is always the track screen. Otherwise the request is granted.
    static func resolve(current: AppTab,
                        requested: AppTab,
                        runInProgress: Bool,
                        trackInProgress: Bool) -> AppTab {
        if runInProgress {
            return .run
        }
        if trackInProgress {
            return .track
        }
        return requested
    }
}
