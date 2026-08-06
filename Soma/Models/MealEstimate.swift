import Foundation

/// AI's best-guess calorie/macro breakdown for a freeform food description
/// (e.g. "2 eggs, toast, and coffee with milk"), returned by
/// parse-meal-text. Never saved as-is -- LogMealView shows this back in
/// its normal editable fields so the user reviews/adjusts before it's
/// actually written to meal_log.
struct MealEstimate: Decodable {
    let label: String
    let calories: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
}
