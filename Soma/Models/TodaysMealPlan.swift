import Foundation

/// Today's persisted daily-autopilot meal recommendation, if one has been
/// generated -- survives app relaunch, same "cached row, not an in-memory
/// session state" role TodaysAIPlan plays for the workout side
/// (Soma/Models/AIWorkoutPlan.swift). Fetched/generated in one round trip
/// via SupabaseClient.fetchOrGenerateTodaysMealPlan(date:), which is
/// itself a thin wrapper around generate-meal-recommendation's `mode:
/// "daily"` branch -- the server does the real cache-signature check, this
/// struct just decodes whatever it hands back on a hit or a fresh
/// generation.
struct TodaysMealPlan: Decodable {
    let date: String
    /// Today's push_hard/moderate/light/rest category, if a
    /// daily_recommendation row existed yet when this was generated --
    /// nil is a normal, silently-degraded case, not an error (mirrors
    /// generate-meal-recommendation/index.ts's own best-effort read).
    let category: String?
    let recommendation: MealRecommendation
}

/// Decodes generate-meal-recommendation's `mode: "daily"` response, which
/// is either an actual plan or `{"empty": true}` when the pantry has no
/// items yet -- kept as its own DTO (rather than making every field on
/// TodaysMealPlan optional) so the two real states stay easy to switch on
/// via DailyMealPlanResult.
struct DailyMealPlanEnvelope: Decodable {
    let empty: Bool?
    let date: String?
    let category: String?
    let recommendation: MealRecommendation?
}

enum DailyMealPlanResult {
    case plan(TodaysMealPlan)
    case empty
}
