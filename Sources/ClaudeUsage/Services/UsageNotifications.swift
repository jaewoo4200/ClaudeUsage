import Foundation
import Combine
import UserNotifications
import AppKit
import OSLog

struct NotificationPermission {
    var authorization: UNAuthorizationStatus
    var alertsEnabled: Bool

}

@MainActor
protocol UsageNotificationClient {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate)
    func settings() async -> NotificationPermission
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

@MainActor
struct SystemUsageNotificationClient: UsageNotificationClient {
    func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {
        UNUserNotificationCenter.current().delegate = delegate
    }

    func settings() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermission(authorization: settings.authorizationStatus,
                                      alertsEnabled: settings.alertSetting == .enabled)
    }

    func requestAuthorization() async throws -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}

enum AlertProvider: String, Codable, CaseIterable {
    case claude, codex
    var title: String { self == .claude ? "Claude" : "Codex" }
}

struct UsageAlert: Equatable {
    enum Kind: String { case warning, critical, reset, login, connection }
    let kind: Kind
    let metric: String
    let utilization: Int
}

/// Only the last observation and delivered warning level are retained, not a usage history.
struct UsageAlertPolicy: Codable {
    struct Counter: Codable {
        var utilization: Double
        var resetsAt: Date?
        var observedAt: Date
        var notifiedLevel: Int
    }
    struct Failure: Codable {
        var count = 0
        var notifiedConnection = false
        var notifiedLogin = false
    }
    private(set) var counters: [String: Counter] = [:]
    private(set) var failures: [String: Failure] = [:]

    mutating func success(
        provider: AlertProvider, metrics: [UsageDisplayMetric], now: Date,
        usageEnabled: Bool, resetEnabled: Bool
    ) -> [UsageAlert] {
        failures.removeValue(forKey: provider.rawValue)
        let prefix = provider.rawValue + "/"
        let keys = Set(metrics.map { prefix + $0.id })
        counters = counters.filter { !$0.key.hasPrefix(prefix) || keys.contains($0.key) }
        var alerts: [UsageAlert] = []
        for metric in metrics where metric.utilization.isFinite && metric.utilization >= 0 {
            let key = prefix + metric.id
            let previous = counters[key]
            let newWindow: Bool
            if let oldDate = previous?.resetsAt, let newDate = metric.resetsAt {
                newWindow = newDate.timeIntervalSince(oldDate) > 300
                    && (oldDate <= now || metric.utilization < (previous?.utilization ?? 0))
            } else {
                newWindow = false
            }
            var level = newWindow ? 0 : (previous?.notifiedLevel ?? 0)
            if resetEnabled, newWindow, let previous,
               previous.utilization > 0, metric.utilization < previous.utilization,
               now.timeIntervalSince(previous.observedAt) < 2 * 3_600 {
                alerts.append(UsageAlert(kind: .reset, metric: metric.title, utilization: 0))
            }
            let currentLevel = metric.utilization >= 90 ? 90 : (metric.utilization >= 70 ? 70 : 0)
            if usageEnabled, currentLevel > level {
                alerts.append(UsageAlert(kind: currentLevel == 90 ? .critical : .warning,
                                         metric: metric.title,
                                         utilization: Int(min(100, metric.utilization).rounded())))
                level = currentLevel
            }
            counters[key] = Counter(utilization: metric.utilization, resetsAt: metric.resetsAt,
                                    observedAt: now, notifiedLevel: level)
        }
        return alerts
    }

    mutating func failure(provider: AlertProvider, loginRequired: Bool) -> [UsageAlert] {
        var state = failures[provider.rawValue] ?? Failure()
        defer { failures[provider.rawValue] = state }
        state.count = min(3, state.count + 1)
        if loginRequired, !state.notifiedLogin {
            state.notifiedLogin = true
            return [UsageAlert(kind: .login, metric: "", utilization: 0)]
        }
        if !loginRequired, state.count >= 3, !state.notifiedConnection, !state.notifiedLogin {
            state.notifiedConnection = true
            return [UsageAlert(kind: .connection, metric: "", utilization: 0)]
        }
        return []
    }

    mutating func forget(_ provider: AlertProvider) {
        counters = counters.filter { !$0.key.hasPrefix(provider.rawValue + "/") }
        failures.removeValue(forKey: provider.rawValue)
    }
}

@MainActor
final class UsageNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = UsageNotifications()
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var authorizationChecked = false
    @Published private(set) var alertsEnabled = false
    @Published private(set) var isRequestingAuthorization = false
    @Published private(set) var isSendingTest = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var testMessage: String?
    private let stateKey = "usageNotificationState.v1"
    private var policy: UsageAlertPolicy
    private let client: any UsageNotificationClient
    private let defaults: UserDefaults
    private static let logger = Logger(subsystem: "app.claudeusage", category: "Notifications")

    override convenience init() {
        self.init(client: SystemUsageNotificationClient(), defaults: .standard)
    }

    init(client: any UsageNotificationClient, defaults: UserDefaults) {
        self.client = client
        self.defaults = defaults
        policy = defaults.data(forKey: "usageNotificationState.v1")
            .flatMap { try? JSONDecoder().decode(UsageAlertPolicy.self, from: $0) } ?? UsageAlertPolicy()
        super.init()
    }

    func start() {
        client.setDelegate(self)
        Task { await refreshAuthorization() }
    }

    func refreshAuthorization() async {
        let permission = await client.settings()
        authorization = permission.authorization
        alertsEnabled = permission.alertsEnabled
        authorizationChecked = true
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard !isRequestingAuthorization else { return false }
        isRequestingAuthorization = true
        defer { isRequestingAuthorization = false }
        errorMessage = nil
        testMessage = nil
        await refreshAuthorization()
        if authorization == .authorized || authorization == .provisional { return true }
        guard authorization == .notDetermined else { return false }
        do {
            let granted = try await client.requestAuthorization()
            await refreshAuthorization()
            return granted && (authorization == .authorized || authorization == .provisional)
        } catch {
            await refreshAuthorization()
            record(error, messageKey: "notifications_permission_error")
            return false
        }
    }

    func success(provider: AlertProvider, metrics: [UsageDisplayMetric]) async {
        let settings = AppSettings.shared
        guard settings.usageAlertsEnabled || settings.resetAlertsEnabled || settings.connectionAlertsEnabled else { return }
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional else { return }
        guard isVisible(provider) else { return }
        let alerts = policy.success(provider: provider, metrics: metrics, now: Date(),
                                    usageEnabled: settings.usageAlertsEnabled, resetEnabled: settings.resetAlertsEnabled)
        if !(await deliver(alerts, provider: provider)) { policy.forget(provider) }
        persist()
    }

    func failure(provider: AlertProvider, loginRequired: Bool) async {
        guard AppSettings.shared.connectionAlertsEnabled, isVisible(provider) else { return }
        await refreshAuthorization()
        guard authorization == .authorized || authorization == .provisional, isVisible(provider) else { return }
        let alerts = policy.failure(provider: provider, loginRequired: loginRequired)
        if !(await deliver(alerts, provider: provider)) { policy.forget(provider) }
        persist()
    }

    func forgetHiddenProviders() {
        for provider in AlertProvider.allCases where !isVisible(provider) { policy.forget(provider) }
        persist()
    }

    func forget(_ provider: AlertProvider) {
        policy.forget(provider)
        persist()
    }

    func sendTest() async {
        guard !isSendingTest, !isRequestingAuthorization else { return }
        isSendingTest = true
        defer { isSendingTest = false }
        guard await requestAuthorization() else { return }
        if await enqueue(id: "notification-test-\(UUID().uuidString)", title: "ClaudeUsage",
                         body: "notifications_test_body".l) {
            testMessage = "notifications_test_sent".l
        }
    }

    private func isVisible(_ provider: AlertProvider) -> Bool {
        provider == .claude ? AppSettings.shared.showClaude : AppSettings.shared.showCodex
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(policy) { defaults.set(data, forKey: stateKey) }
    }

    private func deliver(_ alerts: [UsageAlert], provider: AlertProvider) async -> Bool {
        guard !alerts.isEmpty, isVisible(provider) else { return true }
        // One banner per provider/refresh, even when several model windows cross a threshold together.
        let body = alerts.prefix(4).map { alert -> String in
            switch alert.kind {
            case .warning, .critical:
                return String(format: "notifications_usage_body".l, alert.metric, alert.utilization)
            case .reset: return String(format: "notifications_reset_body".l, alert.metric)
            case .login: return "notifications_login_body".l
            case .connection: return "notifications_connection_body".l
            }
        }.joined(separator: "\n")
        return await enqueue(id: "usage-\(provider.rawValue)-\(UUID().uuidString)", title: provider.title, body: body)
    }

    private func enqueue(id: String, title: String, body: String) async -> Bool {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        do {
            try await client.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
            errorMessage = nil
            return true
        } catch {
            record(error, messageKey: "notifications_delivery_error")
            return false
        }
    }

    private func record(_ error: Error, messageKey: String) {
        let error = error as NSError
        Self.logger.error("Notification operation failed: \(error.domain, privacy: .public) code \(error.code)")
        errorMessage = "\(messageKey.l) (\(error.domain) \(error.code))"
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
