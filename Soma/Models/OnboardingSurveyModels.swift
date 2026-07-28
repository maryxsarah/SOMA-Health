import Foundation

/// Answers collected by the onboarding survey (screens between Sign in
/// with Apple and Connect Device). Fixed enums throughout -- no free text
/// -- so every answer maps directly to a `users` column value.

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female, other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .male: "Male"
        case .female: "Female"
        case .other: "Other"
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
        case .zeroToTwo: "0-2"
        case .threeToFive: "3-5"
        case .sixPlus: "6+"
        }
    }
    var subtitle: String {
        switch self {
        case .zeroToTwo: "Workouts now and then"
        case .threeToFive: "A few workouts per week"
        case .sixPlus: "Dedicated athlete"
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
        case .youtube: "YouTube"
        case .tiktok: "TikTok"
        case .appStore: "App Store"
        case .google: "Google"
        case .friendsFamily: "Friends & Family"
        case .x: "X"
        case .tv: "TV"
        case .facebook: "Facebook"
        case .instagram: "Instagram"
        case .other: "Other"
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
        case .slow: "Slow"
        case .recommended: "Recommended"
        case .fast: "Fast"
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
        case .lackOfConsistency: "Lack of consistency"
        case .unhealthyHabits: "Unhealthy habits"
        case .lackOfSupport: "Lack of support and plan"
        case .busySchedule: "Busy schedule"
        case .noIdeaWhereToStart: "No idea where to start"
        case .overwhelmed: "Overwhelmed with exercises"
        case .fatigue: "Constant fatigue and exhaustion"
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
        case .balanced: "Balanced"
        case .wholeFood: "Whole-food focus"
        case .mediterranean: "Mediterranean"
        case .pescatarian: "Pescatarian"
        case .flexitarian: "Flexitarian"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .lowCarb: "Low-carb"
        case .keto: "Keto"
        case .paleo: "Paleo"
        case .noDiet: "I don't follow any diet"
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
        case .boostEnergy: "Boost my energy and mood"
        case .stayMotivated: "Stay motivated and consistent"
        case .feelBetterBody: "Feel better about my body"
        case .knowWorkout: "Know exactly what workout to do every day"
        case .understandBody: "Understand my body better"
        case .buildStrength: "Build strength and muscle"
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
    var worksWithTrainer: Bool?
    var goal: GoalTag?
    var desiredWeightKg: Double?
    var goalPace: GoalPace?
    var blockers: Set<BlockerTag> = []
    var dietType: DietType?
    var accomplishmentGoal: AccomplishmentGoal?
    var marketingOptIn = false
}
