import Foundation

struct UsageWindow: Codable, Equatable {
    let utilization: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
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

private struct UsageWindowCandidate: Equatable {
    let window: UsageWindow
    let confidence: Int
    let path: [String]
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

    init(
        fiveHour: UsageWindow? = nil,
        sevenDay: UsageWindow? = nil,
        sevenDaySonnet: UsageWindow? = nil,
        sevenDayOpus: UsageWindow? = nil,
        sevenDayOmelette: UsageWindow? = nil,
        sevenDayFable: UsageWindow? = nil,
        extraUsage: ExtraUsage? = nil,
        additionalSevenDayWindows: [String: UsageWindow] = [:]
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDaySonnet = sevenDaySonnet
        self.sevenDayOpus = sevenDayOpus
        self.sevenDayOmelette = sevenDayOmelette
        self.sevenDayFable = sevenDayFable
        self.extraUsage = extraUsage
        self.additionalSevenDayWindows = additionalSevenDayWindows
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

    static func decode(from data: Data) throws -> UsageData {
        let decoded = try JSONDecoder().decode(UsageData.self, from: data)
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return decoded }
        return decoded.merging(Self.extractAdditionalWindows(from: raw, weeklyReset: decoded.sevenDay?.resetsAt))
    }

    private func merging(_ additionalWindows: [String: UsageWindow]) -> UsageData {
        var merged = additionalSevenDayWindows
        let extractedFable = additionalWindows[CodingKeys.sevenDayFable.rawValue]
        let normalizedFable = Self.bestFableWindow(
            decoded: sevenDayFable,
            extracted: extractedFable,
            weeklyReset: sevenDay?.resetsAt
        )

        for (key, window) in additionalWindows {
            guard key != CodingKeys.sevenDayFable.rawValue else { continue }
            merged[key] = window
        }
        return UsageData(
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            sevenDaySonnet: sevenDaySonnet,
            sevenDayOpus: sevenDayOpus,
            sevenDayOmelette: sevenDayOmelette,
            sevenDayFable: normalizedFable,
            extraUsage: extraUsage,
            additionalSevenDayWindows: merged
        )
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

    private static func extractAdditionalWindows(from raw: Any, weeklyReset: Date?) -> [String: UsageWindow] {
        var bestFable: UsageWindowCandidate?
        walkJSONObject(raw) { path, value in
            guard let object = value as? [String: Any],
                  isFableContext(path: path, object: object),
                  let candidate = usageWindowCandidate(
                    from: object,
                    path: path,
                    weeklyReset: weeklyReset,
                    allowNested: !isBroadUsageContainer(object)
                  ) else {
                return
            }
            if isBetterCandidate(candidate, than: bestFable, weeklyReset: weeklyReset) {
                bestFable = candidate
            }
        }

        guard let candidate = bestFable else { return [:] }
        let fable = UsageWindow(
            utilization: candidate.window.utilization,
            resetsAt: weeklyReset ?? candidate.window.resetsAt
        )
        return [CodingKeys.sevenDayFable.rawValue: fable]
    }

    private static func walkJSONObject(_ value: Any, path: [String] = [], visit: ([String], Any) -> Void) {
        visit(path, value)

        if let object = value as? [String: Any] {
            for (key, child) in object {
                walkJSONObject(child, path: path + [key], visit: visit)
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                walkJSONObject(child, path: path + [String(index)], visit: visit)
            }
        }
    }

    private static func isFableContext(path: [String], object: [String: Any]) -> Bool {
        if pathContains(path, "fable") {
            return true
        }

        let identityKeys = [
            "id",
            "key",
            "name",
            "title",
            "label",
            "model",
            "model_name",
            "modelName",
            "display_name",
            "displayName",
            "slug",
            "type"
        ]

        let normalizedIdentityKeys = Set(identityKeys.map { $0.lowercased() })

        return object.contains { key, value in
            let normalizedKey = key.lowercased()
            return normalizedKey.contains("fable")
                || (normalizedIdentityKeys.contains(normalizedKey)
                    && stringValue(value)?.lowercased().contains("fable") == true)
        }
    }

    private static func usageWindowCandidate(
        from object: [String: Any],
        path: [String],
        weeklyReset: Date?,
        allowNested: Bool
    ) -> UsageWindowCandidate? {
        guard !isFiveHourPath(path) else { return nil }

        let directPercentKeys = [
            "utilization",
            "usage_percentage",
            "usage_percent",
            "used_percentage",
            "used_percent",
            "percentage",
            "percent",
            "percent_used"
        ]
        var candidates: [UsageWindowCandidate] = []

        for key in directPercentKeys {
            if let value = numberValue(object[key]) {
                candidates.append(
                    UsageWindowCandidate(
                        window: UsageWindow(utilization: normalizedPercent(value), resetsAt: resetDate(from: object)),
                        confidence: key == "utilization" ? 100 : 90,
                        path: path + [key]
                    )
                )
            }
        }

        let usedKeys = ["used", "used_credits", "used_tokens", "current", "consumed", "value"]
        let limitKeys = ["limit", "monthly_limit", "token_limit", "max", "total", "quota"]
        for usedKey in usedKeys {
            guard let used = numberValue(object[usedKey]) else { continue }
            for limitKey in limitKeys {
                guard let limit = numberValue(object[limitKey]), limit > 0 else { continue }
                candidates.append(
                    UsageWindowCandidate(
                        window: UsageWindow(utilization: normalizedPercent(used / limit), resetsAt: resetDate(from: object)),
                        confidence: 80,
                        path: path + [usedKey, limitKey]
                    )
                )
            }
        }

        if allowNested, let nested = nestedUsageWindowCandidate(from: object, path: path, weeklyReset: weeklyReset) {
            candidates.append(nested)
        }

        return candidates.reduce(nil) { best, candidate in
            isBetterCandidate(candidate, than: best, weeklyReset: weeklyReset) ? candidate : best
        }
    }

    private static func nestedUsageWindowCandidate(from object: [String: Any], path: [String], weeklyReset: Date?) -> UsageWindowCandidate? {
        var best: UsageWindowCandidate?
        for (key, value) in object {
            guard let child = value as? [String: Any],
                  shouldInspectNestedFableCandidate(key: key, child: child, parentPath: path),
                  let candidate = usageWindowCandidate(
                    from: child,
                    path: path + [key],
                    weeklyReset: weeklyReset,
                    allowNested: true
                  ) else {
                continue
            }
            let adjusted = UsageWindowCandidate(window: candidate.window, confidence: candidate.confidence - 1, path: candidate.path)
            if isBetterCandidate(adjusted, than: best, weeklyReset: weeklyReset) {
                best = adjusted
            }
        }
        return best
    }

    private static func resetDate(from object: [String: Any]) -> Date? {
        let resetKeys = ["resets_at", "reset_at", "resetsAt", "resetAt", "reset_time", "resetTime"]
        for key in resetKeys {
            guard let value = stringValue(object[key]) else { continue }
            if let date = ISO8601DateFormatter.shared.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func numberValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let number = value as? Int { return Double(number) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let value { return String(describing: value) }
        return nil
    }

    private static func normalizedPercent(_ value: Double) -> Double {
        if value >= 0, value <= 1 {
            return value * 100
        }
        return value
    }

    private static func bestFableWindow(decoded: UsageWindow?, extracted: UsageWindow?, weeklyReset: Date?) -> UsageWindow? {
        let candidates = [
            decoded.map {
                UsageWindowCandidate(
                    window: $0,
                    confidence: 110,
                    path: [CodingKeys.sevenDayFable.rawValue]
                )
            },
            extracted.map {
                UsageWindowCandidate(
                    window: $0,
                    confidence: 100,
                    path: [CodingKeys.sevenDayFable.rawValue]
                )
            }
        ].compactMap { $0 }

        guard let best = candidates.reduce(nil, { best, candidate in
            isBetterCandidate(candidate, than: best, weeklyReset: weeklyReset) ? candidate : best
        }) else {
            return nil
        }
        return UsageWindow(utilization: best.window.utilization, resetsAt: weeklyReset ?? best.window.resetsAt)
    }

    private static func isBetterCandidate(_ candidate: UsageWindowCandidate, than current: UsageWindowCandidate?, weeklyReset: Date?) -> Bool {
        guard let current else { return true }

        let candidateScore = candidate.confidence + contextScore(for: candidate, weeklyReset: weeklyReset)
        let currentScore = current.confidence + contextScore(for: current, weeklyReset: weeklyReset)

        let candidateUtilization = candidate.window.utilization
        let currentUtilization = current.window.utilization
        if candidateUtilization > 0, currentUtilization == 0 {
            return candidateScore >= currentScore - 80
        }
        if candidateUtilization == 0, currentUtilization > 0 {
            return candidateScore > currentScore + 80
        }

        if abs(candidateScore - currentScore) > 10 {
            return candidateScore > currentScore
        }

        if candidateScore != currentScore {
            return candidateScore > currentScore
        }
        return candidateUtilization > currentUtilization
    }

    private static func contextScore(for candidate: UsageWindowCandidate, weeklyReset: Date?) -> Int {
        var score = 0
        if isFiveHourPath(candidate.path) {
            score -= 1_000
        }
        if pathContains(candidate.path, "seven_day") || pathContains(candidate.path, "weekly") || pathContains(candidate.path, "week") {
            score += 30
        }
        if let reset = candidate.window.resetsAt, let weeklyReset {
            if abs(reset.timeIntervalSince(weeklyReset)) < 60 {
                score += 60
            } else {
                score -= 120
            }
        }
        return score
    }

    private static func isBroadUsageContainer(_ object: [String: Any]) -> Bool {
        let keys = Set(object.keys.map { $0.lowercased() })
        return keys.contains("five_hour")
            || keys.contains("fivehour")
            || keys.contains("seven_day")
            || keys.contains("sevenday")
    }

    private static func shouldInspectNestedFableCandidate(key: String, child: [String: Any], parentPath: [String]) -> Bool {
        if key.lowercased().contains("fable") { return true }
        if pathContains(parentPath, "fable") { return true }
        if isFableContext(path: parentPath + [key], object: child) { return true }

        let usageKeys = [
            "usage",
            "usage_window",
            "usageWindow",
            "window",
            "limit",
            "limits",
            "quota",
            "rate_limit",
            "rateLimit",
            "weekly",
            "week",
            "seven_day",
            "sevenDay"
        ]
        return usageKeys.contains(key) || usageKeys.map { $0.lowercased() }.contains(key.lowercased())
    }

    private static func isFiveHourPath(_ path: [String]) -> Bool {
        let normalized = path.joined(separator: ".").lowercased()
        return normalized.contains("five_hour")
            || normalized.contains("fivehour")
            || normalized.contains("5_hour")
    }

    private static func pathContains(_ path: [String], _ value: String) -> Bool {
        path.joined(separator: ".").lowercased().contains(value.lowercased())
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
