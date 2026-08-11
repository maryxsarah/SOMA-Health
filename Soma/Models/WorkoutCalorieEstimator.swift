import Foundation

/// Rough calorie-burn estimate for a workout with no real measured number
/// (no wearable/HealthKit data covering the session) -- used only as an
/// honest, explicitly-labeled fallback, never presented as a measured
/// value. See CompletedWorkoutView's calorie hero stat and its
/// `caloriesEstimated`-gated "Estimated" label.
///
/// DRAFTED, NOT EXPERT-REVIEWED MET values -- same standing caveat this
/// codebase already applies to its other rough physiological thresholds
/// (see generate-recommendation/index.ts's sleep/HRV/stress caps). Rest is
/// intentionally excluded: nothing in this app ever logs a rest day as a
/// workout_log row (LogManualWorkoutView's category picker excludes it,
/// and no other source logs "rest" either).
enum WorkoutCalorieEstimator {
    /// Compendium-of-physical-activities-style MET (metabolic equivalent)
    /// values, one per non-rest RecommendationCategory -- a coarse proxy
    /// for effort since this app tracks category, not per-exercise MET.
    private static func met(for category: RecommendationCategory) -> Double? {
        switch category {
        case .light: 4.0
        case .moderate: 6.0
        case .pushHard: 8.5
        case .rest: nil
        }
    }

    /// Standard kcal/min formula: kcal/min = MET * 3.5 * weightKg / 200.
    /// Returns nil -- never a guessed number -- when weight is unknown or
    /// duration is non-positive: an "estimate" with no real weight behind
    /// it isn't an estimate, it's a fabrication, and this app's whole
    /// convention is not to present one of those as fact.
    static func estimateCalories(category: RecommendationCategory, durationMinutes: Int, weightKg: Double?) -> Int? {
        guard let weightKg, weightKg > 0, durationMinutes > 0, let met = met(for: category) else { return nil }
        let kcalPerMinute = met * 3.5 * weightKg / 200
        return Int((kcalPerMinute * Double(durationMinutes)).rounded())
    }
}
