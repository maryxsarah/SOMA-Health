import SwiftUI

/// Quick food entry -- type numbers directly, describe the meal in plain
/// words, or dictate it out loud (mic button, on-device speech-to-text)
/// -- either text path then lets Claude estimate calories/macros
/// (parse-meal-text). Every path lands in the same editable fields
/// below, reviewed and adjustable before Save -- the AI path is an
/// assist, never a silent auto-log. Calories and protein are required
/// (the two numbers most people actually know off-hand); carbs/fat are
/// optional.
///
/// No `date` is captured at construction time -- `save()` computes
/// `NutritionView.todayDateString()` itself, at the moment of the actual
/// write. This sheet can stay open through a whole dictate ->
/// AI-estimate -> review round trip; capturing "today" once when the
/// sheet opens meant a save that happened to land after local midnight
/// silently wrote yesterday's date, and the entry would never show up in
/// "today's" totals even though it saved successfully. Same fix already
/// applied correctly in MealRecommendationView.logThisMeal -- this just
/// brings LogMealView in line with that existing pattern.
struct LogMealView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speechRecognizer = SpeechRecognizer()

    @State private var label = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var isSaving = false
    @State private var isEstimating = false
    @State private var errorMessage: String?
    /// True once an estimate has been fetched -- tags the eventual save
    /// as source "text_ai" instead of "manual", even if the user tweaks
    /// a number afterward (still AI-assisted provenance). Dictation is
    /// just another way of producing the text that gets estimated, so it
    /// shares this same flag rather than a separate "text_ai_voice" value.
    @State private var usedAIEstimate = false
    /// Per-ingredient breakdown from the latest estimate, shown read-only
    /// for transparency into what was actually estimated -- and, if still
    /// present at save time, persisted alongside the totals (see
    /// meal_log.ingredient_breakdown). Dropped the moment the user edits
    /// any total field afterward (see dropStaleIngredientsIfNeeded): a
    /// breakdown that no longer sums to the saved total would be actively
    /// misleading shown later in MealDetailView.
    @State private var ingredients: [MealIngredient] = []
    /// Guards dropStaleIngredientsIfNeeded from misfiring on the writes
    /// estimate() itself makes to the four total fields -- only a
    /// genuine user edit afterward should clear `ingredients`.
    @State private var isPopulatingFromEstimate = false

    private var calories: Int? { Int(caloriesText) }
    private var protein: Int? { Int(proteinText) }
    private var canSave: Bool { calories != nil && protein != nil && !isSaving }
    private var canEstimate: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEstimating && !speechRecognizer.isListening
    }

    /// Same bounds as meal_log's CHECK constraints. Optional fields pass when blank.
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
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        TextField("What did you eat? e.g. \"2 eggs, toast, and coffee with milk\"", text: $label, axis: .vertical)
                            .lineLimit(1...3)
                        dictateButton
                    }
                    if speechRecognizer.isListening {
                        Label {
                            Text(String(localized: "logMeal.input.listening", defaultValue: "Listening -- tap the mic when you're done, or just stop talking.", comment: "Hint shown while dictating a meal description with the mic"))
                        } icon: {
                            Image(systemName: "waveform")
                        }
                        .font(.caption2)
                        .foregroundStyle(SomaTokens.accent)
                    }
                    if isEstimating {
                        // Shuffled per appearance so back-to-back estimates
                        // in one sitting don't always open on the same fact.
                        SomaLoadingBar(messages: SomaLoadingBar.mealFunFacts.shuffled(), barWidth: 220)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .listRowBackground(Color.clear)
                    } else {
                        Button {
                            Task { await estimate() }
                        } label: {
                            Label("Estimate calories & macros with AI", systemImage: "sparkles")
                        }
                        .disabled(!canEstimate)
                    }
                } footer: {
                    Text(String(localized: "logMeal.footer.description", defaultValue: "Type it, dictate it, or describe your meal in words -- Soma fills in the fields below either way. Review and adjust anything before saving.", comment: "Footer note explaining the meal entry section on the log meal screen"))
                }
                .listRowBackground(SomaTokens.surface2)
                if !ingredients.isEmpty {
                    Section {
                        ForEach(ingredients) { ingredient in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ingredient.name)
                                        .font(.system(size: 13.5))
                                    Text(String(localized: "logMeal.ingredient.grams", defaultValue: "\(Int(ingredient.gramsEstimate.rounded()))g", comment: "Estimated gram portion for one ingredient in the meal breakdown, e.g. '150g'"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(localized: "logMeal.ingredient.macros", defaultValue: "\(ingredient.calories) kcal · \(ingredient.proteinG)g P", comment: "Per-ingredient calorie and protein summary in the meal breakdown, e.g. '250 kcal · 32g P'"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text(String(localized: "logMeal.ingredients.header", defaultValue: "Estimated breakdown", comment: "Header for the read-only per-ingredient estimate list on the log meal screen"))
                    } footer: {
                        Text(String(localized: "logMeal.ingredients.footer", defaultValue: "Editing the totals below clears this breakdown.", comment: "Footer explaining that editing the total fields discards the per-ingredient breakdown"))
                    }
                    .listRowBackground(SomaTokens.surface2)
                }
                Section("Required") {
                    LabeledContent("Calories") {
                        TextField("kcal", text: $caloriesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Protein") {
                        TextField("g", text: $proteinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .listRowBackground(SomaTokens.surface2)
                Section("Optional") {
                    LabeledContent("Carbs") {
                        TextField("g", text: $carbsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Fat") {
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
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
        .onChange(of: speechRecognizer.transcript) { _, newValue in
            label = newValue
        }
        .onChange(of: speechRecognizer.errorMessage) { _, newValue in
            if let newValue { errorMessage = newValue }
        }
        .onChange(of: speechRecognizer.isListening) { wasListening, isListening in
            // The recognizer finalizes on its own once it detects the end
            // of an utterance -- auto-estimating right here is what makes
            // "just dictate" feel like one action instead of two, same as
            // if the user had typed the text and tapped Estimate
            // themselves. Skipped on an error (nothing was said) or an
            // empty result.
            guard wasListening, !isListening, speechRecognizer.errorMessage == nil,
                  !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            Task { await estimate() }
        }
        .onDisappear {
            speechRecognizer.stop()
        }
        .onChange(of: caloriesText) { _, _ in dropStaleIngredientsIfNeeded() }
        .onChange(of: proteinText) { _, _ in dropStaleIngredientsIfNeeded() }
        .onChange(of: carbsText) { _, _ in dropStaleIngredientsIfNeeded() }
        .onChange(of: fatText) { _, _ in dropStaleIngredientsIfNeeded() }
    }

    /// A genuine user edit to any total field after an estimate populated
    /// it invalidates the stored per-ingredient breakdown -- see
    /// `ingredients`'s own doc comment. Guarded by isPopulatingFromEstimate
    /// so estimate()'s own writes to these same fields don't immediately
    /// clear the breakdown it just set.
    private func dropStaleIngredientsIfNeeded() {
        guard !isPopulatingFromEstimate, !ingredients.isEmpty else { return }
        ingredients = []
    }

    private var dictateButton: some View {
        Button {
            toggleDictation()
        } label: {
            Image(systemName: speechRecognizer.isListening ? "mic.fill" : "mic")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(speechRecognizer.isListening ? .white : SomaTokens.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(speechRecognizer.isListening ? SomaTokens.danger : SomaTokens.accentSoft))
        }
        .buttonStyle(.plain)
        .disabled(isEstimating)
    }

    private func toggleDictation() {
        if speechRecognizer.isListening {
            speechRecognizer.stop()
        } else {
            speechRecognizer.start()
        }
    }

    private func estimate() async {
        errorMessage = nil
        isEstimating = true
        defer { isEstimating = false }
        do {
            let result = try await SupabaseClient.shared.parseMealText(label)
            // Item 8: a name the user typed themselves is kept exactly as
            // entered (no Title Case, no translation) -- the AI's shortened
            // label only replaces genuinely long free-text descriptions.
            let typed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if typed.split(whereSeparator: \.isWhitespace).count > 8 {
                label = result.label
            } else {
                label = typed
            }
            isPopulatingFromEstimate = true
            caloriesText = String(result.calories)
            proteinText = String(result.proteinG)
            carbsText = String(result.carbsG)
            fatText = String(result.fatG)
            ingredients = result.ingredients
            isPopulatingFromEstimate = false
            usedAIEstimate = true
        } catch {
            errorMessage = String(localized: "logMeal.estimateFailed", defaultValue: "Couldn't estimate that -- try describing it differently, or enter the numbers below yourself.", comment: "Error shown when AI meal estimation fails")
        }
    }

    private func save() async {
        guard let calories, let protein else { return }
        guard macrosInRange else {
            errorMessage = String(localized: "logMeal.macrosOutOfRange", defaultValue: "Calories should be 0-5000 and macros 0-500g -- check your numbers.", comment: "Validation error shown when entered meal macros are out of allowed range")
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await SupabaseClient.shared.logMeal(
                date: NutritionView.todayDateString(),
                label: label,
                calories: calories,
                proteinG: protein,
                carbsG: Int(carbsText),
                fatG: Int(fatText),
                source: usedAIEstimate ? "text_ai" : "manual",
                ingredients: ingredients.isEmpty ? nil : ingredients
            )
            dismiss()
        } catch {
            errorMessage = String(localized: "logMeal.saveFailed", defaultValue: "Couldn't save that entry. Try again.", comment: "Error shown when saving a meal log entry fails")
        }
    }
}

#Preview {
    LogMealView()
}
