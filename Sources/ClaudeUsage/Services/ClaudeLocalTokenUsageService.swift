import Foundation

struct ClaudeLocalTokenUsage: Equatable {
    let todayTokens: Int64
    let updatedAt: Date
}

enum ClaudeLocalTokenUsageService {
    static func fetch(now: Date = Date(), rootURL: URL? = nil) async -> ClaudeLocalTokenUsage? {
        await Task.detached(priority: .utility) {
            scan(now: now, rootURL: rootURL)
        }.value
    }

    private static func scan(now: Date, rootURL: URL?) -> ClaudeLocalTokenUsage? {
        let root = rootURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var todayTokens: Int64 = 0
        var seenMessages = Set<String>()

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= todayStart else {
                continue
            }

            forEachLine(in: url) { line in
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let message = object["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any],
                      let timestamp = object["timestamp"] as? String,
                      let date = parseDate(timestamp),
                      date >= todayStart,
                      date <= now else { return }

                let identity = [
                    object["requestId"] as? String,
                    message["id"] as? String,
                    timestamp
                ]
                .compactMap { $0 }
                .joined(separator: "|")
                guard identity.isEmpty || seenMessages.insert(identity).inserted else { return }

                let tokens = [
                    "input_tokens",
                    "output_tokens",
                    "cache_creation_input_tokens",
                    "cache_read_input_tokens"
                ]
                .compactMap { number(usage[$0]) }
                .reduce(0, +)

                todayTokens += tokens
            }
        }

        return ClaudeLocalTokenUsage(
            todayTokens: todayTokens,
            updatedAt: now
        )
    }

    private static func forEachLine(in url: URL, body: (Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            guard let chunk = try? handle.read(upToCount: 64 * 1_024), !chunk.isEmpty else { break }
            buffer.append(chunk)
            while let newline = buffer.firstRange(of: Data([0x0A])) {
                let line = buffer.subdata(in: buffer.startIndex..<newline.lowerBound)
                buffer.removeSubrange(buffer.startIndex...newline.lowerBound)
                if !line.isEmpty { body(line) }
            }
        }
        if !buffer.isEmpty { body(buffer) }
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter.fractional.date(from: value) { return date }
        return ISO8601DateFormatter.basic.date(from: value)
    }

    private static func number(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}

private extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let basic: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
