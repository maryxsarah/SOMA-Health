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

/// Per-injury severity -- feeds the deterministic contraindication map
/// (supabase/functions/_shared/contraindications.ts) and, for `.severe`,
/// the injury_recovery_state protocol. Stored as `users.injury_severity`,
/// a jsonb dict keyed by InjuryTag.rawValue -- kept separate from
/// `injuryTags` (a plain text[]) rather than reshaping that column, so
/// every existing reader of injury_tags keeps working unmodified.
enum InjurySeverity: String, Codable, CaseIterable, Identifiable {
    case mild
    case moderate
    case severe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }
}

/// Injury type -- optional, separate from severity and from the free-text
/// `injuryNotes`. A small fixed set (not free text) for the same reason as
/// InjuryTag/InjurySeverity: informational only today (doesn't affect
/// contraindication filtering or the recovery-protocol state machine), but
/// structured so it can later without a data migration.
enum InjuryType: String, Codable, CaseIterable, Identifiable {
    case strain
    case sprain
    case tendinitis
    case postSurgical = "post_surgical"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .strain: "Strain"
        case .sprain: "Sprain"
        case .tendinitis: "Tendinitis"
        case .postSurgical: "Post-surgical"
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
    /// Keyed by InjuryTag.rawValue. A tag present in `injuryTags` with no
    /// entry here is treated as `.moderate` by the backend (never silently
    /// as "no injury") -- see contraindications.ts's describeContraindications.
    var injurySeverity: [String: InjurySeverity] = [:]
    /// Both optional and purely informational -- absent for any tag means
    /// "not specified," never inferred. Keyed by InjuryTag.rawValue, same
    /// pattern as injurySeverity.
    var injuryType: [String: InjuryType] = [:]
    /// Self-reported pain level, 1-10. Also purely informational.
    var injuryPainLevel: [String: Int] = [:]
    var experienceLevel: ExperienceLevel?
    /// Self-reported only, never assumed -- adjusts (never withholds)
    /// generated workouts, and caps the day's category at moderate.
    var pregnancy: Bool?
    /// Optional, only meaningful when `pregnancy == true`. Drives
    /// trimester-scaled guidance -- see pregnancyGuidance.ts.
    var pregnancyWeek: Int?
    /// Real, user-set weekly session-count goal, shown against actual
    /// progress (workouts logged this week) on the Profile screen. Purely
    /// a personal-tracking display -- not read by any recommendation logic.
    var weeklySessionTarget: Int?
    /// Storage paths (not the image itself), behind Config.enableBodyPhotoUpload
    /// -- managed only via SupabaseClient's uploadBodyPhoto/deleteBodyPhoto,
    /// not through the general profile save() flow, hence the defaults.
    var goalBodyPhotoPath: String? = nil
    var currentBodyPhotoPath: String? = nil

    enum CodingKeys: String, CodingKey {
        case contactEmail = "contact_email"
        case goals
        case otherGoalNotes = "other_goal_notes"
        case equipment
        case otherEquipmentNotes = "other_equipment_notes"
        case injuryTags = "injury_tags"
        case injuryNotes = "injury_notes"
        case injurySeverity = "injury_severity"
        case injuryType = "injury_type"
        case injuryPainLevel = "injury_pain_level"
        case experienceLevel = "experience_level"
        case pregnancy
        case pregnancyWeek = "pregnancy_week"
        case weeklySessionTarget = "weekly_session_target"
        case goalBodyPhotoPath = "goal_body_photo_path"
        case currentBodyPhotoPath = "current_body_photo_path"
    }

    static let empty = UserProfile(
        contactEmail: nil,
        goals: [],
        otherGoalNotes: nil,
        equipment: [],
        otherEquipmentNotes: nil,
        injuryTags: [],
        injuryNotes: nil,
        experienceLevel: nil,
        pregnancy: nil,
        pregnancyWeek: nil,
        weeklySessionTarget: nil,
        goalBodyPhotoPath: nil,
        currentBodyPhotoPath: nil
    )
}
