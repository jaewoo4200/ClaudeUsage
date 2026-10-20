import SwiftUI

/// The original themes keep their own typography and layouts, independent of the new gauges.
struct LegacyMetricView<Label: View>: View {
    let metric: UsageDisplayMetric
    let theme: ThemeKind
    let isWidget: Bool
    let now: Date
    @ViewBuilder let label: () -> Label

    private var tokens: DesignTokens { theme.tokens }
    private var percentage: String { "\(Int(metric.utilization.rounded()))%" }
    private var timer: some View {
        Text(GaugeCountdown.text(resetsAt: metric.resetsAt, isWeekly: metric.isWeekly, now: now, short: false))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    var body: some View {
        if isWidget {
            widgetRow
        } else {
            dropdownCard
        }
    }

    @ViewBuilder
    private var widgetRow: some View {
        if theme == .daangn {
            HStack(spacing: 12) {
                RingView(progress: metric.utilization, size: 48, lineWidth: 5,
                         label: percentage, tokens: tokens)
                VStack(alignment: .leading, spacing: 2) {
                    label()
                    timer.font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tokens.textPrimary)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if theme == .hybrid {
                    HStack {
                        label()
                        Spacer(minLength: 4)
                        timer.font(.system(size: 11, weight: .bold))
                    }
                    percent(size: 20)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        percent(size: 22)
                        Spacer(minLength: 4)
                        timer.font(.system(size: 10)).foregroundStyle(tokens.textTertiary)
                    }
                    label()
                }
                LinearBar(progress: metric.utilization, height: theme == .toss ? 5 : 7,
                          tokens: tokens, gradient: theme == .hybrid)
            }
        }
    }

    private var dropdownCard: some View {
        VStack(alignment: .leading, spacing: theme == .daangn ? 12 : 10) {
            HStack {
                label()
                Spacer(minLength: 6)
                timer.font(.system(size: 11, weight: theme == .toss ? .regular : .semibold))
                    .foregroundStyle(tokens.textTertiary)
            }
            if theme == .daangn {
                HStack(spacing: 14) {
                    RingView(progress: metric.utilization, size: 56, lineWidth: 6,
                             label: percentage, tokens: tokens)
                    VStack(alignment: .leading, spacing: 4) {
                        percent(size: 22)
                        comment
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    percent(size: theme == .toss ? 32 : 26)
                    Spacer(minLength: 4)
                    if theme == .hybrid { comment }
                }
                LinearBar(progress: metric.utilization, height: theme == .toss ? 6 : 8,
                          tokens: tokens, gradient: theme == .hybrid)
            }
        }
        .padding(theme == .hybrid ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerCard))
    }

    private func percent(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text("\(Int(metric.utilization.rounded()))")
                .font(.system(size: size, weight: theme == .toss ? .bold : .heavy,
                              design: theme == .daangn ? .rounded : .default))
                .foregroundStyle(tokens.textPrimary)
            Text("%").font(.system(size: isWidget ? 12 : 14, weight: .semibold))
                .foregroundStyle(tokens.textTertiary)
        }
        .monospacedDigit()
    }

    private var comment: some View {
        Text(theme.comment(forUtilization: metric.utilization, isWeekly: metric.isWeekly))
            .font(.system(size: 11))
            .foregroundStyle(tokens.textTertiary)
    }
}

struct LegacyProviderHeader: View {
    let provider: ProviderBrand
    let plan: String?
    let status: String
    let theme: ThemeKind
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            if !compact || theme != .toss {
                ProviderBrandIcon(provider: provider, size: compact ? 20 : 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(compact && theme == .toss ? provider.displayName.uppercased() : provider.displayName)
                    .font(.system(size: compact ? 11 : 15, weight: compact ? .heavy : .bold))
                    .foregroundStyle(compact && provider == .claude ? theme.tokens.accent : theme.tokens.textPrimary)
                    .lineLimit(1)
                if !compact {
                    HStack(spacing: 5) {
                        Circle().fill(plan == nil ? theme.tokens.textTertiary : theme.tokens.ok)
                            .frame(width: 5, height: 5)
                        Text(status).font(.system(size: 11)).foregroundStyle(theme.tokens.textTertiary)
                    }
                }
            }
            Spacer(minLength: 4)
            if let plan {
                TextPlanBadge(displayName: plan, compactName: plan, theme: theme)
                    .scaleEffect(compact ? 0.85 : 1)
            }
        }
    }
}
