import Foundation

enum OpenAIUsageError: Error, Equatable {
    case notConnected
    case authExpired
    case network(String)
    case decode
}

enum OpenAIUsageService {
    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static func hasLocalSession() -> Bool {
        (try? loadCredentials()) != nil
    }

    static func fetchUsage() async throws -> OpenAIUsageData {
        let credentials = try loadCredentials()
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeUsage/\(appVersion)", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenAIUsageError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIUsageError.network("invalid response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OpenAIUsageError.authExpired
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIUsageError.network("HTTP \(http.statusCode)")
        }

        do {
            return try JSONDecoder().decode(OpenAIUsageData.self, from: data)
        } catch {
            throw OpenAIUsageError.decode
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private static func loadCredentials() throws -> Credentials {
        let url = authFileURL()
        guard let data = try? Data(contentsOf: url),
              let auth = try? JSONDecoder().decode(CodexAuthFile.self, from: data),
              auth.authMode?.lowercased() == "chatgpt",
              let accessToken = auth.tokens?.accessToken,
              !accessToken.isEmpty else {
            throw OpenAIUsageError.notConnected
        }
        return Credentials(accessToken: accessToken, accountID: auth.tokens?.accountID)
    }

    private static func authFileURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    private struct Credentials {
        let accessToken: String
        let accountID: String?
    }

    private struct CodexAuthFile: Decodable {
        let authMode: String?
        let tokens: Tokens?

        enum CodingKeys: String, CodingKey {
            case authMode = "auth_mode"
            case tokens
        }
    }

    private struct Tokens: Decodable {
        let accessToken: String?
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
        }
    }
}
