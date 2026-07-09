import SwiftUI

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
                .animation(.easeOut(duration: 0.4), value: p)
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
                    .animation(.easeOut(duration: 0.4), value: p)
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

struct OpenAIIconDot: View {
    let theme: ThemeKind
    let size: CGFloat

    var body: some View {
        let tokens = theme.tokens
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(tokens.textPrimary)
                .frame(width: size, height: size)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(tokens.bg)
        }
    }
}
