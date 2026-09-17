import SwiftUI

struct UsageBreakdownView: View {
    let breakdown: UsageBreakdown
    var compact = true
    var includesProvider = false

    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        let tokens = theme.current.tokens
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(includesProvider ? "breakdown_claude_title".l : "breakdown_title".l)
                    .font(.system(size: compact ? 11 : 13, weight: .bold))
                    .foregroundStyle(tokens.textPrimary)
                Text("breakdown_share".l)
                    .font(.system(size: compact ? 9 : 11))
                    .foregroundStyle(tokens.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            compositionBar

            if compact {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(breakdown.rows) { row in
                        legend(row)
                    }
                }
            } else {
                ForEach(breakdown.rows) { row in
                    VStack(spacing: 5) {
                        legend(row)
                        GeometryReader { proxy in
                            Rectangle()
                                .fill(color(for: row.key))
                                .frame(width: proxy.size.width * row.percent / 100)
                        }
                        .frame(height: 4)
                        .background(tokens.bgRing)
                        .clipShape(Capsule())
                        .accessibilityHidden(true)
                    }
                }
                if let asOf = breakdown.asOf {
                    Text("breakdown_as_of".l + " " + asOf.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10))
                        .foregroundStyle(tokens.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("claude-weekly-breakdown")
        .help("breakdown_explanation".l)
    }

    private var compositionBar: some View {
        GeometryReader { proxy in
            // Rounded server percentages can sum to 99 or 101; keep every segment inside the bar.
            let denominator = max(100, breakdown.rows.reduce(0) { $0 + $1.percent })
            HStack(spacing: 0) {
                ForEach(breakdown.rows) { row in
                    Rectangle()
                        .fill(color(for: row.key))
                        .frame(width: proxy.size.width * row.percent / denominator)
                }
            }
        }
        .frame(height: compact ? 7 : 9)
        .background(theme.current.tokens.bgRing)
        .clipShape(RoundedRectangle(cornerRadius: theme.current == .hybrid ? 2 : 4))
        .accessibilityHidden(true)
    }

    private func legend(_ row: UsageBreakdown.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Circle()
                .fill(color(for: row.key))
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(title(for: row))
                .foregroundStyle(theme.current.tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            Text(row.percent.formatted(.number.precision(.fractionLength(0...1))) + "%")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(theme.current.tokens.textPrimary)
                .fixedSize()
        }
        .font(.system(size: compact ? 10 : 11))
        .accessibilityElement(children: .combine)
    }

    private func title(for row: UsageBreakdown.Row) -> String {
        switch row.key {
        case "claude_code": return compact ? "Code" : "Claude Code"
        case "chat": return "breakdown_chats".l
        case "cowork": return "Cowork"
        case "other": return "breakdown_other".l
        default: return row.displayName
        }
    }

    private func color(for key: String) -> Color {
        let tokens = theme.current.tokens
        switch key {
        case "claude_code": return tokens.accent
        case "chat": return Color(red: 0.16, green: 0.58, blue: 0.67)
        case "cowork": return Color(red: 0.48, green: 0.46, blue: 0.78)
        default: return tokens.textTertiary
        }
    }
}
