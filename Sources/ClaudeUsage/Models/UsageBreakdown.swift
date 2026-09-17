import Foundation

struct UsageBreakdown: Codable, Equatable {
    struct Row: Codable, Equatable, Identifiable {
        let key: String
        let displayName: String
        let percent: Double

        var id: String { key }

        enum CodingKeys: String, CodingKey {
            case key, percent
            case displayName = "display_name"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            key = try container.decode(String.self, forKey: .key)
            percent = try container.decode(Double.self, forKey: .percent)
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  percent.isFinite, (0...100).contains(percent) else {
                throw DecodingError.dataCorruptedError(forKey: .percent, in: container, debugDescription: "Invalid breakdown row")
            }
            let name = (try? container.decode(String.self, forKey: .displayName))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? key
        }
    }

    let asOf: Date?
    let windowStartedAt: Date?
    let rows: [Row]

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case windowStartedAt = "window_started_at"
        case rows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        asOf = Self.date(try? container.decode(String.self, forKey: .asOf))
        windowStartedAt = Self.date(try? container.decode(String.self, forKey: .windowStartedAt))
        let decoded = try container.decode([LossyRow].self, forKey: .rows)
        var seen = Set<String>()
        rows = decoded.compactMap(\.value).filter { seen.insert($0.key).inserted }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(asOf.map { ISO8601DateFormatter.shared.string(from: $0) }, forKey: .asOf)
        try container.encodeIfPresent(windowStartedAt.map { ISO8601DateFormatter.shared.string(from: $0) }, forKey: .windowStartedAt)
        try container.encode(rows, forKey: .rows)
    }

    private struct LossyRow: Decodable {
        let value: Row?

        init(from decoder: Decoder) throws {
            value = try? Row(from: decoder)
        }
    }

    private static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateFormatter.shared.date(from: string)
            ?? ISO8601DateFormatter().date(from: string)
    }
}
