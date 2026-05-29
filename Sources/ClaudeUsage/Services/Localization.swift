import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case ko, en
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ko: return "한국어"
        case .en: return "English"
        }
    }
}

@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()
    private let key = "appLanguage"

    @Published var current: AppLanguage {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: key) }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: raw) {
            self.current = lang
        } else {
            // 시스템 locale에 따라 첫 설정
            let lang = Locale.current.language.languageCode?.identifier ?? "ko"
            self.current = lang.hasPrefix("ko") ? .ko : .en
        }
    }
}

// String을 key로 보고 dictionary lookup
extension String {
    @MainActor
    var l: String {
        L10n.t(self)
    }
}

enum L10n {
    @MainActor
    static func t(_ key: String) -> String {
        let lang = LanguageStore.shared.current
        return strings[key]?[lang] ?? key
    }

    static let strings: [String: [AppLanguage: String]] = [
        // ==== 메뉴바 라벨 ====
        "login": [.ko: "로그인", .en: "Sign in"],

        // ==== 드롭다운 헤더 ====
        "claude_usage": [.ko: "Claude 사용량", .en: "Claude Usage"],
        "logged_in": [.ko: "로그인됨", .en: "Signed in"],

        // ==== 사용량 카드 ====
        "five_hour": [.ko: "5시간", .en: "5-hour"],
        "seven_day": [.ko: "7일", .en: "7-day"],
        "claude_design": [.ko: "Claude Design", .en: "Claude Design"],

        // ==== 푸터 버튼 ====
        "show_widget": [.ko: "위젯 켜기", .en: "Show widget"],
        "hide_widget": [.ko: "위젯 숨기기", .en: "Hide widget"],
        "logout": [.ko: "로그아웃", .en: "Sign out"],

        // ==== 로그인 페이지 ====
        "please_login": [.ko: "Claude에 로그인해 주세요", .en: "Please sign in to Claude"],
        "login_desc": [.ko: "사용량을 보려면 claude.ai 계정이 필요해요.", .en: "You need a claude.ai account to see usage."],
        "login_action": [.ko: "로그인하기", .en: "Sign in"],
        "quit": [.ko: "종료", .en: "Quit"],

        // ==== 로딩 / 에러 ====
        "loading": [.ko: "불러오는 중…", .en: "Loading…"],
        "retry": [.ko: "다시 시도", .en: "Try again"],
        "load_failed": [.ko: "불러오기 실패", .en: "Load failed"],
        "login_required": [.ko: "메뉴바에서 로그인해 주세요", .en: "Please sign in from the menu bar"],
        "no_cookie": [.ko: "로그인이 필요해요", .en: "Sign-in required"],
        "session_expired": [.ko: "세션이 만료됐어요", .en: "Session expired"],
        "decode_failed": [.ko: "데이터를 읽지 못했어요", .en: "Couldn't read data"],
        "network_error_prefix": [.ko: "네트워크 오류: ", .en: "Network error: "],

        // ==== 설정 창 헤더 ====
        "settings_title": [.ko: "설정", .en: "Settings"],

        // ==== 설정 섹션 헤더 ====
        "section_theme": [.ko: "디자인 테마", .en: "Design Theme"],
        "section_widget": [.ko: "위젯", .en: "Widget"],
        "section_account": [.ko: "계정", .en: "Account"],
        "section_language": [.ko: "언어", .en: "Language"],

        // ==== 테마 ====
        "theme_daangn": [.ko: "당근 스타일", .en: "Daangn Style"],
        "theme_toss": [.ko: "토스 스타일", .en: "Toss Style"],
        "theme_hybrid": [.ko: "하이브리드", .en: "Hybrid"],
        "theme_daangn_sub": [.ko: "따뜻한 오렌지, 원형 그래프", .en: "Warm orange, ring graph"],
        "theme_toss_sub": [.ko: "정돈된 블루, 막대 그래프", .en: "Calm blue, bar graph"],
        "theme_hybrid_sub": [.ko: "미드나이트 + 그라데이션", .en: "Midnight + gradient"],

        // ==== 위젯 설정 ====
        "always_on_top": [.ko: "항상 위에 표시", .en: "Always on top"],
        "always_on_top_on_desc": [.ko: "다른 윈도우 위에 항상 떠 있어요", .en: "Stays above other windows"],
        "always_on_top_off_desc": [.ko: "다른 윈도우 아래로 들어갈 수 있어요", .en: "Can go behind other windows"],

        // ==== Appearance (다크/라이트) ====
        "section_appearance": [.ko: "화면 모드", .en: "Appearance"],
        "appearance_auto": [.ko: "자동", .en: "Auto"],
        "appearance_light": [.ko: "라이트", .en: "Light"],
        "appearance_dark": [.ko: "다크", .en: "Dark"],

        // ==== 위젯 헤더 ====
        "claude_short": [.ko: "Claude", .en: "Claude"],

        // ==== 코멘트 (당근 톤) ====
        "comment_relaxed": [.ko: "아직 여유로워요 🙂", .en: "Plenty of room 🙂"],
        "comment_moderate": [.ko: "적당히 쓰는 중이에요 😊", .en: "Pacing well 😊"],
        "comment_slow_down_week": [.ko: "조금만 아껴 써요 😯", .en: "Slow down a bit 😯"],
        "comment_slow_down_window": [.ko: "속도 조절이 필요해요 ⚡", .en: "Take it easy ⚡"],
        "comment_almost_done_week": [.ko: "이번 주 거의 다 썼어요 🥲", .en: "Almost out this week 🥲"],
        "comment_almost_done_window": [.ko: "이번 윈도우 거의 다 썼어요 🚨", .en: "Window nearly out 🚨"],

        // ==== 코멘트 (하이브리드 톤) ====
        "comment_h_plenty": [.ko: "충분히 여유", .en: "Plenty left"],
        "comment_h_pace": [.ko: "적당한 페이스", .en: "Good pace"],
        "comment_h_slow": [.ko: "속도 조절", .en: "Slow down"],
        "comment_h_limit": [.ko: "한도 임박", .en: "Near limit"],

        // ==== 뱃지 ====
        "badge_short": [.ko: "SHORT", .en: "SHORT"],
        "badge_long": [.ko: "LONG", .en: "LONG"],

        // ==== 리셋 표시 ====
        "resetting": [.ko: "리셋 중", .en: "Resetting"],

        // ==== 로그인 창 ====
        "login_window_title": [.ko: "Claude 로그인", .en: "Sign in to Claude"],
        "login_reload": [.ko: "새로고침", .en: "Reload"],
        "login_clear_data": [.ko: "초기화", .en: "Reset"],
        "loading_status": [.ko: "불러오는 중…", .en: "Loading…"],
        "login_safari_hint": [.ko: "Safari에서 로그인 후 다시 시도", .en: "Sign in via Safari, then retry"],
    ]
}
