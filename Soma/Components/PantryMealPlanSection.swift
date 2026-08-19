import SwiftUI

/// NutritionView's pantry entry point + daily-autopilot "Today's meal
/// plan" card -- pulled out into its own file the same way
/// AIWorkoutPlanSections.swift already splits HomeView/
/// RecommendationDetailView's AI plan rendering out of the screens that
/// use it, purely to keep NutritionView's own file size manageable; no
/// behavior change from when this lived inline there.
///
/// Gates between the daily-autopilot experience (a pantry on file) and
/// the original zero-setup "What can I make?" flow (no pantry yet) -- the
/// manual card (passed in as `emptyPantryContent`, unowned by this file
/// since it predates the pantry feature) never disappears, it just moves
/// to secondary billing once there's a real pantry to generate from.
struct PantryMealPlanSection<EmptyPantryContent: View>: View {
    let pantryItems: [PantryItem]
    let todaysMealPlan: TodaysMealPlan?
    let isLoadingMealPlan: Bool
    let onManagePantry: () -> Void
    let onOpenAutopilot: () -> Void
    let onWantDifferent: () -> Void
    @ViewBuilder var emptyPantryContent: () -> EmptyPantryContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            pantryRow
            if pantryItems.isEmpty {
                emptyPantryContent()
            } else {
                if let todaysMealPlan {
                    autopilotMealCard(todaysMealPlan)
                } else if isLoadingMealPlan {
                    CardView {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(String(localized: "nutrition.mealPlan.building", defaultValue: "Building today's meal plan...", comment: "Loading state shown while the daily autopilot meal plan is generating"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                wantSomethingDifferentButton
            }
        }
    }

    private var pantryRow: some View {
        Button(action: onManagePantry) {
            HStack(spacing: 10) {
                Image(systemName: "refrigerator")
                    .foregroundStyle(SomaTokens.accent)
                Text(pantryItems.isEmpty
                    ? String(localized: "nutrition.pantry.rowEmpty", defaultValue: "Pantry -- nothing added yet", comment: "Pantry entry row, shown when the pantry has no items")
                    : String(localized: "nutrition.pantry.rowCount", defaultValue: "Pantry -- \(pantryItems.count) items", comment: "Pantry entry row, shown with the current item count"))
                    .font(.caption.bold())
                    .foregroundStyle(SomaTokens.ink2)
                Spacer()
                Text(String(localized: "nutrition.pantry.manage", defaultValue: "Manage", comment: "Button to open the pantry list for editing"))
                    .font(.caption.bold())
                    .foregroundStyle(SomaTokens.accent)
            }
        }
        .buttonStyle(.plain)
    }

    /// The daily-autopilot plan card -- surfaces "Today's meal plan"
    /// directly on Nutrition, no need to tap into MealRecommendationView
    /// or retype ingredients. Tapping opens the full recipe/logging flow
    /// pre-populated with the cached recommendation (no network call).
    private func autopilotMealCard(_ plan: TodaysMealPlan) -> some View {
        Button(action: onOpenAutopilot) {
            CardView {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle().fill(SomaTokens.accentSoft).frame(width: 40, height: 40)
                        Image(systemName: "fork.knife")
                            .foregroundStyle(SomaTokens.accent)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "nutrition.mealPlan.title", defaultValue: "Today's meal plan", comment: "Title of the daily autopilot meal plan card"))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(plan.recommendation.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SomaTokens.ink)
                        Text(plan.recommendation.whyThisMeal)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Label(String(localized: "nutrition.mealPlan.caloriesLabel", defaultValue: "\(plan.recommendation.calories) kcal", comment: "Calorie count shown on the daily autopilot meal plan card"), systemImage: "flame")
                            .font(.caption2.bold())
                            .foregroundStyle(SomaTokens.accent)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SomaTokens.ink4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var wantSomethingDifferentButton: some View {
        Button(action: onWantDifferent) {
            Text(String(localized: "nutrition.mealPlan.wantDifferent", defaultValue: "Want something different? →", comment: "Button opening the on-demand meal recommendation flow as a one-off variation on the daily plan"))
                .font(.caption.bold())
                .foregroundStyle(SomaTokens.accent)
        }
        .buttonStyle(.plain)
    }
}
