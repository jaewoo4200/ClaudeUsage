import Foundation

enum TodayTokenState: Equatable {
    case available(Int64)
    case pending
    case disabled
    case unavailable

    var count: Int64? {
        guard case .available(let value) = self, value >= 0 else { return nil }
        return value
    }
}

struct TodayTokenSummary: Equatable {
    let claude: TodayTokenState
    let codex: TodayTokenState
    let latestCodexBucket: OpenAITokenDailyBucket?

    var total: Int64? {
        guard let claude = claude.count, let codex = codex.count else { return nil }
        return claude + codex
    }

    var reportedTotal: Int64? {
        let values = [claude.count, codex.count].compactMap { $0 }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
