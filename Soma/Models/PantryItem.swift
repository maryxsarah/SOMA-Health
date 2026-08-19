import Foundation

/// One entry in the user's persistent "what I have at home" list --
/// structured (name + optional quantity/unit), not a free-text blob, so
/// it's easy to scan and edit as the fridge/pantry actually changes
/// through the week. Feeds generate-meal-recommendation's daily autopilot
/// plan (see SupabaseClient.fetchOrGenerateTodaysMealPlan) the same way
/// household_equipment feeds its equipment awareness -- a persisted,
/// user-editable input rather than something retyped every call.
struct PantryItem: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var quantity: Double?
    var unit: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit
        case updatedAt = "updated_at"
    }
}

extension Array where Element == PantryItem {
    /// Turns the pantry into the same natural-language ingredients string
    /// MealRecommendationView's text field expects (e.g. "2 cups rice,
    /// chicken breast, onion") -- used to prefill the on-demand "What can
    /// I make?" flow from the saved pantry instead of a blank field.
    var asIngredientsText: String {
        map { item in
            let quantityPart = item.quantity.map { qty in
                qty.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(qty)) : String(qty)
            }
            let amount = [quantityPart, item.unit].compactMap { $0 }.joined(separator: " ")
            return amount.isEmpty ? item.name : "\(amount) \(item.name)"
        }.joined(separator: ", ")
    }
}
