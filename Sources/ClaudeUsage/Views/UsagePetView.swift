import SwiftUI

struct PetSummaryCard: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var history: UsageHistoryStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        let snapshot = vm.historySnapshot(includingSpark: settings.showOpenAISparkLimits)
        let trend = settings.usageHistoryEnabled ? history.trend() : .empty
        let mood = PetMood.resolve(
            snapshot: snapshot,
            trend: trend,
            sensitivity: settings.mimoSensitivity
        )

        HStack(spacing: 12) {
            MimoAvatar(
                mood: mood,
                pressure: snapshot.pressure ?? 0,
                theme: theme.current,
                size: 58,
                animationMode: settings.mimoAnimationMode
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Mimo")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tokens.textPrimary)
                    Text(mood.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(moodColor(mood, tokens: tokens))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(moodColor(mood, tokens: tokens).opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(mood.message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tokens.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(detailText(snapshot: snapshot, trend: trend))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tokens.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    if trend.points.count > 1 {
                        MiniUsageSparkline(points: trend.points, color: moodColor(mood, tokens: tokens))
                            .frame(width: 60, height: 20)
                    }
                }
            }
        }
        .padding(10)
        .background(tokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tokens.border, lineWidth: 1)
        )
    }

    private func detailText(snapshot: UsageHistorySnapshot, trend: UsageTrend) -> String {
        if let tokens = trend.recentTokenDelta, tokens > 0 {
            return String(format: "pet_recent_tokens_format".l, TokenCountFormatter.compact(tokens))
        }
        if let burn = trend.percentPerHour, burn > 0.1 {
            return String(format: "pet_recent_rate_format".l, burn)
        }
        if let pressure = snapshot.pressure {
            return String(format: "pet_pressure_format".l, pressure)
        }
        return "pet_waiting_detail".l
    }
}

struct WidgetMimoCompanion: View {
    var wide: Bool = false

    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var history: UsageHistoryStore
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        let tokens = theme.current.tokens
        let snapshot = vm.historySnapshot(includingSpark: settings.showOpenAISparkLimits)
        let trend = settings.usageHistoryEnabled ? history.trend() : .empty
        let mood = PetMood.resolve(
            snapshot: snapshot,
            trend: trend,
            sensitivity: settings.mimoSensitivity
        )

        Group {
            if wide {
                wideLayout(snapshot: snapshot, trend: trend, mood: mood, tokens: tokens)
            } else {
                compactLayout(snapshot: snapshot, trend: trend, mood: mood, tokens: tokens)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mimo, \(mood.title), \(mood.message)")
    }

    private func compactLayout(
        snapshot: UsageHistorySnapshot,
        trend: UsageTrend,
        mood: PetMood,
        tokens: DesignTokens
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            MimoAvatar(
                mood: mood,
                pressure: snapshot.pressure ?? 0,
                theme: theme.current,
                size: 66,
                animationMode: settings.mimoAnimationMode,
                animationActive: settings.floatingWidgetVisible
            )
            .frame(width: 66, height: 66, alignment: .top)

            VStack(alignment: .leading, spacing: 2) {
                nameRow(mood: mood, tokens: tokens)
                    .frame(height: 16, alignment: .leading)
                Text(mood.message)
                    .font(.system(size: 9.2, weight: .semibold))
                    .foregroundStyle(tokens.textSecondary)
                    .lineLimit(3)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                    .layoutPriority(2)

                HStack(spacing: 4) {
                    Text(compactDetail(snapshot: snapshot, trend: trend))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(tokens.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .allowsTightening(true)
                        .layoutPriority(1)
                    Spacer(minLength: 2)
                    if trend.points.count > 1 {
                        MiniUsageSparkline(points: trend.points, color: moodColor(mood, tokens: tokens))
                            .frame(width: 34, height: 13)
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 66)
    }

    private func wideLayout(
        snapshot: UsageHistorySnapshot,
        trend: UsageTrend,
        mood: PetMood,
        tokens: DesignTokens
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            MimoAvatar(
                mood: mood,
                pressure: snapshot.pressure ?? 0,
                theme: theme.current,
                size: 78,
                animationMode: settings.mimoAnimationMode,
                animationActive: settings.floatingWidgetVisible
            )
            .frame(width: 78, height: 78)

            VStack(alignment: .leading, spacing: 2) {
                nameRow(mood: mood, tokens: tokens)
                    .frame(height: 16, alignment: .leading)
                Text(mood.message)
                    .font(.system(size: 9.2, weight: .semibold))
                    .foregroundStyle(tokens.textSecondary)
                    .lineLimit(3)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .topLeading)
                    .layoutPriority(2)
                HStack(spacing: 4) {
                    Text(compactDetail(snapshot: snapshot, trend: trend))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(tokens.textTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .layoutPriority(1)
                    Spacer(minLength: 2)
                    if trend.points.count > 1 {
                        MiniUsageSparkline(points: trend.points, color: moodColor(mood, tokens: tokens))
                            .frame(width: 30, height: 13)
                    }
                }
                .frame(height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
    }

    private func nameRow(mood: PetMood, tokens: DesignTokens) -> some View {
        HStack(spacing: 5) {
            Text("Mimo")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tokens.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(mood.title)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(moodColor(mood, tokens: tokens))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(moodColor(mood, tokens: tokens).opacity(0.12))
                .clipShape(Capsule())
                .layoutPriority(2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactDetail(snapshot: UsageHistorySnapshot, trend: UsageTrend) -> String {
        if let tokens = trend.recentTokenDelta, tokens > 0 {
            return String(format: "pet_recent_tokens_short_format".l, TokenCountFormatter.compact(tokens))
        }
        if let burn = trend.percentPerHour, burn > 0.1 {
            return String(format: "pet_recent_rate_short_format".l, burn)
        }
        if let pressure = snapshot.pressure {
            return String(format: "pet_pressure_short_format".l, pressure)
        }
        return "pet_waiting_detail".l
    }
}

struct WidgetPetRow: View {
    var body: some View {
        WidgetMimoCompanion()
    }
}

struct MimoAvatar: View {
    let mood: PetMood
    let pressure: Double
    let theme: ThemeKind
    let size: CGFloat
    var animationTime: TimeInterval? = nil
    var animationMode: MimoAnimationMode = .automatic
    var animationActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let tokens = theme.tokens
        let stateColor = moodColor(mood, tokens: tokens)
        ZStack {
            Circle()
                .stroke(tokens.bgRing, lineWidth: max(2, size * 0.055))
            Circle()
                .trim(from: 0, to: max(0.04, min(1, pressure / 100)))
                .stroke(
                    stateColor,
                    style: StrokeStyle(lineWidth: max(2, size * 0.055), lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            character(tokens: tokens, stateColor: stateColor)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Mimo, \(mood.title)")
    }

    @ViewBuilder
    private func character(tokens: DesignTokens, stateColor: Color) -> some View {
        if let animationTime {
            MimoCharacter(
                mood: mood,
                pressure: pressure,
                theme: theme,
                tokens: tokens,
                stateColor: stateColor,
                size: size,
                time: reduceMotion ? 0 : animationTime
            )
        } else if !reduceMotion,
                  animationActive,
                  let interval = animationMode.updateInterval(for: mood) {
            TimelineView(.periodic(from: .now, by: interval)) { context in
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let tick = Int(elapsed / interval)
                MimoCharacter(
                    mood: mood,
                    pressure: pressure,
                    theme: theme,
                    tokens: tokens,
                    stateColor: stateColor,
                    size: size,
                    time: TimeInterval(tick) * interval
                )
                .animation(
                    .easeInOut(duration: animationMode.transitionDuration(for: mood)),
                    value: tick
                )
            }
        } else {
            MimoCharacter(
                mood: mood,
                pressure: pressure,
                theme: theme,
                tokens: tokens,
                stateColor: stateColor,
                size: size,
                time: 0
            )
        }
    }
}

private struct MimoCharacter: View {
    let mood: PetMood
    let pressure: Double
    let theme: ThemeKind
    let tokens: DesignTokens
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let pose = MimoPose.resolve(mood: mood, time: time)
        let levelColor = tokens.color(forLevel: UsageLevel.from(pressure))

        ZStack {
            MimoLeg(size: size, color: levelColor, angle: pose.leftLeg, footDirection: -1)
                .offset(x: -size * 0.12, y: size * 0.28)
            MimoLeg(size: size, color: tokens.accentSecondary, angle: pose.rightLeg, footDirection: 1)
                .offset(x: size * 0.12, y: size * 0.28)

            MimoArm(size: size, color: levelColor, angle: pose.leftArm)
                .offset(x: -size * 0.27, y: size * 0.035)
            MimoArm(size: size, color: tokens.accentSecondary, angle: pose.rightArm)
                .offset(x: size * 0.27, y: size * 0.035)

            Capsule()
                .fill(levelColor.opacity(0.7))
                .frame(width: size * 0.105, height: size * 0.25)
                .offset(x: -size * 0.29, y: -size * 0.035)
            Capsule()
                .fill(tokens.accentSecondary.opacity(0.7))
                .frame(width: size * 0.105, height: size * 0.25)
                .offset(x: size * 0.29, y: -size * 0.035)

            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(theme.iconGradient)
                .frame(width: size * 0.56, height: size * 0.58)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .stroke(Color.white.opacity(0.28), lineWidth: max(0.8, size * 0.014))
                )
                .offset(y: size * 0.005)

            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .fill(Color(red: 0.055, green: 0.071, blue: 0.11))
                .frame(width: size * 0.43, height: size * 0.25)
                .overlay(
                    MimoExpression(
                        mood: mood,
                        color: stateColor,
                        size: size,
                        eyeShift: size * pose.eyeShift,
                        blinkScale: pose.blinkScale
                    )
                )
                .offset(y: -size * 0.07)

            if mood == .focused {
                MimoLaptop(
                    size: size,
                    leftHandColor: levelColor,
                    rightHandColor: tokens.accentSecondary,
                    screenAccent: stateColor,
                    time: time
                )
            } else {
                Circle()
                    .fill(Color.white.opacity(0.92))
                    .frame(width: size * 0.075, height: size * 0.075)
                    .overlay(
                        Circle()
                            .trim(from: 0, to: max(0.08, min(1, pressure / 100)))
                            .stroke(stateColor, lineWidth: max(1, size * 0.022))
                            .rotationEffect(.degrees(-90))
                    )
                    .scaleEffect(pose.statusPulse)
                    .offset(y: size * 0.205)
            }

            MimoActionMark(mood: mood, color: stateColor, size: size, time: time)
        }
        .frame(width: size, height: size)
    }
}

private struct MimoLaptop: View {
    let size: CGFloat
    let leftHandColor: Color
    let rightHandColor: Color
    let screenAccent: Color
    let time: TimeInterval

    var body: some View {
        let leftTap = CGFloat(sin(time * 7.2)) * size * 0.012
        let rightTap = CGFloat(sin(time * 7.2 + .pi)) * size * 0.012

        ZStack {
            // Mimo faces the display; the viewer sees the back of the lid.
            RoundedRectangle(cornerRadius: size * 0.045, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.14, blue: 0.20),
                            Color(red: 0.045, green: 0.06, blue: 0.11)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.54, height: size * 0.25)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.045, style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: max(0.7, size * 0.012))
                )
                .shadow(color: screenAccent.opacity(0.22), radius: size * 0.035)
                .offset(y: size * 0.205)

            Circle()
                .fill(screenAccent.opacity(0.95))
                .frame(width: size * 0.095, height: size * 0.095)
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: size * 0.025, height: size * 0.025)
                )
                .offset(y: size * 0.205)

            MimoKeyboardDeck(size: size, accent: screenAccent)
                .offset(y: size * 0.055)

            Circle()
                .fill(leftHandColor)
                .frame(width: size * 0.09, height: size * 0.09)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.6))
                .offset(x: -size * 0.16, y: size * 0.015 + leftTap)

            Circle()
                .fill(rightHandColor)
                .frame(width: size * 0.09, height: size * 0.09)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.6))
                .offset(x: size * 0.16, y: size * 0.015 + rightTap)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct MimoKeyboardDeck: View {
    let size: CGFloat
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.92), Color.white.opacity(0.62)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.58, height: size * 0.12)
                .rotation3DEffect(.degrees(54), axis: (x: 1, y: 0, z: 0))

            VStack(spacing: size * 0.018) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: size * 0.018) {
                        ForEach(0..<5, id: \.self) { column in
                            Capsule()
                                .fill((row == 1 && column == 2 ? accent : Color.black).opacity(0.48))
                                .frame(width: size * 0.05, height: max(1, size * 0.012))
                        }
                    }
                }
            }
            .offset(y: -size * 0.008)
        }
        .frame(width: size * 0.62, height: size * 0.14)
    }
}

private struct MimoArm: View {
    let size: CGFloat
    let color: Color
    let angle: Double

    var body: some View {
        VStack(spacing: -size * 0.025) {
            Capsule()
                .fill(color.opacity(0.94))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.7))
                .frame(width: size * 0.095, height: size * 0.22)
            Circle()
                .fill(color)
                .frame(width: size * 0.11, height: size * 0.11)
        }
        .frame(width: size * 0.13, height: size * 0.30, alignment: .top)
        .rotationEffect(.degrees(angle), anchor: .top)
    }
}

private struct MimoLeg: View {
    let size: CGFloat
    let color: Color
    let angle: Double
    let footDirection: CGFloat

    var body: some View {
        VStack(spacing: -size * 0.018) {
            Capsule()
                .fill(color.opacity(0.94))
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.7))
                .frame(width: size * 0.095, height: size * 0.15)
            Capsule()
                .fill(color)
                .frame(width: size * 0.14, height: size * 0.07)
                .offset(x: footDirection * size * 0.025)
        }
        .frame(width: size * 0.16, height: size * 0.23, alignment: .top)
        .rotationEffect(.degrees(angle), anchor: .top)
    }
}

private struct MimoPose {
    let leftArm: Double
    let rightArm: Double
    let leftLeg: Double
    let rightLeg: Double
    let eyeShift: CGFloat
    let blinkScale: CGFloat
    let statusPulse: CGFloat

    static func resolve(mood: PetMood, time: TimeInterval) -> MimoPose {
        let slow = sin(time * 1.35)
        let quick = sin(time * 3.4)
        let glance = CGFloat(sin(time * 0.85))
        let blinkCycle = time.truncatingRemainder(dividingBy: 4.4)
        let blink: CGFloat = blinkCycle > 4.12 ? 0.16 : 1
        let pulse = CGFloat(0.94 + abs(sin(time * 1.7)) * 0.08)

        switch mood {
        case .waiting:
            return MimoPose(
                leftArm: 17 + slow * 5,
                rightArm: -17 - slow * 5,
                leftLeg: quick * 7,
                rightLeg: -quick * 7,
                eyeShift: glance * 0.028,
                blinkScale: blink,
                statusPulse: pulse
            )
        case .calm:
            return MimoPose(
                leftArm: 16 + slow * 4,
                rightArm: -16 - slow * 4,
                leftLeg: slow * 2,
                rightLeg: -slow * 2,
                eyeShift: glance * 0.022,
                blinkScale: blink,
                statusPulse: pulse
            )
        case .focused:
            return MimoPose(
                leftArm: 22 + quick * 7,
                rightArm: -22 - quick * 7,
                leftLeg: quick * 3,
                rightLeg: -quick * 3,
                eyeShift: CGFloat(quick) * 0.026,
                blinkScale: max(0.7, blink),
                statusPulse: pulse
            )
        case .sleepy:
            return MimoPose(
                leftArm: 24 + slow * 4,
                rightArm: -24 - slow * 4,
                leftLeg: 8,
                rightLeg: -8,
                eyeShift: 0,
                blinkScale: 0.42,
                statusPulse: 0.94
            )
        case .tired:
            return MimoPose(
                leftArm: 34 + slow * 5,
                rightArm: -34 - slow * 5,
                leftLeg: 12,
                rightLeg: -12,
                eyeShift: 0,
                blinkScale: 1,
                statusPulse: 0.9
            )
        case .refreshed:
            return MimoPose(
                leftArm: 16 + slow * 4,
                rightArm: -132 + quick * 24,
                leftLeg: -4 + quick * 6,
                rightLeg: 4 - quick * 6,
                eyeShift: glance * 0.03,
                blinkScale: blink,
                statusPulse: pulse
            )
        }
    }
}

private struct MimoActionMark: View {
    let mood: PetMood
    let color: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let opacity = 0.55 + abs(sin(time * 1.6)) * 0.35
        Group {
            switch mood {
            case .focused:
                Image(systemName: "bolt.fill")
            case .sleepy:
                Text("z")
            case .tired:
                Image(systemName: "drop.fill")
            case .refreshed:
                Image(systemName: "sparkles")
            case .waiting, .calm:
                EmptyView()
            }
        }
        .font(.system(size: size * 0.105, weight: .heavy))
        .foregroundStyle(color)
        .opacity(opacity)
        .offset(x: size * 0.31, y: -size * 0.29)
        .accessibilityHidden(true)
    }
}

private struct MimoExpression: View {
    let mood: PetMood
    let color: Color
    let size: CGFloat
    let eyeShift: CGFloat
    let blinkScale: CGFloat

    var body: some View {
        VStack(spacing: max(1, size * 0.025)) {
            HStack(spacing: size * 0.105) {
                eye(mirrored: false)
                eye(mirrored: true)
            }
            .offset(x: eyeShift)
            .scaleEffect(x: 1, y: blinkScale, anchor: .center)
            mouth
        }
    }

    @ViewBuilder
    private func eye(mirrored: Bool) -> some View {
        switch mood {
        case .waiting:
            Circle().fill(color).frame(width: size * 0.045, height: size * 0.045)
        case .calm, .refreshed:
            Capsule().fill(color).frame(width: size * 0.09, height: size * 0.038)
        case .focused:
            Capsule()
                .fill(color)
                .frame(width: size * 0.09, height: size * 0.032)
                .rotationEffect(.degrees(mirrored ? 11 : -11))
        case .sleepy:
            Capsule().fill(color).frame(width: size * 0.09, height: size * 0.025)
        case .tired:
            Image(systemName: "xmark")
                .font(.system(size: size * 0.09, weight: .heavy))
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch mood {
        case .waiting, .focused:
            Circle().fill(color).frame(width: size * 0.028, height: size * 0.028)
        case .calm:
            Capsule().fill(color).frame(width: size * 0.10, height: size * 0.024)
        case .refreshed:
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.075, weight: .heavy))
                .foregroundStyle(color)
        case .sleepy:
            Capsule().fill(color).frame(width: size * 0.075, height: size * 0.02)
        case .tired:
            MimoWavyMouth(color: color)
                .frame(width: size * 0.12, height: size * 0.045)
        }
    }
}

private struct MimoWavyMouth: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height * 0.7))
            path.addLine(to: CGPoint(x: size.width * 0.33, y: size.height * 0.3))
            path.addLine(to: CGPoint(x: size.width * 0.66, y: size.height * 0.7))
            path.addLine(to: CGPoint(x: size.width, y: size.height * 0.3))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        }
    }
}

private struct MiniUsageSparkline: View {
    let points: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard points.count > 1,
                  let minimum = points.min(),
                  let maximum = points.max() else { return }
            let range = max(8, maximum - minimum)
            var path = Path()
            for (index, point) in points.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(points.count - 1)
                let normalized = (point - minimum) / range
                let y = size.height - (size.height * CGFloat(normalized) * 0.8 + size.height * 0.1)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private func moodColor(_ mood: PetMood, tokens: DesignTokens) -> Color {
    switch mood {
    case .waiting: return tokens.textTertiary
    case .calm, .refreshed: return tokens.ok
    case .focused: return tokens.accent
    case .sleepy: return tokens.warn
    case .tired: return tokens.danger
    }
}

enum TokenCountFormatter {
    static func compact(_ value: Int64) -> String {
        let number = Double(value)
        if value >= 1_000_000_000 { return String(format: "%.1fB", number / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return "\(value)"
    }
}

private extension PetMood {
    @MainActor
    var title: String {
        switch self {
        case .waiting: return "pet_mood_waiting".l
        case .calm: return "pet_mood_calm".l
        case .focused: return "pet_mood_focused".l
        case .sleepy: return "pet_mood_sleepy".l
        case .tired: return "pet_mood_tired".l
        case .refreshed: return "pet_mood_refreshed".l
        }
    }

    @MainActor
    var message: String {
        let keys: [String]
        let moodOffset: Int
        switch self {
        case .waiting:
            keys = ["pet_message_waiting", "pet_message_waiting_alt1", "pet_message_waiting_alt2"]
            moodOffset = 0
        case .calm:
            keys = ["pet_message_calm", "pet_message_calm_alt1", "pet_message_calm_alt2"]
            moodOffset = 1
        case .focused:
            keys = ["pet_message_focused", "pet_message_focused_alt1", "pet_message_focused_alt2"]
            moodOffset = 2
        case .sleepy:
            keys = ["pet_message_sleepy", "pet_message_sleepy_alt1", "pet_message_sleepy_alt2"]
            moodOffset = 3
        case .tired:
            keys = ["pet_message_tired", "pet_message_tired_alt1", "pet_message_tired_alt2"]
            moodOffset = 4
        case .refreshed:
            keys = ["pet_message_refreshed", "pet_message_refreshed_alt1", "pet_message_refreshed_alt2"]
            moodOffset = 5
        }
        let timeBucket = Int(Date().timeIntervalSince1970 / 300)
        return keys[(timeBucket + moodOffset) % keys.count].l
    }
}
