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
    @State private var scoreBreakdown: [String]?
    @State private var isRating = false
    @State private var ratingError: String?
    @State private var showEditMacros = false
    /// Editable local copy -- MealDetailView is handed an immutable `entry`
    /// (init-time snapshot), so "Edit macros" needs somewhere of its own to
    /// write the corrected numbers back to for this screen to reflect them
    /// immediately, same reasoning as `score`/`rationale` already being
    /// separate @State rather than mutating `entry` directly.
    @State private var calories: Int
    @State private var proteinG: Int
    @State private var carbsG: Int?
    @State private var fatG: Int?

    init(entry: MealLogEntry) {
        self.entry = entry
        _score = State(initialValue: entry.score)
        _rationale = State(initialValue: entry.rationale)
        _scoreBreakdown = State(initialValue: entry.scoreBreakdown)
        _calories = State(initialValue: entry.calories)
        _proteinG = State(initialValue: entry.proteinG)
        _carbsG = State(initialValue: entry.carbsG)
        _fatG = State(initialValue: entry.fatG)
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
                    Button(String(localized: "meal.detail.doneButton", defaultValue: "Done", comment: "Toolbar button that dismisses the meal detail sheet")) { dismiss() }
                }
            }
        }
        .task {
            if score == nil { await rate() }
        }
        .sheet(isPresented: $showEditMacros) {
            EditMealMacrosSheet(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG) { newCalories, newProteinG, newCarbsG, newFatG in
                await saveEditedMacros(calories: newCalories, proteinG: newProteinG, carbsG: newCarbsG, fatG: newFatG)
            }
        }
    }

    // MARK: - Details

    private var detailsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "meal.detail.sectionTitle", defaultValue: "Details", comment: "Section title above a logged meal's calorie/macro breakdown"))
                        .font(.subheadline.bold())
                    Spacer()
                    Button {
                        showEditMacros = true
                    } label: {
                        Text(String(localized: "meal.detail.editMacrosButton", defaultValue: "Edit macros", comment: "Button that opens a sheet to correct a logged meal's calorie/macro numbers"))
                            .font(.caption.bold())
                            .foregroundStyle(SomaTokens.accent)
                    }
                    .buttonStyle(.plain)
                }
                detailRow(String(localized: "meal.detail.caloriesLabel", defaultValue: "Calories", comment: "Row label for a meal's calorie count"), String(localized: "meal.detail.caloriesValue", defaultValue: "\(calories) kcal", comment: "Calorie amount with unit, e.g. 520 kcal"))
                detailRow(String(localized: "meal.detail.proteinLabel", defaultValue: "Protein", comment: "Row label for a meal's protein amount"), String(localized: "meal.detail.gramsValue", defaultValue: "\(proteinG) g", comment: "Gram amount with unit, e.g. 42 g"))
                if let carbsG {
                    detailRow(String(localized: "meal.detail.carbsLabel", defaultValue: "Carbs", comment: "Row label for a meal's carbohydrate amount"), String(localized: "meal.detail.gramsValue", defaultValue: "\(carbsG) g", comment: "Gram amount with unit, e.g. 42 g"))
                }
                if let fatG {
                    detailRow(String(localized: "meal.detail.fatLabel", defaultValue: "Fat", comment: "Row label for a meal's fat amount"), String(localized: "meal.detail.gramsValue", defaultValue: "\(fatG) g", comment: "Gram amount with unit, e.g. 42 g"))
                }
                detailRow(String(localized: "meal.detail.loggedLabel", defaultValue: "Logged", comment: "Row label for when a meal was logged"), Self.timeString(entry.loggedAt))
                detailRow(String(localized: "meal.detail.sourceLabel", defaultValue: "Source", comment: "Row label for how a meal's numbers were entered"), Self.sourceLabel(entry.source))
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }

    /// Re-derives macros locally, clears the now-stale score/rationale/
    /// breakdown, then re-rates against the corrected numbers -- same
    /// "clear on edit, re-derive lazily" shape SupabaseClient.updateMealLog
    /// applies server-side, kept in sync here so this screen doesn't show a
    /// rating computed from the numbers the user just corrected.
    private func saveEditedMacros(calories: Int, proteinG: Int, carbsG: Int?, fatG: Int?) async {
        do {
            try await SupabaseClient.shared.updateMealLog(id: entry.id, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
            self.calories = calories
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
            score = nil
            rationale = nil
            scoreBreakdown = nil
            await rate()
        } catch {
            ratingError = String(localized: "meal.editMacros.error", defaultValue: "Couldn't save those changes. Try again later.", comment: "Error shown when saving edited meal macros fails")
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
                Text(String(localized: "meal.detail.ratingSectionTitle", defaultValue: "How this fits your goal", comment: "Section title above a logged meal's fit score and rationale"))
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
                            Text(String(localized: "meal.detail.outOfTen", defaultValue: "out of 10", comment: "Caption under the meal fit score's verdict title"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let rationale {
                        Text(rationale)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    // Item 8 fix: the +/- breakdown that produced the score
                    // above, so the number never reads as arbitrary.
                    if let scoreBreakdown, !scoreBreakdown.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(scoreBreakdown.compactMap(MealScoreModifier.init(raw:))) { modifier in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(modifier.isPositive ? "+" : "-")
                                        .font(.caption.bold())
                                        .foregroundStyle(modifier.isPositive ? SomaTokens.success : SomaTokens.danger)
                                    Text(modifier.label)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                } else if let ratingError {
                    Text(ratingError)
                        .font(.caption)
                        .foregroundStyle(SomaTokens.danger)
                } else {
                    Text(String(localized: "meal.detail.notRatedYet", defaultValue: "Not rated yet.", comment: "Shown before a logged meal has been rated"))
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
            scoreBreakdown = result.breakdown
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

/// Item 8's "Edit macros" affordance -- a wrong AI-estimated or mistyped
/// entry was previously permanent (no update RLS policy existed, and no UI
/// offered it), so a bad score had no way to get fixed even once the user
/// noticed the numbers were off. Same field/validation shape as
/// LogMealView's Required/Optional sections, minus the description/AI-
/// estimate path (the meal is already logged -- this only corrects numbers).
private struct EditMealMacrosSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    let onSave: (Int, Int, Int?, Int?) async -> Void

    init(calories: Int, proteinG: Int, carbsG: Int?, fatG: Int?, onSave: @escaping (Int, Int, Int?, Int?) async -> Void) {
        _caloriesText = State(initialValue: String(calories))
        _proteinText = State(initialValue: String(proteinG))
        _carbsText = State(initialValue: carbsG.map(String.init) ?? "")
        _fatText = State(initialValue: fatG.map(String.init) ?? "")
        self.onSave = onSave
    }

    private var calories: Int? { Int(caloriesText) }
    private var protein: Int? { Int(proteinText) }
    private var canSave: Bool { calories != nil && protein != nil && !isSaving }

    /// Same bounds as meal_log's CHECK constraints.
    private static func isInRange(_ value: Int?, max: Int) -> Bool {
        guard let value else { return true }
        return value >= 0 && value <= max
    }

    private var macrosInRange: Bool {
        Self.isInRange(calories, max: 5000) && Self.isInRange(protein, max: 500)
            && Self.isInRange(Int(carbsText), max: 500) && Self.isInRange(Int(fatText), max: 500)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "meal.editMacros.requiredSection", defaultValue: "Required", comment: "Section header for calories/protein fields in the edit-macros sheet")) {
                    LabeledContent(String(localized: "meal.editMacros.caloriesLabel", defaultValue: "Calories", comment: "Field label for calorie count in the edit-macros sheet")) {
                        TextField("kcal", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "meal.editMacros.proteinLabel", defaultValue: "Protein", comment: "Field label for protein amount in the edit-macros sheet")) {
                        TextField("g", text: $proteinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .listRowBackground(SomaTokens.surface2)
                Section(String(localized: "meal.editMacros.optionalSection", defaultValue: "Optional", comment: "Section header for carbs/fat fields in the edit-macros sheet")) {
                    LabeledContent(String(localized: "meal.editMacros.carbsLabel", defaultValue: "Carbs", comment: "Field label for carbohydrate amount in the edit-macros sheet")) {
                        TextField("g", text: $carbsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent(String(localized: "meal.editMacros.fatLabel", defaultValue: "Fat", comment: "Field label for fat amount in the edit-macros sheet")) {
                        TextField("g", text: $fatText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .listRowBackground(SomaTokens.surface2)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .somaBackground()
            .navigationTitle(String(localized: "meal.editMacros.title", defaultValue: "Edit macros", comment: "Navigation title for the edit-macros sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "meal.editMacros.cancelButton", defaultValue: "Cancel", comment: "Cancel button on the edit-macros sheet")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "meal.editMacros.saveButton", defaultValue: "Save", comment: "Save button on the edit-macros sheet")) { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        guard let calories, let protein else { return }
        guard macrosInRange else {
            errorMessage = String(localized: "meal.editMacros.outOfRange", defaultValue: "Calories should be 0-5000 and macros 0-500g -- check your numbers.", comment: "Validation error shown when edited meal macros are out of allowed range")
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        await onSave(calories, protein, Int(carbsText), Int(fatText))
        dismiss()
    }
}

#Preview {
    MealDetailView(entry: MealLogEntry(
        id: "1", date: "2026-08-06", label: "Grilled chicken and rice", calories: 520,
        proteinG: 42, carbsG: 55, fatG: 12, source: "manual", loggedAt: "2026-08-06T12:30:00Z"
    ))
}
