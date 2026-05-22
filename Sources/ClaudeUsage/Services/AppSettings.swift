import SwiftUI
import AppKit
import Combine

enum AppearanceMode: String, CaseIterable, Codable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .auto: return "appearance_auto".l
        case .light: return "appearance_light".l
        case .dark: return "appearance_dark".l
        }
    }

    var systemSymbol: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    /// nil이면 시스템 따라감 (auto)
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let widgetAlwaysOnTopChanged = Notification.Name("widgetAlwaysOnTopChanged")
    static let appearanceChanged = Notification.Name("appearanceChanged")

    private let topKey = "widgetAlwaysOnTop"
    private let apprKey = "appearanceMode"

    @Published var widgetAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(widgetAlwaysOnTop, forKey: topKey)
            NotificationCenter.default.post(name: Self.widgetAlwaysOnTopChanged, object: nil)
        }
    }

    @Published var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: apprKey)
            applyAppearance()
            NotificationCenter.default.post(name: Self.appearanceChanged, object: nil)
        }
    }

    init() {
        // widget always-on-top
        if UserDefaults.standard.object(forKey: "widgetAlwaysOnTop") == nil {
            self.widgetAlwaysOnTop = true
        } else {
            self.widgetAlwaysOnTop = UserDefaults.standard.bool(forKey: "widgetAlwaysOnTop")
        }
        // appearance
        if let raw = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: raw) {
            self.appearance = mode
        } else {
            self.appearance = .auto
        }
    }

    /// 앱 전체 appearance를 강제 적용 (nil이면 시스템 따라감)
    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }
}
