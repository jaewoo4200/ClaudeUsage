import SwiftUI

struct TodayTokensButton<Label: View>: View {
    @ViewBuilder let label: () -> Label
    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails.toggle() } label: { label() }
            .buttonStyle(.plain)
            .help("today_tokens_details".l)
            .accessibilityIdentifier("today-token-details-button")
            .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
                TodayTokensView()
            }
    }
}

struct TodayTokensView: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        let summary = vm.todayTokenSummary(localCollectionEnabled: settings.usageHistoryEnabled)
        let tokens = theme.current.tokens
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("widget_today_tokens".l).font(.system(size: 14, weight: .bold))
                Spacer(minLength: 8)
                Text(summary.total.map { $0.formatted(.number) } ?? summary.displayTotal)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
            Divider()
            providerRow("Claude", source: "today_tokens_claude_source".l, state: summary.claude)
            providerRow("Codex", source: "today_tokens_codex_source".l, state: summary.codex)

            if summary.codex == .pending {
                Text("today_tokens_codex_pending".l)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if summary.codex.count == nil, let bucket = summary.latestCodexBucket {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("today_tokens_last_report".l + " · " + bucket.startDate)
                        .font(.system(size: 10))
                        .foregroundStyle(tokens.textTertiary)
                    Text(bucket.tokens.formatted(.number) + " " + "today_tokens_unit".l)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .foregroundStyle(tokens.textPrimary)
        .padding(16)
        .frame(width: 310)
        .background(tokens.bg)
    }

    private func providerRow(_ title: String, source: String, state: TodayTokenState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fontWeight(.semibold)
                Spacer(minLength: 8)
                Text(state.displayValue)
                    .monospacedDigit()
                    .fixedSize()
            }
            .font(.system(size: 12))
            Text(source)
                .font(.system(size: 10))
                .foregroundStyle(theme.current.tokens.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

extension TodayTokenSummary {
    @MainActor
    var displayTotal: String {
        if let total { return TokenCountFormatter.compact(total) }
        if let reportedTotal, reportedTotal > 0 {
            return String(format: "today_tokens_partial".l, TokenCountFormatter.compact(reportedTotal))
        }
        if claude == .pending || codex == .pending { return "today_tokens_pending".l }
        if let reportedTotal {
            return String(format: "today_tokens_partial".l, TokenCountFormatter.compact(reportedTotal))
        }
        return "today_tokens_unavailable".l
    }
}

extension TodayTokenState {
    @MainActor
    var displayValue: String {
        switch self {
        case .available(let value): return value.formatted(.number)
        case .pending: return "today_tokens_pending".l
        case .disabled: return "today_tokens_disabled".l
        case .unavailable: return "today_tokens_unavailable".l
        }
    }
}
