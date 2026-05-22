import SwiftUI
import Combine

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let widgetAlwaysOnTopChanged = Notification.Name("widgetAlwaysOnTopChanged")

    private let key = "widgetAlwaysOnTop"

    @Published var widgetAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(widgetAlwaysOnTop, forKey: key)
            NotificationCenter.default.post(name: Self.widgetAlwaysOnTopChanged, object: nil)
        }
    }

    init() {
        // default: true (항상 위)
        if UserDefaults.standard.object(forKey: key) == nil {
            self.widgetAlwaysOnTop = true
        } else {
            self.widgetAlwaysOnTop = UserDefaults.standard.bool(forKey: key)
        }
    }
}
