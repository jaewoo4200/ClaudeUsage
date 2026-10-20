import SwiftUI
import UserNotifications

struct NotificationSettingsRow: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var theme: ThemeStore
    @ObservedObject private var notifications: UsageNotifications
    @ObservedObject private var updates = UpdateChecker.shared

    @MainActor init(notifications: UsageNotifications? = nil) {
        self.notifications = notifications ?? .shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("notifications_usage".l, isOn: notificationBinding(\.usageAlertsEnabled))
            Toggle("notifications_reset".l, isOn: notificationBinding(\.resetAlertsEnabled))
            Toggle("notifications_connection".l, isOn: notificationBinding(\.connectionAlertsEnabled))
            HStack(alignment: .top) {
                Text(permissionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.current.tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if notifications.isRequestingAuthorization || notifications.isSendingTest {
                    ProgressView().controlSize(.small)
                }
            }
            HStack {
                if notifications.authorization == .notDetermined {
                    Button { Task { await notifications.requestAuthorization() } } label: {
                        Label("notifications_request".l, systemImage: "bell")
                    }
                    .disabled(notifications.isRequestingAuthorization || notifications.isSendingTest)
                }
                Button { Task { await notifications.sendTest() } } label: {
                    Label("notifications_test".l, systemImage: "bell.badge")
                }
                .disabled(notifications.isRequestingAuthorization || notifications.isSendingTest
                          || notifications.authorization == .denied)
            }
            Button("notifications_open_settings".l) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
            if let error = notifications.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(theme.current.tokens.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message = notifications.testMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(theme.current.tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle("updates_automatic".l, isOn: $settings.automaticUpdateChecks)
                .onChange(of: settings.automaticUpdateChecks) { enabled in
                    if enabled { Task { await updates.check(manual: false) } }
                }
            HStack {
                if updates.isChecking { ProgressView().controlSize(.small) }
                Text(updates.status).font(.system(size: 11)).foregroundStyle(theme.current.tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { Task { await updates.check(manual: true) } } label: {
                    Label("updates_check".l, systemImage: "arrow.down.circle")
                }
                .disabled(updates.isChecking)
            }
            if let release = updates.availableRelease {
                Button { updates.present(release) } label: {
                    Label(String(format: "updates_available".l, release.tagName), systemImage: "shippingbox")
                }
            }
        }
        .font(.system(size: 12))
        .toggleStyle(.switch)
        .padding(12)
        .background(theme.current.tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task { await notifications.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await notifications.refreshAuthorization() }
        }
    }

    private func notificationBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { enabled in
            settings[keyPath: keyPath] = enabled
            if enabled { Task { await notifications.requestAuthorization() } }
        })
    }

    private var permissionLabel: String {
        guard notifications.authorizationChecked else { return "notifications_checking".l }
        switch notifications.authorization {
        case .authorized, .provisional:
            return (notifications.alertsEnabled ? "notifications_allowed" : "notifications_banners_off").l
        case .denied: return "notifications_denied".l
        default: return "notifications_not_requested".l
        }
    }
}
