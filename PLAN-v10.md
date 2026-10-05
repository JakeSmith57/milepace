# MilePace v1.8: metronome follows pause, voice picker

Builds on v1.7 (`main`, compiles and passes CI). Same constraints: Swift 5 mode, iOS 17, Xcode 16 CI,
no local compiler, Instrument design system. `MARKETING_VERSION: "1.8"`. **Do not regress v1.7.**

## 1. Bug: the metronome keeps clicking while a run is paused (HIGH)
Today `RunView.pauseButton` calls `tracker.pause()` and never touches `Metronome.shared`.

- `Metronome` gains a suspend state:
  - `private(set) var isSuspended = false` (observable).
  - `func suspend()`: if `isRunning`: halt the engine, `isRunning = false`, release the session via
    `AudioSessionCoordinator.shared.endMetronome()`, set `isSuspended = true`, log "metronome paused".
    If not running (e.g. an interruption already stopped it and `wasRunningBeforeInterruption` is true),
    move that intent into `isSuspended = true` and clear `wasRunningBeforeInterruption`, so the
    interruption ending cannot restart the click during a pause. Otherwise no-op.
  - `func resumeFromSuspend()`: if `isSuspended`: `isSuspended = false`, then `start()`.
  - `stop()` also clears `isSuspended`.
  - `handleInterruption(.ended)` must never start the click while `isSuspended` (guard it).
  - `handleRouteChange` (output lost) clears `isSuspended` too (it already calls stop()).
- Drive it from the run's state, not the button, so every pause path is covered: in `RunView`'s
  existing `.onChange(of: tracker.phase)` add: `.paused` → `metronome.suspend()`; `.running` (coming
  from paused) → `metronome.resumeFromSuspend()`; `.idle` → nothing extra (endRun already stops).
  `resumeFromSuspend` is a no-op when nothing was suspended, so calling it on start is harmless, but
  keep `startRun`'s explicit start logic as is.
- Cadence row tap (`toggleMetronome`) while paused: if `metronome.isSuspended`, the tap turns it off
  (clear suspend: call `metronome.stop()`); if paused and not suspended, the tap does nothing audible
  but marks it to come back on resume — implement as: set BPM/volume, then `metronome.suspendedStart()`
  which just sets `isSuspended = true` (add this tiny method). Never start audio while paused.
- Cadence readout: "♩<bpm>" only when `isRunning`; when `isSuspended` append `" \u{2669}paused"`.
- Track tab has no metronome; nothing to change there (confirm by grep and say so).
- Tests (pure): extract the decision into a pure helper in `Models/MetronomePauseLogic.swift`:
  ```swift
  enum MetronomePauseLogic {
      struct State: Equatable { var running: Bool; var suspended: Bool; var interruptedWhileRunning: Bool }
      static func onPause(_ s: State) -> State
      static func onResume(_ s: State) -> (State, startAudio: Bool)
      static func onInterruptionEnded(_ s: State, shouldResume: Bool) -> (State, startAudio: Bool)
  }
  ```
  and have `Metronome` use it. Tests: running → pause → suspended, not running; resume → starts audio;
  not running → pause → resume → no audio; interrupted while running, then paused, interruption ends
  → no audio, then resume → audio; suspended + interruption ended → no audio.

## 2. Voice picker in Settings
Today `Coach.speak` hardcodes `AVSpeechSynthesisVoice(language: "en-US")`.

- Setting `@AppStorage("voiceIdentifier")` String, default "" (= system default en-US). Add to
  `SettingsKey`/`AppSettings` (`AppSettings.voiceIdentifier`). Also `@AppStorage("voiceRate")` Double,
  default 0.5 (= `AVSpeechUtteranceDefaultSpeechRate`), range 0.40…0.60, shown as "slower / normal /
  faster" ChoiceRow with values 0.44 / 0.5 / 0.56.
- Pure helper `Models/VoiceCatalog.swift` (pure, no AVFoundation types in its API):
  ```swift
  struct VoiceOption: Equatable, Identifiable { let id: String /*identifier*/; let name: String
      let language: String; let quality: Int /*1 default, 2 enhanced, 3 premium*/ }
  enum VoiceCatalog {
      /// English voices only (language hasPrefix "en"), novelty voices removed, sorted by
      /// quality desc, then en-US first, then name. Deduplicates by identifier.
      static func options(from all: [VoiceOption]) -> [VoiceOption]
      static func label(_ v: VoiceOption) -> String   // "ava  premium  us", lowercase; quality word only for 2/3
      static func resolve(identifier: String, available: [VoiceOption]) -> VoiceOption?  // nil → default
  }
  ```
  Novelty filter: drop identifiers containing "speech.synthesis.voice." (Apple's Eloquence/novelty
  set like Bells, Bubbles, Boing, Jester, Whisper, Zarvox, Trinoids, Organ, Cellos, Bahh, Albert,
  Bad News, Good News, Superstar, Wobble). Keep personal voices out (filter `voiceTraits` containing
  `.isPersonalVoice` in the service layer).
  Language region short code: "en-US" → "us", "en-GB" → "uk", "en-AU" → "au", "en-IE" → "ie",
  "en-ZA" → "za", "en-IN" → "in", else the lowercased region.
- `Coach`: `static func availableVoices() -> [VoiceOption]` maps `AVSpeechSynthesisVoice.speechVoices()`
  (quality `.default`=1, `.enhanced`=2, `.premium`=3). `speak` uses
  `AVSpeechSynthesisVoice(identifier:)` when the stored identifier resolves, else en-US; rate from
  setting. Add `func preview(identifier: String)` which stops current speech and says
  "Mile 1. Split 7 minutes 2. Speed up." with that voice (goes through the same speak path so
  the audio session ducking still applies; reason "preview").
- Settings → "voice and feedback": at the top, a ReadoutRow "voice" showing the current label
  (or "default") that pushes a `VoicePickerView` (NavigationLink styled with InstrumentButtonStyle;
  if SettingsView isn't in a NavigationStack, use a `.sheet` instead — check and say which).
  `VoicePickerView`: Instrument list, first row "default (system)", then each option as a selectable
  ReadoutRow (selected style like the run-mode rows); tapping selects and previews. Below, the
  "speed" ChoiceRow. Micro note: "more voices: ios settings → accessibility → spoken content →
  voices → english. download an enhanced or premium voice, then come back." Reload the list on
  `scenePhase == .active` so freshly downloaded voices appear.
- Test week note already says voices are real settings; no change.
- Tests `VoiceCatalogTests`: filters non-English and novelty; ordering (premium before default,
  en-US before en-GB at equal quality); label text; resolve unknown id → nil; dedupe.

## Done criteria
Self-review every edited file (MainActor, exact AVFoundation signatures: `AVSpeechSynthesisVoice
.speechVoices()`, `.identifier`, `.name`, `.language`, `.quality`, `.voiceTraits`,
`AVSpeechSynthesisVoice(identifier:)`, `AVSpeechUtterance.rate`). Add the new files to nothing by
hand (XcodeGen globs folders; confirm). Append one short "v1.8" section to HANDOFF.md (re-read from
disk, append only). README field notes. Bump MARKETING_VERSION to 1.8. Report files, tests,
deviations, least-confident spots. Don't commit.
