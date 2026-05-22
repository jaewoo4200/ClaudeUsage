import SwiftUI

// 사용량 단계별 색상 키
enum UsageLevel {
    case ok, warn, danger
    static func from(_ u: Double) -> UsageLevel {
        if u >= 90 { return .danger }
        if u >= 70 { return .warn }
        return .ok
    }
}

// 테마별 디자인 토큰
struct DesignTokens {
    let accent: Color           // 메인 컬러 (브랜드)
    let accentSecondary: Color  // 보조 (그라데이션 등에 사용)
    let warn: Color
    let danger: Color
    let ok: Color

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    let bg: Color
    let bgSecondary: Color
    let bgRing: Color
    let border: Color
    let divider: Color

    let cornerCard: CGFloat      // 카드 코너
    let cornerOuter: CGFloat     // 외곽 패널 코너
    let cornerSmall: CGFloat     // 뱃지 등

    func color(forLevel level: UsageLevel) -> Color {
        switch level {
        case .ok: return accent
        case .warn: return warn
        case .danger: return danger
        }
    }

    func bgColor(forLevel level: UsageLevel) -> Color {
        switch level {
        case .ok: return bgRing
        case .warn: return warn.opacity(0.15)
        case .danger: return danger.opacity(0.15)
        }
    }
}

extension ThemeKind {
    var tokens: DesignTokens {
        switch self {
        case .daangn:
            return DesignTokens(
                accent: Color(red: 1.0, green: 0.435, blue: 0.058),         // #FF6F0F
                accentSecondary: Color(red: 1.0, green: 0.561, blue: 0.121),// #FF8F1F
                warn: Color(red: 1.0, green: 0.584, blue: 0.0),
                danger: Color(red: 0.945, green: 0.267, blue: 0.322),
                ok: Color(red: 0.318, green: 0.812, blue: 0.4),
                textPrimary: Color(red: 0.129, green: 0.129, blue: 0.141),
                textSecondary: Color(red: 0.286, green: 0.314, blue: 0.337),
                textTertiary: Color(red: 0.525, green: 0.557, blue: 0.588),
                bg: Color.white,
                bgSecondary: Color(red: 0.98, green: 0.98, blue: 0.98),
                bgRing: Color(red: 1.0, green: 0.91, blue: 0.839),
                border: Color.black.opacity(0.06),
                divider: Color(red: 0.945, green: 0.953, blue: 0.961),
                cornerCard: 16,
                cornerOuter: 22,
                cornerSmall: 999  // pill
            )
        case .toss:
            return DesignTokens(
                accent: Color(red: 0.192, green: 0.510, blue: 0.965),       // #3182F6
                accentSecondary: Color(red: 0.353, green: 0.659, blue: 1.0),
                warn: Color(red: 1.0, green: 0.584, blue: 0.0),
                danger: Color(red: 0.941, green: 0.267, blue: 0.322),
                ok: Color(red: 0.318, green: 0.812, blue: 0.4),
                textPrimary: Color(red: 0.098, green: 0.122, blue: 0.157),  // #191F28
                textSecondary: Color(red: 0.420, green: 0.463, blue: 0.518),// #6B7684
                textTertiary: Color(red: 0.545, green: 0.584, blue: 0.631), // #8B95A1
                bg: Color.white,
                bgSecondary: Color(red: 0.976, green: 0.980, blue: 0.984),  // #F9FAFB
                bgRing: Color(red: 0.910, green: 0.949, blue: 1.0),         // #E8F2FF
                border: Color.black.opacity(0.04),
                divider: Color(red: 0.949, green: 0.957, blue: 0.965),
                cornerCard: 12,
                cornerOuter: 16,
                cornerSmall: 6
            )
        case .hybrid:
            return DesignTokens(
                accent: Color(red: 0.055, green: 0.647, blue: 0.914),       // #0EA5E9
                accentSecondary: Color(red: 0.024, green: 0.714, blue: 0.831),// #06B6D4
                warn: Color(red: 0.984, green: 0.451, blue: 0.122),         // #FB923C → #F97316
                danger: Color(red: 0.957, green: 0.247, blue: 0.369),       // #F43F5E
                ok: Color(red: 0.204, green: 0.827, blue: 0.600),           // #34D399
                textPrimary: Color(red: 0.059, green: 0.090, blue: 0.161),  // #0F1729
                textSecondary: Color(red: 0.118, green: 0.161, blue: 0.231),// #1E293B
                textTertiary: Color(red: 0.392, green: 0.455, blue: 0.545), // #64748B
                bg: Color.white,
                bgSecondary: Color(red: 0.973, green: 0.980, blue: 0.988),  // #F8FAFC
                bgRing: Color(red: 0.886, green: 0.949, blue: 0.992),
                border: Color(red: 0.059, green: 0.090, blue: 0.161).opacity(0.06),
                divider: Color(red: 0.945, green: 0.961, blue: 0.973),
                cornerCard: 14,
                cornerOuter: 18,
                cornerSmall: 6
            )
        }
    }

    // 5시간/7일에 어떤 코멘트 보여줄지 (당근 / 하이브리드 톤)
    @MainActor
    func comment(forUtilization u: Double, isWeekly: Bool) -> String {
        let level = UsageLevel.from(u)
        switch self {
        case .daangn:
            switch level {
            case .ok: return u < 30 ? "comment_relaxed".l : "comment_moderate".l
            case .warn: return isWeekly ? "comment_slow_down_week".l : "comment_slow_down_window".l
            case .danger: return isWeekly ? "comment_almost_done_week".l : "comment_almost_done_window".l
            }
        case .hybrid:
            switch level {
            case .ok: return u < 30 ? "comment_h_plenty".l : "comment_h_pace".l
            case .warn: return "comment_h_slow".l
            case .danger: return "comment_h_limit".l
            }
        case .toss:
            return ""
        }
    }

    // 아이콘 그라데이션 (대시보드 헤더)
    var iconGradient: LinearGradient {
        let t = tokens
        switch self {
        case .daangn:
            return LinearGradient(colors: [t.accent, t.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .toss:
            return LinearGradient(colors: [t.accent, t.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .hybrid:
            return LinearGradient(colors: [t.textPrimary, t.textSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // 메뉴바 라벨에 아이콘 보일지 여부
    var menubarShowsIcon: Bool {
        switch self {
        case .toss: return false
        case .daangn, .hybrid: return true
        }
    }
}

// 카운트다운 텍스트 (테마 무관)
struct CountdownText: View {
    let resetsAt: Date?
    let isWeekly: Bool
    @State private var now: Date = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(label)
            .monospacedDigit()
            .onReceive(timer) { now = $0 }
    }

    private var label: String {
        guard let r = resetsAt else { return "–" }
        let d = r.timeIntervalSince(now)
        if d <= 0 { return "resetting".l }
        if isWeekly {
            let days = Int(d / 86400)
            let hours = Int((d.truncatingRemainder(dividingBy: 86400)) / 3600)
            let mins = Int((d.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(days)d \(hours)h \(mins)m"
        } else {
            let h = Int(d / 3600)
            let m = Int(d.truncatingRemainder(dividingBy: 3600) / 60)
            let s = Int(d.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d:%02d", h, m, s)
        }
    }
}
