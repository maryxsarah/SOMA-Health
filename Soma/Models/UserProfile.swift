import Foundation

/// Injury/limitation tags -- structured (not free text) so the decision
/// engine and workout filtering can actually act on them without any AI
/// text parsing. `injuryNotes` on UserProfile is separate, free-text, and
/// display-only.
enum InjuryTag: String, Codable, CaseIterable, Identifiable {
    case knee
    case ankle
    case back
    case shoulder
    case hip
    case wrist
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .knee: "Knee"
        case .ankle: "Ankle"
        case .back: "Back"
        case .shoulder: "Shoulder"
        case .hip: "Hip"
        case .wrist: "Wrist"
        case .other: "Other"
        }
    }
}

/// Mirrors the profile-related columns on `users`. Contact email is
/// display-only profile info -- the app still signs in only via Sign in
/// with Apple, this never becomes a password/login credential.
struct UserProfile: Codable, Equatable {
    var contactEmail: String?
    var goals: [GoalTag]
    var otherGoalNotes: String?
    var equipment: [EquipmentTag]
    var otherEquipmentNotes: String?
    var injuryTags: [InjuryTag]
    var injuryNotes: String?

    enum CodingKeys: String, CodingKey {
        case contactEmail = "contact_email"
        case goals
        case otherGoalNotes = "other_goal_notes"
        case equipment
        case otherEquipmentNotes = "other_equipment_notes"
        case injuryTags = "injury_tags"
        case injuryNotes = "injury_notes"
    }

    static let empty = UserProfile(
        contactEmail: nil,
        goals: [],
        otherGoalNotes: nil,
        equipment: [],
        otherEquipmentNotes: nil,
        injuryTags: [],
        injuryNotes: nil
    )
}
