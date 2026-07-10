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
        "openai_usage": [.ko: "Codex 사용량", .en: "Codex Usage"],
        "logged_in": [.ko: "로그인됨", .en: "Signed in"],
        "connected_automatically": [.ko: "자동 연결됨", .en: "Connected automatically"],

        // ==== 사용량 카드 ====
        "five_hour": [.ko: "5시간", .en: "5-hour"],
        "seven_day": [.ko: "7일", .en: "7-day"],
        "claude_design": [.ko: "Claude Design", .en: "Claude Design"],
        "claude_fable": [.ko: "Claude Fable", .en: "Claude Fable"],

        // ==== Mimo companion ====
        "section_companion": [.ko: "Mimo", .en: "Mimo"],
        "pet_enabled_desc": [.ko: "사용량에 따라 표정이 달라져요", .en: "Reacts to your current usage"],
        "usage_history": [.ko: "사용량 추이 기록", .en: "Usage history"],
        "usage_history_local_desc": [.ko: "14일 동안 이 Mac에만 저장", .en: "Stored only on this Mac for 14 days"],
        "clear_usage_history": [.ko: "사용량 기록 지우기", .en: "Clear usage history"],
        "open_usage_history": [.ko: "사용량 그래프 열기", .en: "Open usage charts"],
        "usage_history_dashboard": [.ko: "사용량 기록", .en: "Usage history"],
        "mimo_sensitivity": [.ko: "반응 민감도", .en: "Reaction sensitivity"],
        "mimo_sensitivity_responsive": [.ko: "민감", .en: "Early"],
        "mimo_sensitivity_balanced": [.ko: "균형", .en: "Balanced"],
        "mimo_sensitivity_relaxed": [.ko: "느긋", .en: "Relaxed"],
        "mimo_sensitivity_threshold_format": [.ko: "집중 %.0f%% · 속도 %.0f%%p/h", .en: "Focus %.0f%% · pace %.0f%%p/h"],
        "mimo_animation": [.ko: "애니메이션", .en: "Animation"],
        "mimo_animation_desc": [.ko: "자동은 상태별로 움직임을 조절해요", .en: "Auto adjusts motion to the current state"],
        "mimo_animation_auto": [.ko: "자동", .en: "Auto"],
        "mimo_animation_lively": [.ko: "활발", .en: "Lively"],
        "mimo_animation_still": [.ko: "정지", .en: "Still"],
        "history_range_hour": [.ko: "1시간", .en: "1 hour"],
        "history_range_day": [.ko: "24시간", .en: "24 hours"],
        "history_range_week": [.ko: "7일", .en: "7 days"],
        "history_range_two_weeks": [.ko: "14일", .en: "14 days"],
        "history_scope_all": [.ko: "전체", .en: "All"],
        "history_scope_claude": [.ko: "Claude", .en: "Claude"],
        "history_scope_codex": [.ko: "Codex", .en: "Codex"],
        "history_chart_title": [.ko: "한도 사용률", .en: "Quota utilization"],
        "history_peak": [.ko: "최고 사용률", .en: "Peak usage"],
        "history_change": [.ko: "기간 변화", .en: "Range change"],
        "history_samples": [.ko: "기록 수", .en: "Samples"],
        "history_resets": [.ko: "감지한 초기화", .en: "Detected resets"],
        "history_empty_title": [.ko: "아직 표시할 기록이 없어요", .en: "No history to show yet"],
        "history_empty_desc": [.ko: "설정에서 기록을 켜면 5분 간격으로 이 Mac에만 저장해요.", .en: "Enable history in Settings to save five-minute samples on this Mac."],
        "history_tracking_off": [.ko: "기록이 꺼져 있어 새 데이터는 추가되지 않아요.", .en: "History is off, so new samples are not being added."],
        "history_pressure_explanation": [.ko: "최고 사용률은 Claude·Codex의 5시간, 주간, 표시 중인 모델별 한도 가운데 가장 큰 값이며 합산이나 평균이 아닙니다.", .en: "Peak pressure is the highest visible Claude or Codex 5-hour, weekly, or model limit; it is not a sum or average."],
        "history_series_claude_five": [.ko: "Claude · 5시간", .en: "Claude · 5-hour"],
        "history_series_claude_weekly": [.ko: "Claude · 주간", .en: "Claude · weekly"],
        "history_series_codex_five": [.ko: "Codex · 5시간", .en: "Codex · 5-hour"],
        "history_series_codex_weekly": [.ko: "Codex · 주간", .en: "Codex · weekly"],
        "history_percent_format": [.ko: "%.0f%%", .en: "%.0f%%"],
        "history_delta_format": [.ko: "%+.1f%%p", .en: "%+.1f%%p"],
        "pet_mood_waiting": [.ko: "대기", .en: "Waiting"],
        "pet_mood_calm": [.ko: "편안함", .en: "Calm"],
        "pet_mood_focused": [.ko: "집중", .en: "Focused"],
        "pet_mood_sleepy": [.ko: "졸림", .en: "Sleepy"],
        "pet_mood_tired": [.ko: "지침", .en: "Tired"],
        "pet_mood_refreshed": [.ko: "회복", .en: "Refreshed"],
        "pet_message_waiting": [.ko: "연결을 기다리고 있어요", .en: "Waiting for a usage source"],
        "pet_message_waiting_alt1": [.ko: "사용량이 보이면 바로 알려줄게요", .en: "I'll speak up when usage appears"],
        "pet_message_waiting_alt2": [.ko: "Mimo가 조용히 대기 중이에요", .en: "Mimo is standing by quietly"],
        "pet_message_calm": [.ko: "가볍게 작업 중이에요", .en: "Working at an easy pace"],
        "pet_message_calm_alt1": [.ko: "지금 페이스가 딱 좋아요", .en: "This pace feels just right"],
        "pet_message_calm_alt2": [.ko: "한도가 아직 넉넉해요", .en: "There is plenty of limit left"],
        "pet_message_focused": [.ko: "노트북 켜고 열심히 작업 중이에요", .en: "Laptop open and working hard"],
        "pet_message_focused_alt1": [.ko: "사용량이 빠르게 올라가요", .en: "Usage is climbing quickly"],
        "pet_message_focused_alt2": [.ko: "Mimo도 집중해서 일해요", .en: "Mimo is focused and working too"],
        "pet_message_sleepy": [.ko: "조금 졸리기 시작했어요", .en: "Starting to feel sleepy"],
        "pet_message_sleepy_alt1": [.ko: "사용량이 많아요, 조금 쉬어가요", .en: "Usage is high; let's slow down a little"],
        "pet_message_sleepy_alt2": [.ko: "한도가 꽤 찼어요", .en: "The limit is getting quite full"],
        "pet_message_tired": [.ko: "한도가 가까워 잠깐 쉬고 싶어요", .en: "The limit is close; time for a pause"],
        "pet_message_tired_alt1": [.ko: "Mimo가 많이 지쳤어요", .en: "Mimo is feeling very tired"],
        "pet_message_tired_alt2": [.ko: "리셋 전까지 쉬어갈까요?", .en: "Shall we rest until the reset?"],
        "pet_message_refreshed": [.ko: "초기화되어 다시 생생해졌어요", .en: "Reset and feeling refreshed"],
        "pet_message_refreshed_alt1": [.ko: "한도가 돌아왔어요, 다시 출발!", .en: "The limit is back; ready to go"],
        "pet_message_refreshed_alt2": [.ko: "Mimo가 푹 쉬고 일어났어요", .en: "Mimo woke up well rested"],
        "pet_recent_tokens_format": [.ko: "1시간 +%@ 토큰", .en: "1h +%@ tokens"],
        "pet_recent_rate_format": [.ko: "1시간 +%.1f%%p", .en: "1h +%.1f%%p"],
        "pet_pressure_format": [.ko: "현재 부담 %.0f%%", .en: "Current pressure %.0f%%"],
        "pet_recent_tokens_short_format": [.ko: "1시간 +%@ tokens", .en: "1h +%@ tokens"],
        "pet_recent_rate_short_format": [.ko: "1시간 +%.1f%%p", .en: "1h +%.1f%%p"],
        "pet_pressure_short_format": [.ko: "현재 %.0f%%", .en: "Now %.0f%%"],
        "pet_waiting_detail": [.ko: "아직 기록이 없어요", .en: "No history yet"],

        // ==== 푸터 버튼 ====
        "show_widget": [.ko: "위젯 켜기", .en: "Show widget"],
        "hide_widget": [.ko: "위젯 숨기기", .en: "Hide widget"],
        "logout": [.ko: "로그아웃", .en: "Sign out"],
        "claude_logout": [.ko: "Claude 로그아웃", .en: "Sign out of Claude"],

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
        "usage_unavailable": [.ko: "표시할 수 있는 사용량 한도가 없어요", .en: "No usage limits are available"],
        "network_error_prefix": [.ko: "네트워크 오류: ", .en: "Network error: "],
        "openai_not_connected": [.ko: "ChatGPT 또는 Codex 앱 로그인이 필요해요", .en: "Sign in to the ChatGPT or Codex app"],
        "openai_connect_desc": [.ko: "앱 로그인 정보를 자동으로 읽어 사용량을 표시해요.", .en: "Usage is read automatically from your app sign-in."],
        "openai_session_expired": [.ko: "ChatGPT/Codex 세션을 새로고침해 주세요", .en: "Refresh your ChatGPT/Codex session"],
        "openai_decode_failed": [.ko: "Codex 사용량 데이터를 읽지 못했어요", .en: "Couldn't read Codex usage data"],
        "open_usage_page": [.ko: "사용량 페이지 열기", .en: "Open usage page"],

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
        "widget_layout": [.ko: "위젯 배치", .en: "Widget layout"],
        "widget_layout_stacked": [.ko: "세로", .en: "Stack"],
        "widget_layout_horizontal": [.ko: "가로", .en: "Wide"],
        "widget_layout_paged": [.ko: "전환", .en: "Pages"],
        "widget_layout_separate": [.ko: "분리", .en: "Split"],
        "widget_layout_stacked_desc": [.ko: "Claude와 Codex를 세로로 이어서 표시", .en: "Show Claude and Codex in one vertical widget"],
        "widget_layout_horizontal_desc": [.ko: "두 사용량을 좌우로 나란히 표시", .en: "Place both providers side by side"],
        "widget_layout_paged_desc": [.ko: "작은 위젯에서 화살표로 전환", .en: "Switch providers with arrows in a compact widget"],
        "widget_layout_separate_desc": [.ko: "Claude와 Codex를 독립된 위젯으로 표시", .en: "Show Claude and Codex as independent widgets"],
        "separate_widgets": [.ko: "분리해서 표시할 위젯", .en: "Separate widgets to show"],
        "show_claude_widget": [.ko: "Claude 위젯", .en: "Claude widget"],
        "show_openai_widget": [.ko: "Codex 위젯", .en: "Codex widget"],
        "show_spark_limits": [.ko: "GPT-5.3-Codex-Spark 표시", .en: "Show GPT-5.3-Codex-Spark"],
        "show_spark_limits_desc": [.ko: "필요할 때만 전용 5시간·주간 한도를 표시", .en: "Show its dedicated 5-hour and weekly limits only when needed"],
        "widget_previous_provider": [.ko: "이전 사용량", .en: "Previous provider"],
        "widget_next_provider": [.ko: "다음 사용량", .en: "Next provider"],
        "widget_headroom": [.ko: "최소 여유", .en: "Least headroom"],
        "widget_next_reset": [.ko: "다음 초기화", .en: "Next reset"],
        "widget_reset_credits": [.ko: "초기화권", .en: "Reset passes"],
        "widget_reset_credits_none": [.ko: "없음", .en: "None"],
        "widget_reset_credits_count": [.ko: "%d장", .en: "%d"],
        "widget_reset_credits_expiry": [.ko: "%d장 · %d/%d", .en: "%d · %d/%d"],
        "widget_recent_activity": [.ko: "최근 1시간", .en: "Last hour"],
        "widget_today_tokens": [.ko: "오늘 토큰", .en: "Tokens today"],
        "widget_history_off": [.ko: "기록 꺼짐", .en: "History off"],
        "widget_reset_detected": [.ko: "초기화됨", .en: "Reset detected"],
        "widget_recent_tokens_value": [.ko: "+%@ 토큰", .en: "+%@ tok"],
        "widget_no_recent_change": [.ko: "변화 없음", .en: "No change"],
        "widget_collecting_history": [.ko: "기록 수집 중", .en: "Collecting"],

        // ==== Appearance (다크/라이트) ====
        "section_appearance": [.ko: "화면 모드", .en: "Appearance"],
        "appearance_auto": [.ko: "자동", .en: "Auto"],
        "appearance_light": [.ko: "라이트", .en: "Light"],
        "appearance_dark": [.ko: "다크", .en: "Dark"],

        // ==== 위젯 헤더 ====
        "claude_short": [.ko: "Claude", .en: "Claude"],
        "openai_short": [.ko: "Codex", .en: "Codex"],

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
