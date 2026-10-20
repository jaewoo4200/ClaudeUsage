import SwiftUI

// Shared metrics retain the classic themes and offer three independent gauge styles.
// Dropdown details expand inline; widgets delegate details to their layout-specific panel.

/// 드롭다운/위젯별 크기. 폭을 알면 겹치지 않는 크기를 계산한다.
struct GaugeStyle {
    let width: CGFloat
    let isWidget: Bool

    /// 드롭다운 콘텐츠 폭: MenuBarContentView 320 − 스크롤 여백 2
    static let dropdown = GaugeStyle(width: 318, isWidget: false)
    static func widget(width: CGFloat) -> GaugeStyle { GaugeStyle(width: width, isWidget: true) }

    // 헤일로 바 · 오라
    /// 줄 하나의 높이를 도넛 줄과 같게 맞춘다: 라벨 줄 + 간격 + 막대 = 도넛 지름, 줄 사이 간격도 도넛과 같다.
    /// 그래서 테마를 바꿔도 드롭다운·위젯 크기가 그대로다.
    /// 막대를 두툼하게 두려고 라벨 줄을 글자 높이만큼만 쓴다: 드롭다운 52 − 14 − 2 = 36pt, 위젯 44 − 16 − 4 = 24pt.
    /// 단, 남은 시간과 "100%"가 겹치지 않는 높이를 넘지 않는다(위젯은 폭 때문에 24pt가 한계).
    var barHeight: CGFloat { min(donutDiameter - barLabelHeight - barLabelGap, Self.maxBarHeight(width: width)) }
    /// 짧은 표기: 7일 창이 하루 이상 남았을 때 분을 뺀다 ("3d 11h"). 5시간 창은 항상 시:분:초.
    var shortTimer: Bool { true }
    var barLabelSize: CGFloat { isWidget ? 10.5 : 12 }
    /// 도넛 줄의 라벨 줄 높이("구성" 버튼이 들어가는 높이)
    var labelHeight: CGFloat { isWidget ? 16 : 20 }
    /// 바·오라 줄의 라벨 줄 높이. 드롭다운은 라벨 글자 높이(12pt ≈ 14)만큼만 쓰고 "구성" 버튼을 그 안에 맞춘다.
    var barLabelHeight: CGFloat { isWidget ? 16 : 14 }
    /// 라벨과 막대 사이
    var barLabelGap: CGFloat { isWidget ? 4 : 2 }
    /// 바·오라 드롭다운의 "구성" 버튼 위아래 여백(라벨 줄 14pt 안에 들어가게)
    var barToggleVerticalPadding: CGFloat? { isWidget ? nil : 1 }
    var barRowSpacing: CGFloat { donutRowSpacing }

    // C안 도넛
    var donutDiameter: CGFloat { isWidget ? 44 : 52 }
    var donutTimerCap: CGFloat { isWidget ? 12 : 22 }
    var donutLabelSize: CGFloat { isWidget ? 11 : 13 }
    var donutMetaGap: CGFloat { isWidget ? 6 : 12 }
    var donutRowSpacing: CGFloat { isWidget ? 8 : 14 }

    // 주간 구성
    var legendFontSize: CGFloat { isWidget ? 10.5 : 12 }
    func toggleFontSize(donut: Bool) -> CGFloat { isWidget ? 9.5 : (donut ? 10.5 : 10) }

    /// 남은 시간(바에 나올 수 있는 표기 중 가장 넓은 "23h 59m")과 "100%"가 바 안에서 겹치지 않는 최대 높이.
    /// 필요한 폭 = 양쪽 여백(높이×0.24×2) + 남은 시간 + "100%" + 반올림 여유 + 최소 간격 8. 모두 높이에 비례한다.
    static func maxBarHeight(width: CGFloat) -> CGFloat {
        let perHeight = 0.48 + GaugeFonts.shortTimerWidthPerCap + 0.1 + GaugeFonts.percentWidthPerCap
        return floor((width - 8) / perHeight)
    }

    /// C안 % 숫자 높이: "100%"가 칸에 들어가는 가장 큰 크기(최대 = 도넛 지름). 모든 줄이 같은 크기.
    var percentCap: CGFloat {
        let timerWidth = donutTimerCap * (GaugeFonts.longestTimerWidthPerCap + 0.63)
        let box = width - timerWidth - donutMetaGap - 8 - donutDiameter - 8
        return max(8, min(donutDiameter, box / GaugeFonts.percentWidthPerCap))
    }
}

/// 한 공급자의 사용량 줄 목록
struct GaugeMetricList: View {
    let metrics: [UsageDisplayMetric]
    var breakdown: UsageBreakdown? = nil
    var breakdownMetricID = "seven_day"
    let theme: ThemeKind
    var style: GaugeStyle = .dropdown
    /// 처음부터 주간 구성을 펼친 상태로 보여줄지 (스크린샷용)
    var breakdownInitiallyPinned = false
    var widgetBreakdownOpen = false
    var onWidgetBreakdownHover: (() -> Void)?
    var onWidgetBreakdownToggle: (() -> Void)?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: theme.isLegacy ? (style.isWidget ? 8 : 10) : style.donutRowSpacing) {
                ForEach(metrics) { metric in
                    GaugeMetricRow(
                        metric: metric,
                        now: context.date,
                        theme: theme,
                        style: style,
                        breakdown: metric.id == breakdownMetricID ? breakdown : nil,
                        initiallyPinned: breakdownInitiallyPinned,
                        widgetBreakdownOpen: widgetBreakdownOpen,
                        onWidgetBreakdownHover: onWidgetBreakdownHover,
                        onWidgetBreakdownToggle: onWidgetBreakdownToggle
                    )
                }
            }
        }
    }
}

/// 사용량 한 줄
struct GaugeMetricRow: View {
    let metric: UsageDisplayMetric
    let now: Date
    let theme: ThemeKind
    let style: GaugeStyle
    var breakdown: UsageBreakdown?
    var widgetBreakdownOpen: Bool
    var onWidgetBreakdownHover: (() -> Void)?
    var onWidgetBreakdownToggle: (() -> Void)?

    @State private var hovering = false
    @State private var pinned: Bool

    init(metric: UsageDisplayMetric, now: Date, theme: ThemeKind, style: GaugeStyle,
         breakdown: UsageBreakdown?, initiallyPinned: Bool = false,
         widgetBreakdownOpen: Bool = false, onWidgetBreakdownHover: (() -> Void)? = nil,
         onWidgetBreakdownToggle: (() -> Void)? = nil) {
        self.metric = metric
        self.now = now
        self.theme = theme
        self.style = style
        self.breakdown = breakdown
        self.widgetBreakdownOpen = widgetBreakdownOpen
        self.onWidgetBreakdownHover = onWidgetBreakdownHover
        self.onWidgetBreakdownToggle = onWidgetBreakdownToggle
        _pinned = State(initialValue: initiallyPinned)
    }

    private var tokens: DesignTokens { theme.tokens }
    private var isDonut: Bool { theme == .donut || theme == .daangn }
    private var isOpen: Bool {
        breakdown != nil && (style.isWidget ? widgetBreakdownOpen : (hovering || pinned))
    }

    private var segments: [GaugeSegment]? {
        guard isOpen, let breakdown else { return nil }
        return breakdown.rows.map {
            GaugeSegment(id: $0.key, percent: $0.percent, color: GaugeSegment.color(forKey: $0.key))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style.isWidget ? 4 : 6) {
            switch theme {
            case .daangn, .toss, .hybrid:
                LegacyMetricView(metric: metric, theme: theme, isWidget: style.isWidget, now: now) { label }
            case .donut: donutRow
            case .halo: barRow
            case .aura: auraRow
            }
            if isOpen, !style.isWidget, let breakdown {
                GaugeBreakdownLegend(
                    breakdown: breakdown,
                    utilization: metric.utilization,
                    tokens: tokens,
                    fontSize: style.legendFontSize,
                    showsCaption: isDonut
                )
            }
        }
        .contentShape(Rectangle())
        .background(
            WidgetHoverRegion(enabled: style.isWidget && breakdown != nil) { inside in
                if inside { onWidgetBreakdownHover?() }
            }
        )
        .onHover { inside in
            guard !style.isWidget else { return }
            hovering = inside
        }
    }

    private var label: some View {
        HStack(spacing: style.isWidget ? 4 : 6) {
            Text(metric.title)
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundStyle(tokens.gaugeCaption)
                .lineLimit(theme.isLegacy ? 2 : 1)
                .minimumScaleFactor(theme.isLegacy ? 0.75 : 1)
            if breakdown != nil {
                if style.isWidget {
                    Button { onWidgetBreakdownToggle?() } label: {
                        Image(systemName: "chart.pie")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isOpen ? tokens.accent : tokens.textSecondary)
                            .frame(width: 20, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("breakdown_toggle_help".l)
                    .accessibilityLabel("breakdown_toggle_help".l)
                } else {
                    GaugeBreakdownToggle(isOpen: isOpen, pinned: $pinned, tokens: tokens,
                                         fontSize: style.toggleFontSize(donut: isDonut),
                                         verticalPadding: isDonut ? nil : style.barToggleVerticalPadding)
                }
            }
        }
        // 도넛은 왼쪽 칸에 라벨·남은 시간을 쌓으므로 여유 있게, 바·오라는 막대를 두껍게 두려고 딱 글자 높이만큼
        .frame(minHeight: !theme.isLegacy && isDonut ? style.labelHeight : nil, alignment: .leading)
        .frame(height: theme.isLegacy || isDonut ? nil : style.barLabelHeight, alignment: .leading)
    }

    private var labelFontSize: CGFloat {
        if theme.isLegacy { return style.isWidget ? (theme == .daangn ? 11 : 10) : 13 }
        return isDonut ? style.donutLabelSize : style.barLabelSize
    }

    private var timerText: String {
        GaugeCountdown.text(resetsAt: metric.resetsAt, isWeekly: metric.isWeekly, now: now,
                            short: isDonut ? false : style.shortTimer)
    }

    // 헤일로 바: 라벨은 바 위 작은 글씨, 바 안에 남은 시간(왼쪽)과 %(오른쪽)
    private var barRow: some View {
        VStack(alignment: .leading, spacing: style.barLabelGap) {
            label
            BigGaugeBar(
                progress: metric.utilization,
                timer: timerText,
                height: style.barHeight,
                colors: GaugePalette.colors(theme, UsageLevel.from(metric.utilization)),
                knockout: tokens.bg,
                segments: segments,
                cornerRadius: style.isWidget ? 6 : 8
            )
        }
    }

    // 오라: 라벨은 위 작은 글씨, 사용률만큼 퍼진 흐린 빛 위에 남은 시간(왼쪽)과 %(오른쪽)
    private var auraRow: some View {
        VStack(alignment: .leading, spacing: style.barLabelGap) {
            label
            AuraGauge(
                progress: metric.utilization,
                timer: timerText,
                height: style.barHeight,
                colors: GaugePalette.colors(theme, UsageLevel.from(metric.utilization)),
                segments: segments,
                // 남은 시간 글자 머리를 위 라벨("5시간" 등) 글자 머리에 맞춘다
                timerInkX: GaugeFonts.leadingInk(
                    metric.title, font: .systemFont(ofSize: style.barLabelSize, weight: .semibold))
            )
        }
    }

    // 도넛: 라벨 + 남은 시간 / 도넛 / %. % 칸 폭이 고정이라 모든 줄에서 도넛 위치가 같다.
    private var donutRow: some View {
        let diameter = style.donutDiameter
        let percentCap = style.percentCap
        let level = UsageLevel.from(metric.utilization)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: style.isWidget ? 4 : 6) {
                label
                GaugeTimerText(text: timerText, capHeight: style.donutTimerCap, color: tokens.textPrimary)
                    .frame(height: style.donutTimerCap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, style.donutMetaGap)

            DonutGauge(progress: metric.utilization, diameter: diameter, segments: segments)

            // % 숫자는 섞인 색 없이 파랑·주황·빨강 세 가지만
            GaugePercentText(value: metric.utilization, capHeight: percentCap, color: GaugePalette.colors(.donut, level).ink)
                .frame(width: ceil(percentCap * GaugeFonts.percentWidthPerCap) + 2, height: diameter, alignment: .trailing)
                .padding(.leading, 8)
        }
    }
}

// MARK: - 주간 구성 펼치기

struct GaugeBreakdownToggle: View {
    let isOpen: Bool
    @Binding var pinned: Bool
    let tokens: DesignTokens
    var fontSize: CGFloat = 11.5
    /// nil이면 글자 크기 × 0.22
    var verticalPadding: CGFloat? = nil

    var body: some View {
        Button {
            pinned.toggle()
        } label: {
            HStack(spacing: 2) {
                Text("breakdown_toggle".l)
                Image(systemName: "chevron.down")
                    .font(.system(size: fontSize * 0.68, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(pinned ? tokens.bg : tokens.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, (fontSize * 0.5).rounded())
            .padding(.vertical, verticalPadding ?? (fontSize * 0.22).rounded())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(pinned ? tokens.textPrimary : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(pinned ? tokens.textPrimary : tokens.textTertiary, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("breakdown_toggle_help".l)
        .accessibilityLabel("breakdown_toggle_help".l)
    }
}

struct GaugeBreakdownLegend: View {
    let breakdown: UsageBreakdown
    let utilization: Double
    let tokens: DesignTokens
    var fontSize: CGFloat = 12
    var showsCaption = true

    var body: some View {
        let denominator = max(100, breakdown.rows.reduce(0) { $0 + $1.percent })
        let dot = (fontSize * 0.83).rounded()
        VStack(alignment: .leading, spacing: 4) {
            if showsCaption {
                Text(String(format: "breakdown_of_week".l, Int(utilization.rounded())))
                    .font(.system(size: fontSize))
                    .foregroundStyle(tokens.gaugeCaption)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
                      alignment: .leading, spacing: 3) {
                ForEach(breakdown.rows) { row in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(GaugeSegment.color(forKey: row.key))
                            .frame(width: dot, height: dot)
                        Text(name(for: row))
                            .foregroundStyle(tokens.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int((row.percent / denominator * 100).rounded()))%")
                            .fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundStyle(tokens.textPrimary)
                    }
                    .font(.system(size: fontSize))
                }
            }
        }
        .padding(.top, 2)
        .help("breakdown_explanation".l)
    }

    private func name(for row: UsageBreakdown.Row) -> String {
        switch row.key {
        case "claude_code": return "Code"
        case "chat": return "breakdown_chats".l
        case "cowork": return "Cowork"
        case "other": return "breakdown_other".l
        default: return row.displayName
        }
    }
}
