import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        DashboardDropdown()
            .frame(width: 320)
            .padding(20)
            .background(theme.current.tokens.bg)
            .id("\(language.current.rawValue)-\(theme.current.rawValue)")
    }
}

private struct DashboardDropdown: View {
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings
    @State private var scrollHeight: CGFloat = 360
    /// 바깥 여백(20)만큼 좌우로, 아래 구분선까지(14) 번짐이 퍼질 자리
    private static let glowRoomX: CGFloat = 20
    private static let glowRoomBottom: CGFloat = 14

    var body: some View {
        let tokens = theme.current.tokens
        VStack(spacing: 14) {
            ScrollView {
                VStack(spacing: 16) {
                    if settings.usagePetEnabled {
                        PetSummaryCard()
                    }
                    // 설정 > 표시할 서비스에서 끈 서비스는 빼고, 둘 다 보일 때만 구분선
                    if settings.showClaude {
                        ClaudeProviderSection()
                    }
                    if settings.showClaude && settings.showCodex {
                        Divider().background(tokens.divider)
                    }
                    if settings.showCodex {
                        OpenAIProviderSection()
                    }
                }
                .padding(.trailing, 2)
                // 빛 번짐(헤일로·오라)이 스크롤 영역 경계에서 잘리지 않도록, 스크롤 영역을 바깥 여백까지 넓히고
                // 같은 만큼 안쪽 여백을 준다. 겉보기 배치는 그대로다.
                .padding(.horizontal, Self.glowRoomX)
                .padding(.bottom, Self.glowRoomBottom)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MenuScrollContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .frame(height: scrollHeight)
            .padding(.horizontal, -Self.glowRoomX)
            .padding(.bottom, -Self.glowRoomBottom)
            .onPreferenceChange(MenuScrollContentHeightKey.self) { measuredHeight in
                guard measuredHeight > 0 else { return }
                let clampedHeight = min(ceil(measuredHeight), 560 + Self.glowRoomBottom)
                if abs(scrollHeight - clampedHeight) >= 0.5 {
                    scrollHeight = clampedHeight
                }
            }

            Divider().background(tokens.divider)
            FooterRow()
        }
    }
}

private struct MenuScrollContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ClaudeProviderSection: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        VStack(spacing: 12) {
            ProviderHeaderSection(
                title: "claude_short".l,
                status: statusText,
                isOpenAI: false,
                planDisplayName: vm.state.isLoaded ? vm.plan.displayName : nil
            )

            switch vm.state {
            case .loaded:
                // 주간 구성은 7일 줄 안에 접혀 있다가 호버·"구성" 버튼으로 펼친다
                GaugeMetricList(
                    metrics: vm.claudeDisplayMetrics,
                    breakdown: vm.claudeWeeklyBreakdown,
                    theme: theme.current
                )
            case .loading:
                ProviderLoadingView()
            case .needsLogin:
                ProviderActionView(
                    message: "login_desc".l,
                    actionTitle: "login_action".l,
                    action: {
                        appDelegate.presentLogin { cookie in
                            vm.onLoggedIn(cookie: cookie)
                        }
                    }
                )
            case .error(let message):
                ProviderErrorView(message: message)
            }
        }
    }

    private var statusText: String {
        switch vm.state {
        case .loaded: return "logged_in".l
        case .loading: return "loading".l
        case .needsLogin: return "login_required".l
        case .error: return "load_failed".l
        }
    }
}

private struct OpenAIProviderSection: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let metrics = vm.openAIDisplayMetrics(includingSpark: settings.showOpenAISparkLimits)
        VStack(spacing: 12) {
            ProviderHeaderSection(
                title: "openai_short".l,
                status: statusText,
                isOpenAI: true,
                planDisplayName: vm.openAIState.isLoaded ? vm.openAIPlanDisplayName : nil
            )

            switch vm.openAIState {
            case .loaded:
                if metrics.isEmpty {
                    ProviderMessageView(message: "usage_unavailable".l)
                } else {
                    GaugeMetricList(metrics: metrics, theme: theme.current)
                }
            case .loading:
                ProviderLoadingView()
            case .unavailable:
                ProviderActionView(
                    message: "openai_connect_desc".l,
                    actionTitle: "open_usage_page".l,
                    action: openUsagePage
                )
            case .error(let message):
                ProviderActionView(
                    message: message,
                    actionTitle: "open_usage_page".l,
                    action: openUsagePage
                )
            }
        }
    }

    private var statusText: String {
        switch vm.openAIState {
        case .loaded: return "connected_automatically".l
        case .loading: return "loading".l
        case .unavailable: return "openai_not_connected".l
        case .error: return "load_failed".l
        }
    }

    private func openUsagePage() {
        guard let url = URL(string: "https://chatgpt.com/codex/cloud/settings/analytics#usage") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ProviderHeaderSection: View {
    let title: String
    let status: String
    let isOpenAI: Bool
    let planDisplayName: String?

    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        // 앱 아이콘 + 이름(오른쪽 위 연결 점) + 요금제 작은 대문자. 상태 문구는 툴팁.
        GaugeProviderHeader(
            name: title,
            nameColor: isOpenAI ? ProviderNameColor.codex : ProviderNameColor.claude,
            plan: planDisplayName,
            isLoaded: planDisplayName != nil,
            status: status,
            tokens: theme.current.tokens
        ) {
            if isOpenAI {
                CodexProviderIcon(size: 28)
            } else {
                ClaudeProviderIcon(size: 28)
            }
        }
    }
}

private struct ProviderLoadingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("loading".l)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private struct ProviderMessageView: View {
    let message: String
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        Text(message)
            .font(.system(size: 11))
            .foregroundStyle(theme.current.tokens.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

private struct ProviderActionView: View {
    let message: String
    let actionTitle: String
    let action: () -> Void

    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(tokens.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(tokens.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ProviderErrorView: View {
    let message: String
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(tokens.warn)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(tokens.textSecondary)
            Spacer()
            Button("retry".l) { vm.refreshNow() }
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.vertical, 8)
    }
}

private struct FooterRow: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        HStack(spacing: 14) {
            Button {
                appDelegate.toggleWidget(viewModel: vm)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: appDelegate.widgetVisible ? "square.dashed" : "square.on.square")
                        .font(.system(size: 10, weight: .semibold))
                    Text(appDelegate.widgetVisible ? "hide_widget".l : "show_widget".l)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(tokens.textTertiary)
            }
            .buttonStyle(.plain)

            Spacer()

            TodayTokensButton {
                Image(systemName: "sum")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
            }

            Button {
                appDelegate.openUsageHistory(viewModel: vm)
            } label: {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
            }
            .buttonStyle(.plain)
            .help("open_usage_history".l)

            Button {
                appDelegate.openSettings(viewModel: vm)
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
            }
            .buttonStyle(.plain)
            .help("settings_title".l)

            Button {
                vm.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
                    .rotationEffect(.degrees(vm.isRefreshing ? 360 : 0))
                    .animation(
                        vm.isRefreshing
                            ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                            : .default,
                        value: vm.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .help("retry".l)

            if vm.state.isLoaded {
                Button {
                    vm.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tokens.textTertiary)
                }
                .buttonStyle(.plain)
                .help("claude_logout".l)
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
            }
            .buttonStyle(.plain)
            .help("quit".l)
        }
    }
}
