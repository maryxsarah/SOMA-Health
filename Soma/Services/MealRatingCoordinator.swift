import Foundation

/// Dedupes concurrent rate-meal calls for the same meal_log id.
/// NutritionView's sweep and an open MealDetailView can both fire one at once.
actor MealRatingCoordinator {
    static let shared = MealRatingCoordinator()

    private var inFlight: [String: Task<(score: Int, rationale: String), Error>] = [:]

    func rate(id: String) async throws -> (score: Int, rationale: String) {
        if let existing = inFlight[id] {
            return try await existing.value
        }

        let task = Task<(score: Int, rationale: String), Error> {
            try await SupabaseClient.shared.rateMeal(id: id)
        }
        inFlight[id] = task
        do {
            let result = try await task.value
            inFlight[id] = nil
            return result
        } catch {
            inFlight[id] = nil
            throw error
        }
    }
}
