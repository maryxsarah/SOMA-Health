import Foundation

/// Answers collected by the onboarding survey (screens between Sign in
/// with Apple and Connect Device). Fixed enums throughout -- no free text
/// -- so every answer maps directly to a `users` column value.

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female, other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .male: String(localized: "sex.male", defaultValue: "Male", comment: "Onboarding sex selection option")
        case .female: String(localized: "sex.female", defaultValue: "Female", comment: "Onboarding sex selection option")
        case .other: String(localized: "sex.other", defaultValue: "Other", comment: "Onboarding sex selection option")
        }
    }
    var systemImageName: String {
        switch self {
        case .male: "figure.stand"
        case .female: "figure.stand.dress"
        case .other: "person.fill"
        }
    }
}

enum WorkoutFrequency: String, Codable, CaseIterable, Identifiable {
    case zeroToTwo = "zero_to_two"
    case threeToFive = "three_to_five"
    case sixPlus = "six_plus"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .zeroToTwo: String(localized: "workoutFrequency.zeroToTwo", defaultValue: "0-2", comment: "Onboarding workout frequency option, workouts per week range")
        case .threeToFive: String(localized: "workoutFrequency.threeToFive", defaultValue: "3-5", comment: "Onboarding workout frequency option, workouts per week range")
        case .sixPlus: String(localized: "workoutFrequency.sixPlus", defaultValue: "6+", comment: "Onboarding workout frequency option, workouts per week range")
        }
    }
    var subtitle: String {
        switch self {
        case .zeroToTwo: String(localized: "workoutFrequency.zeroToTwoSubtitle", defaultValue: "Workouts now and then", comment: "Onboarding workout frequency option subtitle")
        case .threeToFive: String(localized: "workoutFrequency.threeToFiveSubtitle", defaultValue: "A few workouts per week", comment: "Onboarding workout frequency option subtitle")
        case .sixPlus: String(localized: "workoutFrequency.sixPlusSubtitle", defaultValue: "Dedicated athlete", comment: "Onboarding workout frequency option subtitle")
        }
    }
    var systemImageName: String {
        switch self {
        case .zeroToTwo: "circle.fill"
        case .threeToFive: "square.grid.3x1.fill"
        case .sixPlus: "square.grid.3x3.fill"
        }
    }
}

enum ReferralSource: String, Codable, CaseIterable, Identifiable {
    case youtube, tiktok, appStore = "app_store", google
    case friendsFamily = "friends_family"
    case x, tv, facebook, instagram, other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .youtube: String(localized: "referralSource.youtube", defaultValue: "YouTube", comment: "Onboarding referral source option")
        case .tiktok: String(localized: "referralSource.tiktok", defaultValue: "TikTok", comment: "Onboarding referral source option")
        case .appStore: String(localized: "referralSource.appStore", defaultValue: "App Store", comment: "Onboarding referral source option")
        case .google: String(localized: "referralSource.google", defaultValue: "Google", comment: "Onboarding referral source option")
        case .friendsFamily: String(localized: "referralSource.friendsFamily", defaultValue: "Friends & Family", comment: "Onboarding referral source option")
        case .x: String(localized: "referralSource.x", defaultValue: "X", comment: "Onboarding referral source option")
        case .tv: String(localized: "referralSource.tv", defaultValue: "TV", comment: "Onboarding referral source option")
        case .facebook: String(localized: "referralSource.facebook", defaultValue: "Facebook", comment: "Onboarding referral source option")
        case .instagram: String(localized: "referralSource.instagram", defaultValue: "Instagram", comment: "Onboarding referral source option")
        case .other: String(localized: "referralSource.other", defaultValue: "Other", comment: "Onboarding referral source option")
        }
    }
    var systemImageName: String {
        switch self {
        case .youtube: "play.rectangle.fill"
        case .tiktok: "music.note"
        case .appStore: "apple.logo"
        case .google: "magnifyingglass"
        case .friendsFamily: "person.2.fill"
        case .x: "xmark"
        case .tv: "tv.fill"
        case .facebook: "f.square.fill"
        case .instagram: "camera.fill"
        case .other: "ellipsis.circle.fill"
        }
    }
}

enum GoalPace: String, Codable, CaseIterable, Identifiable {
    case slow, recommended, fast
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .slow: String(localized: "goalPace.slow", defaultValue: "Slow", comment: "Onboarding goal pace option")
        case .recommended: String(localized: "goalPace.recommended", defaultValue: "Recommended", comment: "Onboarding goal pace option")
        case .fast: String(localized: "goalPace.fast", defaultValue: "Fast", comment: "Onboarding goal pace option")
        }
    }
    var systemImageName: String {
        switch self {
        case .slow: "tortoise.fill"
        case .recommended: "hare.fill"
        case .fast: "bolt.fill"
        }
    }
    /// Fixed, rule-based multiplier on the "recommended" pace's timeline --
    /// no AI/ML estimate, just a simple deterministic scale matching the
    /// spec's "realistic estimate" ask.
    var timelineMultiplier: Double {
        switch self {
        case .slow: 2.2
        case .recommended: 1.0
        case .fast: 0.55
        }
    }

    /// The same deterministic estimate GoalPaceQuestionView shows live
    /// while picking a pace ("You should reach your goal in N months") --
    /// pulled out here so the later on-track/plan-summary screens can show
    /// this same real number instead of a generic, unrelated chart
    /// timeline (tester feedback: "needs to be realistic with recommended
    /// timeline").
    static func estimatedMonths(deltaKg: Double, pace: GoalPace) -> Int {
        let baselineMonthsPerKg = 0.9
        let months = abs(deltaKg) * baselineMonthsPerKg * pace.timelineMultiplier
        return max(1, Int(months.rounded()))
    }
}

enum BlockerTag: String, Codable, CaseIterable, Identifiable {
    case lackOfConsistency = "lack_of_consistency"
    case unhealthyHabits = "unhealthy_habits"
    case lackOfSupport = "lack_of_support"
    case busySchedule = "busy_schedule"
    case noIdeaWhereToStart = "no_idea_where_to_start"
    case overwhelmed
    case fatigue
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lackOfConsistency: String(localized: "blockerTag.lackOfConsistency", defaultValue: "Lack of consistency", comment: "Onboarding blocker tag option")
        case .unhealthyHabits: String(localized: "blockerTag.unhealthyHabits", defaultValue: "Unhealthy habits", comment: "Onboarding blocker tag option")
        case .lackOfSupport: String(localized: "blockerTag.lackOfSupport", defaultValue: "Lack of support and plan", comment: "Onboarding blocker tag option")
        case .busySchedule: String(localized: "blockerTag.busySchedule", defaultValue: "Busy schedule", comment: "Onboarding blocker tag option")
        case .noIdeaWhereToStart: String(localized: "blockerTag.noIdeaWhereToStart", defaultValue: "No idea where to start", comment: "Onboarding blocker tag option")
        case .overwhelmed: String(localized: "blockerTag.overwhelmed", defaultValue: "Overwhelmed with exercises", comment: "Onboarding blocker tag option")
        case .fatigue: String(localized: "blockerTag.fatigue", defaultValue: "Constant fatigue and exhaustion", comment: "Onboarding blocker tag option")
        }
    }
    var systemImageName: String {
        switch self {
        case .lackOfConsistency: "chart.bar.fill"
        case .unhealthyHabits: "fork.knife"
        case .lackOfSupport: "person.2.slash.fill"
        case .busySchedule: "calendar"
        case .noIdeaWhereToStart: "questionmark.circle.fill"
        case .overwhelmed: "brain.head.profile"
        case .fatigue: "battery.25"
        }
    }
}

/// Where the user is on their fitness/health journey -- deliberately
/// separate from `ExperienceLevel` (training competency, e.g. "can I do a
/// barbell squat safely") and `WorkoutFrequency` (current weekly volume):
/// this is motivational/journey context that neither of those capture,
/// e.g. a `six_plus` advanced lifter can still be `returningAfterBreak`
/// after an injury layoff, and a `zeroToTwo` newbie might be either
/// `justStarting` or someone who's tried and stalled many times before.
enum JourneyStage: String, Codable, CaseIterable, Identifiable {
    case justStarting = "just_starting"
    case returningAfterBreak = "returning_after_break"
    case consistentButPlateaued = "consistent_but_plateaued"
    case experienced
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .justStarting: String(localized: "journeyStage.justStarting", defaultValue: "Just starting out", comment: "Onboarding journey stage option")
        case .returningAfterBreak: String(localized: "journeyStage.returningAfterBreak", defaultValue: "Returning after a break", comment: "Onboarding journey stage option")
        case .consistentButPlateaued: String(localized: "journeyStage.consistentButPlateaued", defaultValue: "Consistent, but plateaued", comment: "Onboarding journey stage option")
        case .experienced: String(localized: "journeyStage.experienced", defaultValue: "Experienced and progressing", comment: "Onboarding journey stage option")
        }
    }
    var systemImageName: String {
        switch self {
        case .justStarting: "sparkles"
        case .returningAfterBreak: "arrow.clockwise"
        case .consistentButPlateaued: "chart.line.flattrend.xyaxis"
        case .experienced: "trophy.fill"
        }
    }
}

enum DietType: String, Codable, CaseIterable, Identifiable {
    // `noDiet`, not `none`: this is consumed as `DietType?`, and a case
    // literally named `none` would make `answers.dietType = .none` resolve
    // to `Optional.none` -- i.e. nil -- silently discarding the user's
    // answer, since saveOnboardingSurvey only writes diet_type under
    // `if let`. The rawValue stays "none" so stored data is unaffected.
    case balanced, wholeFood = "whole_food", mediterranean
    case pescatarian, flexitarian, vegetarian, vegan
    case lowCarb = "low_carb", keto, paleo, noDiet = "none"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .balanced: String(localized: "dietType.balanced", defaultValue: "Balanced", comment: "Onboarding diet type option")
        case .wholeFood: String(localized: "dietType.wholeFood", defaultValue: "Whole-food focus", comment: "Onboarding diet type option")
        case .mediterranean: String(localized: "dietType.mediterranean", defaultValue: "Mediterranean", comment: "Onboarding diet type option")
        case .pescatarian: String(localized: "dietType.pescatarian", defaultValue: "Pescatarian", comment: "Onboarding diet type option")
        case .flexitarian: String(localized: "dietType.flexitarian", defaultValue: "Flexitarian", comment: "Onboarding diet type option")
        case .vegetarian: String(localized: "dietType.vegetarian", defaultValue: "Vegetarian", comment: "Onboarding diet type option")
        case .vegan: String(localized: "dietType.vegan", defaultValue: "Vegan", comment: "Onboarding diet type option")
        case .lowCarb: String(localized: "dietType.lowCarb", defaultValue: "Low-carb", comment: "Onboarding diet type option")
        case .keto: String(localized: "dietType.keto", defaultValue: "Keto", comment: "Onboarding diet type option")
        case .paleo: String(localized: "dietType.paleo", defaultValue: "Paleo", comment: "Onboarding diet type option")
        case .noDiet: String(localized: "dietType.noDiet", defaultValue: "I don't follow any diet", comment: "Onboarding diet type option")
        }
    }
}

/// Provisional: `buildStrength` was added as the clearest gap against the
/// original 5 options (none of which covered a strength/performance
/// outcome), per a tester-feedback brief that flagged this screen as
/// needing expansion without specifying the exact missing option(s).
/// Revisit the full set once real tester feedback names what's missing.
enum AccomplishmentGoal: String, Codable, CaseIterable, Identifiable {
    case boostEnergy = "boost_energy"
    case stayMotivated = "stay_motivated"
    case feelBetterBody = "feel_better_body"
    case knowWorkout = "know_workout"
    case understandBody = "understand_body"
    case buildStrength = "build_strength_muscle"
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .boostEnergy: String(localized: "accomplishmentGoal.boostEnergy", defaultValue: "Boost my energy and mood", comment: "Onboarding accomplishment goal option")
        case .stayMotivated: String(localized: "accomplishmentGoal.stayMotivated", defaultValue: "Stay motivated and consistent", comment: "Onboarding accomplishment goal option")
        case .feelBetterBody: String(localized: "accomplishmentGoal.feelBetterBody", defaultValue: "Feel better about my body", comment: "Onboarding accomplishment goal option")
        case .knowWorkout: String(localized: "accomplishmentGoal.knowWorkout", defaultValue: "Know exactly what workout to do every day", comment: "Onboarding accomplishment goal option")
        case .understandBody: String(localized: "accomplishmentGoal.understandBody", defaultValue: "Understand my body better", comment: "Onboarding accomplishment goal option")
        case .buildStrength: String(localized: "accomplishmentGoal.buildStrength", defaultValue: "Build strength and muscle", comment: "Onboarding accomplishment goal option")
        }
    }
    var systemImageName: String {
        switch self {
        case .boostEnergy: "sun.max.fill"
        case .stayMotivated: "figure.strengthtraining.traditional"
        case .feelBetterBody: "heart.fill"
        case .knowWorkout: "checklist"
        case .understandBody: "waveform.path.ecg"
        case .buildStrength: "dumbbell.fill"
        }
    }
}

/// All answers collected across the survey, held in-memory by
/// OnboardingSurveyView until the final submit.
struct OnboardingSurveyAnswers: Equatable {
    var sex: Sex?
    var workoutFrequency: WorkoutFrequency?
    var dateOfBirth: Date?
    var referralSource: ReferralSource?
    var weightKg: Double?
    /// Optional -- Goal Body feature (TDEE calculation, and the ruler
    /// picker defaults to a sane middle value rather than 0 if unset).
    var heightCm: Double?
    var worksWithTrainer: Bool?
    // Multi-select -- more than one goal/accomplishment genuinely applies
    // for most people, and forcing a single pick here just meant whichever
    // one they picked lost the others (tester feedback).
    var goal: Set<GoalTag> = []
    var desiredWeightKg: Double?
    var goalPace: GoalPace?
    var journeyStage: JourneyStage?
    var blockers: Set<BlockerTag> = []
    /// Optional free-text elaboration on `blockers`, same shape as
    /// injuryNotes alongside injuryTags -- structured tags drive filtering,
    /// free text is display-only context for humans (a coach) or future
    /// prompt personalization.
    var blockersNotes: String?
    var dietType: DietType?
    var accomplishmentGoals: Set<AccomplishmentGoal> = []
    var marketingOptIn = false
}
