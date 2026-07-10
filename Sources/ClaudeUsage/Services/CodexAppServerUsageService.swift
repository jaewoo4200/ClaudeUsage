import Foundation

enum CodexAppServerUsageError: Error, Equatable {
    case unavailable
    case timeout
    case rpc(String)
    case decode
}

enum CodexAppServerUsageService {
    static func hasAvailableExecutable() -> Bool {
        executableURL() != nil
    }

    static func fetchUsage() async throws -> OpenAIUsageData {
        guard let executableURL = executableURL() else { throw CodexAppServerUsageError.unavailable }
        let response = try await CodexRPCSession.run(executableURL: executableURL)
        return makeUsageData(rateLimits: response.rateLimits, tokenUsage: response.tokenUsage)
    }

    static func decodeFixture(rateLimitsJSON: Data, tokenUsageJSON: Data?) throws -> OpenAIUsageData {
        let decoder = JSONDecoder()
        let rateLimits = try decoder.decode(CodexRateLimitsResult.self, from: rateLimitsJSON)
        let tokenUsage = try tokenUsageJSON.map { try decoder.decode(CodexTokenUsageResult.self, from: $0) }
        return makeUsageData(rateLimits: rateLimits, tokenUsage: tokenUsage)
    }

    private static func makeUsageData(
        rateLimits: CodexRateLimitsResult,
        tokenUsage: CodexTokenUsageResult?
    ) -> OpenAIUsageData {
        let indexed = rateLimits.rateLimitsByLimitID ?? [:]
        let standard = rateLimits.rateLimits
            ?? indexed["codex"]
            ?? indexed.values.first { $0.limitName == nil }

        var codeReview: OpenAIRateLimit?
        var additional: [OpenAIAdditionalRateLimit] = []

        for (limitID, limit) in indexed.sorted(by: { $0.key < $1.key }) {
            if limitID == standard?.limitID || (limitID == "codex" && limit.limitName == nil) {
                continue
            }
            let normalized = "\(limitID) \(limit.limitName ?? "")".lowercased()
            if normalized.contains("code_review") || normalized.contains("code review") {
                codeReview = limit.openAIRateLimit
                continue
            }
            additional.append(
                OpenAIAdditionalRateLimit(
                    limitName: limit.limitName,
                    meteredFeature: limitID,
                    rateLimit: limit.openAIRateLimit
                )
            )
        }

        let activity = tokenUsage.map { result in
            OpenAITokenActivity(
                summary: result.summary.map {
                    OpenAITokenUsageSummary(
                        lifetimeTokens: $0.lifetimeTokens,
                        peakDailyTokens: $0.peakDailyTokens,
                        longestRunningTurnSeconds: $0.longestRunningTurnSeconds,
                        currentStreakDays: $0.currentStreakDays,
                        longestStreakDays: $0.longestStreakDays
                    )
                },
                dailyBuckets: result.dailyUsageBuckets.map {
                    OpenAITokenDailyBucket(startDate: $0.startDate, tokens: $0.tokens)
                }
            )
        }

        return OpenAIUsageData(
            planType: standard?.planType,
            rateLimit: standard?.openAIRateLimit,
            codeReviewRateLimit: codeReview,
            additionalRateLimits: additional,
            tokenActivity: activity,
            rateLimitResetCredits: rateLimits.rateLimitResetCredits.map { resetCredits in
                OpenAIRateLimitResetCredits(
                    availableCount: resetCredits.availableCount,
                    credits: resetCredits.credits.map { credit in
                        OpenAIRateLimitResetCredit(
                            id: credit.id,
                            resetType: credit.resetType,
                            status: credit.status,
                            grantedAt: credit.grantedAt.map {
                                Date(timeIntervalSince1970: TimeInterval($0))
                            },
                            expiresAt: credit.expiresAt.map {
                                Date(timeIntervalSince1970: TimeInterval($0))
                            },
                            title: credit.title,
                            description: credit.description
                        )
                    }
                )
            }
        )
    }

    private static func executableURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }
}

private struct CodexRPCUsageResponse {
    let rateLimits: CodexRateLimitsResult
    let tokenUsage: CodexTokenUsageResult?
}

private final class CodexRPCSession: @unchecked Sendable {
    private let executableURL: URL
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let lock = NSLock()
    private var buffer = Data()
    private var continuation: CheckedContinuation<CodexRPCUsageResponse, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var isFinished = false
    private var didInitialize = false
    private var rateLimits: CodexRateLimitsResult?
    private var tokenUsage: CodexTokenUsageResult?
    private var tokenUsageCompleted = false

    private init(executableURL: URL) {
        self.executableURL = executableURL
    }

    static func run(executableURL: URL) async throws -> CodexRPCUsageResponse {
        try await withCheckedThrowingContinuation { continuation in
            let session = CodexRPCSession(executableURL: executableURL)
            session.start(continuation: continuation)
        }
    }

    private func start(continuation: CheckedContinuation<CodexRPCUsageResponse, Error>) {
        self.continuation = continuation
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            if data.isEmpty {
                finishIfIncomplete(error: CodexAppServerUsageError.rpc("app-server closed"))
            } else {
                consume(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [self] _ in
            finishIfIncomplete(error: CodexAppServerUsageError.rpc("app-server exited"))
        }

        do {
            try process.run()
        } catch {
            finish(.failure(CodexAppServerUsageError.unavailable))
            return
        }

        send(
            """
            {"method":"initialize","id":0,"params":{"clientInfo":{"name":"claude_usage","title":"ClaudeUsage","version":"1.0"},"capabilities":{}}}
            """
        )

        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(CodexAppServerUsageError.timeout))
        }
        timeoutWorkItem = timeout
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: timeout)
    }

    private func consume(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [Data] = []
        while let newline = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<newline.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newline.lowerBound)
            if !line.isEmpty { lines.append(line) }
        }
        lock.unlock()

        for line in lines {
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = (object["id"] as? NSNumber)?.intValue else { return }

        if id == 0 {
            lock.lock()
            let shouldInitialize = !didInitialize
            didInitialize = true
            lock.unlock()
            if shouldInitialize {
                send("{\"method\":\"initialized\",\"params\":{}}")
                send("{\"method\":\"account/rateLimits/read\",\"id\":7}")
                send("{\"method\":\"account/usage/read\",\"id\":8}")
            }
            return
        }

        if id == 7 {
            do {
                let response = try JSONDecoder().decode(RPCResponse<CodexRateLimitsResult>.self, from: data)
                if let error = response.error {
                    finish(.failure(CodexAppServerUsageError.rpc(error.message)))
                    return
                }
                guard let result = response.result else {
                    finish(.failure(CodexAppServerUsageError.decode))
                    return
                }
                lock.lock()
                rateLimits = result
                let ready = tokenUsageCompleted
                lock.unlock()
                if ready { finishSuccessIfReady() }
            } catch {
                finish(.failure(CodexAppServerUsageError.decode))
            }
            return
        }

        if id == 8 {
            let response = try? JSONDecoder().decode(RPCResponse<CodexTokenUsageResult>.self, from: data)
            lock.lock()
            tokenUsage = response?.result
            tokenUsageCompleted = true
            let ready = rateLimits != nil
            lock.unlock()
            if ready { finishSuccessIfReady() }
        }
    }

    private func finishSuccessIfReady() {
        lock.lock()
        let rateLimits = self.rateLimits
        let tokenUsage = self.tokenUsage
        lock.unlock()
        guard let rateLimits else { return }
        finish(.success(CodexRPCUsageResponse(rateLimits: rateLimits, tokenUsage: tokenUsage)))
    }

    private func send(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        inputPipe.fileHandleForWriting.write(data)
    }

    private func finishIfIncomplete(error: Error) {
        lock.lock()
        let finished = isFinished
        lock.unlock()
        if !finished { finish(.failure(error)) }
    }

    private func finish(_ result: Result<CodexRPCUsageResponse, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }
        isFinished = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        timeoutWorkItem?.cancel()
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        continuation?.resume(with: result)
    }
}

private struct RPCResponse<ResultType: Decodable>: Decodable {
    let result: ResultType?
    let error: RPCErrorPayload?
}

private struct RPCErrorPayload: Decodable {
    let message: String
}

struct CodexRateLimitsResult: Decodable {
    let rateLimits: CodexRateLimit?
    let rateLimitsByLimitID: [String: CodexRateLimit]?
    let rateLimitResetCredits: CodexRateLimitResetCredits?

    enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
        case rateLimitResetCredits
    }
}

struct CodexRateLimitResetCredits: Decodable {
    let availableCount: Int
    let credits: [CodexRateLimitResetCredit]
}

struct CodexRateLimitResetCredit: Decodable {
    let id: String
    let resetType: String?
    let status: String
    let grantedAt: Int?
    let expiresAt: Int?
    let title: String?
    let description: String?
}

struct CodexRateLimit: Decodable {
    let limitID: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let planType: String?

    enum CodingKeys: String, CodingKey {
        case limitID = "limitId"
        case limitName
        case primary
        case secondary
        case planType
    }

    var openAIRateLimit: OpenAIRateLimit {
        OpenAIRateLimit(
            primaryWindow: primary?.openAIWindow,
            secondaryWindow: secondary?.openAIWindow
        )
    }
}

struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMinutes: Int?
    let resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent
        case windowDurationMinutes = "windowDurationMins"
        case resetsAt
    }

    var openAIWindow: OpenAIUsageWindow {
        OpenAIUsageWindow(
            usedPercent: usedPercent,
            resetAt: resetsAt,
            resetAfterSeconds: nil,
            limitWindowSeconds: windowDurationMinutes.map { $0 * 60 }
        )
    }
}

struct CodexTokenUsageResult: Decodable {
    let summary: CodexTokenUsageSummary?
    let dailyUsageBuckets: [CodexTokenDailyBucket]
}

struct CodexTokenUsageSummary: Decodable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int?
    let longestStreakDays: Int?

    enum CodingKeys: String, CodingKey {
        case lifetimeTokens
        case peakDailyTokens
        case longestRunningTurnSeconds = "longestRunningTurnSec"
        case currentStreakDays
        case longestStreakDays
    }
}

struct CodexTokenDailyBucket: Decodable {
    let startDate: String
    let tokens: Int64
}
