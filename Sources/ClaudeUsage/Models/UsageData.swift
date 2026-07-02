import Foundation

struct UsageWindow: Codable, Equatable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.utilization = (try? c.decode(Double.self, forKey: .utilization)) ?? 0
        if let str = try? c.decode(String.self, forKey: .resetsAt) {
            self.resetsAt = ISO8601DateFormatter.shared.date(from: str)
        } else {
            self.resetsAt = nil
        }
    }
}

struct ExtraUsage: Codable, Equatable {
    let isEnabled: Bool
    let monthlyLimit: Double
    let usedCredits: Double
    let utilization: Double
    let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case currency
    }

    // 모든 필드를 graceful하게 처리 — 한 필드 null이어도 ExtraUsage 자체는 살림
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = (try? c.decode(Bool.self, forKey: .isEnabled)) ?? false
        self.monthlyLimit = (try? c.decode(Double.self, forKey: .monthlyLimit)) ?? 0
        self.usedCredits = (try? c.decode(Double.self, forKey: .usedCredits)) ?? 0
        self.utilization = (try? c.decode(Double.self, forKey: .utilization)) ?? 0
        self.currency = try? c.decode(String.self, forKey: .currency)
    }
}

struct UsageData: Codable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDaySonnet: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDayOmelette: UsageWindow?
    let sevenDayFable: UsageWindow?
    let extraUsage: ExtraUsage?
    let additionalSevenDayWindows: [String: UsageWindow]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
        case sevenDayOmelette = "seven_day_omelette"
        case sevenDayFable = "seven_day_fable"
        case extraUsage = "extra_usage"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fiveHour = try? c.decodeIfPresent(UsageWindow.self, forKey: .fiveHour)
        self.sevenDay = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDay)
        self.sevenDaySonnet = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDaySonnet)
        self.sevenDayOpus = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOpus)
        self.sevenDayOmelette = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDayOmelette)
        self.sevenDayFable = try? c.decodeIfPresent(UsageWindow.self, forKey: .sevenDayFable)
        self.extraUsage = try? c.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
        self.additionalSevenDayWindows = Self.decodeAdditionalSevenDayWindows(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(fiveHour, forKey: .fiveHour)
        try c.encodeIfPresent(sevenDay, forKey: .sevenDay)
        try c.encodeIfPresent(sevenDaySonnet, forKey: .sevenDaySonnet)
        try c.encodeIfPresent(sevenDayOpus, forKey: .sevenDayOpus)
        try c.encodeIfPresent(sevenDayOmelette, forKey: .sevenDayOmelette)
        try c.encodeIfPresent(sevenDayFable, forKey: .sevenDayFable)
        try c.encodeIfPresent(extraUsage, forKey: .extraUsage)

        var dynamic = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, window) in additionalSevenDayWindows {
            guard let codingKey = DynamicCodingKey(stringValue: key) else { continue }
            try dynamic.encode(window, forKey: codingKey)
        }
    }

    private static func decodeAdditionalSevenDayWindows(from decoder: Decoder) -> [String: UsageWindow] {
        guard let dynamic = try? decoder.container(keyedBy: DynamicCodingKey.self) else { return [:] }
        let knownKeys = Set(CodingKeys.allCases.map(\.rawValue))

        return dynamic.allKeys.reduce(into: [:]) { result, key in
            let rawKey = key.stringValue
            guard !knownKeys.contains(rawKey), shouldDisplayDynamicUsageKey(rawKey) else { return }
            guard let window = try? dynamic.decode(UsageWindow.self, forKey: key) else { return }
            result[rawKey] = window
        }
    }

    private static func shouldDisplayDynamicUsageKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.hasPrefix("seven_day_") || normalized.contains("fable")
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

enum Plan: String, Codable, Equatable {
    case free, pro, max5x, max20x, team, enterprise, unknown

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .max5x: return "Max 5×"
        case .max20x: return "Max 20×"
        case .team: return "Team"
        case .enterprise: return "Enterprise"
        case .unknown: return "—"
        }
    }

    var compactName: String {
        switch self {
        case .free: return "FREE"
        case .pro: return "PRO"
        case .max5x: return "MAX 5×"
        case .max20x: return "MAX 20×"
        case .team: return "TEAM"
        case .enterprise: return "ENT"
        case .unknown: return "—"
        }
    }

    static func parse(capabilities: [String], rateLimitTier: String?) -> Plan {
        // rate_limit_tier 우선 (가장 구체적)
        if let tier = rateLimitTier?.lowercased() {
            if tier.contains("max_20x") { return .max20x }
            if tier.contains("max_5x") || tier.contains("max") { return .max5x }
            if tier.contains("pro") { return .pro }
            if tier.contains("team") { return .team }
            if tier.contains("enterprise") { return .enterprise }
        }
        let caps = capabilities.map { $0.lowercased() }
        if caps.contains("claude_max") { return .max5x }
        if caps.contains("claude_pro") { return .pro }
        if caps.contains("claude_team") { return .team }
        if caps.contains("claude_enterprise") { return .enterprise }
        if caps.contains("chat") { return .free }
        return .unknown
    }
}

struct Organization: Codable, Equatable {
    let uuid: String
    let name: String?
    let capabilities: [String]?
    let rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case uuid, name, capabilities
        case rateLimitTier = "rate_limit_tier"
    }

    var plan: Plan {
        Plan.parse(capabilities: capabilities ?? [], rateLimitTier: rateLimitTier)
    }
}

struct AccountSnapshot: Equatable {
    let organization: Organization
    let usage: UsageData
}

extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
