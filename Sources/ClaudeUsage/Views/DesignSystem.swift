import SwiftUI
import AppKit

// MARK: - Dark mode helper

extension Color {
    /// Light/Dark에 따라 자동으로 변하는 동적 Color
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    /// 0xRRGGBB 정수로 만드는 sRGB 색
    init(hexRGB hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// 라이트/다크 값을 0xRRGGBB로 지정
    init(light: UInt32, dark: UInt32) {
        self.init(light: Color(hexRGB: light), dark: Color(hexRGB: dark))
    }
}

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
//
// 사용량 단계 색(levelOk · warn · danger)은 라이트와 다크가 다르다.
// 다크 값 = 라이트 값을 OKLCH 밝기만 0.06 낮춘 색(채도·색상 유지). 어두운 바탕에서 같은 색이
// 더 밝아 보이는 것을 보정한다. 단, 어두운 배경과의 대비가 3:1 아래로 내려가면 거기서 멈춘다.
struct DesignTokens {
    let accent: Color           // 메인 컬러 (브랜드) — 라이트/다크 동일
    let accentSecondary: Color  // 보조 (그라데이션)
    let warn: Color             // 사용량 70% 이상 (다른 화면의 경고 색으로도 쓰임)
    let danger: Color           // 사용량 90% 이상
    let ok: Color               // 상태 초록 (사용량 단계 색 아님)
    let levelOk: Color          // 사용량 70% 미만 게이지 색
    let levelOkTrack: Color     // 70% 미만일 때 도넛 트랙 색

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    let bg: Color
    let bgSecondary: Color
    let bgRing: Color
    let border: Color
    let divider: Color

    let cornerCard: CGFloat
    let cornerOuter: CGFloat
    let cornerSmall: CGFloat

    func color(forLevel level: UsageLevel) -> Color {
        switch level {
        case .ok: return levelOk
        case .warn: return warn
        case .danger: return danger
        }
    }

    func bgColor(forLevel level: UsageLevel) -> Color {
        switch level {
        case .ok: return levelOkTrack
        case .warn: return warn.opacity(0.15)
        case .danger: return danger.opacity(0.15)
        }
    }

    /// 헤더 이름 옆 연결 점. 라이트는 흰 바탕 대비 3:1 이상(#2F9E44), 다크는 기존 초록.
    var statusDot: Color { Color(light: Color(hexRGB: 0x2F9E44), dark: ok) }

    /// 게이지 화면의 작은 글자(줄 라벨, 요금제). 라이트는 흰 바탕 4.5:1 이상(#6B7280), 다크는 기존 3차 글자색.
    var gaugeCaption: Color { Color(light: Color(hexRGB: 0x6B7280), dark: Color(white: 0.55)) }
}

extension ThemeKind {
    var tokens: DesignTokens {
        // 공통 시스템 색 (자동 다크/라이트 대응)
        let textPrimary = Color.primary
        let textSecondary = Color(light: Color(red: 0.286, green: 0.314, blue: 0.337),
                                   dark: Color(white: 0.78))
        let textTertiary = Color(light: Color(red: 0.525, green: 0.557, blue: 0.588),
                                  dark: Color(white: 0.55))
        let bg = Color(light: .white,
                        dark: Color(red: 0.118, green: 0.122, blue: 0.137))     // #1E1F22
        let bgSecondary = Color(light: Color(red: 0.976, green: 0.980, blue: 0.984),
                                 dark: Color(red: 0.157, green: 0.165, blue: 0.184))  // #282A2F
        let divider = Color(light: Color(red: 0.945, green: 0.953, blue: 0.961),
                             dark: Color.white.opacity(0.08))
        let border = Color(light: Color.black.opacity(0.06),
                            dark: Color.white.opacity(0.10))

        switch self {
        case .daangn:
            // 강조색 = 여유 단계 색(파랑). 주황·빨강은 경고·위험에만 쓴다. (예전 #FF6F0F는 경고 주황과 ΔE2000 2.7)
            let accent = Color(light: 0x3182F6, dark: 0x1B6FE1)
            return DesignTokens(
                accent: accent,
                accentSecondary: Color(red: 0.353, green: 0.659, blue: 1.0),// #5AA8FF
                // 도넛 테마: 파랑 → 주황 → 빨강 (게이지 고리 색 띠의 세 기준 색)
                warn: Color(light: 0xFF7A1A, dark: 0xE56B0A),
                danger: Color(light: 0xF14452, dark: 0xDB2C41),
                ok: Color(red: 0.318, green: 0.812, blue: 0.4),
                levelOk: Color(light: 0x3182F6, dark: 0x1B6FE1),
                levelOkTrack: Color(light: Color(hexRGB: 0x3182F6).opacity(0.15),
                                    dark: Color(hexRGB: 0x1B6FE1).opacity(0.18)),
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textTertiary: textTertiary,
                bg: bg,
                bgSecondary: bgSecondary,
                bgRing: Color(light: Color(red: 0.910, green: 0.949, blue: 1.0),
                               dark: accent.opacity(0.18)),
                border: border,
                divider: divider,
                cornerCard: 16,
                cornerOuter: 22,
                cornerSmall: 999
            )
        case .toss:
            let accent = Color(light: 0x3182F6, dark: 0x1B6FE1)              // 여유 단계 색
            return DesignTokens(
                accent: accent,
                accentSecondary: Color(red: 0.353, green: 0.659, blue: 1.0),
                warn: Color(light: 0xFF9500, dark: 0xE48608),
                danger: Color(light: 0xF14452, dark: 0xDB2C41),
                ok: Color(red: 0.318, green: 0.812, blue: 0.4),
                levelOk: Color(light: 0x3182F6, dark: 0x1B6FE1),
                levelOkTrack: Color(light: Color(red: 0.910, green: 0.949, blue: 1.0),
                                    dark: Color(hexRGB: 0x1B6FE1).opacity(0.18)),
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textTertiary: textTertiary,
                bg: bg,
                bgSecondary: bgSecondary,
                bgRing: Color(light: Color(red: 0.910, green: 0.949, blue: 1.0),
                               dark: accent.opacity(0.18)),
                border: border,
                divider: divider,
                cornerCard: 12,
                cornerOuter: 16,
                cornerSmall: 6
            )
        case .hybrid:
            let accent = Color(light: 0x0EA5E9, dark: 0x0B92CE)              // 여유 단계 색
            return DesignTokens(
                accent: accent,
                accentSecondary: Color(red: 0.024, green: 0.714, blue: 0.831),// #06B6D4
                warn: Color(light: 0xFB731F, dark: 0xE16411),
                danger: Color(light: 0xF43F5E, dark: 0xE1294F),   // 다크는 대비 3:1 하한 때문에 밝기 −0.052
                ok: Color(red: 0.204, green: 0.827, blue: 0.600),
                levelOk: Color(light: 0x0EA5E9, dark: 0x0B92CE),
                levelOkTrack: Color(light: Color(red: 0.886, green: 0.949, blue: 0.992),
                                    dark: Color(hexRGB: 0x0B92CE).opacity(0.18)),
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textTertiary: textTertiary,
                bg: bg,
                bgSecondary: bgSecondary,
                bgRing: Color(light: Color(red: 0.886, green: 0.949, blue: 0.992),
                               dark: accent.opacity(0.18)),
                border: border,
                divider: divider,
                cornerCard: 14,
                cornerOuter: 18,
                cornerSmall: 6
            )
        }
    }

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

    var iconGradient: LinearGradient {
        let t = tokens
        switch self {
        case .daangn, .toss:
            return LinearGradient(colors: [t.accent, t.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .hybrid:
            // hybrid는 미드나이트 그라데이션 — 다크모드에선 약간 밝게
            return LinearGradient(
                colors: [
                    Color(light: Color(red: 0.059, green: 0.090, blue: 0.161), dark: Color(red: 0.27, green: 0.30, blue: 0.38)),
                    Color(light: Color(red: 0.118, green: 0.161, blue: 0.231), dark: Color(red: 0.38, green: 0.42, blue: 0.50))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var menubarShowsIcon: Bool {
        switch self {
        case .toss: return false
        case .daangn, .hybrid: return true
        }
    }
}

// MARK: - Countdown

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
