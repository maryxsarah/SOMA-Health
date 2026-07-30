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
}
