import Foundation

enum RecommendationCategory: String, Codable {
    case rest
    case light
    case moderate
    case pushHard = "push_hard"

    var displayTitle: String {
        switch self {
        case .rest: "Rest"
        case .light: "Light Movement"
        case .moderate: "Moderate"
        case .pushHard: "Push Hard"
        }
    }

    /// Fixed, rule-based target -- not personalized per user, but tied to
    /// today's category (which itself is derived from the user's data).
    var stepTarget: String {
        switch self {
        case .pushHard: "10,000+ steps"
        case .moderate: "7,000–9,000 steps"
        case .light: "4,000–6,000 steps"
        case .rest: "2,000–3,000 steps"
        }
    }

    /// Fixed, specific suggestions per category -- concrete activity +
    /// duration, no AI generation, same pattern as the existing 4 message
    /// templates. Each carries equipment/impact/body-part tags so the
    /// detail view can prioritize/filter by the user's profile and show
    /// what today's session actually targets.
    var workoutSuggestions: [WorkoutSuggestion] {
        switch self {
        case .pushHard:
            [
                WorkoutSuggestion(title: "50 min full-body strength training", equipment: .gym, goals: [.buildStrength, .gainMuscle], highImpact: false, bodyPart: .fullBody, targetDurationMinutes: 50...50),
                WorkoutSuggestion(title: "40 min upper body strength (chest, back, shoulders, arms)", equipment: .gym, goals: [.buildStrength, .gainMuscle], highImpact: false, bodyPart: .upperBody, targetDurationMinutes: 40...40),
                WorkoutSuggestion(title: "40 min lower body strength (quads, hamstrings, glutes)", equipment: .gym, goals: [.buildStrength, .gainMuscle], highImpact: false, bodyPart: .lowerBody, targetDurationMinutes: 40...40),
                WorkoutSuggestion(title: "30 min HIIT circuit", equipment: .bodyweightOnly, goals: [.leanerToned, .moreSculpted, .cardioEndurance], highImpact: true, bodyPart: .fullBody, targetDurationMinutes: 30...30),
                WorkoutSuggestion(title: "45 min hard run", equipment: .bodyweightOnly, goals: [.cardioEndurance, .leanerToned], highImpact: true, bodyPart: .cardio, targetDurationMinutes: 45...45),
                WorkoutSuggestion(title: "45 min hard bike ride", equipment: .bike, goals: [.cardioEndurance], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 45...45),
                WorkoutSuggestion(title: "40 min resistance band strength circuit", equipment: .resistanceBands, goals: [.buildStrength, .gainMuscle], highImpact: false, bodyPart: .fullBody, targetDurationMinutes: 40...40),
            ]
        case .moderate:
            [
                WorkoutSuggestion(title: "40 min moderate strength training", equipment: .gym, goals: [.buildStrength, .gainMuscle, .generalFitness], highImpact: false, bodyPart: .fullBody, targetDurationMinutes: 40...40),
                WorkoutSuggestion(title: "35 min upper body strength", equipment: .gym, goals: [.buildStrength, .gainMuscle, .generalFitness], highImpact: false, bodyPart: .upperBody, targetDurationMinutes: 35...35),
                WorkoutSuggestion(title: "35 min lower body strength", equipment: .gym, goals: [.buildStrength, .gainMuscle, .generalFitness], highImpact: false, bodyPart: .lowerBody, targetDurationMinutes: 35...35),
                WorkoutSuggestion(title: "35 min steady-state run", equipment: .bodyweightOnly, goals: [.cardioEndurance], highImpact: true, bodyPart: .cardio, targetDurationMinutes: 35...35),
                WorkoutSuggestion(title: "30 min swim", equipment: .pool, goals: [.cardioEndurance, .generalFitness], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 30...30),
                WorkoutSuggestion(title: "45 min moderate bike ride", equipment: .bike, goals: [.cardioEndurance], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 45...45),
                WorkoutSuggestion(title: "30 min resistance band circuit", equipment: .resistanceBands, goals: [.buildStrength, .moreSculpted, .generalFitness], highImpact: false, bodyPart: .fullBody, targetDurationMinutes: 30...30),
                WorkoutSuggestion(title: "45 min vinyasa or power yoga", equipment: .yogaStudio, goals: [.improveFlexibility, .generalFitness], highImpact: false, bodyPart: .core, targetDurationMinutes: 45...45),
            ]
        case .light:
            [
                WorkoutSuggestion(title: "30 min yoga session", equipment: .yogaStudio, goals: [.improveFlexibility, .activeRecovery], highImpact: false, bodyPart: .core, targetDurationMinutes: 30...30),
                WorkoutSuggestion(title: "25 min easy bike ride", equipment: .bike, goals: [.activeRecovery], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 25...25),
                WorkoutSuggestion(title: "20–30 min easy walk", equipment: .bodyweightOnly, goals: [.activeRecovery, .generalFitness], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 20...30),
                WorkoutSuggestion(title: "20 min light mobility work", equipment: .bodyweightOnly, goals: [.improveFlexibility, .activeRecovery], highImpact: false, bodyPart: .core, targetDurationMinutes: 20...20),
                WorkoutSuggestion(title: "20 min easy swim", equipment: .pool, goals: [.activeRecovery], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 20...20),
            ]
        case .rest:
            [
                WorkoutSuggestion(title: "15–20 min gentle walk", equipment: .bodyweightOnly, goals: [.activeRecovery, .betterSleep], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 15...20),
                WorkoutSuggestion(title: "15 min restorative yoga or stretching", equipment: .yogaStudio, goals: [.improveFlexibility, .activeRecovery, .betterSleep], highImpact: false, bodyPart: .core, targetDurationMinutes: 15...15),
                WorkoutSuggestion(title: "10 min foam rolling / mobility", equipment: .bodyweightOnly, goals: [.activeRecovery], highImpact: false, bodyPart: .core, targetDurationMinutes: 10...10),
                WorkoutSuggestion(title: "Full rest day", equipment: .bodyweightOnly, goals: [.activeRecovery, .betterSleep], highImpact: false, bodyPart: .recovery, targetDurationMinutes: nil),
            ]
        }
    }
}

/// What today's suggested session actually targets -- shown alongside the
/// suggestion, and used to deprioritize repeating the same body part on
/// consecutive days once a workout has been logged.
enum BodyPartFocus: String, Codable {
    case fullBody = "full_body"
    case upperBody = "upper_body"
    case lowerBody = "lower_body"
    case core
    case cardio
    case recovery

    var displayName: String {
        switch self {
        case .fullBody: "Full Body"
        case .upperBody: "Upper Body"
        case .lowerBody: "Lower Body"
        case .core: "Abs & Core"
        case .cardio: "Cardio"
        case .recovery: "Recovery"
        }
    }
}

/// Equipment/access tags -- used both for the user's stored profile and to
/// tag each WorkoutSuggestion with what it needs. `.bodyweightOnly` means
/// "needs nothing special" and is always considered available. `.other`
/// pairs with UserProfile.otherEquipmentNotes (free text) for anything not
/// covered by the fixed list.
enum EquipmentTag: String, Codable, CaseIterable, Identifiable {
    case gym
    case homeGym = "home_gym"
    case yogaStudio = "yoga_studio"
    case resistanceBands = "resistance_bands"
    case bike
    case pool
    case boxingGym = "boxing_gym"
    case matPilates = "mat_pilates"
    case calisthenicsGymnastics = "calisthenics_gymnastics"
    case crossfit
    case hiitCircuitStudio = "hiit_circuit_studio"
    case bodyweightOnly = "bodyweight_only"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gym: "Gym"
        case .homeGym: "Home Gym"
        case .yogaStudio: "Yoga Studio"
        case .resistanceBands: "Resistance Bands"
        case .bike: "Bike"
        case .pool: "Pool"
        case .boxingGym: "Boxing Gym"
        case .matPilates: "Mat Pilates"
        case .calisthenicsGymnastics: "Calisthenics & Gymnastics"
        case .crossfit: "CrossFit"
        case .hiitCircuitStudio: "HIIT or Circuit Studio"
        case .bodyweightOnly: "No Equipment"
        case .other: "Other"
        }
    }
}

/// Training goal tags -- used to prioritize which workout suggestions
/// surface first, not to filter them out.
enum GoalTag: String, Codable, CaseIterable, Identifiable {
    case loseWeight = "lose_weight"
    case maintain
    case buildStrength = "build_strength"
    case gainMuscle = "gain_muscle"
    case leanerToned = "leaner_toned"
    case moreSculpted = "more_sculpted"
    case cardioEndurance = "cardio_endurance"
    case improveFlexibility = "improve_flexibility"
    case betterSleep = "better_sleep"
    case generalFitness = "general_fitness"
    case activeRecovery = "active_recovery"
    case other

    var id: String { rawValue }

    /// Exact 9-option subset (in order) for the onboarding "What is your
    /// goal?" screen -- excludes buildStrength/generalFitness/other, which
    /// only apply to the post-onboarding Profile screen's fuller list.
    static let onboardingOptions: [GoalTag] = [
        .loseWeight, .maintain, .leanerToned, .gainMuscle, .cardioEndurance,
        .betterSleep, .improveFlexibility, .activeRecovery, .moreSculpted,
    ]

    var displayName: String {
        switch self {
        case .loseWeight: "Lose Weight"
        case .maintain: "Maintain"
        case .buildStrength: "Build Strength"
        case .gainMuscle: "Gain More Muscle"
        case .leanerToned: "Getting Leaner/Toned"
        case .moreSculpted: "More Sculpted"
        case .cardioEndurance: "Cardiovascular Endurance"
        case .improveFlexibility: "Improving Flexibility"
        case .betterSleep: "Better Sleep"
        case .generalFitness: "General Fitness"
        case .activeRecovery: "Active Recovery"
        case .other: "Other"
        }
    }
}

/// A single concrete, fixed workout suggestion with a specific duration.
struct WorkoutSuggestion: Identifiable {
    var id: String { title }
    let title: String
    let equipment: EquipmentTag
    let goals: Set<GoalTag>
    let highImpact: Bool
    let bodyPart: BodyPartFocus
    /// The duration this suggestion's title claims (e.g. "40 min..." ->
    /// 40...40, "20–30 min..." -> 20...30) -- an explicit value per entry
    /// rather than parsed from `title` at runtime, so copy can change
    /// without silently breaking a parser. `nil` only for "Full rest day",
    /// which makes no time claim. Used to validate the AI-generated plan's
    /// actual summed duration against what was promised.
    var targetDurationMinutes: ClosedRange<Int>?
}

/// Which provider/band drove today's category -- lets the app show a
/// fixed, template-driven "why" explanation without re-deriving the
/// decision-engine logic on-device (the Edge Function is the single
/// source of truth for the actual decision).
enum RecommendationReason: String, Codable {
    case whoopHigh = "whoop_high"
    case whoopMedium = "whoop_medium"
    case whoopLow = "whoop_low"
    case ouraHigh = "oura_high"
    case ouraMediumHigh = "oura_medium_high"
    case ouraMedium = "oura_medium"
    case ouraLow = "oura_low"
    case healthkitHigh = "healthkit_high"
    case healthkitMedium = "healthkit_medium"
    case healthkitLow = "healthkit_low"
    /// Zero usable HealthKit signals today (typically day 1, before any
    /// baseline exists) -- distinct from `.healthkitMedium` so a brand-new
    /// user isn't shown the exact same "medium recovery" explanation a real
    /// reading would get. The underlying category is still a cautious
    /// "moderate" -- only the presented reason differs.
    case insufficientData = "insufficient_data"
    case unknown

    /// Fixed explanation template. `%@` is filled in with the relevant
    /// metric's real value from today's daily_snapshot row when available.
    var explanationTemplate: String {
        switch self {
        case .whoopHigh: "Your Whoop recovery was %@%%, well into the high range (67%%+) -- your body is well-recovered today."
        case .whoopMedium: "Your Whoop recovery was %@%%, in the medium range (34-66%%) -- your body has some room to work, but isn't fully topped up."
        case .whoopLow: "Your Whoop recovery was %@%%, in the low range (under 34%%) -- your body is signaling it needs rest."
        case .ouraHigh: "Your Oura readiness was %@, well into the high range (85+) -- you're set up well for a hard effort."
        case .ouraMediumHigh: "Your Oura readiness was %@, in the medium-high range (70-84) -- solidly good, if not peak."
        case .ouraMedium: "Your Oura readiness was %@, in the medium range (60-69) -- moderate effort suits today."
        case .ouraLow: "Your Oura readiness was %@, under 60 -- your body needs a lighter day."
        case .healthkitHigh: "Your HRV was close to your recent baseline and you slept enough -- a good sign of recovery."
        case .healthkitMedium: "Your HRV was somewhat below your recent baseline, or sleep was a little short -- a moderate day fits best."
        case .healthkitLow: "Your HRV was well below your recent baseline, or sleep was short -- your body needs to ease up today."
        case .insufficientData: "Not enough health data yet to build a personalized read -- Soma is defaulting to a cautious moderate session while your baseline builds."
        case .unknown: "Today's recommendation is based on the data currently available."
        }
    }

    /// Fixed "what to look out for tomorrow" tip, keyed the same way.
    var tomorrowTip: String {
        switch self {
        case .whoopHigh, .ouraHigh:
            "Keep it up -- consistent sleep and hydration tonight will help maintain this trend."
        case .whoopMedium, .ouraMediumHigh, .ouraMedium, .healthkitMedium:
            "A solid night's sleep tonight can push tomorrow into a higher-intensity day."
        case .whoopLow, .ouraLow, .healthkitLow:
            "Prioritize sleep tonight and keep today's effort light -- recovery compounds over a few days, not just one."
        case .healthkitHigh:
            "You're on a good trend -- keep sleep and activity consistent to stay here."
        case .insufficientData:
            "Wearing your Apple Watch overnight, or connecting Whoop or Oura, will give you a personalized read starting tomorrow."
        case .unknown:
            "Connecting Whoop or Oura gives a more precise recovery score than Apple Health alone."
        }
    }
}

/// Mirrors a `daily_recommendation` row (only the fields the app reads).
/// How much the day's band actually rests on. `.low` means one signal or
/// none -- the HealthKit-only path when the watch wasn't worn overnight, or
/// before there's enough history for a baseline. Optional because rows
/// written before the column existed have genuinely unknown confidence, and
/// those show no caveat rather than a made-up one.
enum DataConfidence: String, Codable {
    case high
    case low

    /// Shown under the explanation on the detail screen. Naming the gap turns
    /// a run of identical days from "this app is broken" into something the
    /// user can act on.
    var caveat: String? {
        switch self {
        case .high: nil
        case .low:
            "Today's read is based on limited data — Apple Health didn't record much to go on. Wearing your watch overnight, or connecting Whoop or Oura, makes this more precise."
        }
    }
}

struct DailyRecommendation: Codable, Equatable {
    let date: String
    let category: RecommendationCategory
    let message: String
    let reason: RecommendationReason
    let sleepCapApplied: Bool
    let injuryCapApplied: Bool
    let loadCapApplied: Bool
    let consecutiveDaysCapApplied: Bool
    let injuryProtocolCapApplied: Bool
    let dataConfidence: DataConfidence?

    enum CodingKeys: String, CodingKey {
        case date, category, message, reason
        case dataConfidence = "data_confidence"
        case sleepCapApplied = "sleep_cap_applied"
        case injuryCapApplied = "injury_cap_applied"
        case loadCapApplied = "load_cap_applied"
        case consecutiveDaysCapApplied = "consecutive_days_cap_applied"
        case injuryProtocolCapApplied = "injury_protocol_cap_applied"
    }
}
