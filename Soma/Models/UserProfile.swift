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

/// Training experience -- feeds AI workout plan generation (block count,
/// superset usage, rest periods) so the same category/day produces
/// meaningfully different structure for a newbie vs. an advanced lifter,
/// not just the same template with adjusted numbers.
enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case newbie
    case moderate
    case advanced

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newbie: "Newbie"
        case .moderate: "Moderate"
        case .advanced: "Advanced"
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
    var experienceLevel: ExperienceLevel?

    enum CodingKeys: String, CodingKey {
        case contactEmail = "contact_email"
        case goals
        case otherGoalNotes = "other_goal_notes"
        case equipment
        case otherEquipmentNotes = "other_equipment_notes"
        case injuryTags = "injury_tags"
        case injuryNotes = "injury_notes"
        case experienceLevel = "experience_level"
    }

    static let empty = UserProfile(
        contactEmail: nil,
        goals: [],
        otherGoalNotes: nil,
        equipment: [],
        otherEquipmentNotes: nil,
        injuryTags: [],
        injuryNotes: nil,
        experienceLevel: nil
    )
}
