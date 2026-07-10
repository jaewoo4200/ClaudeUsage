import Foundation

enum OpenAIWindowKind: String, Equatable {
    case fiveHour
    case weekly

    var isWeekly: Bool { self == .weekly }

    static func resolve(durationSeconds: Int?, fallback: OpenAIWindowKind) -> OpenAIWindowKind {
        guard let durationSeconds, durationSeconds > 0 else { return fallback }
        if durationSeconds <= 6 * 60 * 60 { return .fiveHour }
        if durationSeconds >= 6 * 24 * 60 * 60 { return .weekly }
        return fallback
    }
}

struct OpenAIUsageWindow: Decodable, Equatable {
    let usedPercent: Double
    let resetAt: Int?
    let resetAfterSeconds: Int?
    let limitWindowSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetAt = "reset_at"
        case resetAfterSeconds = "reset_after_seconds"
        case limitWindowSeconds = "limit_window_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = Self.decodeDouble(container, forKey: .usedPercent) ?? 0
        resetAt = Self.decodeInt(container, forKey: .resetAt)
        resetAfterSeconds = Self.decodeInt(container, forKey: .resetAfterSeconds)
        limitWindowSeconds = Self.decodeInt(container, forKey: .limitWindowSeconds)
    }

    init(
        usedPercent: Double,
        resetAt: Int?,
        resetAfterSeconds: Int?,
        limitWindowSeconds: Int?
    ) {
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.resetAfterSeconds = resetAfterSeconds
        self.limitWindowSeconds = limitWindowSeconds
    }

    func resetDate(now: Date = Date()) -> Date? {
        if let resetAt, resetAt > 0 {
            return Date(timeIntervalSince1970: TimeInterval(resetAt))
        }
        if let resetAfterSeconds, resetAfterSeconds > 0 {
            return now.addingTimeInterval(TimeInterval(resetAfterSeconds))
        }
        return nil
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }

    private static func decodeInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }
}

struct OpenAIRateLimit: Decodable, Equatable {
    let primaryWindow: OpenAIUsageWindow?
    let secondaryWindow: OpenAIUsageWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    init(primaryWindow: OpenAIUsageWindow?, secondaryWindow: OpenAIUsageWindow?) {
        self.primaryWindow = primaryWindow
        self.secondaryWindow = secondaryWindow
    }
}

struct OpenAIAdditionalRateLimit: Decodable, Equatable {
    let limitName: String?
    let meteredFeature: String?
    let rateLimit: OpenAIRateLimit?

    enum CodingKeys: String, CodingKey {
        case limitName = "limit_name"
        case meteredFeature = "metered_feature"
        case rateLimit = "rate_limit"
    }

    init(limitName: String?, meteredFeature: String?, rateLimit: OpenAIRateLimit?) {
        self.limitName = limitName
        self.meteredFeature = meteredFeature
        self.rateLimit = rateLimit
    }
}

private struct LossyOpenAIAdditionalRateLimit: Decodable {
    let value: OpenAIAdditionalRateLimit?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(OpenAIAdditionalRateLimit.self)
    }
}

struct OpenAIUsageCounter: Identifiable, Equatable {
    enum Scope: Equatable {
        case standard
        case codeReview
        case model
    }

    let id: String
    let name: String?
    let window: OpenAIUsageWindow
    let kind: OpenAIWindowKind
    let scope: Scope
}

struct OpenAITokenUsageSummary: Codable, Equatable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int?
    let longestStreakDays: Int?
}

struct OpenAITokenDailyBucket: Codable, Equatable {
    let startDate: String
    let tokens: Int64
}

struct OpenAITokenActivity: Codable, Equatable {
    let summary: OpenAITokenUsageSummary?
    let dailyBuckets: [OpenAITokenDailyBucket]

    func tokens(on date: Date, calendar: Calendar = .current) -> Int64? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let key = formatter.string(from: date)
        return dailyBuckets.first { $0.startDate == key }?.tokens
    }
}

struct OpenAIRateLimitResetCredit: Equatable, Identifiable {
    let id: String
    let resetType: String?
    let status: String
    let grantedAt: Date?
    let expiresAt: Date?
    let title: String?
    let description: String?

    func isUsable(at date: Date = Date()) -> Bool {
        guard status.lowercased() == "available" else { return false }
        return expiresAt.map { $0 > date } ?? true
    }
}

struct OpenAIRateLimitResetCredits: Equatable {
    let availableCount: Int
    let credits: [OpenAIRateLimitResetCredit]

    func usableCredits(at date: Date = Date()) -> [OpenAIRateLimitResetCredit] {
        credits.filter { $0.isUsable(at: date) }
    }

    func usableCount(at date: Date = Date()) -> Int {
        credits.isEmpty ? max(0, availableCount) : usableCredits(at: date).count
    }

    func earliestExpiry(at date: Date = Date()) -> Date? {
        usableCredits(at: date).compactMap(\.expiresAt).min()
    }
}

struct OpenAIUsageData: Decodable, Equatable {
    let planType: String?
    let rateLimit: OpenAIRateLimit?
    let codeReviewRateLimit: OpenAIRateLimit?
    let additionalRateLimits: [OpenAIAdditionalRateLimit]
    let tokenActivity: OpenAITokenActivity?
    let rateLimitResetCredits: OpenAIRateLimitResetCredits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case codeReviewRateLimit = "code_review_rate_limit"
        case additionalRateLimits = "additional_rate_limits"
        case tokenActivity = "token_activity"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try? container.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try? container.decodeIfPresent(OpenAIRateLimit.self, forKey: .rateLimit)
        codeReviewRateLimit = try? container.decodeIfPresent(OpenAIRateLimit.self, forKey: .codeReviewRateLimit)
        tokenActivity = try? container.decodeIfPresent(OpenAITokenActivity.self, forKey: .tokenActivity)
        rateLimitResetCredits = nil

        let lossy = try? container.decodeIfPresent(
            [LossyOpenAIAdditionalRateLimit].self,
            forKey: .additionalRateLimits
        )
        additionalRateLimits = lossy?.compactMap(\.value) ?? []
    }

    init(
        planType: String?,
        rateLimit: OpenAIRateLimit?,
        codeReviewRateLimit: OpenAIRateLimit?,
        additionalRateLimits: [OpenAIAdditionalRateLimit],
        tokenActivity: OpenAITokenActivity? = nil,
        rateLimitResetCredits: OpenAIRateLimitResetCredits? = nil
    ) {
        self.planType = planType
        self.rateLimit = rateLimit
        self.codeReviewRateLimit = codeReviewRateLimit
        self.additionalRateLimits = additionalRateLimits
        self.tokenActivity = tokenActivity
        self.rateLimitResetCredits = rateLimitResetCredits
    }

    var planDisplayName: String {
        guard let planType, !planType.isEmpty else { return "—" }
        switch planType.lowercased() {
        case "free": return "Free"
        case "go": return "Go"
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu", "education": return "Edu"
        default:
            return planType
                .split(separator: "_")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    var planCompactName: String {
        planDisplayName.uppercased()
    }

    var counters: [OpenAIUsageCounter] {
        var result: [OpenAIUsageCounter] = []
        var usedIDs = Set<String>()

        Self.append(
            rateLimit: rateLimit,
            idBase: "openai-standard",
            name: nil,
            scope: .standard,
            to: &result,
            usedIDs: &usedIDs
        )
        Self.append(
            rateLimit: codeReviewRateLimit,
            idBase: "openai-code-review",
            name: "Code Review",
            scope: .codeReview,
            to: &result,
            usedIDs: &usedIDs
        )

        let sortedAdditional = additionalRateLimits.sorted {
            Self.displayName(for: $0).localizedCaseInsensitiveCompare(Self.displayName(for: $1)) == .orderedAscending
        }
        for entry in sortedAdditional {
            let source = Self.firstNonEmpty(entry.meteredFeature, entry.limitName) ?? "model"
            let slug = Self.slug(source)
            Self.append(
                rateLimit: entry.rateLimit,
                idBase: "openai-model-\(slug.isEmpty ? "unknown" : slug)",
                name: Self.displayName(for: entry),
                scope: .model,
                to: &result,
                usedIDs: &usedIDs
            )
        }

        return result
    }

    private static func append(
        rateLimit: OpenAIRateLimit?,
        idBase: String,
        name: String?,
        scope: OpenAIUsageCounter.Scope,
        to result: inout [OpenAIUsageCounter],
        usedIDs: inout Set<String>
    ) {
        let candidates: [(OpenAIUsageWindow?, OpenAIWindowKind)] = [
            (rateLimit?.primaryWindow, .fiveHour),
            (rateLimit?.secondaryWindow, .weekly)
        ]

        for (window, fallbackKind) in candidates {
            guard let window else { continue }
            let kind = OpenAIWindowKind.resolve(
                durationSeconds: window.limitWindowSeconds,
                fallback: fallbackKind
            )
            let suffix = kind == .weekly ? "weekly" : "five-hour"
            let id = "\(idBase)-\(suffix)"
            guard usedIDs.insert(id).inserted else { continue }
            result.append(
                OpenAIUsageCounter(
                    id: id,
                    name: name,
                    window: window,
                    kind: kind,
                    scope: scope
                )
            )
        }
    }

    private static func displayName(for entry: OpenAIAdditionalRateLimit) -> String {
        if let limitName = firstNonEmpty(entry.limitName) { return limitName }
        guard let feature = firstNonEmpty(entry.meteredFeature) else { return "Codex model" }
        return feature
            .split { !$0.isLetter && !$0.isNumber }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private static func slug(_ value: String) -> String {
        var result = ""
        var lastWasDash = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
