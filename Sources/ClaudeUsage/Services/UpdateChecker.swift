import AppKit
import Combine

struct ReleaseVersion: Comparable, Equatable {
    let parts: [Int]

    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) }) else { return nil }
        let numbers = pieces.compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        parts = numbers
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
}

struct PublishedRelease: Decodable, Equatable {
    struct Asset: Decodable, Equatable { let name: String; let size: Int }
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", htmlURL = "html_url", draft, prerelease, assets
    }

    func isAvailable(after current: String) -> Bool {
        guard !draft, !prerelease,
              let version = ReleaseVersion(tagName), let installed = ReleaseVersion(current), version > installed,
              htmlURL.scheme == "https", htmlURL.host == "github.com", htmlURL.user == nil, htmlURL.password == nil,
              htmlURL.port == nil,
              htmlURL.path == "/jaewoo4200/ClaudeUsage/releases/tag/\(tagName)",
              htmlURL.query == nil, htmlURL.fragment == nil else { return false }
        let plainVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        // A source-only release or a Windows-only artifact is not a macOS update.
        return assets.contains { $0.name == "ClaudeUsage-\(plainVersion).dmg" && $0.size > 0 }
    }
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    @Published private(set) var availableRelease: PublishedRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var status = ""
    private var task: Task<Void, Never>?
    private var isPresenting = false
    private let defaults: UserDefaults
    private let session: URLSession
    private let currentVersion: String
    static let endpoint = URL(string: "https://api.github.com/repos/jaewoo4200/ClaudeUsage/releases/latest")!

    init(defaults: UserDefaults = .standard, session: URLSession? = nil, currentVersion: String? = nil) {
        self.defaults = defaults
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        self.session = session ?? URLSession(configuration: config)
        self.currentVersion = currentVersion ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check(manual: false)
                try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)
            }
        }
    }

    func check(manual: Bool) async {
        guard !isChecking else { return }
        if !manual {
            guard AppSettings.shared.automaticUpdateChecks else { return }
            if let last = defaults.object(forKey: "updateLastAttempt") as? Date,
               Date().timeIntervalSince(last) < 24 * 60 * 60 { return }
        }
        isChecking = true
        status = "updates_checking".l
        defer { isChecking = false }
        defaults.set(Date(), forKey: "updateLastAttempt")
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeUsage/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = "updates_error".l
                return
            }
            let release = try JSONDecoder().decode(PublishedRelease.self, from: data)
            guard release.isAvailable(after: currentVersion) else {
                availableRelease = nil
                status = "updates_current".l
                return
            }
            availableRelease = release
            status = String(format: "updates_available".l, release.tagName)
            if manual || (AppSettings.shared.automaticUpdateChecks
                          && defaults.string(forKey: "updatePromptedVersion") != release.tagName) {
                present(release)
            }
        } catch {
            status = "updates_error".l
        }
    }

    func present(_ release: PublishedRelease) {
        guard !isPresenting else { return }
        isPresenting = true
        defer { isPresenting = false }
        defaults.set(release.tagName, forKey: "updatePromptedVersion")
        let alert = NSAlert()
        alert.messageText = String(format: "updates_available".l, release.tagName)
        alert.informativeText = String(format: "updates_prompt".l, currentVersion, release.tagName)
        alert.addButton(withTitle: "updates_open_release".l)
        alert.addButton(withTitle: "updates_later".l)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.htmlURL) }
    }
}
