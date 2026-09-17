import Foundation
import Combine

@MainActor
final class UsageHistoryStore: ObservableObject {
    static let shared = UsageHistoryStore()

    @Published private(set) var samples: [UsageHistorySample]

    private let fileURL: URL
    private let minimumSampleInterval: TimeInterval
    private let retentionInterval: TimeInterval
    private let maximumSamples: Int

    init(
        fileURL: URL? = nil,
        minimumSampleInterval: TimeInterval = 5 * 60,
        retentionInterval: TimeInterval = 14 * 24 * 60 * 60,
        maximumSamples: Int = 4_200
    ) {
        self.fileURL = fileURL ?? UsageHistoryStore.defaultFileURL
        self.minimumSampleInterval = minimumSampleInterval
        self.retentionInterval = retentionInterval
        self.maximumSamples = maximumSamples
        self.samples = Self.load(from: fileURL ?? UsageHistoryStore.defaultFileURL)
    }

    var hasSamples: Bool { !samples.isEmpty }

    func record(_ snapshot: UsageHistorySnapshot, at timestamp: Date = Date(), force: Bool = false) {
        guard snapshot.hasUsage else { return }
        let sample = UsageHistorySample(timestamp: timestamp, snapshot: snapshot)

        if let last = samples.last, !force {
            let elapsed = timestamp.timeIntervalSince(last.timestamp)
            let resetDetected = (last.snapshot.pressure ?? 0) - (sample.snapshot.pressure ?? 0) >= 15
            guard elapsed >= minimumSampleInterval || resetDetected else { return }
        }

        samples.append(sample)
        prune(now: timestamp)
        persist()
    }

    func clear() {
        samples = []
        try? FileManager.default.removeItem(at: fileURL)
    }

    func trend(now: Date = Date(), window: TimeInterval = 60 * 60) -> UsageTrend {
        let cutoff = now.addingTimeInterval(-window)
        var recent = samples.filter { $0.timestamp >= cutoff && $0.timestamp <= now }
        guard !recent.isEmpty else { return .empty }
        recent.sort { $0.timestamp < $1.timestamp }

        var latestResetDate: Date?
        var segmentStart = 0
        if recent.count > 1 {
            for index in 1..<recent.count {
                guard let previous = recent[index - 1].snapshot.pressure,
                      let current = recent[index].snapshot.pressure else { continue }
                if previous - current >= 15 {
                    latestResetDate = recent[index].timestamp
                    segmentStart = index
                }
            }
        }

        let segment = Array(recent[segmentStart...])
        let pressureSamples = segment.compactMap { sample -> (Date, Double)? in
            guard let pressure = sample.snapshot.pressure else { return nil }
            return (sample.timestamp, pressure)
        }
        let points = Array(pressureSamples.suffix(24).map(\.1))

        var deltaPercent: Double?
        var percentPerHour: Double?
        if let first = pressureSamples.first, let last = pressureSamples.last {
            let duration = last.0.timeIntervalSince(first.0)
            if duration >= 60 {
                let delta = max(0, last.1 - first.1)
                deltaPercent = delta
                percentPerHour = min(100, delta / (duration / 3_600))
            }
        }

        let tokenDelta = Self.tokenDelta(in: segment)

        return UsageTrend(
            points: points,
            deltaPercent: deltaPercent,
            percentPerHour: percentPerHour,
            recentTokenDelta: tokenDelta,
            resetDetected: latestResetDate.map { now.timeIntervalSince($0) <= 30 * 60 } ?? false
        )
    }

    private static func tokenDelta(in samples: [UsageHistorySample]) -> Int64? {
        guard let first = samples.first, let last = samples.last,
              Calendar.current.isDate(first.timestamp, inSameDayAs: last.timestamp) else { return nil }
        let providers: [KeyPath<UsageHistorySample, Int64?>] = [\.claudeTodayTokens, \.openAITodayTokens]
        var delta: Int64 = 0
        var hasProvider = false
        for provider in providers {
            let values = samples.compactMap { $0[keyPath: provider] }
            if values.isEmpty { continue }
            // A newly reported daily total is not an hour's worth of new usage.
            guard values.count == samples.count, values.allSatisfy({ $0 >= 0 }),
                  zip(values, values.dropFirst()).allSatisfy({ $0.0 <= $0.1 }) else { return nil }
            delta += values.last! - values.first!
            hasProvider = true
        }
        return hasProvider ? delta : nil
    }

    private func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-retentionInterval)
        samples.removeAll { $0.timestamp < cutoff }
        if samples.count > maximumSamples {
            samples.removeFirst(samples.count - maximumSamples)
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(samples)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[History] save failed: \(error.localizedDescription)")
            #endif
        }
    }

    private static func load(from url: URL) -> [UsageHistorySample] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([UsageHistorySample].self, from: data) else {
            return []
        }
        // Older versions recorded the composition payload as a zero-percent model limit.
        return decoded.map { UsageHistorySample(timestamp: $0.timestamp, snapshot: $0.snapshot) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("ClaudeUsage", isDirectory: true)
            .appendingPathComponent("usage-history.json")
    }
}
