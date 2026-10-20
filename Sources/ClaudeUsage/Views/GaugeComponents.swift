import SwiftUI
import AppKit
import CoreText

// MARK: - 큰 게이지 공통 요소 (B안 큰 바 · C안 도넛)
//
// % 숫자: Helvetica Neue Bold. 숫자의 대문자 높이를 목표 높이(바 높이 등)에 정확히 맞춘다.
// 남은 시간: Barlow Condensed Light (Resources/Fonts, SIL OFL 1.1).
//            번들에 서체가 없으면 시스템 서체 condensed light로 대신한다.

enum GaugeFonts {
    static let percentName = "HelveticaNeue-Bold"
    static let timerName = "BarlowCondensed-Light"

    /// 번들에 들어 있는 Barlow Condensed를 앱 프로세스에 한 번만 등록한다.
    static let hasTimerFont: Bool = {
        if NSFont(name: timerName, size: 12) != nil { return true }
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls where url.lastPathComponent.hasPrefix("BarlowCondensed") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return NSFont(name: timerName, size: 12) != nil
    }()

    static func percentNSFont(size: CGFloat) -> NSFont {
        NSFont(name: percentName, size: size) ?? .systemFont(ofSize: size, weight: .bold)
    }

    /// 대문자 높이 ÷ 글자 크기
    static let percentCapRatio: CGFloat = capRatio(percentNSFont(size: 100), fallback: 0.714)
    static var timerCapRatio: CGFloat {
        hasTimerFont ? capRatio(NSFont(name: timerName, size: 100), fallback: 0.70)
                     : capRatio(.systemFont(ofSize: 100, weight: .light), fallback: 0.70)
    }

    private static func capRatio(_ font: NSFont?, fallback: CGFloat) -> CGFloat {
        guard let font, font.capHeight > 0 else { return fallback }
        return font.capHeight / font.pointSize
    }

    /// 대문자 높이가 capHeight가 되는 % 숫자 서체
    static func percentFont(capHeight: CGFloat) -> Font {
        .custom(percentName, fixedSize: capHeight / percentCapRatio)
    }

    /// 대문자 높이가 capHeight가 되는 남은 시간 서체
    static func timerFont(capHeight: CGFloat) -> Font {
        let size = capHeight / timerCapRatio
        return hasTimerFont ? .custom(timerName, fixedSize: size)
                            : .system(size: size, weight: .light).width(.condensed)
    }

    /// 남은 시간 서체(NSFont). 화면의 .monospacedDigit()과 같게 고정폭 숫자를 켠다.
    static func timerNSFont(capHeight: CGFloat) -> NSFont {
        let size = capHeight / timerCapRatio
        let base = (hasTimerFont ? NSFont(name: timerName, size: size) : nil)
            ?? NSFont.systemFont(ofSize: size, weight: .light)
        let descriptor = base.fontDescriptor.addingAttributes([
            .featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
            ]]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// 글자열의 실제 잉크 범위(기준선 위가 +, pt). 둥근 글자가 대문자 높이 위아래로 살짝 넘치는 것까지 포함.
    static func inkBounds(_ string: String, font: NSFont) -> (bottom: CGFloat, top: CGFloat) {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: [.font: font]))
        let r = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return r.isNull ? (0, font.capHeight) : (r.minY, r.maxY)
    }

    /// % 숫자(0~9)의 잉크 범위 ÷ 대문자 높이. Helvetica Neue Bold는 둥근 숫자 위끝 = 대문자 높이, 아래로 2% 넘침.
    static let percentDigitInk: (bottom: CGFloat, top: CGFloat) = {
        let font = percentNSFont(size: 100)
        let b = inkBounds("0123456789", font: font)
        let cap = 100 * percentCapRatio
        return (b.bottom / cap, b.top / cap)
    }()

    /// 남은 시간(0~9, d·h·m, :)의 잉크 범위 ÷ 대문자 높이. Barlow는 둥근 글자가 위아래로 1.4%씩 넘침.
    static var timerInk: (bottom: CGFloat, top: CGFloat) {
        let b = inkBounds("0123456789dhm:", font: timerNSFont(capHeight: 100))
        return (b.bottom / 100, b.top / 100)
    }

    /// 높이 h인 칸에 잉크가 위아래 선에 꼭 맞게 들어가는 대문자 높이(cap)와,
    /// 대문자 가운데 맞춤에서 잉크 가운데 맞춤으로 옮기기 위해 올릴 양(raise, pt).
    static func inkFit(_ h: CGFloat, ink: (bottom: CGFloat, top: CGFloat)) -> (cap: CGFloat, raise: CGFloat) {
        let cap = h / (ink.top - ink.bottom)
        return (cap, cap * (1 - ink.top - ink.bottom) / 2)
    }

    /// % 기호를 숫자 잉크 범위 안에 넣는 글자 크기 비율과 올림(글자 크기 대비).
    /// %는 숫자보다 위아래로 조금 더 커서(Helvetica Neue Bold 기준 위 +0.8, 아래 −0.7 / 100) 그대로 두면 막대에 잘린다.
    static let percentSignFit: (scale: CGFloat, raise: CGFloat) = {
        let font = percentNSFont(size: 100)
        let d = inkBounds("0123456789", font: font)
        let p = inkBounds("%", font: font)
        let scale = min(1, (d.top - d.bottom) / max(1, p.top - p.bottom))
        return (scale, (d.top - scale * p.top) / 100)
    }()

    /// 첫 글자의 잉크가 글자 칸 왼쪽에서 떨어진 거리(pt). 서로 다른 크기의 글자 머리를 맞출 때 쓴다.
    static func leadingInk(_ string: String, font: NSFont) -> CGFloat {
        guard let first = string.first else { return 0 }
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(first), attributes: [.font: font]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        return bounds.isNull ? 0 : bounds.minX
    }

    /// 텍스트 폭(pt)
    static func width(_ string: String, font: NSFont, tracking: CGFloat = 0) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .kern: tracking])
        return ceil(attributed.size().width)
    }

    /// "100%"(좁힌 % 포함) 폭 ÷ 대문자 높이. % 칸 크기를 정할 때 쓴다.
    static let percentWidthPerCap: CGFloat = {
        let size: CGFloat = 100
        let font = percentNSFont(size: size)
        let w = width("100", font: font, tracking: -0.035 * size) + width("%", font: font) * 0.68
        return w / (size * percentCapRatio)
    }()

    /// 가장 긴 남은 시간 표기("3d 11h 19m")의 폭 ÷ 대문자 높이
    static let longestTimerWidthPerCap: CGFloat = timerWidthPerCap("3d 11h 19m")
    /// 바(짧은 표기)에 나올 수 있는 표기 중 가장 넓은 경우의 폭 ÷ 대문자 높이.
    /// 7일 창: 하루 이상 "6d 23h" → 0d가 되면 "23h 59m" → 0h가 되면 "0:59:59". 5시간 창: 항상 "4:59:59".
    static let shortTimerWidthPerCap: CGFloat = ["6d 23h", "3d 11h", "23h 59m", "20h 48m", "18h 08m", "4:59:59", "0:59:59", "0:00:00"]
        .map { timerWidthPerCap($0) }
        .max() ?? 0

    /// 남은 시간 문자열 폭 ÷ 대문자 높이
    static func timerWidthPerCap(_ string: String) -> CGFloat {
        guard hasTimerFont, let font = NSFont(name: timerName, size: 100) else {
            return CGFloat(string.count) * 0.36 / 0.70   // 서체가 없을 때의 대략값
        }
        return width(string, font: font) / (100 * timerCapRatio)
    }
}

extension View {
    /// 부모의 세로 가운데에 '대문자 높이'의 가운데를 맞춘다. 위아래 여백 없이 꽉 채울 때 쓴다.
    func gaugeCapCentered(_ capHeight: CGFloat) -> some View {
        alignmentGuide(VerticalAlignment.center) { d in d[.firstTextBaseline] - capHeight / 2 }
    }
}

// MARK: - 남은 시간 문자열

enum GaugeCountdown {
    /// 남은 시간 표기 규칙
    /// - 7일 창: 하루 이상이면 "3d 11h"(바) / "3d 11h 19m"(도넛). 0d가 되면 "11h 19m".
    ///   0h가 되면 5시간 창과 같은 시:분:초 "0:45:12".
    /// - 5시간 창: 항상 시:분:초 "2:29:59".
    /// - 0이 된 맨 앞 단위만 뺀다. 가운데 단위가 0이면 남긴다("3d 0h").
    /// - 다 지나면 "0:00:00" (다음 새로고침 전까지).
    static func text(resetsAt: Date?, isWeekly: Bool, now: Date, short: Bool) -> String {
        guard let resetsAt else { return "–" }
        return format(seconds: resetsAt.timeIntervalSince(now), isWeekly: isWeekly, short: short)
    }

    /// 남은 초를 표기 문자열로. short는 7일 창이 하루 이상 남았을 때만 분을 뺀다.
    static func format(seconds d: TimeInterval, isWeekly: Bool, short: Bool) -> String {
        let total = max(0, Int(d))
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if isWeekly {
            if days > 0 { return short ? "\(days)d \(hours)h" : "\(days)d \(hours)h \(minutes)m" }
            if hours > 0 { return "\(hours)h \(minutes)m" }
        }
        return String(format: "%d:%02d:%02d", total / 3_600, minutes, secs)
    }
}

// MARK: - 글자

/// 좁힌 %가 붙은 Helvetica Neue Bold 숫자. 대문자 높이 = capHeight
struct GaugePercentText: View {
    let value: Double
    let capHeight: CGFloat
    let color: Color

    var body: some View {
        let size = capHeight / GaugeFonts.percentCapRatio
        let sign = GaugeFonts.percentSignFit
        let percentWidth = GaugeFonts.width("%", font: GaugeFonts.percentNSFont(size: size * sign.scale))
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(Int(value.rounded()))")
                .tracking(-0.035 * size)
            // %는 숫자 잉크 범위(둥근 숫자 위끝~아래끝) 안에 들어가게 조금 줄이고 올린다
            Text("%")
                .font(.custom(GaugeFonts.percentName, fixedSize: size * sign.scale))
                .opacity(0.5)
                .scaleEffect(x: 0.68, y: 1, anchor: .leading)
                .padding(.trailing, -percentWidth * 0.32)
                .offset(y: -size * sign.raise)
        }
        .font(GaugeFonts.percentFont(capHeight: capHeight))
        .monospacedDigit()
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
        .gaugeCapCentered(capHeight)
    }
}

/// 남은 시간. 숫자는 그대로, 단위(d·h·m)는 연하게. 대문자 높이 = capHeight
struct GaugeTimerText: View {
    let text: String
    let capHeight: CGFloat
    let color: Color

    var body: some View {
        styled
            .font(GaugeFonts.timerFont(capHeight: capHeight))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .gaugeCapCentered(capHeight)
    }

    private var styled: Text {
        var result = Text("")
        var run = ""
        var runIsUnit = false
        for ch in text {
            let isUnit = ch.isLetter
            if isUnit != runIsUnit, !run.isEmpty {
                result = result + Text(run).foregroundColor(runIsUnit ? color.opacity(0.5) : color)
                run = ""
            }
            runIsUnit = isUnit
            run.append(ch)
        }
        if !run.isEmpty {
            result = result + Text(run).foregroundColor(runIsUnit ? color.opacity(0.5) : color)
        }
        return result
    }
}

// MARK: - 공급자 헤더

/// 공급자 이름 색. 테마와 상관없이 각 앱 아이콘에서 가장 많이 쓰인 색.
/// 다크는 단계 색과 같은 규칙(OKLCH 밝기 −0.06).
enum ProviderNameColor {
    static let claude = Color(light: 0xDD5236, dark: 0xC83E22)
    static let codex = Color(light: 0x5E6EFE, dark: 0x4F5AE9)
}

/// 드롭다운·위젯 공용 헤더: 앱 아이콘 + 이름(오른쪽 위에 연결 점) + 오른쪽 끝 요금제(작은 대문자).
/// 연결 상태 문구는 점과 이름에 마우스를 올리면 툴팁으로 보인다.
struct GaugeProviderHeader<Icon: View>: View {
    let name: String
    let nameColor: Color
    let plan: String?
    let isLoaded: Bool
    var status: String = ""
    let tokens: DesignTokens
    var compact = false
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        let nameSize: CGFloat = compact ? 14 : 20
        let nameCap = nameSize * GaugeFonts.percentCapRatio
        let dot: CGFloat = compact ? 5 : 6
        let planSize: CGFloat = compact ? 9 : 10.5
        HStack(spacing: compact ? 7 : 9) {
            icon()
            HStack(alignment: .firstTextBaseline, spacing: compact ? 2 : 3) {
                Text(name)
                    .font(.custom(GaugeFonts.percentName, fixedSize: nameSize))
                    .tracking(-0.03 * nameSize)
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .fixedSize()
                // 각도 기호처럼: 점의 윗선을 대문자 윗선보다 1pt 위에 둔다
                Circle()
                    .fill(isLoaded ? tokens.statusDot : tokens.textTertiary)
                    .frame(width: dot, height: dot)
                    .alignmentGuide(.firstTextBaseline) { _ in nameCap + 1 }
            }
            .help(status)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.isEmpty ? name : "\(name), \(status)")
            .gaugeCapCentered(nameCap)
            Spacer(minLength: 8)
            if let plan, !plan.isEmpty {
                Text(plan.uppercased())
                    .font(.system(size: planSize, weight: .bold))
                    .tracking(planSize * 0.08)
                    .foregroundStyle(tokens.gaugeCaption)
                    .lineLimit(1)
                    .fixedSize()
                    .gaugeCapCentered(planSize * Self.systemCapRatio)
            }
        }
    }

    private static var systemCapRatio: CGFloat {
        let font = NSFont.systemFont(ofSize: 100, weight: .bold)
        return font.capHeight > 0 ? font.capHeight / 100 : 0.7
    }
}

// MARK: - 주간 구성 조각

struct GaugeSegment: Identifiable {
    let id: String
    let percent: Double
    let color: Color

    /// 주간 구성 색. 경고용 주황·빨강을 피하고, 인접한 칸끼리 색각이상 구분 검증을 통과한 조합.
    static func color(forKey key: String) -> Color {
        switch key {
        case "claude_code": return Color(light: Color(gaugeRGB: 0x2A78D6), dark: Color(gaugeRGB: 0x3987E5))
        case "chat":        return Color(light: Color(gaugeRGB: 0x1BAF7A), dark: Color(gaugeRGB: 0x199E70))
        case "cowork":      return Color(light: Color(gaugeRGB: 0x4A3AA7), dark: Color(gaugeRGB: 0x9085E9))
        default:            return Color(light: Color(gaugeRGB: 0x8A877F), dark: Color(gaugeRGB: 0x8C8C8C))
        }
    }

    /// 합이 100을 넘으면 앱의 구성 막대와 같이 max(100, 합)으로 나눈다.
    static func denominator(_ segments: [GaugeSegment]) -> Double {
        max(100, segments.reduce(0) { $0 + $1.percent })
    }
}

private extension Color {
    init(gaugeRGB hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - 테마별 게이지 색

/// 단계 하나의 게이지 색. deep(시작) → mid → bright(끝) 그라데이션, ink = 바탕 위 글자(%) 색.
struct GaugeLevelColors {
    let deep: Color
    let mid: Color
    let bright: Color
    let ink: Color
}

/// 세 테마의 게이지 색.
/// - 도넛: 고리는 파랑 → 주황 → 빨강 스펙트럼(OKLab 곧장 섞기), % 숫자는 섞인 색 없이 세 가지만.
/// - 헤일로 바: 진한 색 → 밝은 색 그라데이션. 라이트의 밝은 끝은 흰 녹아웃 글자 대비 3:1 이상으로 낮춤.
/// - 오라: 같은 그라데이션을 흐린 빛으로.
/// 다크 값은 라이트를 OKLCH 밝기 −0.06 한 색(채도 유지).
enum GaugePalette {
    static func colors(_ theme: ThemeKind, _ level: UsageLevel) -> GaugeLevelColors {
        switch theme {
        case .daangn:
            let c: Color
            switch level {
            case .ok: c = Color(light: 0x3182F6, dark: 0x1B6FE1)
            case .warn: c = Color(light: 0xFF7A1A, dark: 0xE56B0A)
            case .danger: c = Color(light: 0xF14452, dark: 0xDB2C41)
            }
            return GaugeLevelColors(deep: c, mid: c, bright: c, ink: c)
        case .toss:
            switch level {
            case .ok: return make((0x1149D4, 0x126EFF), (0x126EFF, 0x2F8CFF), (0x179DE0, 0x7CD3FF), (0x1149D4, 0x6CC4FF))
            case .warn: return make((0xC2410C, 0xE8590C), (0xF06418, 0xF57C1F), (0xE47600, 0xFFC078), (0xC2410C, 0xFFA94D))
            case .danger: return make((0xB3123A, 0xD6204A), (0xE1294F, 0xF0455F), (0xE37182, 0xFF9AAA), (0xB3123A, 0xFF7A8F))
            }
        case .hybrid:
            switch level {
            case .ok: return make((0x1149D4, 0x126EFF), (0x126EFF, 0x2F8CFF), (0x44BBFF, 0x7CD3FF), (0x1149D4, 0x6CC4FF))
            case .warn: return make((0xC2410C, 0xE8590C), (0xF06418, 0xF57C1F), (0xFFB347, 0xFFC078), (0xC2410C, 0xFFA94D))
            case .danger: return make((0xB3123A, 0xD6204A), (0xE1294F, 0xF0455F), (0xFF8A9A, 0xFF9AAA), (0xB3123A, 0xFF7A8F))
            }
        }
    }

    private static func make(_ deep: (UInt32, UInt32), _ mid: (UInt32, UInt32),
                             _ bright: (UInt32, UInt32), _ ink: (UInt32, UInt32)) -> GaugeLevelColors {
        GaugeLevelColors(deep: Color(light: deep.0, dark: deep.1), mid: Color(light: mid.0, dark: mid.1),
                         bright: Color(light: bright.0, dark: bright.1), ink: Color(light: ink.0, dark: ink.1))
    }

    // 도넛 색 띠: 0~100%를 2.5% 간격 41칸. 40%까지 파랑, 40~70 파랑 → 주황, 70~80 주황, 80~90 주황 → 빨강, 90~ 빨강.
    static let donutLight: [UInt32] = [
        0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6,
        0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x3182F6, 0x4D85E9, 0x6388DC, 0x768ACE,
        0x888BC0, 0x988CB2, 0xA88BA3, 0xB78B94, 0xC68984, 0xD48772, 0xE3835E, 0xF17F44, 0xFF7A1A, 0xFF7A1A,
        0xFF7A1A, 0xFF7A1A, 0xFF7A1A, 0xFC6E31, 0xF8613F, 0xF5544A, 0xF14452, 0xF14452, 0xF14452, 0xF14452,
        0xF14452
    ]
    static let donutDark: [UInt32] = [
        0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1,
        0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x1B6FE1, 0x3C72D5, 0x5276C8, 0x6578BA,
        0x7679AD, 0x867A9F, 0x957991, 0xA47982, 0xB27772, 0xC07560, 0xCF714C, 0xDC6C2F, 0xE56B0A, 0xE56B0A,
        0xE56B0A, 0xE56B0A, 0xE56B0A, 0xE75A16, 0xE24D2A, 0xDF3F38, 0xDB2C41, 0xDB2C41, 0xDB2C41, 0xDB2C41,
        0xDB2C41
    ]
    static let donutRedLight: UInt32 = 0xF14452
    static let donutRedDark: UInt32 = 0xDB2C41

    /// 90%부터 95%까지 고리 전체가 빨강으로 물드는 정도 (0~1)
    static func donutRedBlend(progress u: Double) -> Double { max(0, min(1, (u - 90) / 5)) }

    /// 사용률에 맞춘 도넛 색 띠 (각도 0 = 위, 시계 방향)
    static func donutStops(progress u: Double) -> [Gradient.Stop] {
        let t = donutRedBlend(progress: u)
        let last = CGFloat(donutLight.count - 1)
        return donutLight.indices.map { i in
            let light = mixHex(donutLight[i], donutRedLight, t)
            let dark = mixHex(donutDark[i], donutRedDark, t)
            return Gradient.Stop(color: Color(light: light, dark: dark), location: CGFloat(i) / last)
        }
    }

    /// 두 sRGB 색을 선형 빛 기준으로 섞는다
    static func mixHex(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        guard t > 0 else { return a }
        guard t < 1 else { return b }
        func channel(_ v: UInt32, _ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) / 255 }
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        func srgb(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
        var out: UInt32 = 0
        for shift: UInt32 in [16, 8, 0] {
            let v = srgb(lin(channel(a, shift)) + (lin(channel(b, shift)) - lin(channel(a, shift))) * t)
            out |= UInt32((max(0, min(1, v)) * 255).rounded()) << shift
        }
        return out
    }
}

/// 빛 위 글자를 떼어 보이게 하는 그림자: 라이트는 흰 그림자, 다크는 검은 그림자(바탕과 같은 쪽).
struct GaugeTextShadow: ViewModifier {
    var isOn = true
    @Environment(\.colorScheme) private var scheme

    // if/else로 그림자를 켜고 끄면 SwiftUI가 글자의 '대문자 가운데' 정렬 기준(gaugeCapCentered)을 잃어
    // 글자가 3pt쯤 내려간다. 그래서 조건문 없이 꺼진 경우엔 투명 그림자를 둔다.
    func body(content: Content) -> some View {
        let base = scheme == .dark ? Color.black.opacity(0.75) : Color.white.opacity(0.95)
        let c = isOn ? base : Color.clear
        content
            .shadow(color: c, radius: isOn ? 1 : 0)
            .shadow(color: c, radius: isOn ? 3.5 : 0)
            .shadow(color: c.opacity(0.7), radius: isOn ? 7 : 0)
    }
}

/// 남은 시간(왼쪽)과 %(오른쪽)를 높이만큼 크게 놓는 공통 글자 층
private struct GaugeInlineLabels: View {
    let progress: Double
    let timer: String
    let height: CGFloat
    let timerColor: Color
    let percentColor: Color
    var shadow = false
    /// 남은 시간 첫 글자의 잉크가 시작할 x(pt). nil이면 막대 안쪽 여백(높이 × 0.24).
    var timerInkX: CGFloat? = nil
    /// true면 글자의 실제 잉크(둥근 글자 넘침 포함)가 칸 위아래 선에 꼭 맞게 조금 줄인다. 막대처럼 선이 있는 곳에 쓴다.
    /// false면 대문자 높이 = 칸 높이.
    var fitInk = false

    var body: some View {
        let padX = (height * 0.24).rounded()
        let t = fitInk ? GaugeFonts.inkFit(height, ink: GaugeFonts.timerInk) : (cap: height, raise: 0)
        let p = fitInk ? GaugeFonts.inkFit(height, ink: GaugeFonts.percentDigitInk) : (cap: height, raise: 0)
        let timerPad = timerInkX.map {
            $0 - GaugeFonts.leadingInk(timer, font: GaugeFonts.timerNSFont(capHeight: t.cap))
        } ?? padX
        Color.clear
            .overlay(alignment: .leading) {
                GaugeTimerText(text: timer, capHeight: t.cap, color: timerColor)
                    .modifier(GaugeTextShadow(isOn: shadow))
                    .padding(.leading, timerPad)
                    .offset(y: -t.raise)
            }
            .overlay(alignment: .trailing) {
                GaugePercentText(value: progress, capHeight: p.cap, color: percentColor)
                    .modifier(GaugeTextShadow(isOn: shadow))
                    .padding(.trailing, padX)
                    .offset(y: -p.raise)
            }
    }
}

// MARK: - 헤일로 바 (블루 바 자리)

/// 진한 색 → 밝은 색 그라데이션으로 채우고, 같은 채움을 흐리게 한 빛이 막대 밖으로 번진다.
/// 트랙 위 글자는 단계 글자 색, 채움과 겹친 부분은 배경색(녹아웃).
struct BigGaugeBar: View {
    let progress: Double            // 0~100
    let timer: String
    let height: CGFloat
    let colors: GaugeLevelColors
    let knockout: Color             // 채움과 겹친 글자 색 = 배경색
    var segments: [GaugeSegment]? = nil
    var cornerRadius: CGFloat = 8

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = max(0, min(1, progress / 100))
        let dark = scheme == .dark
        let radius = min(cornerRadius, height / 2)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        GeometryReader { geo in
            let fillWidth = geo.size.width * p
            ZStack(alignment: .leading) {
                // 헤일로: 채움 복사본을 흐리게. 막대를 자르는 모양 밖에 둬야 빛이 번진다.
                fill(width: fillWidth)
                    .frame(width: fillWidth, height: height + 4)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .blur(radius: height * (dark ? 0.28 : 0.23))
                    .opacity(dark ? 0.75 : 0.55)
                ZStack(alignment: .leading) {
                    shape.fill(colors.mid.opacity(dark ? 0.14 : 0.10))
                    fill(width: fillWidth)
                    GaugeInlineLabels(progress: progress, timer: timer, height: height,
                                      timerColor: colors.ink, percentColor: colors.ink, fitInk: true)
                    GaugeInlineLabels(progress: progress, timer: timer, height: height,
                                      timerColor: knockout, percentColor: knockout, fitInk: true)
                        .mask(alignment: .leading) { Rectangle().frame(width: fillWidth) }
                }
                .frame(width: geo.size.width, height: height)
                .clipShape(shape)
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(progress.rounded()))%, \(timer)")
    }

    @ViewBuilder
    private func fill(width: CGFloat) -> some View {
        if let segments, !segments.isEmpty {
            let denominator = GaugeSegment.denominator(segments)
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Rectangle().fill(segment.color).frame(width: width * segment.percent / denominator)
                }
            }
            .frame(width: width, alignment: .leading)
        } else {
            Rectangle()
                .fill(LinearGradient(stops: [
                    .init(color: colors.deep, location: 0),
                    .init(color: colors.mid, location: 0.6),
                    .init(color: colors.bright, location: 1)
                ], startPoint: .leading, endPoint: .trailing))
                .frame(width: width)
        }
    }
}

// MARK: - 오라 (그라데이션 바 자리)

/// 막대 테두리 없이, 사용률만큼 퍼진 흐린 빛 위에 남은 시간과 %를 놓는다.
/// 라이트 타이머는 먹색, 다크는 흰색. % 숫자는 단계 글자 색. 글자에는 바탕 쪽 그림자.
struct AuraGauge: View {
    let progress: Double            // 0~100
    let timer: String
    let height: CGFloat
    let colors: GaugeLevelColors
    var segments: [GaugeSegment]? = nil
    /// 남은 시간 첫 글자의 잉크 시작 x(pt). 위 라벨 글자 머리와 맞출 때 라벨의 잉크 시작값을 넘긴다.
    var timerInkX: CGFloat? = nil

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = max(0, min(1, progress / 100))
        let dark = scheme == .dark
        GeometryReader { geo in
            let w = geo.size.width * p
            ZStack(alignment: .leading) {
                glow
                    .frame(width: w + 12, height: height + 8)
                    .clipShape(Capsule())
                    .blur(radius: height * 0.31)
                    .opacity(dark ? 0.9 : 0.75)
                    .offset(x: -6)
                GaugeInlineLabels(progress: progress, timer: timer, height: height,
                                  timerColor: Color(light: 0x1D1D1F, dark: 0xFFFFFF),
                                  percentColor: colors.ink, shadow: true, timerInkX: timerInkX)
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(progress.rounded()))%, \(timer)")
    }

    @ViewBuilder
    private var glow: some View {
        if let segments, !segments.isEmpty {
            let denominator = GaugeSegment.denominator(segments)
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(segments) { segment in
                        Rectangle().fill(segment.color).frame(width: g.size.width * segment.percent / denominator)
                    }
                    Spacer(minLength: 0)
                }
            }
        } else {
            Rectangle().fill(EllipticalGradient(stops: [
                .init(color: colors.deep, location: 0),
                .init(color: colors.mid, location: 0.45),
                .init(color: colors.bright.opacity(0.9), location: 0.75),
                .init(color: colors.bright.opacity(0), location: 1)
            ], center: .leading, startRadiusFraction: 0, endRadiusFraction: 1.2))
        }
    }
}

// MARK: - 도넛

/// 끝이 직선(.butt)인 링. 두께 = 지름 × thickness.
/// 고리는 파랑 → 주황 → 빨강 색 띠(각도에 고정)를 채운 만큼 보여주고, 같은 고리를 흐리게 한 헤일로를 깐다.
/// 트랙은 전체 색 띠를 옅게. 90~95%에 걸쳐 전체가 빨강으로 물든다.
struct DonutGauge: View {
    let progress: Double            // 0~100
    let diameter: CGFloat
    var thickness: CGFloat = 0.22
    var segments: [GaugeSegment]? = nil
    var halo = true

    @Environment(\.colorScheme) private var scheme

    private struct Arc {
        let from: CGFloat
        let to: CGFloat
        let color: Color
    }

    var body: some View {
        let p = max(0, min(1, progress / 100))
        let dark = scheme == .dark
        let lineWidth = (diameter * thickness * 10).rounded() / 10
        let ring = Circle().inset(by: lineWidth / 2)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
        let spectrum = AngularGradient(stops: GaugePalette.donutStops(progress: progress),
                                       center: .center, startAngle: .degrees(0), endAngle: .degrees(360))

        ZStack {
            ring.stroke(spectrum, lineWidth: lineWidth).opacity(dark ? 0.2 : 0.16)
            if let segments, !segments.isEmpty {
                ForEach(Array(arcs(total: p, segments: segments).enumerated()), id: \.offset) { _, arc in
                    ring.trim(from: arc.from, to: arc.to).stroke(arc.color, style: style)
                }
            } else {
                if halo {
                    ring.trim(from: 0, to: p).stroke(spectrum, style: style)
                        .blur(radius: diameter / (dark ? 7.5 : 8.5))
                        .opacity(dark ? 0.85 : 0.6)
                }
                ring.trim(from: 0, to: p).stroke(spectrum, style: style)
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(progress.rounded()))%")
    }

    private func arcs(total p: CGFloat, segments: [GaugeSegment]) -> [Arc] {
        let denominator = GaugeSegment.denominator(segments)
        var start: CGFloat = 0
        return segments.map { segment in
            let length = p * CGFloat(segment.percent / denominator)
            defer { start += length }
            return Arc(from: start, to: start + length, color: segment.color)
        }
    }
}

// MARK: - 미리보기: 색 구간 경계값

struct GaugeComponents_Previews: PreviewProvider {
    static let values: [Double] = [0, 1, 38, 55, 69, 70, 89, 92, 100]
    static let sampleSegments: [GaugeSegment] = [
        GaugeSegment(id: "claude_code", percent: 72, color: GaugeSegment.color(forKey: "claude_code")),
        GaugeSegment(id: "chat", percent: 20, color: GaugeSegment.color(forKey: "chat")),
        GaugeSegment(id: "cowork", percent: 6, color: GaugeSegment.color(forKey: "cowork")),
        GaugeSegment(id: "other", percent: 2, color: GaugeSegment.color(forKey: "other"))
    ]

    static func title(_ text: String, _ tokens: DesignTokens) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(tokens.textTertiary)
    }

    static var barColumn: some View {
        let tokens = ThemeKind.toss.tokens
        return VStack(alignment: .leading, spacing: 12) {
            title("헤일로 바", tokens)
            ForEach(values, id: \.self) { v in
                BigGaugeBar(progress: v, timer: v < 50 ? "2:29:59" : "3d 11h", height: 39,
                            colors: GaugePalette.colors(.toss, UsageLevel.from(v)), knockout: tokens.bg)
            }
            title("7d 구성 펼침", tokens)
            BigGaugeBar(progress: 71, timer: "3d 11h", height: 39,
                        colors: GaugePalette.colors(.toss, .warn), knockout: tokens.bg, segments: sampleSegments)
        }
        .frame(width: 318)
        .padding(20)
        .background(tokens.bg)
    }

    static var auraColumn: some View {
        let tokens = ThemeKind.hybrid.tokens
        return VStack(alignment: .leading, spacing: 12) {
            title("오라", tokens)
            ForEach(values, id: \.self) { v in
                AuraGauge(progress: v, timer: v < 50 ? "2:29:59" : "3d 11h", height: 39,
                          colors: GaugePalette.colors(.hybrid, UsageLevel.from(v)))
            }
            title("7d 구성 펼침", tokens)
            AuraGauge(progress: 71, timer: "3d 11h", height: 39,
                      colors: GaugePalette.colors(.hybrid, .warn), segments: sampleSegments)
        }
        .frame(width: 318)
        .padding(20)
        .background(tokens.bg)
    }

    static var donutColumn: some View {
        let tokens = ThemeKind.daangn.tokens
        return VStack(alignment: .leading, spacing: 10) {
            title("도넛", tokens)
            ForEach(values, id: \.self) { v in
                HStack(spacing: 8) {
                    GaugeTimerText(text: v < 50 ? "2:29:59" : "3d 11h 19m", capHeight: 22, color: tokens.textPrimary)
                    Spacer(minLength: 12)
                    DonutGauge(progress: v, diameter: 52)
                    GaugePercentText(value: v, capHeight: 37, color: GaugePalette.colors(.daangn, UsageLevel.from(v)).ink)
                        .frame(width: ceil(37 * GaugeFonts.percentWidthPerCap) + 2, alignment: .trailing)
                }
                .frame(height: 52)
            }
            title("7d 구성 펼침", tokens)
            HStack(spacing: 8) {
                Spacer()
                DonutGauge(progress: 71, diameter: 52, segments: sampleSegments)
            }
        }
        .frame(width: 318)
        .padding(20)
        .background(tokens.bg)
    }

    static var previews: some View {
        HStack(alignment: .top, spacing: 16) {
            donutColumn
            barColumn
            auraColumn
        }
        .padding(16)
        .background(Color.gray.opacity(0.15))
    }
}
