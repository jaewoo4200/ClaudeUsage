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
struct DesignTokens {
    let accent: Color           // 메인 컬러 (브랜드) — 라이트/다크 동일
    let accentSecondary: Color  // 보조 (그라데이션)
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

    let cornerCard: CGFloat
    let cornerOuter: CGFloat
    let cornerSmall: CGFloat

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
            let accent = Color(red: 1.0, green: 0.435, blue: 0.058)         // #FF6F0F
            return DesignTokens(
                accent: accent,
                accentSecondary: Color(red: 1.0, green: 0.561, blue: 0.121),// #FF8F1F
                warn: Color(red: 1.0, green: 0.584, blue: 0.0),
                danger: Color(red: 0.945, green: 0.267, blue: 0.322),
                ok: Color(red: 0.318, green: 0.812, blue: 0.4),
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textTertiary: textTertiary,
                bg: bg,
                bgSecondary: bgSecondary,
                bgRing: Color(light: Color(red: 1.0, green: 0.91, blue: 0.839),
                               dark: accent.opacity(0.18)),
                border: border,
                divider: divider,
                cornerCard: 16,
                cornerOuter: 22,
                cornerSmall: 999
            )
        case .toss:
            let accent = Color(red: 0.192, green: 0.510, blue: 0.965)       // #3182F6
            return DesignTokens(
                accent: accent,
                accentSecondary: Color(red: 0.353, green: 0.659, blue: 1.0),
                warn: Color(red: 1.0, green: 0.584, blue: 0.0),
                danger: Color(red: 0.941, green: 0.267, blue: 0.322),
                ok: Color(red: 0.318, green: 0.812, blue: 0.4),
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
            let accent = Color(red: 0.055, green: 0.647, blue: 0.914)       // #0EA5E9
            return DesignTokens(
                accent: accent,
                accentSecondary: Color(red: 0.024, green: 0.714, blue: 0.831),// #06B6D4
                warn: Color(red: 0.984, green: 0.451, blue: 0.122),
                danger: Color(red: 0.957, green: 0.247, blue: 0.369),
                ok: Color(red: 0.204, green: 0.827, blue: 0.600),
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
