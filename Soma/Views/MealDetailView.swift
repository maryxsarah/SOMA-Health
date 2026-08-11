import SwiftUI

/// Tapped from NutritionView's log -- full details for one logged meal,
/// plus how well it supports the user's goal (rate-meal: Claude Haiku,
/// given the meal's own numbers, the user's real nutrition_targets, and
/// training_emphasis). Computed once and stored on the row; rated lazily
/// here on first view if it doesn't have a score yet -- covers both
/// meals logged before this feature existed, and the rare case where
/// NutritionView's own background pass hasn't finished yet.
struct MealDetailView: View {
    let entry: MealLogEntry
    @Environment(\.dismiss) private var dismiss

    @State private var score: Int?
    @State private var rationale: String?
    @State private var isRating = false
    @State private var ratingError: String?

    init(entry: MealLogEntry) {
        self.entry = entry
        _score = State(initialValue: entry.score)
        _rationale = State(initialValue: entry.rationale)
    }

    private var verdict: MealVerdict? { score.map(MealVerdict.forScore) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    detailsCard
                    ratingCard
                }
                .padding(20)
            }
            .somaBackground()
            .navigationTitle(entry.label?.isEmpty == false ? entry.label! : String(localized: "meal.loggedFoodTitle", defaultValue: "Logged food", comment: "Fallback navigation title for a meal log entry with no label"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            if score == nil { await rate() }
        }
    }

    // MARK: - Details

    private var detailsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Details")
                    .font(.subheadline.bold())
                detailRow("Calories", String(localized: "meal.detail.caloriesValue", defaultValue: "\(entry.calories) kcal", comment: "Calorie amount with unit, e.g. 520 kcal"))
                detailRow("Protein", String(localized: "meal.detail.gramsValue", defaultValue: "\(entry.proteinG) g", comment: "Gram amount with unit, e.g. 42 g"))
                if let carbsG = entry.carbsG {
                    detailRow("Carbs", String(localized: "meal.detail.gramsValue", defaultValue: "\(carbsG) g", comment: "Gram amount with unit, e.g. 42 g"))
                }
                if let fatG = entry.fatG {
                    detailRow("Fat", String(localized: "meal.detail.gramsValue", defaultValue: "\(fatG) g", comment: "Gram amount with unit, e.g. 42 g"))
                }
                detailRow("Logged", Self.timeString(entry.loggedAt))
                detailRow("Source", Self.sourceLabel(entry.source))
            }
        }
    }

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }

    private static func sourceLabel(_ source: String) -> String {
        switch source {
        case "text_ai": String(localized: "meal.source.textAI", defaultValue: "AI-estimated from your description", comment: "Meal log source: estimated from the user's text description")
        case "photo": String(localized: "meal.source.photo", defaultValue: "Photo scan", comment: "Meal log source: estimated from a photo")
        default: String(localized: "meal.source.manual", defaultValue: "Manual entry", comment: "Meal log source: manually entered by the user")
        }
    }

    // MARK: - Rating

    @ViewBuilder
    private var ratingCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                Text("How this fits your goal")
                    .font(.subheadline.bold())
                if isRating {
                    SomaLoadingBar(barWidth: 160)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                } else if let score, let verdict {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(verdict.color.opacity(0.15))
                                .frame(width: 56, height: 56)
                            Text("\(score)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(verdict.color)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verdict.displayTitle)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(verdict.color)
                            Text("out of 10")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let rationale {
                        Text(rationale)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let ratingError {
                    Text(ratingError)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                } else {
                    Text("Not rated yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func rate() async {
        isRating = true
        ratingError = nil
        defer { isRating = false }
        do {
            let result = try await MealRatingCoordinator.shared.rate(id: entry.id)
            score = result.score
            rationale = result.rationale
        } catch {
            ratingError = String(localized: "meal.rating.error", defaultValue: "Couldn't rate this meal right now. Try again later.", comment: "Error shown when rating a meal fails")
        }
    }

    /// Postgres timestamptz comes back as ISO8601 with fractional seconds
    /// -- tries with fractional seconds first, falls back to without,
    /// same pattern as GoalJourneyProgress's own parseISO8601.
    private static func timeString(_ raw: String) -> String {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFractional.date(from: raw) ?? plain.date(from: raw) else { return raw }

        let out = DateFormatter()
        out.dateFormat = "h:mm a"
        out.timeZone = .current
        return out.string(from: date)
    }
}

#Preview {
    MealDetailView(entry: MealLogEntry(
        id: "1", date: "2026-08-06", label: "Grilled chicken and rice", calories: 520,
        proteinG: 42, carbsG: 55, fatG: 12, source: "manual", loggedAt: "2026-08-06T12:30:00Z"
    ))
}
