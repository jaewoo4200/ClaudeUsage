import Foundation

enum UsageError: Error, Equatable {
    case noCookie
    case authExpired
    case network(String)
    case decode
}

enum UsageService {
    private static let baseURL = "https://claude.ai"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 20
        return URLSession(configuration: configuration, delegate: ClaudeUsageRedirectPolicy(), delegateQueue: nil)
    }()

    static func fetchSnapshot() async throws -> AccountSnapshot {
        guard let cookie = CookieStore.load() else { throw UsageError.noCookie }
        return try await fetchSnapshot(cookie: cookie)
    }

    static func fetchSnapshot(cookie: String) async throws -> AccountSnapshot {
        let org = try await fetchOrganization(cookie: cookie)
        let usage = try await fetchUsage(orgId: org.uuid, cookie: cookie)
        return AccountSnapshot(organization: org, usage: usage)
    }

    private static func fetchOrganization(cookie: String) async throws -> Organization {
        let url = URL(string: "\(baseURL)/api/organizations")!
        let (data, response) = try await request(url: url, cookie: cookie)
        try checkStatus(response: response)
        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("[Usage] /organizations: \(raw.prefix(3000))")
            fflush(stdout)
        }
        #endif
        return try selectOrganization(data: data, cookie: cookie)
    }

    static func selectOrganization(data: Data, cookie: String) throws -> Organization {
        let decoder = JSONDecoder()
        let organizations: [Organization]
        if let array = try? decoder.decode([Organization].self, from: data) { organizations = array }
        else if let single = try? decoder.decode(Organization.self, from: data) { organizations = [single] }
        else { throw UsageError.decode }
        let preferred = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("lastActiveOrg=") }.map { String($0.dropFirst("lastActiveOrg=".count)) }
        guard let selected = organizations.first(where: { $0.uuid == preferred })
            ?? organizations.first(where: { $0.capabilities?.contains(where: { $0.lowercased() == "chat" }) == true })
            ?? organizations.first else { throw UsageError.decode }
        return selected
    }

    private static func fetchUsage(orgId: String, cookie: String) async throws -> UsageData {
        let url = URL(string: "\(baseURL)/api/organizations/\(orgId)/usage")!
        let (data, response) = try await request(url: url, cookie: cookie)
        try checkStatus(response: response)
        #if DEBUG
        if let raw = String(data: data, encoding: .utf8) {
            print("[Usage] /usage RAW: \(raw)")
            fflush(stdout)
        }
        #endif
        do {
            return try UsageData.decode(from: data)
        } catch {
            #if DEBUG
            print("[Usage] decode error: \(error)")
            print("[Usage] raw response: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            fflush(stdout)
            #endif
            // Graceful fallback: 일부 필드만이라도 추출
            // 이미 UsageData의 모든 필드가 optional이라 여기 도달했다는 건
            // 응답 자체가 JSON 아니거나 최상위 구조가 다른 경우
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               !json.isEmpty {
                // 최소한 빈 UsageData라도 반환해서 "로그인 OK, 사용량은 표시 안됨" 상태 유지
                return try JSONDecoder().decode(UsageData.self, from: try JSONSerialization.data(withJSONObject: [:] as [String: Any]))
            }
            throw UsageError.decode
        }
    }

    private static func request(url: URL, cookie: String) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("\(baseURL)/", forHTTPHeaderField: "Referer")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")

        do {
            return try await session.data(for: req)
        } catch {
            throw UsageError.network(error.localizedDescription)
        }
    }

    private static func checkStatus(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw UsageError.network("invalid response") }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw UsageError.authExpired
        }
        guard (200..<300).contains(http.statusCode) else {
            throw UsageError.network("HTTP \(http.statusCode)")
        }
    }
}

final class ClaudeUsageRedirectPolicy: NSObject, URLSessionTaskDelegate {
    static func permits(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "claude.ai"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.permits(request.url) ? request : nil)
    }
}
