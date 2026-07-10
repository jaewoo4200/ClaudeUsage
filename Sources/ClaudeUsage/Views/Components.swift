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

// MARK: - App icon dot (헤더 등에 쓰는 작은 아이콘)

struct AppIconDot: View {
    let theme: ThemeKind
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(theme.iconGradient)
                .frame(width: size, height: size)
            Text("C")
                .font(.system(size: size * 0.55, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
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
