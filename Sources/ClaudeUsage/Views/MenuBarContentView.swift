import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        VStack(spacing: 0) {
            switch vm.state {
            case .needsLogin: LoginPromptView()
            case .loading: LoadingView()
            case .loaded: LoadedDropdown()
            case .error(let msg): ErrorView(message: msg)
            }
        }
        .frame(width: 320)
        .padding(20)
        .background(theme.current.tokens.bg)
        .id("\(language.current.rawValue)-\(theme.current.rawValue)")  // 언어/테마 변경 시 트리 재생성
    }
}

private struct LoadedDropdown: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let t = theme.current.tokens
        VStack(spacing: 14) {
            HeaderSection()

            ThemedUsageCard(
                title: "five_hour".l,
                utilization: vm.fiveHourUtilization,
                resetsAt: vm.fiveHourResetsAt,
                isWeekly: false,
                theme: theme.current
            )
            ThemedUsageCard(
                title: "seven_day".l,
                utilization: vm.sevenDayUtilization,
                resetsAt: vm.sevenDayResetsAt,
                isWeekly: true,
                theme: theme.current
            )
            if vm.hasClaudeDesign {
                ThemedUsageCard(
                    title: "claude_design".l,
                    utilization: vm.claudeDesignUtilization,
                    resetsAt: vm.claudeDesignResetsAt,
                    isWeekly: true,
                    theme: theme.current
                )
            }

            Divider().background(t.divider)
            FooterRow()
        }
    }
}

private struct HeaderSection: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let t = theme.current.tokens
        HStack(spacing: 10) {
            AppIconDot(theme: theme.current, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("claude_usage".l)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(t.textPrimary)
                HStack(spacing: 5) {
                    Circle().fill(t.ok).frame(width: 5, height: 5)
                    Text("logged_in".l)
                        .font(.system(size: 11))
                        .foregroundStyle(t.textTertiary)
                }
            }
            Spacer()
            PlanBadge(plan: vm.plan, theme: theme.current)
        }
    }
}

private struct FooterRow: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let t = theme.current.tokens
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
                .foregroundStyle(t.textTertiary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                appDelegate.openSettings(viewModel: vm)
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.textTertiary)
            }
            .buttonStyle(.plain)
            Button {
                vm.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.textTertiary)
                    .rotationEffect(.degrees(vm.isRefreshing ? 360 : 0))
                    .animation(vm.isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: vm.isRefreshing)
            }
            .buttonStyle(.plain)
            Button {
                vm.logout()
            } label: {
                Text("logout".l)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.textTertiary)
            }
            .buttonStyle(.plain)
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LoginPromptView: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var appDelegate: AppDelegate
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        let t = theme.current.tokens
        VStack(spacing: 14) {
            AppIconDot(theme: theme.current, size: 52)
                .padding(.top, 8)
            Text("please_login".l)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(t.textPrimary)
            Text("login_desc".l)
                .font(.system(size: 11))
                .foregroundStyle(t.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                appDelegate.presentLogin { cookie in
                    vm.onLoggedIn(cookie: cookie)
                }
            } label: {
                Text("login_action".l)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(t.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("quit".l)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("loading".l)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct ErrorView: View {
    let message: String
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        let t = theme.current.tokens
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(t.warn)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(t.textSecondary)
                .multilineTextAlignment(.center)
            Button("retry".l) { vm.refreshNow() }
                .buttonStyle(.borderedProminent)
                .tint(t.accent)
        }
        .padding(.vertical, 12)
    }
}
