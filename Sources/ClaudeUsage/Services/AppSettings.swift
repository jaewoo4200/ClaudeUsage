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

enum WidgetLayoutMode: String, CaseIterable, Codable, Identifiable {
    case stacked
    case horizontal
    case paged
    case separate

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .stacked: return "widget_layout_stacked".l
        case .horizontal: return "widget_layout_horizontal".l
        case .paged: return "widget_layout_paged".l
        case .separate: return "widget_layout_separate".l
        }
    }

    @MainActor
    var descriptionText: String {
        switch self {
        case .stacked: return "widget_layout_stacked_desc".l
        case .horizontal: return "widget_layout_horizontal_desc".l
        case .paged: return "widget_layout_paged_desc".l
        case .separate: return "widget_layout_separate_desc".l
        }
    }

    var systemSymbol: String {
        switch self {
        case .stacked: return "rectangle.split.1x2"
        case .horizontal: return "rectangle.split.2x1"
        case .paged: return "arrow.left.arrow.right"
        case .separate: return "rectangle.on.rectangle.angled"
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let widgetAlwaysOnTopChanged = Notification.Name("widgetAlwaysOnTopChanged")
    static let widgetConfigurationChanged = Notification.Name("widgetConfigurationChanged")
    static let appearanceChanged = Notification.Name("appearanceChanged")

    private let topKey = "widgetAlwaysOnTop"
    private let apprKey = "appearanceMode"
    private let petKey = "usagePetEnabled"
    private let historyKey = "usageHistoryEnabled"
    private let widgetLayoutKey = "widgetLayoutMode"
    private let separateClaudeKey = "separateClaudeWidgetEnabled"
    private let separateOpenAIKey = "separateOpenAIWidgetEnabled"
    private let showOpenAISparkKey = "showOpenAISparkLimits"

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

    @Published var usagePetEnabled: Bool {
        didSet { UserDefaults.standard.set(usagePetEnabled, forKey: petKey) }
    }

    @Published var usageHistoryEnabled: Bool {
        didSet { UserDefaults.standard.set(usageHistoryEnabled, forKey: historyKey) }
    }

    @Published var widgetLayoutMode: WidgetLayoutMode {
        didSet {
            UserDefaults.standard.set(widgetLayoutMode.rawValue, forKey: widgetLayoutKey)
            NotificationCenter.default.post(name: Self.widgetConfigurationChanged, object: nil)
        }
    }

    @Published var separateClaudeWidgetEnabled: Bool {
        didSet {
            UserDefaults.standard.set(separateClaudeWidgetEnabled, forKey: separateClaudeKey)
            NotificationCenter.default.post(name: Self.widgetConfigurationChanged, object: nil)
        }
    }

    @Published var separateOpenAIWidgetEnabled: Bool {
        didSet {
            UserDefaults.standard.set(separateOpenAIWidgetEnabled, forKey: separateOpenAIKey)
            NotificationCenter.default.post(name: Self.widgetConfigurationChanged, object: nil)
        }
    }

    @Published var showOpenAISparkLimits: Bool {
        didSet { UserDefaults.standard.set(showOpenAISparkLimits, forKey: showOpenAISparkKey) }
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
        if UserDefaults.standard.object(forKey: petKey) == nil {
            self.usagePetEnabled = true
        } else {
            self.usagePetEnabled = UserDefaults.standard.bool(forKey: petKey)
        }
        if UserDefaults.standard.object(forKey: historyKey) == nil {
            self.usageHistoryEnabled = false
        } else {
            self.usageHistoryEnabled = UserDefaults.standard.bool(forKey: historyKey)
        }
        if let raw = UserDefaults.standard.string(forKey: widgetLayoutKey),
           let mode = WidgetLayoutMode(rawValue: raw) {
            self.widgetLayoutMode = mode
        } else {
            self.widgetLayoutMode = .stacked
        }

        let storedClaude = UserDefaults.standard.object(forKey: separateClaudeKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: separateClaudeKey)
        let storedOpenAI = UserDefaults.standard.object(forKey: separateOpenAIKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: separateOpenAIKey)
        self.separateClaudeWidgetEnabled = storedClaude || !storedOpenAI
        self.separateOpenAIWidgetEnabled = storedOpenAI

        if UserDefaults.standard.object(forKey: showOpenAISparkKey) == nil {
            self.showOpenAISparkLimits = false
        } else {
            self.showOpenAISparkLimits = UserDefaults.standard.bool(forKey: showOpenAISparkKey)
        }
    }

    /// 앱 전체 appearance를 강제 적용 (nil이면 시스템 따라감)
    func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }
}
