import Foundation

/// Mirrors a `body_photo` row -- one entry per upload, giving a real
/// history alongside the existing single "latest" pointer columns on
/// UserProfile (goalBodyPhotoPath/currentBodyPhotoPath). Feature-flagged,
/// see Config.enableBodyPhotoUpload.
struct BodyPhotoEntry: Codable, Identifiable {
    let id: String
    let kind: String
    let storagePath: String
    let takenAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind
        case storagePath = "storage_path"
        case takenAt = "taken_at"
    }

    /// "Aug 14" -- history-strip date label. nil (not a placeholder date)
    /// if `takenAt` fails to parse, matching every other best-effort photo
    /// read in this feature.
    var shortDate: String? {
        guard let date = Self.parseISO8601(takenAt) else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Postgres timestamptz comes back with fractional seconds; falls back
    /// to without, same as GoalJourneyProgress.parseISO8601.
    private static func parseISO8601(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}
