import Foundation

enum BrowserSession {
    static let loginURL = URL(string: "https://claude.ai/login")!

    static func needsExternalBrowser(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "accounts.google.com" || host.hasSuffix(".accounts.google.com")
    }

    /// Accept only a Claude sessionKey, never a pasted cURL request or unrelated browser cookies.
    static func cookie(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.hasPrefix("sessionKey=") ? String(trimmed.dropFirst("sessionKey=".count)) : trimmed
        guard value.hasPrefix("sk-ant-sid"), (30...4096).contains(value.utf8.count),
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        return "sessionKey=" + value
    }
}
