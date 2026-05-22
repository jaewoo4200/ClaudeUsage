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

    static func fetchSnapshot() async throws -> AccountSnapshot {
        guard let cookie = CookieStore.load() else { throw UsageError.noCookie }
        let org = try await fetchOrganization(cookie: cookie)
        let usage = try await fetchUsage(orgId: org.uuid, cookie: cookie)
        return AccountSnapshot(organization: org, usage: usage)
    }

    private static func fetchOrganization(cookie: String) async throws -> Organization {
        let url = URL(string: "\(baseURL)/api/organizations")!
        let (data, response) = try await request(url: url, cookie: cookie)
        try checkStatus(response: response)
        if let raw = String(data: data, encoding: .utf8) {
            print("[Usage] /organizations: \(raw.prefix(3000))")
            fflush(stdout)
        }
        let decoder = JSONDecoder()
        if let arr = try? decoder.decode([Organization].self, from: data), let first = arr.first {
            return first
        }
        if let single = try? decoder.decode(Organization.self, from: data) {
            return single
        }
        throw UsageError.decode
    }

    private static func fetchUsage(orgId: String, cookie: String) async throws -> UsageData {
        let url = URL(string: "\(baseURL)/api/organizations/\(orgId)/usage")!
        let (data, response) = try await request(url: url, cookie: cookie)
        try checkStatus(response: response)
        if let raw = String(data: data, encoding: .utf8) {
            print("[Usage] /usage RAW: \(raw)")
            fflush(stdout)
        }
        do {
            return try JSONDecoder().decode(UsageData.self, from: data)
        } catch {
            print("[Usage] decode error: \(error)")
            fflush(stdout)
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
            return try await URLSession.shared.data(for: req)
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
