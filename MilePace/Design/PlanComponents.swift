import SwiftUI

// MARK: - Plan bar

/// Slim plan-purple band with onSignal text and one bracketed action: "today: 6 × 400 @ R  [ start ]".
struct PlanBar: View {
    let text: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: Theme.s3) {
            Text(text)
                .font(Theme.mono(.micro))
                .foregroundStyle(Theme.onSignal)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Button(action: action) {
                Text("[ \(actionTitle) ]")
                    .font(Theme.mono(.micro))
                    .foregroundStyle(Theme.onSignal)
                    .lineLimit(1)
                    .padding(.vertical, Theme.s2)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(InstrumentButtonStyle())
        }
        .padding(.horizontal, Theme.s3)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Theme.plan)
    }
}

// MARK: - Plan tag

/// Small plan-purple label such as "tue oct 20".
struct PlanTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.mono(.micro))
            .foregroundStyle(Theme.onSignal)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.plan)
    }
}

// MARK: - Text button

/// "[ title ]" as plain micro text with no fill or border, for small secondary actions.
struct TextBracketButton: View {
    let title: String
    var color: Color = Theme.fg
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("[ \(title) ]")
                .font(Theme.mono(.micro))
                .foregroundStyle(color)
                .lineLimit(1)
                .padding(.vertical, Theme.s2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(InstrumentButtonStyle())
    }
}
