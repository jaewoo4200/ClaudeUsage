import SwiftUI

enum WidgetProvider: String, CaseIterable, Identifiable {
    case claude
    case openAI = "openai"

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .claude: return "claude_short".l
        case .openAI: return "openai_short".l
        }
    }
}

enum WidgetPanelKind: String, CaseIterable, Hashable {
    case combined
    case claude
    case openAI = "openai"

    var provider: WidgetProvider? {
        switch self {
        case .combined: return nil
        case .claude: return .claude
        case .openAI: return .openAI
        }
    }
}

struct WidgetView: View {
    let panelID: String
    let provider: WidgetProvider?

    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var language: LanguageStore
    @EnvironmentObject var settings: AppSettings

    init(
        panelID: String = WidgetPanelKind.combined.rawValue,
        provider: WidgetProvider? = nil
    ) {
        self.panelID = panelID
        self.provider = provider
    }

    var body: some View {
        layout
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: WidgetContentSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(WidgetContentSizeKey.self) { size in
                guard size.width > 0, size.height > 0 else { return }
                NotificationCenter.default.post(
                    name: .widgetContentSizeDidChange,
                    object: nil,
                    userInfo: ["size": size, "panelID": panelID]
                )
            }
    }

    @ViewBuilder
    private var layout: some View {
        if let provider {
            SingleProviderWidget(provider: provider)
        } else {
            switch settings.widgetLayoutMode {
            case .stacked, .separate:
                StackedWidget()
            case .horizontal:
                HorizontalWidget()
            case .paged:
                PagedWidget()
            }
        }
    }
}

extension Notification.Name {
    static let widgetContentSizeDidChange = Notification.Name("widgetContentSizeDidChange")
}

private struct WidgetContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Layouts

private struct StackedWidget: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let tokens = theme.current.tokens
        VStack(alignment: .leading, spacing: 8) {
            ProviderWidgetSection(provider: .claude)
            Divider().background(tokens.divider)
            ProviderWidgetSection(provider: .openAI)
            if settings.usagePetEnabled {
                Divider().background(tokens.divider)
                WidgetMimoCompanion()
            }
        }
        .padding(18)
        .frame(width: 240)
        .background(WidgetPanelSurface(theme: theme.current))
    }
}

private struct HorizontalWidget: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let tokens = theme.current.tokens
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                ProviderWidgetSection(provider: .claude)
                if settings.usagePetEnabled {
                    Divider().background(tokens.divider)
                    WidgetMimoCompanion(wide: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Divider().background(tokens.divider)

            VStack(alignment: .leading, spacing: 10) {
                ProviderWidgetSection(provider: .openAI)
                Divider().background(tokens.divider)
                HorizontalUsageBrief()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(width: 480)
        .background(WidgetPanelSurface(theme: theme.current))
    }
}

private struct HorizontalUsageBrief: View {
    private struct ResetCandidate {
        let provider: WidgetProvider
        let metric: UsageDisplayMetric
    }

    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var history: UsageHistoryStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        let snapshot = vm.historySnapshot(includingSpark: settings.showOpenAISparkLimits)
        let trend = settings.usageHistoryEnabled ? history.trend() : .empty

        VStack(alignment: .leading, spacing: 7) {
            insightRow(
                systemName: "gauge",
                title: "widget_headroom".l,
                color: tokens.color(forLevel: UsageLevel.from(snapshot.pressure ?? 0))
            ) {
                Text(headroomText(snapshot: snapshot))
            }

            insightRow(
                systemName: "clock.arrow.circlepath",
                title: "widget_next_reset".l,
                color: tokens.warn
            ) {
                nextResetValue
            }

            if let resetCredits = vm.openAIUsage?.rateLimitResetCredits {
                insightRow(
                    systemName: "ticket",
                    title: "widget_reset_credits".l,
                    color: tokens.accentSecondary
                ) {
                    Text(resetCreditText(resetCredits))
                }
            }

            insightRow(
                systemName: "chart.line.uptrend.xyaxis",
                title: "widget_recent_activity".l,
                color: tokens.ok
            ) {
                Text(recentActivityText(trend: trend))
            }

            insightRow(
                systemName: "sum",
                title: "widget_today_tokens".l,
                color: tokens.accentSecondary
            ) {
                Text(todayTokensText(snapshot: snapshot))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .top)
        .accessibilityElement(children: .combine)
    }

    private func insightRow<Value: View>(
        systemName: String,
        title: String,
        color: Color,
        @ViewBuilder value: () -> Value
    ) -> some View {
        let tokens = theme.current.tokens
        return HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14, height: 14)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(tokens.textTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            value()
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tokens.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(height: 18)
    }

    @ViewBuilder
    private var nextResetValue: some View {
        if let candidate = nextResetCandidate(), let reset = candidate.metric.resetsAt {
            HStack(spacing: 4) {
                Text(candidate.provider.displayName)
                    .foregroundStyle(theme.current.tokens.textTertiary)
                CountdownText(resetsAt: reset, isWeekly: candidate.metric.isWeekly)
            }
        } else {
            Text("–")
        }
    }

    private func headroomText(snapshot: UsageHistorySnapshot) -> String {
        guard let pressure = snapshot.pressure else { return "–" }
        return "\(Int(max(0, 100 - pressure).rounded()))%"
    }

    private func nextResetCandidate(now: Date = Date()) -> ResetCandidate? {
        let claude = vm.claudeDisplayMetrics.map { ResetCandidate(provider: .claude, metric: $0) }
        let codex = vm.openAIDisplayMetrics(includingSpark: settings.showOpenAISparkLimits)
            .map { ResetCandidate(provider: .openAI, metric: $0) }
        return (claude + codex)
            .filter { ($0.metric.resetsAt ?? .distantPast) > now }
            .min { ($0.metric.resetsAt ?? .distantFuture) < ($1.metric.resetsAt ?? .distantFuture) }
    }

    private func recentActivityText(trend: UsageTrend) -> String {
        guard settings.usageHistoryEnabled else { return "widget_history_off".l }
        if trend.resetDetected { return "widget_reset_detected".l }
        if let tokens = trend.recentTokenDelta, tokens > 0 {
            return String(format: "widget_recent_tokens_value".l, TokenCountFormatter.compact(tokens))
        }
        if let rate = trend.percentPerHour, rate > 0.05 {
            return String(format: "+%.1f%%p", rate)
        }
        if trend.points.count > 1 { return "widget_no_recent_change".l }
        return "widget_collecting_history".l
    }

    private func todayTokensText(snapshot: UsageHistorySnapshot) -> String {
        guard let tokens = snapshot.todayTokens else { return "–" }
        return TokenCountFormatter.compact(tokens)
    }

    private func resetCreditText(_ resetCredits: OpenAIRateLimitResetCredits, now: Date = Date()) -> String {
        let count = resetCredits.usableCount(at: now)
        guard count > 0 else { return "widget_reset_credits_none".l }
        guard let expiry = resetCredits.earliestExpiry(at: now) else {
            return String(format: "widget_reset_credits_count".l, count)
        }
        let components = Calendar.current.dateComponents([.month, .day], from: expiry)
        return String(
            format: "widget_reset_credits_expiry".l,
            count,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

private struct PagedWidget: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings
    @State private var selectedProvider: WidgetProvider = .claude

    var body: some View {
        let tokens = theme.current.tokens
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                pageButton(systemName: "chevron.left", helpKey: "widget_previous_provider")
                Spacer()
                HStack(spacing: 6) {
                    ForEach(WidgetProvider.allCases) { provider in
                        Circle()
                            .fill(provider == selectedProvider ? tokens.accent : tokens.bgRing)
                            .frame(width: 6, height: 6)
                    }
                    Text(selectedProvider.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tokens.textTertiary)
                }
                Spacer()
                pageButton(systemName: "chevron.right", helpKey: "widget_next_provider")
            }

            ProviderWidgetSection(provider: selectedProvider)
                .id(selectedProvider.rawValue)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
                .accessibilityIdentifier("widget-page-\(selectedProvider.rawValue)")

            if settings.usagePetEnabled {
                Divider().background(tokens.divider)
                WidgetMimoCompanion()
            }
        }
        .padding(18)
        .frame(width: 240)
        .background(WidgetPanelSurface(theme: theme.current))
    }

    private func pageButton(systemName: String, helpKey: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedProvider = selectedProvider == .claude ? .openAI : .claude
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(theme.current.tokens.textSecondary)
                .frame(width: 24, height: 24)
                .background(theme.current.tokens.bgSecondary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(helpKey.l)
    }
}

private struct SingleProviderWidget: View {
    let provider: WidgetProvider

    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let tokens = theme.current.tokens
        VStack(alignment: .leading, spacing: 8) {
            ProviderWidgetSection(provider: provider)
            if settings.usagePetEnabled {
                Divider().background(tokens.divider)
                WidgetMimoCompanion()
            }
        }
        .padding(18)
        .frame(width: 240)
        .background(WidgetPanelSurface(theme: theme.current))
    }
}

// MARK: - Provider content

private struct ProviderWidgetSection: View {
    let provider: WidgetProvider

    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            providerHeader
            if provider == .claude {
                if vm.snapshot != nil {
                    metricRows(vm.claudeDisplayMetrics)
                } else {
                    EmptyStateInline()
                }
            } else if vm.openAIState.isLoaded, !openAIMetrics.isEmpty {
                metricRows(openAIMetrics)
            } else {
                OpenAIEmptyStateInline()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var openAIMetrics: [UsageDisplayMetric] {
        vm.openAIDisplayMetrics(includingSpark: settings.showOpenAISparkLimits)
    }

    @ViewBuilder
    private func metricRows(_ metrics: [UsageDisplayMetric]) -> some View {
        ForEach(metrics) { metric in
            WidgetMetricRow(metric: metric)
        }
    }

    private var providerHeader: some View {
        let tokens = theme.current.tokens
        return HStack(spacing: 6) {
            HStack(spacing: 7) {
                if theme.current != .toss {
                    providerIcon(size: theme.current == .hybrid ? 22 : 20)
                }
                Text(theme.current == .toss ? provider.displayName.uppercased() : provider.displayName)
                    .font(.system(size: theme.current == .hybrid ? 12 : 11, weight: .heavy))
                    .foregroundStyle(provider == .claude ? tokens.accent : tokens.textPrimary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            providerStatus
        }
    }

    @ViewBuilder
    private func providerIcon(size: CGFloat) -> some View {
        switch provider {
        case .claude:
            ClaudeProviderIcon(size: size)
        case .openAI:
            CodexProviderIcon(size: size)
        }
    }

    @ViewBuilder
    private var providerStatus: some View {
        let tokens = theme.current.tokens
        switch provider {
        case .claude:
            if vm.snapshot != nil {
                PlanBadge(plan: vm.plan, theme: theme.current)
                    .scaleEffect(theme.current == .hybrid ? 0.9 : 0.85)
            } else {
                Circle().fill(tokens.ok).frame(width: 6, height: 6)
            }
        case .openAI:
            if vm.openAIState.isLoaded {
                TextPlanBadge(
                    displayName: vm.openAIPlanDisplayName,
                    compactName: vm.openAIPlanCompactName,
                    theme: theme.current
                )
                .scaleEffect(theme.current == .hybrid ? 0.9 : 0.85)
            } else {
                Circle().fill(tokens.textTertiary).frame(width: 6, height: 6)
            }
        }
    }
}

private struct WidgetMetricRow: View {
    let metric: UsageDisplayMetric
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        Group {
            switch theme.current {
            case .daangn:
                MetricRowRing(
                    title: metric.title,
                    utilization: metric.utilization,
                    resetsAt: metric.resetsAt,
                    isWeekly: metric.isWeekly,
                    tokens: tokens
                )
            case .toss:
                MetricRowBar(
                    title: metric.title,
                    utilization: metric.utilization,
                    resetsAt: metric.resetsAt,
                    isWeekly: metric.isWeekly,
                    tokens: tokens
                )
            case .hybrid:
                MetricRowHybrid(
                    title: metric.title,
                    utilization: metric.utilization,
                    resetsAt: metric.resetsAt,
                    isWeekly: metric.isWeekly,
                    tokens: tokens
                )
            }
        }
    }
}

// MARK: - Theme metric rows

private struct MetricRowRing: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: 12) {
            RingView(
                progress: utilization,
                size: 48,
                lineWidth: 5,
                label: "\(Int(round(utilization)))%",
                tokens: tokens
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                CountdownText(resetsAt: resetsAt, isWeekly: isWeekly)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tokens.textPrimary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MetricRowBar: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
    let tokens: DesignTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(round(utilization)))")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(tokens.textPrimary)
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tokens.textTertiary)
                }
                Spacer()
                CountdownText(resetsAt: resetsAt, isWeekly: isWeekly)
                    .font(.system(size: 10))
                    .foregroundStyle(tokens.textTertiary)
            }
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(tokens.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            LinearBar(progress: utilization, height: 5, tokens: tokens)
        }
    }
}

private struct MetricRowHybrid: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
    let tokens: DesignTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(tokens.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                Spacer()
                CountdownText(resetsAt: resetsAt, isWeekly: isWeekly)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tokens.textPrimary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(round(utilization)))")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(tokens.textPrimary)
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tokens.textTertiary)
            }
            LinearBar(progress: utilization, height: 7, tokens: tokens, gradient: true)
        }
    }
}

// MARK: - Common

private struct WidgetPanelSurface: View {
    let theme: ThemeKind

    var body: some View {
        let tokens = theme.tokens
        let shape = RoundedRectangle(cornerRadius: tokens.cornerOuter, style: .continuous)
        Group {
            if theme == .hybrid {
                shape.fill(
                    LinearGradient(
                        colors: [tokens.bg, tokens.bgSecondary],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            } else {
                shape.fill(tokens.bg)
            }
        }
        .overlay(shape.stroke(tokens.border, lineWidth: 1))
    }
}

private struct EmptyStateInline: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        switch vm.state {
        case .loading:
            ProgressView().controlSize(.small).padding(.vertical, 12)
        case .needsLogin:
            Text("login_required".l)
                .font(.system(size: 11))
                .foregroundStyle(tokens.textTertiary)
                .padding(.vertical, 12)
        case .error:
            Text("load_failed".l)
                .font(.system(size: 11))
                .foregroundStyle(tokens.warn)
                .padding(.vertical, 12)
        case .loaded:
            EmptyView()
        }
    }
}

private struct OpenAIEmptyStateInline: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        switch vm.openAIState {
        case .loading:
            ProgressView().controlSize(.small).padding(.vertical, 12)
        case .unavailable:
            Text("openai_not_connected".l)
                .font(.system(size: 11))
                .foregroundStyle(tokens.textTertiary)
                .multilineTextAlignment(.leading)
                .padding(.vertical, 12)
        case .error:
            Text("load_failed".l)
                .font(.system(size: 11))
                .foregroundStyle(tokens.warn)
                .padding(.vertical, 12)
        case .loaded:
            Text("usage_unavailable".l)
                .font(.system(size: 11))
                .foregroundStyle(tokens.textTertiary)
                .padding(.vertical, 12)
        }
    }
}
