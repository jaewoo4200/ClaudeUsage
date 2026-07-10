import Foundation

struct UsageHistoryCounter: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let label: String
    let utilization: Double
}

struct UsagePressureSource: Equatable {
    enum Provider: String, Equatable {
        case claude
        case codex
    }

    let id: String
    let label: String
    let provider: Provider
    let utilization: Double
}

struct UsageHistorySnapshot: Equatable {
    let claudeFiveHour: Double?
    let claudeWeekly: Double?
    let claudeModelMaximum: Double?
    let openAIFiveHour: Double?
    let openAIWeekly: Double?
    let openAIModelMaximum: Double?
    let claudeTodayTokens: Int64?
    let openAITodayTokens: Int64?
    let claudeModelCounters: [UsageHistoryCounter]
    let openAIModelCounters: [UsageHistoryCounter]

    init(
        claudeFiveHour: Double?,
        claudeWeekly: Double?,
        claudeModelMaximum: Double?,
        openAIFiveHour: Double?,
        openAIWeekly: Double?,
        openAIModelMaximum: Double?,
        claudeTodayTokens: Int64?,
        openAITodayTokens: Int64?,
        claudeModelCounters: [UsageHistoryCounter] = [],
        openAIModelCounters: [UsageHistoryCounter] = []
    ) {
        self.claudeFiveHour = claudeFiveHour
        self.claudeWeekly = claudeWeekly
        self.claudeModelMaximum = claudeModelMaximum
        self.openAIFiveHour = openAIFiveHour
        self.openAIWeekly = openAIWeekly
        self.openAIModelMaximum = openAIModelMaximum
        self.claudeTodayTokens = claudeTodayTokens
        self.openAITodayTokens = openAITodayTokens
        self.claudeModelCounters = claudeModelCounters
        self.openAIModelCounters = openAIModelCounters
    }

    var pressure: Double? {
        pressureSource?.utilization
    }

    var pressureSource: UsagePressureSource? {
        var sources: [UsagePressureSource] = []
        appendPressureSource(
            value: claudeFiveHour,
            id: "claude-five-hour",
            label: "Claude 5-hour",
            provider: .claude,
            to: &sources
        )
        appendPressureSource(
            value: claudeWeekly,
            id: "claude-weekly",
            label: "Claude weekly",
            provider: .claude,
            to: &sources
        )
        appendPressureSource(
            value: openAIFiveHour,
            id: "codex-five-hour",
            label: "Codex 5-hour",
            provider: .codex,
            to: &sources
        )
        appendPressureSource(
            value: openAIWeekly,
            id: "codex-weekly",
            label: "Codex weekly",
            provider: .codex,
            to: &sources
        )

        sources.append(contentsOf: claudeModelCounters.map {
            UsagePressureSource(
                id: $0.id,
                label: $0.label,
                provider: .claude,
                utilization: $0.utilization
            )
        })
        sources.append(contentsOf: openAIModelCounters.map {
            UsagePressureSource(
                id: $0.id,
                label: $0.label,
                provider: .codex,
                utilization: $0.utilization
            )
        })

        if claudeModelCounters.isEmpty {
            appendPressureSource(
                value: claudeModelMaximum,
                id: "claude-model-maximum",
                label: "Claude model limit",
                provider: .claude,
                to: &sources
            )
        }
        if openAIModelCounters.isEmpty {
            appendPressureSource(
                value: openAIModelMaximum,
                id: "codex-model-maximum",
                label: "Codex model limit",
                provider: .codex,
                to: &sources
            )
        }

        return sources.max { lhs, rhs in
            if lhs.utilization == rhs.utilization { return lhs.id > rhs.id }
            return lhs.utilization < rhs.utilization
        }
    }

    var todayTokens: Int64? {
        let values = [claudeTodayTokens, openAITodayTokens].compactMap { $0 }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var hasUsage: Bool { pressure != nil }

    private func appendPressureSource(
        value: Double?,
        id: String,
        label: String,
        provider: UsagePressureSource.Provider,
        to sources: inout [UsagePressureSource]
    ) {
        guard let value else { return }
        sources.append(
            UsagePressureSource(id: id, label: label, provider: provider, utilization: value)
        )
    }
}

struct UsageHistorySample: Codable, Equatable, Identifiable {
    let timestamp: Date
    let claudeFiveHour: Double?
    let claudeWeekly: Double?
    let claudeModelMaximum: Double?
    let openAIFiveHour: Double?
    let openAIWeekly: Double?
    let openAIModelMaximum: Double?
    let claudeTodayTokens: Int64?
    let openAITodayTokens: Int64?
    let claudeModelCounters: [UsageHistoryCounter]?
    let openAIModelCounters: [UsageHistoryCounter]?

    var id: Date { timestamp }

    init(timestamp: Date, snapshot: UsageHistorySnapshot) {
        self.timestamp = timestamp
        claudeFiveHour = snapshot.claudeFiveHour
        claudeWeekly = snapshot.claudeWeekly
        claudeModelMaximum = snapshot.claudeModelMaximum
        openAIFiveHour = snapshot.openAIFiveHour
        openAIWeekly = snapshot.openAIWeekly
        openAIModelMaximum = snapshot.openAIModelMaximum
        claudeTodayTokens = snapshot.claudeTodayTokens
        openAITodayTokens = snapshot.openAITodayTokens
        claudeModelCounters = snapshot.claudeModelCounters.isEmpty ? nil : snapshot.claudeModelCounters
        openAIModelCounters = snapshot.openAIModelCounters.isEmpty ? nil : snapshot.openAIModelCounters
    }

    var snapshot: UsageHistorySnapshot {
        UsageHistorySnapshot(
            claudeFiveHour: claudeFiveHour,
            claudeWeekly: claudeWeekly,
            claudeModelMaximum: claudeModelMaximum,
            openAIFiveHour: openAIFiveHour,
            openAIWeekly: openAIWeekly,
            openAIModelMaximum: openAIModelMaximum,
            claudeTodayTokens: claudeTodayTokens,
            openAITodayTokens: openAITodayTokens,
            claudeModelCounters: claudeModelCounters ?? [],
            openAIModelCounters: openAIModelCounters ?? []
        )
    }
}

struct UsageTrend: Equatable {
    let points: [Double]
    let deltaPercent: Double?
    let percentPerHour: Double?
    let recentTokenDelta: Int64?
    let resetDetected: Bool

    static let empty = UsageTrend(
        points: [],
        deltaPercent: nil,
        percentPerHour: nil,
        recentTokenDelta: nil,
        resetDetected: false
    )
}

enum PetMood: String, CaseIterable, Equatable {
    case waiting
    case calm
    case focused
    case sleepy
    case tired
    case refreshed

    static func resolve(
        snapshot: UsageHistorySnapshot,
        trend: UsageTrend,
        sensitivity: MimoSensitivity = .balanced
    ) -> PetMood {
        guard let pressure = snapshot.pressure else { return .waiting }
        if trend.resetDetected, pressure < 60 { return .refreshed }

        let burnRate = trend.percentPerHour ?? 0
        if pressure >= sensitivity.tiredPressure || burnRate >= sensitivity.tiredBurnRate { return .tired }
        if pressure >= sensitivity.sleepyPressure || burnRate >= sensitivity.sleepyBurnRate { return .sleepy }
        if pressure >= sensitivity.focusedPressure || burnRate >= sensitivity.focusedBurnRate { return .focused }
        return .calm
    }
}
