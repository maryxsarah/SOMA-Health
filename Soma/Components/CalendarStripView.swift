import SwiftUI

/// 7-day strip at the top of Home: one dot per day, colored by that day's
/// recommendation category -- red (Rest, lowest energy) through green
/// (Push Hard). Today is highlighted with a ring. Days with no
/// recommendation yet show a neutral gray dot rather than guessing.
struct CalendarStripView: View {
    let recommendations: [DailyRecommendation]

    private let dayCount = 7

    var body: some View {
        HStack(spacing: 10) {
            ForEach(lastDays, id: \.dateString) { day in
                VStack(spacing: 6) {
                    Text(day.weekdayLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(color(for: day.dateString))
                        .frame(width: day.isToday ? 32 : 26, height: day.isToday ? 32 : 26)
                        .overlay(
                            Circle().stroke(day.isToday ? Theme.pillFill : .clear, lineWidth: 2)
                        )
                    Text("\(day.dayNumber)")
                        .font(.caption2.bold())
                        .foregroundStyle(day.isToday ? Theme.pillFill : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func color(for dateString: String) -> Color {
        guard let recommendation = recommendations.first(where: { $0.date == dateString }) else {
            return Color(.systemGray5)
        }
        switch recommendation.category {
        case .pushHard: return .green
        case .moderate: return .yellow
        case .light: return .orange
        case .rest: return .red
        }
    }

    private struct DayInfo {
        let dateString: String
        let weekdayLabel: String
        let dayNumber: Int
        let isToday: Bool
    }

    private var lastDays: [DayInfo] {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let weekdayFormatter = DateFormatter()
        weekdayFormatter.dateFormat = "EEE"

        return (0..<dayCount).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return DayInfo(
                dateString: dateFormatter.string(from: date),
                weekdayLabel: weekdayFormatter.string(from: date),
                dayNumber: calendar.component(.day, from: date),
                isToday: offset == 0
            )
        }
    }
}
