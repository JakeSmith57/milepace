import SwiftUI

/// Live GPS, pace and audio readouts with the event log and a CSV export of the run.
@MainActor
struct DiagnosticsPanel: View {
    let onClose: () -> Void

    private let diagnostics = Diagnostics.shared

    @State private var exportURL: URL?
    @State private var exportedCount: Int = -1
    @State private var exportedAt: Date = Date.distantPast

    /// The export file is rewritten at most this often while the panel is open.
    private static let exportRefreshSeconds: Double = 10

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.signal)
                .frame(height: Theme.rule)
            VStack(alignment: .leading, spacing: Theme.s2) {
                header
                grid
                logList
                exportButton
            }
            .padding(.horizontal, Theme.s3)
            .padding(.vertical, Theme.s2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .onAppear {
            refreshExport(force: true)
        }
        .onChange(of: diagnostics.recordCount) { _, _ in
            refreshExport(force: false)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("diagnostics")
                .font(Theme.mono(.body))
                .foregroundStyle(Theme.fg)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text("[ x ]")
                    .font(Theme.mono(.body))
                    .foregroundStyle(Theme.fg)
                    .frame(minWidth: 56, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(InstrumentButtonStyle())
        }
    }

    // MARK: Values

    private func fixed(_ value: Double?, _ format: String, _ unit: String) -> String {
        guard let value = value, value.isFinite else { return "--" }
        return String(format: format, value) + unit
    }

    private var cadenceText: String {
        guard let spm = diagnostics.cadence, spm.isFinite, spm > 0 else { return "--" }
        return "\(Int(spm.rounded()))"
    }

    private func cell(_ key: String, _ value: String) -> some View {
        ReadoutRow(key: key, value: value, size: .micro, keyWidth: 9)
    }

    private var grid: some View {
        HStack(alignment: .top, spacing: Theme.s3) {
            VStack(spacing: 0) {
                cell("h.acc", fixed(diagnostics.lastAccuracy, "%.1f", " m"))
                cell("rate", fixed(diagnostics.sampleRateHz, "%.1f", " hz"))
                cell("accepted", "\(diagnostics.accepted)")
                cell("doppler", formatPace(secondsPerMile: diagnostics.dopplerPace))
                cell("cadence", cadenceText)
            }
            VStack(spacing: 0) {
                cell("spd.acc", fixed(diagnostics.lastSpeedAccuracy, "%.1f", " m/s"))
                cell("age", fixed(diagnostics.lastFixAge, "%.1f", " s"))
                cell("rejected", "\(diagnostics.rejectedTotal)")
                cell("30s avg", formatPace(secondsPerMile: diagnostics.windowPace))
                cell("audio", diagnostics.audioState)
            }
        }
    }

    // MARK: Log

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                if diagnostics.entries.isEmpty {
                    Text(diagnostics.isCollecting ? "no events yet" : "log is off: enable diagnostics in set")
                        .font(Theme.mono(.micro))
                        .foregroundStyle(Theme.dim)
                }
                ForEach(diagnostics.entries) { entry in
                    logLine(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func logLine(_ entry: Diagnostics.Entry) -> some View {
        let parts = entry.text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let keyword = parts.first.map { String($0) } ?? ""
        let rest = parts.count > 1 ? String(parts[1]) : ""
        let loud = entry.kind == .cue || entry.kind == .reject
        return HStack(alignment: .firstTextBaseline, spacing: Theme.s2) {
            Text(ReadoutFormat.stamp(entry.t))
                .foregroundStyle(Theme.dim)
            Text(keyword)
                .foregroundStyle(loud ? Theme.fg : Theme.dim)
            Text(rest)
                .foregroundStyle(Theme.dim)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(Theme.mono(.micro))
    }

    // MARK: Export

    @ViewBuilder
    private var exportButton: some View {
        if let url = exportURL {
            ShareLink(item: url) {
                BracketLabel(title: "export run log", minHeight: 44, size: .micro)
            }
            .buttonStyle(InstrumentButtonStyle())
        } else {
            BracketLabel(title: "export run log", minHeight: 44, size: .micro)
                .opacity(0.35)
        }
    }

    private func refreshExport(force: Bool) {
        let count = diagnostics.recordCount
        guard count != exportedCount else { return }
        let now = Date()
        if !force && now.timeIntervalSince(exportedAt) < DiagnosticsPanel.exportRefreshSeconds {
            return
        }
        exportedCount = count
        exportedAt = now
        exportURL = diagnostics.exportCSV()
    }
}
