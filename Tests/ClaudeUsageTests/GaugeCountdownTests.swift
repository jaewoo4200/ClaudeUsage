import AppKit
import SwiftUI
import XCTest
@testable import ClaudeUsage

final class GaugeCountdownTests: XCTestCase {
    private func seconds(days: Int = 0, hours: Int = 0, minutes: Int = 0, seconds: Int = 0) -> TimeInterval {
        TimeInterval(days * 86_400 + hours * 3_600 + minutes * 60 + seconds)
    }

    func testWeeklyShowsDaysAndHoursWhileADayOrMoreRemains() {
        let d = seconds(days: 3, hours: 11, minutes: 19, seconds: 5)
        XCTAssertEqual(GaugeCountdown.format(seconds: d, isWeekly: true, short: true), "3d 11h")
        XCTAssertEqual(GaugeCountdown.format(seconds: d, isWeekly: true, short: false), "3d 11h 19m")
        // 가운데 단위가 0이면 남긴다
        XCTAssertEqual(GaugeCountdown.format(seconds: seconds(days: 3, minutes: 5), isWeekly: true, short: true), "3d 0h")
        XCTAssertEqual(GaugeCountdown.format(seconds: seconds(days: 1), isWeekly: true, short: false), "1d 0h 0m")
    }

    func testWeeklyDropsZeroDaysUnderADay() {
        let d = seconds(hours: 11, minutes: 19, seconds: 5)
        XCTAssertEqual(GaugeCountdown.format(seconds: d, isWeekly: true, short: true), "11h 19m")
        XCTAssertEqual(GaugeCountdown.format(seconds: d, isWeekly: true, short: false), "11h 19m")
        XCTAssertEqual(GaugeCountdown.format(seconds: seconds(hours: 23, minutes: 59, seconds: 59), isWeekly: true, short: true), "23h 59m")
    }

    func testWeeklyUsesClockUnderAnHour() {
        let d = seconds(minutes: 45, seconds: 12)
        XCTAssertEqual(GaugeCountdown.format(seconds: d, isWeekly: true, short: true), "0:45:12")
        XCTAssertEqual(GaugeCountdown.format(seconds: d, isWeekly: true, short: false), "0:45:12")
    }

    func testFiveHourWindowAlwaysShowsHoursMinutesSeconds() {
        let d = seconds(hours: 2, minutes: 29, seconds: 59)
        XCTAssertEqual(GaugeCountdown.format(seconds: d, isWeekly: false, short: true), "2:29:59")
        XCTAssertEqual(GaugeCountdown.format(seconds: d, isWeekly: false, short: false), "2:29:59")
        XCTAssertEqual(GaugeCountdown.format(seconds: seconds(minutes: 5, seconds: 3), isWeekly: false, short: true), "0:05:03")
    }

    func testZeroOrPastShowsZeroClock() {
        XCTAssertEqual(GaugeCountdown.format(seconds: 0, isWeekly: true, short: true), "0:00:00")
        XCTAssertEqual(GaugeCountdown.format(seconds: -30, isWeekly: false, short: true), "0:00:00")
        let now = Date()
        XCTAssertEqual(GaugeCountdown.text(resetsAt: now.addingTimeInterval(-5), isWeekly: true, now: now, short: true), "0:00:00")
        XCTAssertEqual(GaugeCountdown.text(resetsAt: nil, isWeekly: true, now: now, short: true), "–")
    }

    @MainActor
    func testBarHeightLeavesRoomForWidestTimerAndFullPercent() {
        for width in [204.0, 211.0, 318.0] {
            let style = width == 318 ? GaugeStyle.dropdown : GaugeStyle.widget(width: width)
            let h = style.barHeight
            let needed = h * 0.48
                + h * GaugeFonts.shortTimerWidthPerCap
                + h * GaugeFonts.percentWidthPerCap
                + 8
            XCTAssertLessThanOrEqual(needed, width, "width \(width): bar \(h)pt")
            XCTAssertGreaterThanOrEqual(h, 20, "width \(width)")
        }
    }

    // MARK: - 도넛 색 띠

    func testDonutSpectrumAnchorsMatchLevelThresholds() {
        let light = GaugePalette.donutLight
        XCTAssertEqual(light.count, 41)                       // 0~100%를 2.5% 간격
        XCTAssertEqual(light[0], 0x3182F6)                    // 0% 파랑
        XCTAssertEqual(light[16], 0x3182F6)                   // 40%까지 파랑
        XCTAssertEqual(light[28], 0xFF7A1A)                   // 70% 주황
        XCTAssertEqual(light[32], 0xFF7A1A)                   // 80%까지 주황
        XCTAssertEqual(light[36], 0xF14452)                   // 90% 빨강
        XCTAssertEqual(GaugePalette.donutDark.count, light.count)
    }

    func testDonutTurnsRedBetween90And95() {
        XCTAssertEqual(GaugePalette.donutRedBlend(progress: 89), 0)
        XCTAssertEqual(GaugePalette.donutRedBlend(progress: 90), 0)
        XCTAssertEqual(GaugePalette.donutRedBlend(progress: 92.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(GaugePalette.donutRedBlend(progress: 95), 1)
        XCTAssertEqual(GaugePalette.donutRedBlend(progress: 100), 1)
        for c in GaugePalette.donutLight {
            XCTAssertEqual(GaugePalette.mixHex(c, GaugePalette.donutRedLight, 1), GaugePalette.donutRedLight)
            XCTAssertEqual(GaugePalette.mixHex(c, GaugePalette.donutRedLight, 0), c)
        }
    }

    // MARK: - 테마별 크기

    /// 헤일로 바·오라 줄 목록의 높이 = 도넛 줄 목록의 높이(드롭다운·위젯 모두). 테마를 바꿔도 창 크기가 그대로여야 한다.
    @MainActor
    func testBarAndAuraListsMatchDonutListHeight() {
        let now = Date()
        let metrics = [
            UsageDisplayMetric(id: "five_hour", title: "5시간", utilization: 38,
                               resetsAt: now.addingTimeInterval(9_000), isWeekly: false),
            UsageDisplayMetric(id: "seven_day", title: "7일", utilization: 71,
                               resetsAt: now.addingTimeInterval(300_000), isWeekly: true),
            UsageDisplayMetric(id: "seven_day_fable", title: "Claude Fable", utilization: 93,
                               resetsAt: now.addingTimeInterval(300_000), isWeekly: true)
        ]
        for style in [GaugeStyle.dropdown, .widget(width: WidgetGaugeWidth.narrow)] {
            func height(_ theme: ThemeKind) -> CGFloat {
                let host = NSHostingView(rootView: GaugeMetricList(metrics: metrics, theme: theme, style: style)
                    .frame(width: style.width))
                host.layoutSubtreeIfNeeded()
                return host.fittingSize.height
            }
            let donut = height(.daangn)
            XCTAssertEqual(height(.toss), donut, accuracy: 0.5, "헤일로 바, 폭 \(style.width)")
            XCTAssertEqual(height(.hybrid), donut, accuracy: 0.5, "오라, 폭 \(style.width)")
        }
    }
}
