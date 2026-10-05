import SwiftUI

/// Pick the voice and speed for spoken cues. Shown as a sheet from Set. Tapping a voice selects it and
/// plays a sample.
@MainActor
struct VoicePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(SettingsKey.voiceIdentifier) private var voiceIdentifier: String = ""
    @AppStorage(SettingsKey.voiceRate) private var voiceRate: Double = AppSettings.defaultVoiceRate

    @State private var options: [VoiceOption] = []

    private var speedOptions: [Choice<Double>] {
        return [Choice(0.44, "slower"), Choice(0.5, "normal"), Choice(0.56, "faster")]
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusLine(left: "milepace", center: "voice", right: "")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    voiceList
                    speedSection
                    moreVoicesNote
                }
                .padding(.horizontal, Theme.s3)
                .padding(.bottom, Theme.s4)
            }
            BracketButton(title: "done") {
                Coach.shared.stopSpeaking()
                dismiss()
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2)
        }
        .instrumentScreen()
        .onAppear {
            reload()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                reload()
            }
        }
        .onChange(of: voiceRate) { _, _ in
            Coach.shared.preview(identifier: voiceIdentifier)
        }
    }

    private func reload() {
        options = Coach.availableVoices()
    }

    // MARK: Sections

    private var voiceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("voice")
            defaultRow
            ForEach(options) { option in
                optionRow(option)
            }
        }
    }

    /// The system default (en-US) voice. Also what a chosen voice falls back to once it is deleted.
    private var defaultRow: some View {
        return Button {
            choose("")
        } label: {
            ReadoutRow(key: "default (system)",
                       value: "",
                       selected: isDefaultSelected,
                       leaders: false)
        }
        .buttonStyle(InstrumentButtonStyle())
    }

    private var isDefaultSelected: Bool {
        return VoiceCatalog.resolve(identifier: voiceIdentifier, available: options) == nil
    }

    private func optionRow(_ option: VoiceOption) -> some View {
        let selected = option.id == voiceIdentifier
        return Button {
            choose(option.id)
        } label: {
            ReadoutRow(key: VoiceCatalog.label(option),
                       value: selected ? "on" : "",
                       selected: selected,
                       leaders: false)
        }
        .buttonStyle(InstrumentButtonStyle())
    }

    private func choose(_ identifier: String) {
        voiceIdentifier = identifier
        Coach.shared.preview(identifier: identifier)
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("speed")
            ChoiceRow(label: "speaking speed", options: speedOptions, selection: $voiceRate)
        }
    }

    private var moreVoicesNote: some View {
        Text("more voices: ios settings \u{2192} accessibility \u{2192} spoken content \u{2192} voices \u{2192} english. download an enhanced or premium voice, then come back.")
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.dim)
            .padding(.top, Theme.s2)
    }
}
