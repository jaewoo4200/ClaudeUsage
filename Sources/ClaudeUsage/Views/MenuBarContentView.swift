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

    var body: some View {
        let tokens = theme.current.tokens
        VStack(spacing: 14) {
            ScrollView {
                VStack(spacing: 16) {
                    if settings.usagePetEnabled {
                        PetSummaryCard()
                    }
                    ClaudeProviderSection()
                    Divider().background(tokens.divider)
                    OpenAIProviderSection()
                }
                .padding(.trailing, 2)
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
            .onPreferenceChange(MenuScrollContentHeightKey.self) { measuredHeight in
                guard measuredHeight > 0 else { return }
                let clampedHeight = min(ceil(measuredHeight), 560)
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
                title: "claude_usage".l,
                status: statusText,
                isOpenAI: false,
                planDisplayName: vm.state.isLoaded ? vm.plan.displayName : nil,
                planCompactName: vm.state.isLoaded ? vm.plan.compactName : nil
            )

            switch vm.state {
            case .loaded:
                ForEach(vm.claudeDisplayMetrics) { metric in
                    usageCard(metric)
                }
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

    private func usageCard(_ metric: UsageDisplayMetric) -> some View {
        ThemedUsageCard(
            title: metric.title,
            utilization: metric.utilization,
            resetsAt: metric.resetsAt,
            isWeekly: metric.isWeekly,
            theme: theme.current
        )
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
                title: "openai_usage".l,
                status: statusText,
                isOpenAI: true,
                planDisplayName: vm.openAIState.isLoaded ? vm.openAIPlanDisplayName : nil,
                planCompactName: vm.openAIState.isLoaded ? vm.openAIPlanCompactName : nil
            )

            switch vm.openAIState {
            case .loaded:
                if metrics.isEmpty {
                    ProviderMessageView(message: "usage_unavailable".l)
                } else {
                    ForEach(metrics) { metric in
                        ThemedUsageCard(
                            title: metric.title,
                            utilization: metric.utilization,
                            resetsAt: metric.resetsAt,
                            isWeekly: metric.isWeekly,
                            theme: theme.current
                        )
                    }
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
    let planCompactName: String?

    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        HStack(spacing: 10) {
            Group {
                if isOpenAI {
                    CodexProviderIcon(size: 36)
                } else {
                    ClaudeProviderIcon(size: 36)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tokens.textPrimary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(planDisplayName == nil ? tokens.textTertiary : tokens.ok)
                        .frame(width: 5, height: 5)
                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let planDisplayName, let planCompactName {
                TextPlanBadge(
                    displayName: planDisplayName,
                    compactName: planCompactName,
                    theme: theme.current
                )
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
