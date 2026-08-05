import Foundation

/// Pure aggregation of today's logged meal_log entries against
/// NutritionTargets -- kept as its own testable struct (same pattern as
/// GoalJourneyProgress) rather than computed inline in the view.
struct NutritionDayProgress {
    let consumedCalories: Int
    let consumedProteinG: Int
    let consumedCarbsG: Int
    let consumedFatG: Int
    let targetCalories: Int
    let targetProteinG: Int
    let targetCarbsG: Int
    let targetFatG: Int

    static func compute(entries: [MealLogEntry], target: NutritionTargets) -> NutritionDayProgress {
        NutritionDayProgress(
            consumedCalories: entries.reduce(0) { $0 + $1.calories },
            consumedProteinG: entries.reduce(0) { $0 + $1.proteinG },
            // carbs/fat are optional per entry (a quick manual log might
            // only include calories + protein) -- missing values count as
            // 0 toward the day's total rather than skipping the entry.
            consumedCarbsG: entries.reduce(0) { $0 + ($1.carbsG ?? 0) },
            consumedFatG: entries.reduce(0) { $0 + ($1.fatG ?? 0) },
            targetCalories: target.dailyCalories,
            targetProteinG: target.dailyProteinG,
            targetCarbsG: target.dailyCarbsG,
            targetFatG: target.dailyFatG
        )
    }

    /// Clamped 0...1 -- a bar's fill never overflows visually even if the
    /// user logged more than their target; the real numbers alongside the
    /// bar still tell the honest "you're over" story.
    static func fraction(consumed: Int, target: Int) -> Double {
        guard target > 0 else { return 0 }
        return min(1.0, max(0.0, Double(consumed) / Double(target)))
    }

    var calorieFraction: Double { Self.fraction(consumed: consumedCalories, target: targetCalories) }
    var proteinFraction: Double { Self.fraction(consumed: consumedProteinG, target: targetProteinG) }
    var carbsFraction: Double { Self.fraction(consumed: consumedCarbsG, target: targetCarbsG) }
    var fatFraction: Double { Self.fraction(consumed: consumedFatG, target: targetFatG) }

    var caloriesRemaining: Int { max(0, targetCalories - consumedCalories) }
}
