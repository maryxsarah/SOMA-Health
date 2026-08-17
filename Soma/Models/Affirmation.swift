import Foundation

/// Today's AI-generated affirmation line (16a/16b) -- the wire shape
/// generate-affirmation returns (camelCase, plain JSONDecoder, same
/// convention as MealRecommendation).
struct DailyAffirmation: Codable, Equatable {
    var text: String
    let generatedAt: String?
    /// False once today's one manual "New line" regeneration is spent --
    /// drives the widget's refresh button and the sheet's footer copy.
    /// Nil on the passive REST read, which can't know the quota state.
    let regenerationAvailable: Bool?

    /// "generated 07:30" -- the TODAY card's caption. Postgres/JS ISO
    /// stamps carry fractional seconds, ISO8601DateFormatter's default
    /// config doesn't -- try both rather than silently dropping the caption.
    var generatedAtTimeLabel: String? {
        guard let generatedAt else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = withFractional.date(from: generatedAt) ?? ISO8601DateFormatter().date(from: generatedAt) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// A past day's generated line, still inside 16b's 7-day "Recent" window
/// -- just an old `daily_affirmation` row; nothing is ever moved, recents
/// simply age out of the query window unless hearted into the list.
struct RecentAffirmation: Codable, Identifiable, Equatable {
    let date: String
    let text: String

    var id: String { date }

    /// "Aug 16" -- the Recent row's date chip, in the user's locale.
    var dateLabel: String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        guard let parsed = formatter.date(from: date) else { return nil }
        return parsed.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// One saved line in the user's own list (16b) -- a `user_affirmations`
/// row, read/written directly through RLS (snake_case columns via
/// CodingKeys, like BodyPhoto).
struct AffirmationLine: Codable, Identifiable, Equatable {
    let id: String
    var text: String
    /// "generated" (kept via 16b's Keep) or "custom" (written by hand).
    let source: String
    /// In the reminder rotation (16c) -- toggled by the row's heart
    /// without deleting the line itself.
    var inRotation: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, text, source
        case inRotation = "in_rotation"
        case createdAt = "created_at"
    }
}
