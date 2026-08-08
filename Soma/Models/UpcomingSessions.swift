import Foundation

/// Only `weekdays`/`beforeCourtDays` have a forward occurrence knowable in
/// advance -- every other rule gets a plain description, never a guessed date.
enum UpcomingSessionsDisplay {
    case dates([Date])
    case qualitative(String)
}

enum UpcomingSessions {
    static func display(
        scheduleRule: GoalScheduleRule?, scheduleDays: [Int]?, courtDays: [Int]?, count: Int = 3, from start: Date = Date()
    ) -> UpcomingSessionsDisplay {
        switch scheduleRule {
        case .weekdays:
            let days = Set(scheduleDays ?? [])
            guard !days.isEmpty, let dates = nextMatchingDates(matching: days, count: count, from: start) else {
                return .qualitative("Whenever readiness allows")
            }
            return .dates(dates)
        case .beforeCourtDays:
            let courtSet = Set(courtDays ?? [])
            let matchDays = Set((0...6).filter { courtSet.contains(($0 + 1) % 7) })
            guard !matchDays.isEmpty, let dates = nextMatchingDates(matching: matchDays, count: count, from: start) else {
                return .qualitative("Whenever readiness allows")
            }
            return .dates(dates)
        case .everyOtherDay:
            return .qualitative("Every other day")
        case .readiness, .unknown, nil:
            return .qualitative("Whenever readiness allows")
        }
    }

    /// `days` uses the app's shared 0=Sunday convention (WeekdayMiniPicker,
    /// scheduleDays/courtDays wire values) -- Calendar.weekday is 1=Sunday.
    private static func nextMatchingDates(matching days: Set<Int>, count: Int, from start: Date) -> [Date]? {
        let calendar = Calendar.current
        var results: [Date] = []
        var offset = 0
        while results.count < count && offset < 30 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            let dow = calendar.component(.weekday, from: date) - 1
            if days.contains(dow) { results.append(date) }
            offset += 1
        }
        return results.isEmpty ? nil : results
    }
}
