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
    /// 1-10, computed once by rate-meal (Claude, given this meal's own
    /// numbers plus the user's real nutrition_targets/training_emphasis)
    /// and stored -- nil until first rated (MealDetailView triggers that
    /// lazily). Never recomputed on every view.
    var score: Int? = nil
    /// One short sentence explaining the score. Always present together
    /// with score (both written by the same rate-meal call), never one
    /// without the other.
    var rationale: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, date, label, calories, source, score, rationale
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case loggedAt = "logged_at"
    }

    var verdict: MealVerdict? { score.map(MealVerdict.forScore) }
}

/// Pure derivation from MealLogEntry.score -- never its own stored
/// column (see the 20260806030000 migration's own comment), so a
/// verdict can never drift out of sync with the number it's based on.
enum MealVerdict: Equatable {
    case good, ok, notGreat

    static func forScore(_ score: Int) -> MealVerdict {
        if score >= 7 { return .good }
        if score >= 4 { return .ok }
        return .notGreat
    }

    var displayTitle: String {
        switch self {
        case .good: "Great fit"
        case .ok: "OK fit"
        case .notGreat: "Not a great fit"
        }
    }

    var color: Color {
        switch self {
        case .good: SomaTokens.success
        case .ok: SomaTokens.warn
        case .notGreat: SomaTokens.danger
        }
    }
}
