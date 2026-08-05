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
    /// ISO region code (e.g. "US") -- with `city`, powers future nearby
    /// gym/partner suggestions. Optional, display/settings-only today.
    var country: String? = nil
    /// Free-text city name, same purpose as `country`.
    var city: String? = nil
    /// Storage paths (not the image itself), behind Config.enableBodyPhotoUpload
    /// -- managed only via SupabaseClient's uploadBodyPhoto/deleteBodyPhoto,
    /// not through the general profile save() flow, hence the defaults.
    var goalBodyPhotoPath: String? = nil
    var currentBodyPhotoPath: String? = nil
    /// Storage path (not the image itself) for the profile picture --
    /// managed only via SupabaseClient's uploadAvatar/deleteAvatar, same
    /// "not through the general save() flow" reasoning as the body-photo
    /// paths above.
    var avatarPhotoPath: String? = nil
    /// Read-only here (collected at onboarding; updateProfile never writes
    /// them) -- feeds the dashboard's Body section.
    var weightKg: Double? = nil
    var desiredWeightKg: Double? = nil
    /// Editable via the general save() flow, unlike weightKg/desiredWeightKg
    /// above -- height doesn't change often, but there's no reason to lock
    /// it the way the dashboard's weight-progress fields are locked.
    var heightCm: Double? = nil
    var journeyStage: JourneyStage? = nil
    var blockersNotes: String? = nil
    /// Read-only (set at onboarding, never edited here) -- "yyyy-MM-dd".
    /// Exists on this model ONLY for the Goal Body adult-only gate
    /// (bodyPhotosEditor); every other date-of-birth use is server-side.
    var dateOfBirth: String? = nil
    /// Read-only -- written at onboarding (saveOnboardingSurvey), never
    /// read back until the goal-progress bar needed it alongside
    /// weightKg/desiredWeightKg to recompute GoalPace.estimatedMonths.
    var goalPace: GoalPace? = nil
    /// Read-only -- the AI's own comparison of the user's goal/current
    /// photos (analyze-body-photo). Shown directly on the Progress screen
    /// as of the product-owner decision reversing this feature's original
    /// "never shown to the user" posture -- see
    /// Config.enableBodyPhotoVisionAnalysis's doc comment for the history.
    /// Nil = never analyzed (e.g. only one photo set so far); PostgREST
    /// sends the column as JSON `null` in that case, not an absent key, so
    /// this must be Optional -- a non-optional array default only covers
    /// a missing KEY, not a present-but-null value (which is the common
    /// case here for anyone not yet analyzed).
    var bodyPhotoEmphasisTags: [GoalTag]? = nil
    var trainingEmphasis: TrainingEmphasis? = nil
    /// Read-only, server-assigned at account creation -- the journey
    /// "start date" the goal-progress bar counts elapsed days from. Not a
    /// plan-start date (there isn't a separate one), but close enough: for
    /// the vast majority of users onboarding happens in one sitting.
    /// Raw ISO8601 wire string, same reason as dateOfBirth above (this
    /// model is decoded with a plain JSONDecoder that has no date
    /// strategy configured -- parsed on demand where actually needed).
    var createdAt: String? = nil

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
        case country
        case city
        case goalBodyPhotoPath = "goal_body_photo_path"
        case currentBodyPhotoPath = "current_body_photo_path"
        case avatarPhotoPath = "avatar_photo_path"
        case weightKg = "weight_kg"
        case desiredWeightKg = "desired_weight_kg"
        case heightCm = "height_cm"
        case journeyStage = "journey_stage"
        case blockersNotes = "blockers_notes"
        case dateOfBirth = "date_of_birth"
        case goalPace = "goal_pace"
        case createdAt = "created_at"
        case bodyPhotoEmphasisTags = "body_photo_emphasis_tags"
        case trainingEmphasis = "training_emphasis"
    }

    /// "Austin, US" / "US" / "Austin" -- nil when neither part is set.
    static func regionDisplay(country: String?, city: String?) -> String? {
        let parts = [city, country]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
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
