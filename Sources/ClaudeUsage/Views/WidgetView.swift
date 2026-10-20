import SwiftUI
import AppKit

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
            .modifier(WidgetWindowDrag(panelID: panelID))
    }

    @ViewBuilder
    private var layout: some View {
        if let provider {
            SingleProviderWidget(provider: provider)
        } else if let only = settings.onlyVisibleProvider {
            // 서비스를 하나만 켜면 배치와 상관없이 그 서비스 한 장
            SingleProviderWidget(provider: only)
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

/// 위젯 창을 끌어서 옮긴다.
/// 창의 isMovableByWindowBackground만으로는 안 움직인다: SwiftUI 호스팅 뷰가 마우스 누름을 직접 받아 창까지 넘기지 않기 때문.
/// 그래서 위젯 아무 곳(버튼 제외)이나 3pt 이상 끌면 커서가 움직인 만큼 창을 옮기고, 놓으면 위치를 저장한다.
private struct WidgetWindowDrag: ViewModifier {
    let panelID: String
    @State private var start: (mouse: NSPoint, origin: NSPoint, window: NSWindow)?

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { value in
                    let mouse = NSEvent.mouseLocation          // 화면 좌표(아래가 0)
                    if start == nil, let window = Self.window(at: mouse) {
                        // 끌기가 인식되기 전 움직인 거리만큼 되돌려 처음 누른 곳을 기준으로 삼는다
                        let pressed = NSPoint(x: mouse.x - value.translation.width,
                                              y: mouse.y + value.translation.height)
                        start = (pressed, window.frame.origin, window)
                    }
                    guard let start else { return }
                    start.window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                                        y: start.origin.y + mouse.y - start.mouse.y))
                }
                .onEnded { _ in
                    if let start { WidgetPositionStore.save(start.window.frame.origin, id: panelID) }
                    start = nil
                }
        )
    }

    private static func window(at mouse: NSPoint) -> NSWindow? {
        if let window = NSApp.currentEvent?.window, window is FloatingPanel { return window }
        return NSApp.windows.first { $0 is FloatingPanel && $0.isVisible && $0.frame.contains(mouse) }
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
        .widgetPanelSurface(theme.current)
    }
}

private struct HorizontalWidget: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let tokens = theme.current.tokens
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ProviderWidgetSection(provider: .claude, contentWidth: WidgetGaugeWidth.horizontalColumn)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Divider().background(tokens.divider)

                ProviderWidgetSection(provider: .openAI, contentWidth: WidgetGaugeWidth.horizontalColumn)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)

            Divider().background(tokens.divider)

            HStack(alignment: .center, spacing: 12) {
                if settings.usagePetEnabled {
                    WidgetMimoCompanion(wide: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().background(tokens.divider)
                }
                HorizontalUsageBrief(twoColumns: !settings.usagePetEnabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 480)
        .widgetPanelSurface(theme.current)
    }
}

private struct HorizontalUsageBrief: View {
    var twoColumns = false
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

        let columns = Array(repeating: GridItem(.flexible(), alignment: .leading), count: twoColumns ? 2 : 1)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
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

            TodayTokensButton {
                insightRow(
                    systemName: "sum",
                    title: "widget_today_tokens".l,
                    color: tokens.accentSecondary
                ) {
                    Text(vm.todayTokenSummary(localCollectionEnabled: settings.usageHistoryEnabled).displayTotal)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
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
        .frame(height: 17)
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
        .widgetPanelSurface(theme.current)
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
        .widgetPanelSurface(theme.current)
    }
}

// MARK: - Provider content

private struct ProviderWidgetSection: View {
    let provider: WidgetProvider
    /// 줄이 차지하는 폭. 세로·전환·분리 위젯은 240 − 여백 18×2
    var contentWidth: CGFloat = WidgetGaugeWidth.narrow

    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            providerHeader
            if provider == .claude {
                if vm.snapshot != nil {
                    // 주간 구성은 7일 줄 안에 접혀 있다가 호버·"구성" 버튼으로 펼친다
                    metricRows(vm.claudeDisplayMetrics, breakdown: vm.claudeWeeklyBreakdown)
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

    private func metricRows(_ metrics: [UsageDisplayMetric], breakdown: UsageBreakdown? = nil) -> some View {
        GaugeMetricList(
            metrics: metrics,
            breakdown: breakdown,
            theme: theme.current,
            style: .widget(width: contentWidth)
        )
    }

    private var providerHeader: some View {
        // 드롭다운과 같은 헤더를 작게: 앱 아이콘 + 이름(오른쪽 위 연결 점) + 요금제 작은 대문자
        GaugeProviderHeader(
            name: provider.displayName,
            nameColor: provider == .claude ? ProviderNameColor.claude : ProviderNameColor.codex,
            plan: providerPlan,
            isLoaded: providerIsLoaded,
            tokens: theme.current.tokens,
            compact: true
        ) {
            providerIcon(size: 18)
        }
    }

    private var providerIsLoaded: Bool {
        switch provider {
        case .claude: return vm.snapshot != nil
        case .openAI: return vm.openAIState.isLoaded
        }
    }

    private var providerPlan: String? {
        guard providerIsLoaded else { return nil }
        switch provider {
        case .claude: return vm.plan.displayName
        case .openAI: return vm.openAIPlanDisplayName
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
}

/// 위젯 줄 폭 (WidgetView 레이아웃 치수에서 계산)
enum WidgetGaugeWidth {
    /// 세로·전환·분리: 240 − 여백 18×2
    static let narrow: CGFloat = 204
    /// 가로: (480 − 여백 16×2 − 간격 12×2 − 구분선 1) ÷ 2
    static let horizontalColumn: CGFloat = 211
}

// MARK: - Common

extension View {
    /// 위젯 판을 깐다. 빛 번짐(헤일로·오라)이 둥근 모서리 밖 투명한 창 영역으로 새지 않도록 내용을 판 모양으로 자른다.
    func widgetPanelSurface(_ theme: ThemeKind) -> some View {
        let shape = RoundedRectangle(cornerRadius: theme.tokens.cornerOuter, style: .continuous)
        return clipShape(shape).background(WidgetPanelSurface(theme: theme))
    }
}

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
