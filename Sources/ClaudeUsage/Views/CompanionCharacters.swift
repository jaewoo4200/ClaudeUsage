import SwiftUI

struct CompanionCharacter: View {
    let kind: CompanionKind
    let mood: PetMood
    let pressure: Double
    let theme: ThemeKind
    let tokens: DesignTokens
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    @ViewBuilder
    var body: some View {
        switch kind {
        case .mimo:
            MimoCharacter(
                mood: mood,
                pressure: pressure,
                theme: theme,
                tokens: tokens,
                stateColor: stateColor,
                size: size,
                time: time
            )
        case .lumi:
            LumiCharacter(mood: mood, stateColor: stateColor, size: size, time: time)
        case .kumo:
            KumoCharacter(mood: mood, stateColor: stateColor, size: size, time: time)
        case .dot:
            DotCharacter(mood: mood, stateColor: stateColor, size: size, time: time)
        case .navi:
            NaviCharacter(mood: mood, stateColor: stateColor, size: size, time: time)
        case .bori:
            BoriCharacter(mood: mood, stateColor: stateColor, size: size, time: time)
        case .muru:
            MuruCharacter(mood: mood, stateColor: stateColor, size: size, time: time)
        case .tori:
            ToriCharacter(mood: mood, stateColor: stateColor, size: size, time: time)
        case .pico:
            PicoCharacter(
                mood: mood,
                pressure: pressure,
                stateColor: stateColor,
                size: size,
                time: time
            )
        }
    }
}

private struct CompanionMotion {
    let slow: CGFloat
    let quick: CGFloat
    let glance: CGFloat
    let blink: CGFloat
    let pulse: CGFloat

    init(mood: PetMood, time: TimeInterval) {
        slow = CGFloat(sin(time * 1.35))
        quick = CGFloat(sin(time * 3.4))
        glance = CGFloat(sin(time * 0.85))
        let blinkCycle = time.truncatingRemainder(dividingBy: 4.4)
        switch mood {
        case .sleepy:
            blink = 0.38
        case .tired:
            blink = 1
        default:
            blink = blinkCycle > 4.12 ? 0.16 : 1
        }
        pulse = 0.94 + abs(CGFloat(sin(time * 1.7))) * 0.08
    }
}

private struct LumiCharacter: View {
    let mood: PetMood
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let motion = CompanionMotion(mood: mood, time: time)
        let tilt: Double = switch mood {
        case .focused: -8 + Double(motion.quick) * 3
        case .sleepy: 10
        case .tired: 18
        case .refreshed: -4 + Double(motion.quick) * 8
        case .waiting, .calm: -2 + Double(motion.slow) * 3
        }
        let flicker = mood == .tired ? 0.52 + Double(abs(motion.quick)) * 0.38 : 1

        ZStack {
            if mood == .focused || mood == .refreshed {
                PetTriangle()
                    .fill(Color(red: 1, green: 0.82, blue: 0.30).opacity(0.16))
                    .frame(width: size * 0.58, height: size * 0.58)
                    .rotationEffect(.degrees(180))
                    .offset(y: size * 0.10)
                    .scaleEffect(x: 0.92 + motion.pulse * 0.08, y: 1)
            }

            Capsule()
                .fill(Color(red: 0.20, green: 0.43, blue: 0.62))
                .frame(width: size * 0.075, height: size * 0.38)
                .offset(y: size * 0.09)

            Capsule()
                .fill(Color(red: 0.12, green: 0.23, blue: 0.31))
                .frame(width: size * 0.43, height: size * 0.10)
                .overlay(Capsule().stroke(Color.white.opacity(0.32), lineWidth: 0.7))
                .offset(y: size * 0.28)

            ZStack {
                PetLampShade()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1, green: 0.82, blue: 0.28), Color(red: 1, green: 0.55, blue: 0.18)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(PetLampShade().stroke(Color.white.opacity(0.38), lineWidth: 0.8))

                RoundedRectangle(cornerRadius: size * 0.045, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.12, blue: 0.16))
                    .frame(width: size * 0.27, height: size * 0.13)
                    .overlay(
                        CompanionFace(
                            mood: mood,
                            color: stateColor,
                            size: size * 0.62,
                            eyeShift: motion.glance * size * 0.018,
                            blink: motion.blink
                        )
                    )
                    .offset(y: size * 0.025)
            }
            .frame(width: size * 0.50, height: size * 0.36)
            .rotationEffect(.degrees(tilt), anchor: .bottom)
            .opacity(flicker)
            .offset(y: -size * 0.15)

            CompanionStatusGlyph(mood: mood, color: stateColor, size: size, time: time)
        }
        .frame(width: size, height: size)
    }
}

private struct KumoCharacter: View {
    let mood: PetMood
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let motion = CompanionMotion(mood: mood, time: time)
        let cloudTop = mood == .tired
            ? Color(red: 0.38, green: 0.43, blue: 0.50)
            : Color(red: 0.78, green: 0.91, blue: 0.98)
        let cloudBottom = mood == .sleepy || mood == .tired
            ? Color(red: 0.48, green: 0.58, blue: 0.68)
            : Color(red: 0.42, green: 0.76, blue: 0.93)

        ZStack {
            if mood == .refreshed {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: size * 0.30, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.72, blue: 0.18))
                    .rotationEffect(.degrees(Double(motion.quick) * 8))
                    .offset(x: size * 0.22, y: -size * 0.20)
            }

            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: [cloudTop, cloudBottom], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.62, height: size * 0.34)
                    .offset(y: size * 0.06)
                Circle().fill(cloudTop).frame(width: size * 0.33).offset(x: -size * 0.18, y: -size * 0.07)
                Circle().fill(cloudTop).frame(width: size * 0.42).offset(y: -size * 0.12)
                Circle().fill(cloudTop).frame(width: size * 0.30).offset(x: size * 0.20, y: -size * 0.04)
            }
            .overlay(
                CompanionFace(
                    mood: mood,
                    color: Color(red: 0.08, green: 0.25, blue: 0.36),
                    size: size * 0.78,
                    eyeShift: motion.glance * size * 0.018,
                    blink: motion.blink
                )
                .offset(y: size * 0.04)
            )
            .shadow(color: stateColor.opacity(0.18), radius: size * 0.04)

            weather(motion: motion)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func weather(motion: CompanionMotion) -> some View {
        switch mood {
        case .focused:
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.18, weight: .black))
                .foregroundStyle(Color(red: 1, green: 0.74, blue: 0.12))
                .scaleEffect(motion.pulse)
                .offset(y: size * 0.31)
        case .sleepy:
            HStack(spacing: size * 0.11) {
                ForEach(0..<2, id: \.self) { index in
                    Image(systemName: "drop.fill")
                        .font(.system(size: size * 0.10))
                        .foregroundStyle(Color(red: 0.20, green: 0.62, blue: 0.90))
                        .offset(y: CGFloat(index) * size * 0.03 + motion.slow * size * 0.015)
                }
            }
            .offset(y: size * 0.31)
        case .tired:
            HStack(spacing: size * 0.08) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(Color(red: 0.20, green: 0.58, blue: 0.88))
                        .frame(width: size * 0.025, height: size * 0.15)
                        .offset(y: CGFloat(index % 2) * size * 0.03)
                }
            }
            .offset(y: size * 0.32)
        case .refreshed:
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.14, weight: .bold))
                .foregroundStyle(stateColor)
                .offset(x: -size * 0.27, y: size * 0.24)
        case .waiting, .calm:
            EmptyView()
        }
    }
}

private struct DotCharacter: View {
    let mood: PetMood
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let motion = CompanionMotion(mood: mood, time: time)
        let bodyColor = Color(red: 0.42, green: 0.28, blue: 0.82)
        let pixelTravel = mood == .focused ? motion.quick * size * 0.035 : motion.slow * size * 0.015

        ZStack {
            pixel(color: stateColor, side: size * 0.11).offset(x: -size * 0.31, y: -size * 0.21 + pixelTravel)
            pixel(color: Color(red: 0.26, green: 0.88, blue: 0.70), side: size * 0.085)
                .offset(x: size * 0.31, y: -size * 0.08 - pixelTravel)
            pixel(color: bodyColor.opacity(0.78), side: size * 0.075)
                .offset(x: -size * 0.27, y: size * 0.24 - pixelTravel)

            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [bodyColor, Color(red: 0.17, green: 0.65, blue: 0.74)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.55, height: size * 0.58)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                        .stroke(Color.white.opacity(0.34), lineWidth: 0.8)
                )

            RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                .fill(Color(red: 0.045, green: 0.07, blue: 0.12))
                .frame(width: size * 0.42, height: size * 0.27)
                .overlay(
                    CompanionFace(
                        mood: mood,
                        color: stateColor,
                        size: size * 0.78,
                        eyeShift: motion.glance * size * 0.019,
                        blink: motion.blink
                    )
                )
                .offset(y: -size * 0.07)

            HStack(spacing: size * 0.035) {
                Capsule().fill(stateColor).frame(width: size * 0.10, height: size * 0.02)
                Capsule().fill(Color.white.opacity(0.72)).frame(width: size * 0.06, height: size * 0.02)
                Capsule().fill(Color.white.opacity(0.42)).frame(width: size * 0.04, height: size * 0.02)
            }
            .offset(y: size * 0.20)

            CompanionStatusGlyph(mood: mood, color: stateColor, size: size, time: time)
        }
        .frame(width: size, height: size)
    }

    private func pixel(color: Color, side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: max(1, side * 0.18), style: .continuous)
            .fill(color)
            .frame(width: side, height: side)
    }
}

private struct NaviCharacter: View {
    let mood: PetMood
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let motion = CompanionMotion(mood: mood, time: time)
        let orbitY = motion.slow * size * 0.045

        ZStack {
            Ellipse()
                .stroke(Color(red: 0.43, green: 0.50, blue: 0.92).opacity(0.55), lineWidth: max(1, size * 0.018))
                .frame(width: size * 0.82, height: size * 0.40)
                .rotationEffect(.degrees(-14))

            providerDot(label: "C", color: Color(red: 1, green: 0.43, blue: 0.12))
                .offset(x: -size * 0.34, y: orbitY)
            providerDot(label: "G", color: Color(red: 0.25, green: 0.48, blue: 1))
                .offset(x: size * 0.34, y: -orbitY)

            HStack(spacing: size * 0.32) {
                solarPanel
                solarPanel
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.24, green: 0.46, blue: 0.96), Color(red: 0.42, green: 0.26, blue: 0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.46)
                .overlay(Circle().stroke(Color.white.opacity(0.38), lineWidth: 0.8))

            RoundedRectangle(cornerRadius: size * 0.045, style: .continuous)
                .fill(Color(red: 0.035, green: 0.07, blue: 0.13))
                .frame(width: size * 0.33, height: size * 0.19)
                .overlay(
                    CompanionFace(
                        mood: mood,
                        color: stateColor,
                        size: size * 0.66,
                        eyeShift: motion.glance * size * 0.018,
                        blink: motion.blink
                    )
                )
                .offset(y: -size * 0.025)

            if mood == .focused || mood == .refreshed {
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.18, weight: .bold))
                    .foregroundStyle(Color(red: 1, green: 0.54, blue: 0.12))
                    .scaleEffect(x: 0.8, y: motion.pulse)
                    .offset(y: size * 0.31)
            }

            CompanionStatusGlyph(mood: mood, color: stateColor, size: size, time: time)
        }
        .frame(width: size, height: size)
    }

    private func providerDot(label: String, color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: size * 0.16)
            .overlay(
                Text(label)
                    .font(.system(size: size * 0.075, weight: .black))
                    .foregroundStyle(.white)
            )
    }

    private var solarPanel: some View {
        RoundedRectangle(cornerRadius: size * 0.018, style: .continuous)
            .fill(Color(red: 0.12, green: 0.24, blue: 0.48))
            .frame(width: size * 0.20, height: size * 0.25)
            .overlay(
                VStack(spacing: size * 0.025) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(Color.white.opacity(0.32)).frame(height: 0.6)
                    }
                }
                .padding(.horizontal, size * 0.025)
            )
    }
}

private struct BoriCharacter: View {
    let mood: PetMood
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let motion = CompanionMotion(mood: mood, time: time)
        let orange = Color(red: 0.96, green: 0.45, blue: 0.13)
        let cream = Color(red: 1, green: 0.88, blue: 0.65)
        let tailAngle: Double = switch mood {
        case .focused, .refreshed: -48 + Double(motion.quick) * 14
        case .sleepy, .tired: -18
        case .waiting, .calm: -42 + Double(motion.slow) * 7
        }
        let headTilt = mood == .tired ? 9.0 : Double(motion.slow) * 2.5

        ZStack {
            Capsule()
                .fill(orange)
                .frame(width: size * 0.18, height: size * 0.52)
                .overlay(alignment: .bottom) {
                    Capsule().fill(cream).frame(width: size * 0.18, height: size * 0.17)
                }
                .rotationEffect(.degrees(tailAngle), anchor: .bottom)
                .offset(x: size * 0.27, y: size * 0.08)

            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .fill(orange.opacity(0.92))
                .frame(width: size * 0.39, height: size * 0.40)
                .offset(y: size * 0.16)

            ZStack {
                HStack(spacing: size * 0.19) {
                    foxEar(orange: orange, cream: cream, mirrored: false)
                    foxEar(orange: orange, cream: cream, mirrored: true)
                }
                .offset(y: -size * 0.21)

                RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                    .fill(LinearGradient(colors: [orange, Color(red: 0.82, green: 0.25, blue: 0.09)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.52, height: size * 0.42)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.17).stroke(Color.white.opacity(0.28), lineWidth: 0.8))

                Capsule()
                    .fill(cream)
                    .frame(width: size * 0.25, height: size * 0.14)
                    .offset(y: size * 0.08)

                CompanionFace(
                    mood: mood,
                    color: Color(red: 0.16, green: 0.09, blue: 0.07),
                    size: size * 0.70,
                    eyeShift: motion.glance * size * 0.016,
                    blink: motion.blink
                )
                .offset(y: -size * 0.015)

                if mood == .focused {
                    HStack(spacing: size * 0.055) {
                        Circle().stroke(stateColor, lineWidth: max(1, size * 0.018)).frame(width: size * 0.14)
                        Circle().stroke(stateColor, lineWidth: max(1, size * 0.018)).frame(width: size * 0.14)
                    }
                    .overlay(Capsule().fill(stateColor).frame(width: size * 0.065, height: size * 0.018))
                    .offset(y: -size * 0.045)
                }
            }
            .rotationEffect(.degrees(headTilt))
            .offset(y: -size * 0.08)

            if mood == .focused {
                RoundedRectangle(cornerRadius: size * 0.025, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.11, blue: 0.16))
                    .frame(width: size * 0.40, height: size * 0.16)
                    .overlay(Circle().fill(stateColor).frame(width: size * 0.05))
                    .offset(y: size * 0.27)
            }

            CompanionStatusGlyph(mood: mood, color: stateColor, size: size, time: time)
        }
        .frame(width: size, height: size)
    }

    private func foxEar(orange: Color, cream: Color, mirrored: Bool) -> some View {
        PetTriangle()
            .fill(orange)
            .frame(width: size * 0.22, height: size * 0.28)
            .overlay(
                PetTriangle()
                    .fill(cream.opacity(0.85))
                    .frame(width: size * 0.10, height: size * 0.14)
                    .offset(y: size * 0.045)
            )
            .rotationEffect(.degrees(mirrored ? 8 : -8))
    }
}

private struct MuruCharacter: View {
    let mood: PetMood
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let motion = CompanionMotion(mood: mood, time: time)
        let capColor = mood == .tired
            ? Color(red: 0.62, green: 0.20, blue: 0.20)
            : Color(red: 0.90, green: 0.28, blue: 0.28)
        let capTilt = mood == .sleepy || mood == .tired ? 8.0 : Double(motion.slow) * 2

        ZStack {
            Capsule()
                .fill(Color(red: 0.94, green: 0.82, blue: 0.62))
                .frame(width: size * 0.31, height: size * 0.50)
                .overlay(Capsule().stroke(Color.white.opacity(0.34), lineWidth: 0.8))
                .offset(y: size * 0.13)

            CompanionFace(
                mood: mood,
                color: Color(red: 0.20, green: 0.13, blue: 0.10),
                size: size * 0.68,
                eyeShift: motion.glance * size * 0.016,
                blink: motion.blink
            )
            .offset(y: size * 0.10)

            ZStack {
                PetMushroomCap()
                    .fill(LinearGradient(colors: [capColor, capColor.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                    .overlay(PetMushroomCap().stroke(Color.white.opacity(0.34), lineWidth: 0.8))
                Circle().fill(Color.white.opacity(0.82)).frame(width: size * 0.09).offset(x: -size * 0.16, y: -size * 0.03)
                Circle().fill(Color.white.opacity(0.68)).frame(width: size * 0.07).offset(x: size * 0.14, y: size * 0.01)
                Circle().fill(Color.white.opacity(0.72)).frame(width: size * 0.055).offset(y: -size * 0.09)
            }
            .frame(width: size * 0.66, height: size * 0.38)
            .rotationEffect(.degrees(capTilt), anchor: .bottom)
            .offset(y: -size * 0.20)

            if mood == .refreshed {
                HStack(spacing: -size * 0.02) {
                    Image(systemName: "leaf.fill").rotationEffect(.degrees(-32))
                    Image(systemName: "leaf.fill").rotationEffect(.degrees(32))
                }
                .font(.system(size: size * 0.13, weight: .bold))
                .foregroundStyle(Color(red: 0.24, green: 0.72, blue: 0.36))
                .offset(y: -size * 0.37)
            } else if mood == .focused {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(stateColor)
                    .offset(x: size * 0.27, y: size * 0.22)
            }

            CompanionStatusGlyph(mood: mood, color: stateColor, size: size, time: time)
        }
        .frame(width: size, height: size)
    }
}

private struct ToriCharacter: View {
    let mood: PetMood
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let motion = CompanionMotion(mood: mood, time: time)
        let flap: Double = switch mood {
        case .focused, .refreshed: 22 + Double(motion.quick) * 30
        case .sleepy, .tired: 8
        case .waiting, .calm: 18 + Double(motion.slow) * 8
        }
        let yellow = Color(red: 0.98, green: 0.72, blue: 0.16)

        ZStack {
            if mood == .sleepy || mood == .tired {
                VStack(spacing: size * 0.018) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(Color(red: 0.55, green: 0.34, blue: 0.16).opacity(0.72))
                            .frame(width: size * (0.52 - CGFloat(index) * 0.06), height: size * 0.035)
                    }
                }
                .offset(y: size * 0.29)
            }

            PetWing()
                .fill(Color(red: 0.24, green: 0.56, blue: 0.86))
                .frame(width: size * 0.25, height: size * 0.38)
                .rotationEffect(.degrees(-flap), anchor: .trailing)
                .offset(x: -size * 0.27, y: size * 0.04)

            PetWing()
                .fill(Color(red: 0.24, green: 0.56, blue: 0.86))
                .frame(width: size * 0.25, height: size * 0.38)
                .scaleEffect(x: -1, y: 1)
                .rotationEffect(.degrees(flap), anchor: .leading)
                .offset(x: size * 0.27, y: size * 0.04)

            Circle()
                .fill(LinearGradient(colors: [yellow, Color(red: 0.96, green: 0.46, blue: 0.12)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.50)
                .overlay(Circle().stroke(Color.white.opacity(0.32), lineWidth: 0.8))

            CompanionFace(
                mood: mood,
                color: Color(red: 0.15, green: 0.11, blue: 0.07),
                size: size * 0.68,
                eyeShift: motion.glance * size * 0.016,
                blink: motion.blink
            )
            .offset(y: -size * 0.03)

            PetTriangle()
                .fill(Color(red: 0.92, green: 0.28, blue: 0.08))
                .frame(width: size * 0.11, height: size * 0.10)
                .rotationEffect(.degrees(180))
                .offset(y: size * 0.07)

            CompanionStatusGlyph(mood: mood, color: stateColor, size: size, time: time)
        }
        .frame(width: size, height: size)
    }
}

private struct PicoCharacter: View {
    let mood: PetMood
    let pressure: Double
    let stateColor: Color
    let size: CGFloat
    let time: TimeInterval

    var body: some View {
        let motion = CompanionMotion(mood: mood, time: time)
        let pink = Color(red: 0.96, green: 0.36, blue: 0.52)
        let remaining = max(0.08, min(1, 1 - pressure / 100))
        let batteryWidth = size * 0.20 * remaining
        let earDroop = mood == .sleepy || mood == .tired ? 18.0 : Double(motion.slow) * 3

        ZStack {
            Capsule()
                .fill(pink.opacity(0.86))
                .frame(width: size * 0.09, height: size * 0.38)
                .rotationEffect(.degrees(42 + Double(motion.slow) * 7), anchor: .bottom)
                .offset(x: size * 0.29, y: size * 0.13)

            RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                .fill(LinearGradient(colors: [pink, Color(red: 0.30, green: 0.24, blue: 0.48)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.48, height: size * 0.52)
                .overlay(RoundedRectangle(cornerRadius: size * 0.13).stroke(Color.white.opacity(0.30), lineWidth: 0.8))
                .offset(y: size * 0.07)

            HStack(spacing: size * 0.18) {
                catEar(pink: pink).rotationEffect(.degrees(-earDroop))
                catEar(pink: pink).rotationEffect(.degrees(earDroop))
            }
            .offset(y: -size * 0.27)

            RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                .fill(Color(red: 0.045, green: 0.06, blue: 0.11))
                .frame(width: size * 0.36, height: size * 0.23)
                .overlay(
                    CompanionFace(
                        mood: mood,
                        color: stateColor,
                        size: size * 0.70,
                        eyeShift: motion.glance * size * 0.018,
                        blink: motion.blink
                    )
                )
                .offset(y: -size * 0.07)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: size * 0.018, style: .continuous)
                    .stroke(Color.white.opacity(0.72), lineWidth: max(0.8, size * 0.013))
                    .frame(width: size * 0.22, height: size * 0.085)
                RoundedRectangle(cornerRadius: size * 0.012, style: .continuous)
                    .fill(stateColor)
                    .frame(width: batteryWidth, height: size * 0.055)
                    .padding(.leading, size * 0.012)
            }
            .frame(width: size * 0.22, height: size * 0.085)
            .offset(y: size * 0.20)

            CompanionStatusGlyph(mood: mood, color: stateColor, size: size, time: time)
        }
        .frame(width: size, height: size)
    }

    private func catEar(pink: Color) -> some View {
        PetTriangle()
            .fill(pink)
            .frame(width: size * 0.20, height: size * 0.25)
            .overlay(
                PetTriangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: size * 0.09, height: size * 0.12)
                    .offset(y: size * 0.04)
            )
    }
}

private struct CompanionFace: View {
    let mood: PetMood
    let color: Color
    let size: CGFloat
    let eyeShift: CGFloat
    let blink: CGFloat

    var body: some View {
        VStack(spacing: max(1, size * 0.025)) {
            HStack(spacing: size * 0.105) {
                eye(mirrored: false)
                eye(mirrored: true)
            }
            .offset(x: eyeShift)
            .scaleEffect(x: 1, y: blink)
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
            Image(systemName: "minus")
                .font(.system(size: size * 0.08, weight: .heavy))
                .foregroundStyle(color)
        }
    }
}

private struct CompanionStatusGlyph: View {
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

private struct PetTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PetLampShade: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.30, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.width * 0.70, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PetMushroomCap: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.width * 0.08, y: rect.minY),
            control2: CGPoint(x: rect.width * 0.92, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control1: CGPoint(x: rect.width * 0.78, y: rect.height * 0.82),
            control2: CGPoint(x: rect.width * 0.22, y: rect.height * 0.82)
        )
        path.closeSubpath()
        return path
    }
}

private struct PetWing: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY),
            control1: CGPoint(x: rect.width * 0.58, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.height * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control1: CGPoint(x: rect.width * 0.42, y: rect.height * 0.90),
            control2: CGPoint(x: rect.width * 0.76, y: rect.height * 0.72)
        )
        path.closeSubpath()
        return path
    }
}
