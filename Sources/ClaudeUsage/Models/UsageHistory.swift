import Foundation

struct UsageHistorySnapshot: Equatable {
    let claudeFiveHour: Double?
    let claudeWeekly: Double?
    let claudeModelMaximum: Double?
    let openAIFiveHour: Double?
    let openAIWeekly: Double?
    let openAIModelMaximum: Double?
    let claudeTodayTokens: Int64?
    let openAITodayTokens: Int64?

    var pressure: Double? {
        [
            claudeFiveHour,
            claudeWeekly,
            claudeModelMaximum,
            openAIFiveHour,
            openAIWeekly,
            openAIModelMaximum
        ]
        .compactMap { $0 }
        .max()
    }

    var todayTokens: Int64? {
        let values = [claudeTodayTokens, openAITodayTokens].compactMap { $0 }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    var hasUsage: Bool { pressure != nil }
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
            openAITodayTokens: openAITodayTokens
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

    static func resolve(snapshot: UsageHistorySnapshot, trend: UsageTrend) -> PetMood {
        guard let pressure = snapshot.pressure else { return .waiting }
        if trend.resetDetected, pressure < 60 { return .refreshed }

        let burnRate = trend.percentPerHour ?? 0
        if pressure >= 90 || burnRate >= 45 { return .tired }
        if pressure >= 75 || burnRate >= 28 { return .sleepy }
        if pressure >= 50 || burnRate >= 14 { return .focused }
        return .calm
    }
}
