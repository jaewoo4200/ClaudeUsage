import SwiftUI
import Combine

enum ThemeKind: String, CaseIterable, Codable, Identifiable {
    case daangn
    case toss
    case hybrid

    var id: String { rawValue }

    @MainActor
    var displayName: String {
        switch self {
        case .daangn: return "theme_daangn".l
        case .toss: return "theme_toss".l
        case .hybrid: return "theme_hybrid".l
        }
    }

    @MainActor
    var subtitle: String {
        switch self {
        case .daangn: return "theme_daangn_sub".l
        case .toss: return "theme_toss_sub".l
        case .hybrid: return "theme_hybrid_sub".l
        }
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    private let key = "selectedTheme"

    @Published var current: ThemeKind {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: key)
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
