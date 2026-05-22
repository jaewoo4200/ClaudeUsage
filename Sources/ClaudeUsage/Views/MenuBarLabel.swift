import SwiftUI

struct MenuBarLabel: View {
    @EnvironmentObject var vm: UsageViewModel
    @EnvironmentObject var theme: ThemeStore
    @EnvironmentObject var language: LanguageStore

    var body: some View {
        // MenuBarExtra의 label은 NSStatusItem으로 자동 변환되는데,
        // 커스텀 RoundedRectangle+Text 조합은 monochrome 라스터화 때 망가짐.
        // SF Symbol + Text의 단순 HStack이 가장 안정적.
        HStack(spacing: 4) {
            iconImage
            Text(labelText)
                .monospacedDigit()
        }
        .font(.system(size: 13, weight: textWeight))
        .foregroundStyle(textColor)
    }

    @ViewBuilder
    private var iconImage: some View {
        // 사용량 70%+ 면 경고 모양으로, 90%+ 면 위험 모양으로 강조
        // (macOS 메뉴바는 자동으로 단색 렌더링하므로 색이 아닌 모양으로 단계 표시)
        let level = (vm.state.isLoaded ? UsageLevel.from(vm.fiveHourUtilization) : .ok)
        switch level {
        case .ok:
            switch theme.current {
            case .daangn:
                Image(systemName: "c.square.fill").font(.system(size: 14, weight: .heavy))
            case .toss:
                Image(systemName: "circle.fill").font(.system(size: 7))
            case .hybrid:
                Image(systemName: "c.circle.fill").font(.system(size: 14, weight: .heavy))
            }
        case .warn:
            // 경고 — exclamationmark.triangle.fill
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .heavy))
        case .danger:
            // 위험 — exclamationmark.octagon.fill
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.system(size: 14, weight: .heavy))
        }
    }

    private var labelText: String {
        let _ = language.current  // language 변경 시 view invalidate를 위해 참조
        switch vm.state {
        case .needsLogin: return "login".l
        case .loading: return "—"
        case .error: return "!"
        case .loaded:
            let pct = Int(round(vm.fiveHourUtilization))
            return "\(pct)%"
        }
    }

    private var textWeight: Font.Weight {
        if case .loaded = vm.state {
            switch UsageLevel.from(vm.fiveHourUtilization) {
            case .ok: return .semibold
            case .warn: return .bold
            case .danger: return .heavy
            }
        }
        return .semibold
    }

    // 메뉴바는 macOS가 dark/light mode에 따라 자동 컬러 적용하므로 .primary 사용
    private var textColor: Color {
        if case .loaded = vm.state {
            switch UsageLevel.from(vm.fiveHourUtilization) {
            case .ok: return .primary
            case .warn: return .orange
            case .danger: return .red
            }
        }
        return .primary
    }
}
