import SwiftUI

/// Tick only when the displayed countdown can change; stop after reset or when no date is available.
struct UsageCountdownSchedule: TimelineSchedule {
    let resetsAt: Date?
    let isWeekly: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(date: startDate, resetsAt: resetsAt, isWeekly: isWeekly)
    }

    struct Entries: Sequence, IteratorProtocol {
        var date: Date
        let resetsAt: Date?
        let isWeekly: Bool
        private var first = true

        init(date: Date, resetsAt: Date?, isWeekly: Bool) {
            self.date = date
            self.resetsAt = resetsAt
            self.isWeekly = isWeekly
        }

        mutating func next() -> Date? {
            if first {
                first = false
                return date
            }
            guard let resetsAt, resetsAt > date else { return nil }
            let remaining = resetsAt.timeIntervalSince(date)
            // Weekly gauges switch to seconds in their final hour.
            let quantum: TimeInterval = isWeekly && remaining > 3_600 ? 60 : 1
            let remainder = remaining.truncatingRemainder(dividingBy: quantum)
            // Move just beyond the integer boundary used by the countdown formatter.
            date = date.addingTimeInterval(Swift.max(0.001, remainder + 0.001))
            return date
        }
    }
}
