import SwiftUI

struct WidgetView: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        Group {
            switch theme.current {
            case .daangn: DaangnWidget()
            case .toss:   TossWidget()
            case .hybrid: HybridWidget()
            }
        }
        .id("\(language.current.rawValue)-\(theme.current.rawValue)")  // 트리 재생성 강제
    }
}

// MARK: - Daangn

private struct DaangnWidget: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let t = theme.current.tokens
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    AppIconDot(theme: theme.current, size: 20)
                    Text("claude_short".l)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(t.textPrimary)
                }
                Spacer()
                if vm.snapshot != nil {
                    PlanBadge(plan: vm.plan, theme: theme.current)
                        .scaleEffect(0.85)
                } else {
                    Circle().fill(t.ok).frame(width: 6, height: 6)
                }
            }
            if vm.snapshot != nil {
                MetricRowRing(title: "five_hour".l,
                              utilization: vm.fiveHourUtilization,
                              resetsAt: vm.fiveHourResetsAt,
                              isWeekly: false,
                              tokens: t)
                MetricRowRing(title: "seven_day".l,
                              utilization: vm.sevenDayUtilization,
                              resetsAt: vm.sevenDayResetsAt,
                              isWeekly: true,
                              tokens: t)
                if vm.hasClaudeDesign {
                    MetricRowRing(title: "claude_design".l,
                                  utilization: vm.claudeDesignUtilization,
                                  resetsAt: vm.claudeDesignResetsAt,
                                  isWeekly: true,
                                  tokens: t)
                }
            } else {
                EmptyStateInline()
            }
        }
        .padding(18)
        .frame(width: 240)
        .background(panelBg(t: t))
    }
}

private struct MetricRowRing: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
    let tokens: DesignTokens

    var body: some View {
        HStack(spacing: 12) {
            RingView(progress: utilization, size: 48, lineWidth: 5,
                     label: "\(Int(round(utilization)))%", tokens: tokens)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
                CountdownText(resetsAt: resetsAt, isWeekly: isWeekly)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tokens.textPrimary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Toss

private struct TossWidget: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let t = theme.current.tokens
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("CLAUDE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(t.accent)
                Spacer()
                if vm.snapshot != nil {
                    PlanBadge(plan: vm.plan, theme: theme.current).scaleEffect(0.85)
                } else {
                    Circle().fill(t.ok).frame(width: 6, height: 6)
                }
            }
            if vm.snapshot != nil {
                MetricRowBar(title: "five_hour".l,
                             utilization: vm.fiveHourUtilization,
                             resetsAt: vm.fiveHourResetsAt,
                             isWeekly: false,
                             tokens: t)
                MetricRowBar(title: "seven_day".l,
                             utilization: vm.sevenDayUtilization,
                             resetsAt: vm.sevenDayResetsAt,
                             isWeekly: true,
                             tokens: t)
                if vm.hasClaudeDesign {
                    MetricRowBar(title: "claude_design".l,
                                 utilization: vm.claudeDesignUtilization,
                                 resetsAt: vm.claudeDesignResetsAt,
                                 isWeekly: true,
                                 tokens: t)
                }
            } else {
                EmptyStateInline()
            }
        }
        .padding(18)
        .frame(width: 240)
        .background(panelBg(t: t))
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
            LinearBar(progress: utilization, height: 5, tokens: tokens)
        }
    }
}

// MARK: - Hybrid

private struct HybridWidget: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let t = theme.current.tokens
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 7) {
                    AppIconDot(theme: theme.current, size: 22)
                    Text("claude_short".l)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(t.textPrimary)
                }
                Spacer()
                if vm.snapshot != nil {
                    PlanBadge(plan: vm.plan, theme: theme.current).scaleEffect(0.9)
                } else {
                    Circle().fill(t.ok).frame(width: 6, height: 6)
                }
            }
            if vm.snapshot != nil {
                MetricRowHybrid(title: "five_hour".l,
                                utilization: vm.fiveHourUtilization,
                                resetsAt: vm.fiveHourResetsAt,
                                isWeekly: false,
                                tokens: t)
                MetricRowHybrid(title: "seven_day".l,
                                utilization: vm.sevenDayUtilization,
                                resetsAt: vm.sevenDayResetsAt,
                                isWeekly: true,
                                tokens: t)
                if vm.hasClaudeDesign {
                    MetricRowHybrid(title: "claude_design".l,
                                    utilization: vm.claudeDesignUtilization,
                                    resetsAt: vm.claudeDesignResetsAt,
                                    isWeekly: true,
                                    tokens: t)
                }
            } else {
                EmptyStateInline()
            }
        }
        .padding(18)
        .frame(width: 240)
        .background(
            LinearGradient(colors: [t.bg, t.bgSecondary], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: t.cornerOuter, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.cornerOuter, style: .continuous)
                .stroke(t.border, lineWidth: 1)
        )
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
                    .tracking(0.5)
                    .foregroundStyle(tokens.textTertiary)
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

@ViewBuilder
private func panelBg(t: DesignTokens) -> some View {
    // shadow는 NSPanel.hasShadow가 처리 — SwiftUI shadow를 panel boundary 안에서 그리면 한쪽이 잘려서 이상하게 보임
    RoundedRectangle(cornerRadius: t.cornerOuter, style: .continuous)
        .fill(t.bg)
        .overlay(
            RoundedRectangle(cornerRadius: t.cornerOuter, style: .continuous)
                .stroke(t.border, lineWidth: 1)
        )
}

private struct EmptyStateInline: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    var body: some View {
        let t = theme.current.tokens
        switch vm.state {
        case .loading:
            ProgressView().controlSize(.small).padding(.vertical, 12)
        case .needsLogin:
            Text("login_required".l)
                .font(.system(size: 11))
                .foregroundStyle(t.textTertiary)
                .padding(.vertical, 12)
        case .error:
            Text("load_failed".l)
                .font(.system(size: 11))
                .foregroundStyle(t.warn)
                .padding(.vertical, 12)
        case .loaded:
            EmptyView()
        }
    }
}
