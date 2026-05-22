import SwiftUI

// 통합 진입 — 테마에 따라 분기
struct ThemedUsageCard: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
    let theme: ThemeKind

    var body: some View {
        switch theme {
        case .daangn: DaangnUsageCard(title: title, utilization: utilization, resetsAt: resetsAt, isWeekly: isWeekly, tokens: theme.tokens, theme: theme)
        case .toss:   TossUsageCard(title: title, utilization: utilization, resetsAt: resetsAt, isWeekly: isWeekly, tokens: theme.tokens)
        case .hybrid: HybridUsageCard(title: title, utilization: utilization, resetsAt: resetsAt, isWeekly: isWeekly, tokens: theme.tokens, theme: theme)
        }
    }
}

// MARK: - Daangn 카드

struct DaangnUsageCard: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
    let tokens: DesignTokens
    let theme: ThemeKind

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tokens.textSecondary)
                Spacer()
                CountdownText(resetsAt: resetsAt, isWeekly: isWeekly)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(tokens.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            HStack(spacing: 14) {
                RingView(progress: utilization, size: 56, lineWidth: 6,
                         label: "\(Int(round(utilization)))%", tokens: tokens)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(Int(round(utilization)))")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(tokens.textPrimary)
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(tokens.textTertiary)
                    }
                    Text(theme.comment(forUtilization: utilization, isWeekly: isWeekly))
                        .font(.system(size: 11))
                        .foregroundStyle(tokens.textTertiary)
                }
                Spacer()
            }
        }
        .padding(16)
        .background(tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerCard, style: .continuous))
    }
}

// MARK: - Toss 카드

struct TossUsageCard: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
    let tokens: DesignTokens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tokens.textSecondary)
                Spacer()
                CountdownText(resetsAt: resetsAt, isWeekly: isWeekly)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(round(utilization)))")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(tokens.textPrimary)
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
            }
            LinearBar(progress: utilization, height: 6, tokens: tokens)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerCard, style: .continuous))
    }
}

// MARK: - Hybrid 카드

struct HybridUsageCard: View {
    let title: String
    let utilization: Double
    let resetsAt: Date?
    let isWeekly: Bool
    let tokens: DesignTokens
    let theme: ThemeKind

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(tokens.textSecondary)
                    Text(isWeekly ? "LONG" : "SHORT")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.5)
                        .foregroundStyle(tokens.textTertiary)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(tokens.divider)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Spacer()
                CountdownText(resetsAt: resetsAt, isWeekly: isWeekly)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tokens.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(Int(round(utilization)))")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(tokens.textPrimary)
                        .monospacedDigit()
                    Text("%")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tokens.textTertiary)
                }
                Spacer()
                Text(theme.comment(forUtilization: utilization, isWeekly: isWeekly))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.textTertiary)
            }
            LinearBar(progress: utilization, height: 8, tokens: tokens, gradient: true)
        }
        .padding(14)
        .background(tokens.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: tokens.cornerCard, style: .continuous)
                .stroke(tokens.divider, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: tokens.cornerCard, style: .continuous))
    }
}
