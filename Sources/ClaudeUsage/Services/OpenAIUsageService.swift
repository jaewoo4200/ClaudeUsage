import Foundation

enum OpenAIUsageError: Error, Equatable {
    case notConnected
    case authExpired
    case network(String)
    case decode
}

enum OpenAIUsageService {
    static func hasLocalSession() -> Bool {
        CodexAppServerUsageService.hasAvailableExecutable()
    }

    static func fetchUsage() async throws -> OpenAIUsageData {
        guard CodexAppServerUsageService.hasAvailableExecutable() else {
            throw OpenAIUsageError.notConnected
        }
        do {
            return try await CodexAppServerUsageService.fetchUsage()
        } catch CodexAppServerUsageError.unavailable {
            throw OpenAIUsageError.notConnected
        } catch CodexAppServerUsageError.timeout {
            throw OpenAIUsageError.network("Codex app-server timed out")
        } catch CodexAppServerUsageError.decode {
            throw OpenAIUsageError.decode
        } catch CodexAppServerUsageError.rpc(let message) {
            let normalized = message.lowercased()
            if normalized.contains("auth") || normalized.contains("login") {
                throw OpenAIUsageError.authExpired
            }
            throw OpenAIUsageError.network(message)
        } catch {
            throw OpenAIUsageError.network(error.localizedDescription)
        }
    }
}
