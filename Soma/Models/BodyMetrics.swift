import Foundation

/// Pure, deterministic body metrics derived from data already on the
/// profile (weight, height) -- nothing fabricated or estimated, same
/// "compute, don't guess" rule as NutritionDayProgress/GoalJourneyProgress.
/// Feeds HealthDashboardView's Body tab (tester feedback: "probably need
/// BMI here / some other body metrics + progress toward the goal").
enum BodyMetrics {
    /// nil when either input is missing or height is non-positive --
    /// never a fabricated number.
    static func bmi(weightKg: Double?, heightCm: Double?) -> Double? {
        guard let weightKg, let heightCm, heightCm > 0 else { return nil }
        let heightM = heightCm / 100
        return weightKg / (heightM * heightM)
    }

    /// Standard WHO adult categories -- the same 4 bands cited nearly
    /// universally, not a Soma-specific cutoff.
    static func bmiCategory(_ bmi: Double) -> String {
        switch bmi {
        case ..<18.5: "Underweight"
        case 18.5..<25: "Normal weight"
        case 25..<30: "Overweight"
        default: "Obese"
        }
    }
}
