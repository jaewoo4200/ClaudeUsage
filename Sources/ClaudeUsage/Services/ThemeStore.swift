import SwiftUI
import Combine

enum ThemeKind: String, CaseIterable, Codable, Identifiable {
    case daangn
    case toss
    case hybrid
    case donut
    case halo
    case aura

    var id: String { rawValue }
    var isLegacy: Bool { Self.legacyThemes.contains(self) }
    static let legacyThemes: [Self] = [.daangn, .toss, .hybrid]
    static let gaugeThemes: [Self] = [.donut, .halo, .aura]

    @MainActor
    var displayName: String {
        switch self {
        case .daangn: return "theme_daangn".l
        case .toss: return "theme_toss".l
        case .hybrid: return "theme_hybrid".l
        case .donut: return "theme_donut".l
        case .halo: return "theme_halo".l
        case .aura: return "theme_aura".l
        }
    }

    @MainActor
    var subtitle: String {
        switch self {
        case .daangn: return "theme_daangn_sub".l
        case .toss: return "theme_toss_sub".l
        case .hybrid: return "theme_hybrid_sub".l
        case .donut: return "theme_donut_sub".l
        case .halo: return "theme_halo_sub".l
        case .aura: return "theme_aura_sub".l
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    static let themeChanged = Notification.Name("themeChanged")
    private let key = "selectedTheme"

    @Published var current: ThemeKind {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: key)
            if oldValue != current {
                NotificationCenter.default.post(name: Self.themeChanged, object: current)
            }
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "selectedTheme"),
           let theme = ThemeKind(rawValue: raw) {
            self.current = theme
        } else {
            self.current = .daangn
        }
    }
}
