import Foundation

struct ClaudeLocalTokenUsage: Equatable {
    let todayTokens: Int64
    let updatedAt: Date

    func tokens(on date: Date, calendar: Calendar = .current) -> Int64? {
        guard calendar.isDate(updatedAt, inSameDayAs: date), todayTokens >= 0 else { return nil }
        return todayTokens
    }
}

enum ClaudeLocalTokenUsageService {
    static func fetch(now: Date = Date(), rootURL: URL? = nil) async -> ClaudeLocalTokenUsage? {
        await Task.detached(priority: .utility) {
            scan(now: now, rootURL: rootURL)
        }.value
    }

    private static func scan(now: Date, rootURL: URL?) -> ClaudeLocalTokenUsage? {
        let root = rootURL ?? projectsURL()
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var todayTokens: Int64 = 0
        var seenMessages: [String: Int64] = [:]

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
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

                let requestID = object["requestId"] as? String ?? ""
                let messageID = message["id"] as? String
                let identity = "\(requestID)|\(messageID?.isEmpty == false ? messageID! : timestamp)"

                let tokens = [
                    "input_tokens",
                    "output_tokens",
                    "cache_creation_input_tokens",
                    "cache_read_input_tokens"
                ]
                .compactMap { number(usage[$0]) }
                .reduce(Int64(0), saturatingAdd)

                // Streaming snapshots repeat a message with growing usage, sometimes at new timestamps.
                let previous = seenMessages[identity] ?? 0
                seenMessages[identity] = max(previous, tokens)
                todayTokens = saturatingAdd(todayTokens, max(0, tokens - previous))
            }
        }

        return ClaudeLocalTokenUsage(
            todayTokens: todayTokens,
            updatedAt: now
        )
    }

    static func projectsURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        let configured = environment["CLAUDE_CONFIG_DIR"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        return (configured ?? home.appendingPathComponent(".claude", isDirectory: true))
            .appendingPathComponent("projects", isDirectory: true)
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
        let parsed: Int64?
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            parsed = Int64(number.stringValue)
        } else if let string = value as? String { parsed = Int64(string) }
        else { parsed = nil }
        return parsed.flatMap { $0 >= 0 ? $0 : nil }
    }

    private static func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
        left > Int64.max - right ? Int64.max : left + right
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
