import SwiftUI
import AppKit

// MARK: - Ring (당근 스타일)

struct RingView: View {
    let progress: Double  // 0~100
    let size: CGFloat
    let lineWidth: CGFloat
    let label: String
    let tokens: DesignTokens

    var body: some View {
        let p = max(0, min(1, progress / 100))
        let level = UsageLevel.from(progress)
        let color = tokens.color(forLevel: level)
        let bg = tokens.bgColor(forLevel: level)
        ZStack {
            Circle().stroke(bg, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: p)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: size * 0.28, weight: .heavy, design: .rounded))
                .foregroundStyle(tokens.textPrimary)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Linear bar (토스 스타일)

struct LinearBar: View {
    let progress: Double
    let height: CGFloat
    let tokens: DesignTokens
    var gradient: Bool = false

    var body: some View {
        let p = max(0, min(1, progress / 100))
        let level = UsageLevel.from(progress)
        let color = tokens.color(forLevel: level)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.12))
                Capsule()
                    .fill(gradient
                        ? AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(color))
                    .frame(width: geo.size.width * p)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Plan badge

struct PlanBadge: View {
    let plan: Plan
    let theme: ThemeKind

    var body: some View {
        TextPlanBadge(
            displayName: plan.displayName,
            compactName: plan.compactName,
            theme: theme
        )
    }
}

struct TextPlanBadge: View {
    let displayName: String
    let compactName: String
    let theme: ThemeKind

    var body: some View {
        let t = theme.tokens
        switch theme {
        case .daangn:
            Text(displayName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(t.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(t.bgRing)
                .clipShape(Capsule())
        case .toss:
            Text(displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(t.bgRing)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .hybrid:
            Text(compactName)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .tracking(0.5)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(t.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

// MARK: - App icon dot (설정 머리 로고)

/// 설정 머리 로고. 타일 모양·크기·C 자리는 테마와 상관없이 같고, 재질만 각 테마의 게이지를 따른다.
/// - 도넛: 3시 방향이 열린 색 띠 고리(파랑 → 주황 → 빨강)가 곧 C. 헤일로를 깐다.
/// - 헤일로 바: 왼쪽 62%만 채운 막대 타일. C는 채움 위에선 흰색(녹아웃), 트랙 위에선 단계 글자 색.
/// - 오라: 왼쪽에서 번지는 빛 위의 먹색 C(다크는 흰색) + 바탕 쪽 글자 그림자.
/// 실제 앱 아이콘(.icns)은 바꾸지 않는다. theme.iconGradient는 Mimo도 쓰므로 여기서는 쓰지 않는다.
struct AppIconDot: View {
    let theme: ThemeKind
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        let surface = Color(light: 0xFFFFFF, dark: 0x2A2C31)
        let hairline = dark ? Color.white.opacity(0.10) : Color.black.opacity(0.09)
        Group {
            switch theme {
            case .daangn:
                let lineWidth = size * 0.16
                // 색 띠 전체(0~100%)를 고리의 288°에 펼친다. 89% 값을 쓰면 90%부터의 빨강 물듦이 섞이지 않는다.
                let spectrum = AngularGradient(stops: GaugePalette.donutStops(progress: 89), center: .center,
                                               startAngle: .degrees(0), endAngle: .degrees(288))
                let arc = Circle().inset(by: lineWidth / 2 + size * 0.17).trim(from: 0, to: 0.8)
                    .stroke(spectrum, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(36))   // 열린 곳을 3시 방향 가운데로
                ZStack {
                    shape.fill(surface)
                    shape.strokeBorder(hairline, lineWidth: 1)
                    arc.blur(radius: size * 0.07).opacity(dark ? 0.9 : 0.65)
                    arc
                }
            case .toss:
                let c = GaugePalette.colors(.toss, .ok)
                let fill = LinearGradient(stops: [.init(color: c.deep, location: 0), .init(color: c.mid, location: 0.6),
                                                  .init(color: c.bright, location: 1)],
                                          startPoint: .leading, endPoint: .trailing)
                let fillWidth = size * 0.62
                ZStack(alignment: .leading) {
                    // 헤일로: 채움을 흐리게 깔아 타일 밖으로 번지게
                    Rectangle().fill(fill).frame(width: fillWidth)
                        .blur(radius: size * 0.12).opacity(dark ? 0.75 : 0.55)
                    ZStack(alignment: .leading) {
                        shape.fill(surface)
                        shape.fill(c.mid.opacity(dark ? 0.16 : 0.12))
                        Rectangle().fill(fill).frame(width: fillWidth)
                        glyph(c.ink)
                        glyph(.white).mask(alignment: .leading) { Rectangle().frame(width: fillWidth) }
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(hairline, lineWidth: 1))
                }
            case .hybrid:
                let c = GaugePalette.colors(.hybrid, .ok)
                ZStack {
                    shape.fill(surface)
                    Rectangle()
                        .fill(EllipticalGradient(stops: [.init(color: c.deep, location: 0),
                                                         .init(color: c.mid, location: 0.45),
                                                         .init(color: c.bright.opacity(0.9), location: 0.75),
                                                         .init(color: c.bright.opacity(0), location: 1)],
                                                 center: .leading, startRadiusFraction: 0, endRadiusFraction: 1.2))
                        .frame(width: size * 0.85, height: size * 0.62)
                        .blur(radius: size * 0.13)
                        .opacity(dark ? 0.9 : 0.75)
                        .frame(width: size, height: size, alignment: .leading)
                    glyph(Color(light: 0x1D1D1F, dark: 0xFFFFFF)).modifier(GaugeTextShadow())
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(hairline, lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func glyph(_ color: Color) -> some View {
        Text("C")
            .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }
}

enum ProviderBrand {
    case claude
    case codex

    var compactLabel: String {
        switch self {
        case .claude: return "C"
        case .codex: return "G"
        }
    }

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}

struct ClaudeProviderIcon: View {
    let size: CGFloat

    var body: some View {
        ProviderBrandIcon(provider: .claude, size: size)
    }
}

struct CodexProviderIcon: View {
    let size: CGFloat

    var body: some View {
        ProviderBrandIcon(provider: .codex, size: size)
    }
}

struct ProviderBrandIcon: View {
    let provider: ProviderBrand
    let size: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if let image = ProviderBrandIconLoader.image(for: provider, colorScheme: colorScheme) {
                Image(nsImage: image)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallback: some View {
        switch provider {
        case .claude:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color(red: 0.85, green: 0.43, blue: 0.29))
                Text("C")
                    .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        case .codex:
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.09, blue: 0.11))
                Text(provider.compactLabel)
                    .font(.system(size: size * 0.52, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}

@MainActor
enum ProviderBrandIconLoader {
    private static var cache: [String: NSImage] = [:]

    static func image(for provider: ProviderBrand, colorScheme: ColorScheme) -> NSImage? {
        let key = "\(provider)-\(colorScheme == .dark ? "dark" : "light")"
        if let cached = cache[key] { return cached }

        let image: NSImage?
        switch provider {
        case .claude:
            image = installedAppIcon(named: "Claude.app")
        case .codex:
            image = installedAppIcon(named: "Codex.app")
                ?? installedCodexIcon(colorScheme: colorScheme)
                ?? installedAppIcon(named: "ChatGPT.app")
        }
        if let image { cache[key] = image }
        return image
    }

    private static func installedAppIcon(named appName: String) -> NSImage? {
        for path in applicationPaths(named: appName) where FileManager.default.fileExists(atPath: path) {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return nil
    }

    private static func installedCodexIcon(colorScheme: ColorScheme) -> NSImage? {
        let preferredNames = colorScheme == .dark
            ? ["icon-codex-dark-color", "icon-codex-light"]
            : ["icon-codex-light", "icon-codex-dark-color"]

        for appPath in applicationPaths(named: "ChatGPT.app") {
            guard let bundle = Bundle(url: URL(fileURLWithPath: appPath)) else { continue }
            for name in preferredNames {
                if let url = bundle.url(forResource: name, withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    return image
                }
            }
        }
        return nil
    }

    private static func applicationPaths(named appName: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications/\(appName)", "\(home)/Applications/\(appName)"]
    }
}
