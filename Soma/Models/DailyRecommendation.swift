import Foundation

enum RecommendationCategory: String, Codable {
    case rest
    case light
    case moderate
    case pushHard = "push_hard"

    var displayTitle: String {
        switch self {
        case .rest: String(localized: "recommendationCategory.rest", defaultValue: "Rest", comment: "Daily recommendation category label: full rest day")
        case .light: String(localized: "recommendationCategory.light", defaultValue: "Light Movement", comment: "Daily recommendation category label: light movement day")
        case .moderate: String(localized: "recommendationCategory.moderate", defaultValue: "Moderate", comment: "Daily recommendation category label: moderate effort day")
        case .pushHard: String(localized: "recommendationCategory.pushHard", defaultValue: "Push Hard", comment: "Daily recommendation category label: high intensity day")
        }
    }

    /// Fixed, rule-based target -- not personalized per user, but tied to
    /// today's category (which itself is derived from the user's data).
    var stepTarget: String {
        switch self {
        case .pushHard: String(localized: "recommendationCategory.stepTarget.pushHard", defaultValue: "10,000+ steps", comment: "Daily step target range shown for the Push Hard category")
        case .moderate: String(localized: "recommendationCategory.stepTarget.moderate", defaultValue: "7,000–9,000 steps", comment: "Daily step target range shown for the Moderate category")
        case .light: String(localized: "recommendationCategory.stepTarget.light", defaultValue: "4,000–6,000 steps", comment: "Daily step target range shown for the Light Movement category")
        case .rest: String(localized: "recommendationCategory.stepTarget.rest", defaultValue: "2,000–3,000 steps", comment: "Daily step target range shown for the Rest category")
        }
    }

    /// Numeric form of `stepTarget` (its range's upper bound) -- drives the
    /// step tracker pill's progress math. Keep the two in sync.
    var stepTargetCount: Int {
        switch self {
        case .pushHard: 10000
        case .moderate: 9000
        case .light: 6000
        case .rest: 3000
        }
    }

    /// Rough expected calorie burn for a session in this category -- the
    /// "dayTarget" DayLoadState compares a logged workout's calories
    /// against, so Home/RecommendationDetail can tell "closed today's
    /// quota" apart from "barely started" apart from "way over". Not
    /// personalized (no such per-user target exists yet), same posture as
    /// stepTarget above.
    var dayLoadTargetKcal: Int {
        switch self {
        case .pushHard: 550
        case .moderate: 350
        case .light: 150
        case .rest: 50
        }
    }

    /// Fixed, specific suggestions per category -- concrete activity +
    /// duration, no AI generation, same pattern as the existing 4 message
    /// templates. Each carries equipment/impact/body-part tags so the
    /// detail view can prioritize/filter by the user's profile and show
    /// what today's session actually targets.
    ///
    /// The (bodyPart, goals) shape of this catalog is hand-mirrored, in
    /// reduced form, by generate-gym-workout/targetBodyPart.ts's
    /// CATEGORY_BODY_PART_CANDIDATES (server-side, Deno -- can't share this
    /// Swift catalog directly). If you change which body parts/goals a
    /// category's suggestions carry, update that file's table too, or the
    /// gym-photo flow's default body-part resolution will silently drift
    /// from what this picker shows.
    var workoutSuggestions: [WorkoutSuggestion] {
        switch self {
        case .pushHard:
            [
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.fullBodyStrength50", defaultValue: "50 min full-body strength training", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .gym, goals: [.buildStrength, .gainMuscle], highImpact: false, bodyPart: .fullBody, targetDurationMinutes: 50...50),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.upperBodyStrength40", defaultValue: "40 min upper body strength (chest, back, shoulders, arms)", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .gym, goals: [.buildStrength, .gainMuscle], highImpact: false, bodyPart: .upperBody, targetDurationMinutes: 40...40),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.lowerBodyStrength40", defaultValue: "40 min lower body strength (quads, hamstrings, glutes)", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .gym, goals: [.buildStrength, .gainMuscle], highImpact: false, bodyPart: .lowerBody, targetDurationMinutes: 40...40),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.hiitCircuit30", defaultValue: "30 min HIIT circuit", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bodyweightOnly, goals: [.leanerToned, .moreSculpted, .cardioEndurance], highImpact: true, bodyPart: .fullBody, targetDurationMinutes: 30...30),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.hardRun45", defaultValue: "45 min hard run", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bodyweightOnly, goals: [.cardioEndurance, .leanerToned], highImpact: true, bodyPart: .cardio, targetDurationMinutes: 45...45),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.hardBikeRide45", defaultValue: "45 min hard bike ride", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bike, goals: [.cardioEndurance], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 45...45),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.resistanceBandStrength40", defaultValue: "40 min resistance band strength circuit", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .resistanceBands, goals: [.buildStrength, .gainMuscle], highImpact: false, bodyPart: .fullBody, targetDurationMinutes: 40...40),
            ]
        case .moderate:
            [
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.moderateStrength40", defaultValue: "40 min moderate strength training", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .gym, goals: [.buildStrength, .gainMuscle, .generalFitness], highImpact: false, bodyPart: .fullBody, targetDurationMinutes: 40...40),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.upperBodyStrength35", defaultValue: "35 min upper body strength", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .gym, goals: [.buildStrength, .gainMuscle, .generalFitness], highImpact: false, bodyPart: .upperBody, targetDurationMinutes: 35...35),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.lowerBodyStrength35", defaultValue: "35 min lower body strength", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .gym, goals: [.buildStrength, .gainMuscle, .generalFitness], highImpact: false, bodyPart: .lowerBody, targetDurationMinutes: 35...35),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.steadyStateRun35", defaultValue: "35 min steady-state run", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bodyweightOnly, goals: [.cardioEndurance], highImpact: true, bodyPart: .cardio, targetDurationMinutes: 35...35),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.swim30", defaultValue: "30 min swim", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .pool, goals: [.cardioEndurance, .generalFitness], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 30...30),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.moderateBikeRide45", defaultValue: "45 min moderate bike ride", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bike, goals: [.cardioEndurance], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 45...45),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.resistanceBandCircuit30", defaultValue: "30 min resistance band circuit", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .resistanceBands, goals: [.buildStrength, .moreSculpted, .generalFitness], highImpact: false, bodyPart: .fullBody, targetDurationMinutes: 30...30),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.vinyasaPowerYoga45", defaultValue: "45 min vinyasa or power yoga", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .yogaStudio, goals: [.improveFlexibility, .generalFitness], highImpact: false, bodyPart: .core, targetDurationMinutes: 45...45),
            ]
        case .light:
            [
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.yogaSession30", defaultValue: "30 min yoga session", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .yogaStudio, goals: [.improveFlexibility, .activeRecovery], highImpact: false, bodyPart: .core, targetDurationMinutes: 30...30),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.easyBikeRide25", defaultValue: "25 min easy bike ride", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bike, goals: [.activeRecovery], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 25...25),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.easyWalk2030", defaultValue: "20–30 min easy walk", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bodyweightOnly, goals: [.activeRecovery, .generalFitness], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 20...30),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.lightMobility20", defaultValue: "20 min light mobility work", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bodyweightOnly, goals: [.improveFlexibility, .activeRecovery], highImpact: false, bodyPart: .core, targetDurationMinutes: 20...20),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.easySwim20", defaultValue: "20 min easy swim", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .pool, goals: [.activeRecovery], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 20...20),
            ]
        case .rest:
            [
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.gentleWalk1520", defaultValue: "15–20 min gentle walk", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bodyweightOnly, goals: [.activeRecovery, .betterSleep], highImpact: false, bodyPart: .cardio, targetDurationMinutes: 15...20),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.restorativeYoga15", defaultValue: "15 min restorative yoga or stretching", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .yogaStudio, goals: [.improveFlexibility, .activeRecovery, .betterSleep], highImpact: false, bodyPart: .core, targetDurationMinutes: 15...15),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.foamRolling10", defaultValue: "10 min foam rolling / mobility", comment: "Concrete workout suggestion title shown on the daily recommendation screen"), equipment: .bodyweightOnly, goals: [.activeRecovery], highImpact: false, bodyPart: .core, targetDurationMinutes: 10...10),
                WorkoutSuggestion(title: String(localized: "workoutSuggestion.fullRestDay", defaultValue: "Full rest day", comment: "Concrete workout suggestion title shown on the daily recommendation screen: no exercise, complete rest"), equipment: .bodyweightOnly, goals: [.activeRecovery, .betterSleep], highImpact: false, bodyPart: .recovery, targetDurationMinutes: nil),
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
        case .fullBody: String(localized: "bodyPartFocus.fullBody", defaultValue: "Full Body", comment: "Body part focus label for a workout")
        case .upperBody: String(localized: "bodyPartFocus.upperBody", defaultValue: "Upper Body", comment: "Body part focus label for a workout")
        case .lowerBody: String(localized: "bodyPartFocus.lowerBody", defaultValue: "Lower Body", comment: "Body part focus label for a workout")
        case .core: String(localized: "bodyPartFocus.core", defaultValue: "Abs & Core", comment: "Body part focus label for a workout")
        case .cardio: String(localized: "bodyPartFocus.cardio", defaultValue: "Cardio", comment: "Body part focus label for a workout")
        case .recovery: String(localized: "bodyPartFocus.recovery", defaultValue: "Recovery", comment: "Body part focus label for a workout")
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
        case .gym: String(localized: "equipmentTag.gym", defaultValue: "Gym", comment: "Equipment/access tag label")
        case .homeGym: String(localized: "equipmentTag.homeGym", defaultValue: "Home Gym", comment: "Equipment/access tag label")
        case .yogaStudio: String(localized: "equipmentTag.yogaStudio", defaultValue: "Yoga Studio", comment: "Equipment/access tag label")
        case .resistanceBands: String(localized: "equipmentTag.resistanceBands", defaultValue: "Resistance Bands", comment: "Equipment/access tag label")
        case .bike: String(localized: "equipmentTag.bike", defaultValue: "Bike", comment: "Equipment/access tag label")
        case .pool: String(localized: "equipmentTag.pool", defaultValue: "Pool", comment: "Equipment/access tag label")
        case .boxingGym: String(localized: "equipmentTag.boxingGym", defaultValue: "Boxing Gym", comment: "Equipment/access tag label")
        case .matPilates: String(localized: "equipmentTag.matPilates", defaultValue: "Mat Pilates", comment: "Equipment/access tag label")
        case .calisthenicsGymnastics: String(localized: "equipmentTag.calisthenicsGymnastics", defaultValue: "Calisthenics & Gymnastics", comment: "Equipment/access tag label")
        case .crossfit: String(localized: "equipmentTag.crossfit", defaultValue: "CrossFit", comment: "Equipment/access tag label; CrossFit is a brand name, keep untranslated")
        case .hiitCircuitStudio: String(localized: "equipmentTag.hiitCircuitStudio", defaultValue: "HIIT or Circuit Studio", comment: "Equipment/access tag label")
        case .bodyweightOnly: String(localized: "equipmentTag.bodyweightOnly", defaultValue: "No Equipment", comment: "Equipment/access tag label: needs nothing special")
        case .other: String(localized: "equipmentTag.other", defaultValue: "Other", comment: "Equipment/access tag label: catch-all option")
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
        case .loseWeight: String(localized: "goalTag.loseWeight", defaultValue: "Lose Weight", comment: "Training goal tag label")
        case .maintain: String(localized: "goalTag.maintain", defaultValue: "Maintain", comment: "Training goal tag label")
        case .buildStrength: String(localized: "goalTag.buildStrength", defaultValue: "Build Strength", comment: "Training goal tag label")
        case .gainMuscle: String(localized: "goalTag.gainMuscle", defaultValue: "Gain More Muscle", comment: "Training goal tag label")
        case .leanerToned: String(localized: "goalTag.leanerToned", defaultValue: "Getting Leaner/Toned", comment: "Training goal tag label")
        case .moreSculpted: String(localized: "goalTag.moreSculpted", defaultValue: "More Sculpted", comment: "Training goal tag label")
        case .cardioEndurance: String(localized: "goalTag.cardioEndurance", defaultValue: "Cardiovascular Endurance", comment: "Training goal tag label")
        case .improveFlexibility: String(localized: "goalTag.improveFlexibility", defaultValue: "Improving Flexibility", comment: "Training goal tag label")
        case .betterSleep: String(localized: "goalTag.betterSleep", defaultValue: "Better Sleep", comment: "Training goal tag label")
        case .generalFitness: String(localized: "goalTag.generalFitness", defaultValue: "General Fitness", comment: "Training goal tag label")
        case .activeRecovery: String(localized: "goalTag.activeRecovery", defaultValue: "Active Recovery", comment: "Training goal tag label")
        case .other: String(localized: "goalTag.other", defaultValue: "Other", comment: "Training goal tag label: catch-all option")
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
    /// The reason vocabulary is owned by the server and grows with it --
    /// the `insufficient_data` migration added a value this enum didn't
    /// have, and with plain synthesized decoding one unrecognized string
    /// threw for the whole row (and, in the history fetch, the whole
    /// array): Home showed nothing instead of a recommendation with a
    /// generic explanation. Unknown values decode as `.unknown`.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RecommendationReason(rawValue: raw) ?? .unknown
    }

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

    /// Value is interpolated directly -- a stored "%@" with no matching
    /// interpolation argument crashes String(localized:) resolution on-device.
    func explanation(snapshots: [DailySnapshotRow]) -> String {
        func formatted(_ value: Double?) -> String {
            guard let value else { return "—" }
            return String(Int(value.rounded()))
        }
        switch self {
        case .whoopHigh:
            let percent = formatted(snapshots.first(where: { $0.source == "whoop" })?.recoveryScore)
            return String(localized: "recommendationReason.explanation.whoopHigh", defaultValue: "Your Whoop recovery was \(percent)%, well into the high range (67%+) -- your body is well-recovered today.", comment: "Recovery percent is pre-formatted text, e.g. '72' or '—' when unavailable")
        case .whoopMedium:
            let percent = formatted(snapshots.first(where: { $0.source == "whoop" })?.recoveryScore)
            return String(localized: "recommendationReason.explanation.whoopMedium", defaultValue: "Your Whoop recovery was \(percent)%, in the medium range (34-66%) -- your body has some room to work, but isn't fully topped up.", comment: "Recovery percent is pre-formatted text, e.g. '72' or '—' when unavailable")
        case .whoopLow:
            let percent = formatted(snapshots.first(where: { $0.source == "whoop" })?.recoveryScore)
            return String(localized: "recommendationReason.explanation.whoopLow", defaultValue: "Your Whoop recovery was \(percent)%, in the low range (under 34%) -- your body is signaling it needs rest.", comment: "Recovery percent is pre-formatted text, e.g. '72' or '—' when unavailable")
        case .ouraHigh:
            let score = formatted(snapshots.first(where: { $0.source == "oura" })?.readinessScore)
            return String(localized: "recommendationReason.explanation.ouraHigh", defaultValue: "Your Oura readiness was \(score), well into the high range (85+) -- you're set up well for a hard effort.", comment: "Readiness score is pre-formatted text, e.g. '88' or '—' when unavailable")
        case .ouraMediumHigh:
            let score = formatted(snapshots.first(where: { $0.source == "oura" })?.readinessScore)
            return String(localized: "recommendationReason.explanation.ouraMediumHigh", defaultValue: "Your Oura readiness was \(score), in the medium-high range (70-84) -- solidly good, if not peak.", comment: "Readiness score is pre-formatted text, e.g. '88' or '—' when unavailable")
        case .ouraMedium:
            let score = formatted(snapshots.first(where: { $0.source == "oura" })?.readinessScore)
            return String(localized: "recommendationReason.explanation.ouraMedium", defaultValue: "Your Oura readiness was \(score), in the medium range (60-69) -- moderate effort suits today.", comment: "Readiness score is pre-formatted text, e.g. '88' or '—' when unavailable")
        case .ouraLow:
            let score = formatted(snapshots.first(where: { $0.source == "oura" })?.readinessScore)
            return String(localized: "recommendationReason.explanation.ouraLow", defaultValue: "Your Oura readiness was \(score), under 60 -- your body needs a lighter day.", comment: "Readiness score is pre-formatted text, e.g. '88' or '—' when unavailable")
        case .healthkitHigh:
            return String(localized: "recommendationReason.explanation.healthkitHigh", defaultValue: "Your HRV was close to your recent baseline and you slept enough -- a good sign of recovery.", comment: "No placeholders")
        case .healthkitMedium:
            return String(localized: "recommendationReason.explanation.healthkitMedium", defaultValue: "Your HRV was somewhat below your recent baseline, or sleep was a little short -- a moderate day fits best.", comment: "No placeholders")
        case .healthkitLow:
            return String(localized: "recommendationReason.explanation.healthkitLow", defaultValue: "Your HRV was well below your recent baseline, or sleep was short -- your body needs to ease up today.", comment: "No placeholders")
        case .insufficientData:
            return String(localized: "recommendationReason.explanation.insufficientData", defaultValue: "Not enough health data yet to build a personalized read -- Soma is defaulting to a cautious moderate session while your baseline builds.", comment: "No placeholders")
        case .unknown:
            return String(localized: "recommendationReason.explanation.unknown", defaultValue: "Today's recommendation is based on the data currently available.", comment: "No placeholders; fallback for unrecognized server reason codes")
        }
    }

    /// Fixed "what to look out for tomorrow" tip, keyed the same way.
    var tomorrowTip: String {
        switch self {
        case .whoopHigh, .ouraHigh:
            String(localized: "recommendationReason.tomorrowTip.highRecovery", defaultValue: "Keep it up -- consistent sleep and hydration tonight will help maintain this trend.", comment: "Tomorrow tip shown for a high recovery/readiness day; no placeholders")
        case .whoopMedium, .ouraMediumHigh, .ouraMedium, .healthkitMedium:
            String(localized: "recommendationReason.tomorrowTip.mediumRecovery", defaultValue: "A solid night's sleep tonight can push tomorrow into a higher-intensity day.", comment: "Tomorrow tip shown for a medium recovery/readiness day; no placeholders")
        case .whoopLow, .ouraLow, .healthkitLow:
            String(localized: "recommendationReason.tomorrowTip.lowRecovery", defaultValue: "Prioritize sleep tonight and keep today's effort light -- recovery compounds over a few days, not just one.", comment: "Tomorrow tip shown for a low recovery/readiness day; no placeholders")
        case .healthkitHigh:
            String(localized: "recommendationReason.tomorrowTip.healthkitHigh", defaultValue: "You're on a good trend -- keep sleep and activity consistent to stay here.", comment: "Tomorrow tip shown for a high HealthKit-only recovery day; no placeholders")
        case .insufficientData:
            String(localized: "recommendationReason.tomorrowTip.insufficientData", defaultValue: "Wearing your Apple Watch overnight, or connecting Whoop or Oura, will give you a personalized read starting tomorrow.", comment: "Tomorrow tip shown when there wasn't enough health data today; no placeholders")
        case .unknown:
            String(localized: "recommendationReason.tomorrowTip.unknown", defaultValue: "Connecting Whoop or Oura gives a more precise recovery score than Apple Health alone.", comment: "Tomorrow tip fallback for unrecognized server reason codes; no placeholders")
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
            String(localized: "dataConfidence.caveat.low", defaultValue: "Today's read is based on limited data — Apple Health didn't record much to go on. Wearing your watch overnight, or connecting Whoop or Oura, makes this more precise.", comment: "Caveat shown under the explanation when confidence in today's read is low; no placeholders")
        }
    }
}

struct DailyRecommendation: Codable, Equatable {
    let date: String
    let category: RecommendationCategory
    let message: String
    /// The fuller reasoning `message` was capped down from (caps/confidence
    /// clauses included) -- shown in the "Why this?" disclosure. Nil for
    /// rows written before this column existed, or for the user-requested-
    /// override/insufficient-data paths, which have nothing more to add
    /// beyond `message` itself.
    let messageDetail: String?
    let reason: RecommendationReason
    let sleepCapApplied: Bool
    let injuryCapApplied: Bool
    let loadCapApplied: Bool
    let consecutiveDaysCapApplied: Bool
    let injuryProtocolCapApplied: Bool
    let injuryProtocolModerateCapApplied: Bool
    let pregnancyCapApplied: Bool
    let volumeCapApplied: Bool
    let hrvCapApplied: Bool
    let stressCapApplied: Bool
    /// Set when a severe injury protocol was just reported/escalated in
    /// the last ~24h, or has been trending worse for 3+ consecutive
    /// check-ins -- forces `category` all the way to `.rest`, unlike
    /// `injuryProtocolCapApplied`'s ceiling of `.light`. Real feedback:
    /// "when the user shared a specific injury, if needed a rest day
    /// needs to be recommended."
    let injuryProtocolRestApplied: Bool
    /// Set when today's daily_mood check-in (rating 1-2 of 5) downgraded
    /// the day -- real feedback: "the emoji should be considered for the
    /// workout." Asymmetric like every other cap: a good mood never
    /// upgrades the day, so this only ever appears alongside a downgrade.
    let moodCapApplied: Bool
    /// The uncapped recovery-band category, when the server has it on
    /// record -- lets RecommendationDetailView offer "a standard workout
    /// anyway" without re-deriving the recovery band client-side. Nil for
    /// rows written before this column existed.
    let preCapCategory: RecommendationCategory?
    let dataConfidence: DataConfidence?
    /// Set only via the "request a rest/active-recovery day" affordance --
    /// distinct from every cap above (those are computed from health data;
    /// this is the user's own direct request, which wins outright over all
    /// of them server-side). Nil means no override is active today.
    let userRequestedCategory: RecommendationCategory?

    enum CodingKeys: String, CodingKey {
        case date, category, message, reason
        case messageDetail = "message_detail"
        case dataConfidence = "data_confidence"
        case sleepCapApplied = "sleep_cap_applied"
        case injuryCapApplied = "injury_cap_applied"
        case loadCapApplied = "load_cap_applied"
        case consecutiveDaysCapApplied = "consecutive_days_cap_applied"
        case injuryProtocolCapApplied = "injury_protocol_cap_applied"
        case injuryProtocolModerateCapApplied = "injury_protocol_moderate_cap_applied"
        case pregnancyCapApplied = "pregnancy_cap_applied"
        case volumeCapApplied = "volume_cap_applied"
        case hrvCapApplied = "hrv_cap_applied"
        case stressCapApplied = "stress_cap_applied"
        case injuryProtocolRestApplied = "injury_protocol_rest_applied"
        case moodCapApplied = "mood_cap_applied"
        case preCapCategory = "pre_cap_category"
        case userRequestedCategory = "user_requested_category"
    }
}

// In an extension so the synthesized memberwise init survives.
extension DailyRecommendation {
    /// The newest cap flags decode as absent-means-false. App releases
    /// and Edge Function deployments are not atomic: a response from a
    /// function version predating a flag simply omits the key, and a
    /// required Bool turned that into a decode failure for the whole row
    /// -- the same blank-Home failure mode as an unrecognized reason
    /// string. The three original cap flags predate every deployed
    /// function version, so they stay required.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        category = try container.decode(RecommendationCategory.self, forKey: .category)
        message = try container.decode(String.self, forKey: .message)
        messageDetail = try container.decodeIfPresent(String.self, forKey: .messageDetail)
        reason = try container.decode(RecommendationReason.self, forKey: .reason)
        sleepCapApplied = try container.decode(Bool.self, forKey: .sleepCapApplied)
        injuryCapApplied = try container.decode(Bool.self, forKey: .injuryCapApplied)
        loadCapApplied = try container.decode(Bool.self, forKey: .loadCapApplied)
        consecutiveDaysCapApplied = try container.decodeIfPresent(Bool.self, forKey: .consecutiveDaysCapApplied) ?? false
        injuryProtocolCapApplied = try container.decodeIfPresent(Bool.self, forKey: .injuryProtocolCapApplied) ?? false
        injuryProtocolModerateCapApplied = try container.decodeIfPresent(Bool.self, forKey: .injuryProtocolModerateCapApplied) ?? false
        pregnancyCapApplied = try container.decodeIfPresent(Bool.self, forKey: .pregnancyCapApplied) ?? false
        volumeCapApplied = try container.decodeIfPresent(Bool.self, forKey: .volumeCapApplied) ?? false
        hrvCapApplied = try container.decodeIfPresent(Bool.self, forKey: .hrvCapApplied) ?? false
        stressCapApplied = try container.decodeIfPresent(Bool.self, forKey: .stressCapApplied) ?? false
        injuryProtocolRestApplied = try container.decodeIfPresent(Bool.self, forKey: .injuryProtocolRestApplied) ?? false
        moodCapApplied = try container.decodeIfPresent(Bool.self, forKey: .moodCapApplied) ?? false
        preCapCategory = try container.decodeIfPresent(RecommendationCategory.self, forKey: .preCapCategory)
        dataConfidence = try container.decodeIfPresent(DataConfidence.self, forKey: .dataConfidence)
        userRequestedCategory = try container.decodeIfPresent(RecommendationCategory.self, forKey: .userRequestedCategory)
    }
}
