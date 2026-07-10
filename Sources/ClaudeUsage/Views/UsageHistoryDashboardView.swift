import AppKit
import Charts
import SwiftUI

enum UsageHistoryRange: String, CaseIterable, Identifiable {
    case hour
    case day
    case week
    case twoWeeks

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .hour: return 60 * 60
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .twoWeeks: return 14 * 24 * 60 * 60
        }
    }

    @MainActor
    var title: String {
        switch self {
        case .hour: return "history_range_hour".l
        case .day: return "history_range_day".l
        case .week: return "history_range_week".l
        case .twoWeeks: return "history_range_two_weeks".l
        }
    }
}

enum UsageHistoryProviderScope: String, CaseIterable, Identifiable {
    case all
    case claude
    case codex

    var id: String { rawValue }

    @MainActor
    var title: String {
        switch self {
        case .all: return "history_scope_all".l
        case .claude: return "history_scope_claude".l
        case .codex: return "history_scope_codex".l
        }
    }

    func includes(_ provider: UsagePressureSource.Provider) -> Bool {
        switch self {
        case .all: return true
        case .claude: return provider == .claude
        case .codex: return provider == .codex
        }
    }
}

struct UsageHistoryChartPoint: Identifiable, Equatable {
    let timestamp: Date
    let seriesID: String
    let seriesLabel: String
    let provider: UsagePressureSource.Provider
    let utilization: Double

    var id: String {
        "\(timestamp.timeIntervalSinceReferenceDate)-\(seriesID)"
    }
}

struct UsageHistoryDashboardView: View {
    @EnvironmentObject private var history: UsageHistoryStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var language: LanguageStore

    @State private var range: UsageHistoryRange = .day
    @State private var scope: UsageHistoryProviderScope = .all

    var body: some View {
        let _ = language.current
        let tokens = theme.current.tokens
        let samples = filteredSamples
        let points = chartPoints(from: samples)

        VStack(alignment: .leading, spacing: 0) {
            header(tokens: tokens)
            Divider().background(tokens.divider)

            VStack(alignment: .leading, spacing: 18) {
                controls
                summary(samples: samples, tokens: tokens)

                if points.isEmpty {
                    emptyState(tokens: tokens)
                } else {
                    usageChart(points: points, tokens: tokens)
                }

                VStack(alignment: .leading, spacing: 6) {
                    if !settings.usageHistoryEnabled {
                        Label("history_tracking_off".l, systemImage: "pause.circle")
                            .foregroundStyle(tokens.warn)
                    }
                    Text("history_pressure_explanation".l)
                        .foregroundStyle(tokens.textTertiary)
                }
                .font(.system(size: 11, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
        }
        .frame(minWidth: 640, minHeight: 480)
        .background(tokens.bg)
        .id("\(language.current.rawValue)-\(theme.current.rawValue)")
    }

    private func header(tokens: DesignTokens) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tokens.bgSecondary)
                    .frame(width: 38, height: 38)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tokens.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("usage_history_dashboard".l)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tokens.textPrimary)
                Text("usage_history_local_desc".l)
                    .font(.system(size: 11))
                    .foregroundStyle(tokens.textTertiary)
            }
            Spacer()
            Button {
                history.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .disabled(!history.hasSamples)
            .help("clear_usage_history".l)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("usage_history_dashboard".l, selection: $range) {
                ForEach(UsageHistoryRange.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            Spacer(minLength: 12)

            Picker("history_scope_all".l, selection: $scope) {
                ForEach(UsageHistoryProviderScope.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 230)
        }
    }

    private func summary(samples: [UsageHistorySample], tokens: DesignTokens) -> some View {
        let pressures = samples.compactMap { Self.pressure(in: $0, scope: scope) }
        let peak = pressures.max()
        let delta = pressures.count > 1 ? (pressures.last ?? 0) - (pressures.first ?? 0) : nil
        let resets = Self.detectedResetCount(samples, scope: scope)

        return HStack(spacing: 0) {
            summaryMetric(
                title: "history_peak".l,
                value: peak.map { String(format: "history_percent_format".l, $0) } ?? "—",
                color: tokens.accent
            )
            summaryDivider(tokens: tokens)
            summaryMetric(
                title: "history_change".l,
                value: delta.map { String(format: "history_delta_format".l, $0) } ?? "—",
                color: (delta ?? 0) >= 0 ? tokens.warn : tokens.ok
            )
            summaryDivider(tokens: tokens)
            summaryMetric(
                title: "history_samples".l,
                value: "\(samples.count)",
                color: tokens.textPrimary
            )
            summaryDivider(tokens: tokens)
            summaryMetric(
                title: "history_resets".l,
                value: "\(resets)",
                color: resets > 0 ? tokens.ok : tokens.textPrimary
            )
        }
        .padding(.vertical, 12)
        .background(tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func summaryMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.current.tokens.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private func summaryDivider(tokens: DesignTokens) -> some View {
        Rectangle()
            .fill(tokens.divider)
            .frame(width: 1, height: 36)
    }

    private func usageChart(points: [UsageHistoryChartPoint], tokens: DesignTokens) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("history_chart_title".l)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tokens.textPrimary)

            Chart(points) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.utilization)
                )
                .foregroundStyle(by: .value("Series", point.seriesLabel))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.linear)

                PointMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.utilization)
                )
                .foregroundStyle(by: .value("Series", point.seriesLabel))
                .symbolSize(points.count < 80 ? 14 : 0)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(tokens.divider)
                    AxisValueLabel {
                        if let percent = value.as(Int.self) {
                            Text("\(percent)%")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine().foregroundStyle(tokens.divider.opacity(0.7))
                    AxisValueLabel()
                }
            }
            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
            .frame(minHeight: 245)
        }
    }

    private func emptyState(tokens: DesignTokens) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.flattrend.xyaxis")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(tokens.textTertiary)
            Text("history_empty_title".l)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tokens.textPrimary)
            Text("history_empty_desc".l)
                .font(.system(size: 11))
                .foregroundStyle(tokens.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 245)
        .background(tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var filteredSamples: [UsageHistorySample] {
        let cutoff = Date().addingTimeInterval(-range.interval)
        return history.samples.filter { $0.timestamp >= cutoff }.sorted { $0.timestamp < $1.timestamp }
    }

    private func chartPoints(from samples: [UsageHistorySample]) -> [UsageHistoryChartPoint] {
        samples.flatMap { sample in
            var points: [UsageHistoryChartPoint] = []
            appendPoint(
                value: sample.claudeFiveHour,
                timestamp: sample.timestamp,
                id: "claude-five-hour",
                label: "history_series_claude_five".l,
                provider: .claude,
                to: &points
            )
            appendPoint(
                value: sample.claudeWeekly,
                timestamp: sample.timestamp,
                id: "claude-weekly",
                label: "history_series_claude_weekly".l,
                provider: .claude,
                to: &points
            )
            appendPoint(
                value: sample.openAIFiveHour,
                timestamp: sample.timestamp,
                id: "codex-five-hour",
                label: "history_series_codex_five".l,
                provider: .codex,
                to: &points
            )
            appendPoint(
                value: sample.openAIWeekly,
                timestamp: sample.timestamp,
                id: "codex-weekly",
                label: "history_series_codex_weekly".l,
                provider: .codex,
                to: &points
            )

            if let counters = sample.claudeModelCounters, !counters.isEmpty {
                counters.forEach { counter in
                    appendPoint(
                        value: counter.utilization,
                        timestamp: sample.timestamp,
                        id: "claude-\(counter.id)",
                        label: counter.label,
                        provider: .claude,
                        to: &points
                    )
                }
            } else {
                appendPoint(
                    value: sample.claudeModelMaximum,
                    timestamp: sample.timestamp,
                    id: "claude-model-maximum",
                    label: "Claude · Model",
                    provider: .claude,
                    to: &points
                )
            }

            if let counters = sample.openAIModelCounters, !counters.isEmpty {
                counters.forEach { counter in
                    appendPoint(
                        value: counter.utilization,
                        timestamp: sample.timestamp,
                        id: "codex-\(counter.id)",
                        label: counter.label,
                        provider: .codex,
                        to: &points
                    )
                }
            } else {
                appendPoint(
                    value: sample.openAIModelMaximum,
                    timestamp: sample.timestamp,
                    id: "codex-model-maximum",
                    label: "Codex · Model",
                    provider: .codex,
                    to: &points
                )
            }
            return points
        }
    }

    private func appendPoint(
        value: Double?,
        timestamp: Date,
        id: String,
        label: String,
        provider: UsagePressureSource.Provider,
        to points: inout [UsageHistoryChartPoint]
    ) {
        guard scope.includes(provider), let value else { return }
        points.append(
            UsageHistoryChartPoint(
                timestamp: timestamp,
                seriesID: id,
                seriesLabel: label,
                provider: provider,
                utilization: value
            )
        )
    }

    static func pressure(
        in sample: UsageHistorySample,
        scope: UsageHistoryProviderScope
    ) -> Double? {
        let snapshot = sample.snapshot
        var values: [Double] = []

        if scope.includes(.claude) {
            values.append(contentsOf: [snapshot.claudeFiveHour, snapshot.claudeWeekly].compactMap { $0 })
            if snapshot.claudeModelCounters.isEmpty {
                if let modelMaximum = snapshot.claudeModelMaximum { values.append(modelMaximum) }
            } else {
                values.append(contentsOf: snapshot.claudeModelCounters.map(\.utilization))
            }
        }

        if scope.includes(.codex) {
            values.append(contentsOf: [snapshot.openAIFiveHour, snapshot.openAIWeekly].compactMap { $0 })
            if snapshot.openAIModelCounters.isEmpty {
                if let modelMaximum = snapshot.openAIModelMaximum { values.append(modelMaximum) }
            } else {
                values.append(contentsOf: snapshot.openAIModelCounters.map(\.utilization))
            }
        }

        return values.max()
    }

    static func detectedResetCount(
        _ samples: [UsageHistorySample],
        scope: UsageHistoryProviderScope
    ) -> Int {
        guard samples.count > 1 else { return 0 }
        return zip(samples, samples.dropFirst()).reduce(into: 0) { count, pair in
            guard let previous = pressure(in: pair.0, scope: scope),
                  let current = pressure(in: pair.1, scope: scope),
                  previous - current >= 15 else { return }
            count += 1
        }
    }
}
