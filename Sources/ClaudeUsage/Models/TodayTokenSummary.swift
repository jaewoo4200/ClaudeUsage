import Foundation

enum TodayTokenState: Equatable {
    case available(Int64)
    case pending
    case disabled
    case unavailable
    /// 사용자가 이 서비스를 숨김(설정 > 표시할 서비스). 합계에서 빼고 화면에도 보이지 않는다.
    case hidden

    var count: Int64? {
        guard case .available(let value) = self, value >= 0 else { return nil }
        return value
    }
}

struct TodayTokenSummary: Equatable {
    let claude: TodayTokenState
    let codex: TodayTokenState
    let latestCodexBucket: OpenAITokenDailyBucket?

    /// 보이는 서비스들의 합계. 보이는 서비스가 모두 값을 가졌을 때만 낸다(숨긴 서비스는 뺀다).
    var total: Int64? {
        let shown = [claude, codex].filter { $0 != .hidden }
        guard !shown.isEmpty else { return nil }
        let counts = shown.map(\.count)
        guard counts.allSatisfy({ $0 != nil }) else { return nil }
        return counts.compactMap { $0 }.reduce(0, +)
    }

    var reportedTotal: Int64? {
        let values = [claude, codex].filter { $0 != .hidden }.compactMap(\.count)
        return values.isEmpty ? nil : values.reduce(0, +)
    }
}
