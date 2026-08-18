import Foundation
import SwiftUI

/// Mirrors a `meal_log` row -- manual food-intake entries (source
/// "manual" today; the column also accepts "photo" so a future real
/// meal-scan feature can write into this same table without a schema
/// change). User-entered content, same category as workout_log: no
/// derived/safety logic involved.
struct MealLogEntry: Codable, Identifiable {
    let id: String
    let date: String
    let label: String?
    let calories: Int
    let proteinG: Int
    let carbsG: Int?
    let fatG: Int?
    let source: String
    let loggedAt: String
    /// 1-10, computed once by rate-meal (deterministic: baseScore from
    /// protein density -> modifiers for alcohol/fat-share/processing ->
    /// clamp; see scoreMeal.ts) and stored -- nil until first rated
    /// (MealDetailView triggers that lazily). Never recomputed on every view.
    var score: Int? = nil
    /// One short sentence explaining the score, built FROM the same
    /// modifiers `scoreBreakdown` lists (rate-meal's rationale.ts) -- always
    /// present together with score, never one without the other.
    var rationale: String? = nil
    /// "<sign>:<key>" entries, e.g. "-:alcohol", "+:highProteinDensity" --
    /// the exact modifiers that produced `score`, in the order they fired.
    /// Raw/unlocalized on purpose (see rate-meal/index.ts's own comment):
    /// MealDetailView maps each key to a localized short phrase, same
    /// "server derives, client localizes" split as MealVerdict itself.
    var scoreBreakdown: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, label, calories, source, score, rationale
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case loggedAt = "logged_at"
        case scoreBreakdown = "score_breakdown"
    }

    var verdict: MealVerdict? { score.map(MealVerdict.forScore) }
}

/// One fired scoring modifier, decoded from a MealLogEntry.scoreBreakdown
/// entry ("<sign>:<key>") -- `key` is looked up against a fixed, known set
/// (unrecognized keys fall back to displaying themselves raw rather than
/// disappearing silently, matching this codebase's forward-compat
/// convention for server-owned vocabularies, e.g. RecommendationReason).
struct MealScoreModifier: Identifiable {
    var id: String { raw }
    let raw: String
    let isPositive: Bool
    let label: String

    init?(raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        self.raw = raw
        self.isPositive = parts[0] == "+"
        self.label = Self.displayLabel(for: String(parts[1]))
    }

    private static func displayLabel(for key: String) -> String {
        switch key {
        case "highProteinDensity": String(localized: "mealScore.modifier.highProteinDensity", defaultValue: "High protein for its calories", comment: "Meal score breakdown line: high protein density")
        case "solidProteinDensity": String(localized: "mealScore.modifier.solidProteinDensity", defaultValue: "Solid protein for its calories", comment: "Meal score breakdown line: solid protein density")
        case "lowProteinDensity": String(localized: "mealScore.modifier.lowProteinDensity", defaultValue: "Low protein for its calories", comment: "Meal score breakdown line: low protein density")
        case "largeCutShare": String(localized: "mealScore.modifier.largeCutShare", defaultValue: "A large share of today's calorie budget for a cut", comment: "Meal score breakdown line: large share of daily calories while cutting")
        case "veryHighFatShare": String(localized: "mealScore.modifier.veryHighFatShare", defaultValue: "Over half its calories are from fat", comment: "Meal score breakdown line: very high fat share")
        case "highFatShare": String(localized: "mealScore.modifier.highFatShare", defaultValue: "A high share of its calories are from fat", comment: "Meal score breakdown line: high fat share")
        case "ultraProcessed": String(localized: "mealScore.modifier.ultraProcessed", defaultValue: "Ultra-processed", comment: "Meal score breakdown line: ultra-processed food")
        case "alcohol": String(localized: "mealScore.modifier.alcohol", defaultValue: "Contains alcohol", comment: "Meal score breakdown line: contains alcohol")
        default: key
        }
    }
}

/// Pure derivation from MealLogEntry.score -- never its own stored
/// column (see the 20260806030000 migration's own comment), so a
/// verdict can never drift out of sync with the number it's based on.
/// 4 tiers, not 3 (item 8 fix) -- the old 3-tier scale (7+ "Great fit")
/// made 7/10 read as a strong endorsement even for a meal the deterministic
/// formula only rates "good enough", not "excellent".
enum MealVerdict: Equatable {
    case excellent, normal, mediocre, offTarget

    static func forScore(_ score: Int) -> MealVerdict {
        if score >= 8 { return .excellent }
        if score >= 6 { return .normal }
        if score >= 4 { return .mediocre }
        return .offTarget
    }

    var displayTitle: String {
        switch self {
        case .excellent: String(localized: "mealVerdict.excellent", defaultValue: "Excellent choice", comment: "Meal verdict badge shown for a top-tier score (8-10)")
        case .normal: String(localized: "mealVerdict.normal", defaultValue: "Good fit", comment: "Meal verdict badge shown for a solid score (6-7)")
        case .mediocre: String(localized: "mealVerdict.mediocre", defaultValue: "Mediocre", comment: "Meal verdict badge shown for a middling score (4-5)")
        case .offTarget: String(localized: "mealVerdict.offTarget", defaultValue: "Off target", comment: "Meal verdict badge shown for a low score (1-3)")
        }
    }

    var color: Color {
        switch self {
        case .excellent: SomaTokens.success
        case .normal: SomaTokens.accent
        case .mediocre: SomaTokens.warn
        case .offTarget: SomaTokens.danger
        }
    }
}
