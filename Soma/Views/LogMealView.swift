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
/// `date` defaults to nil, meaning "today, resolved by save() itself at
/// the moment of the actual write" -- this sheet can stay open through a
/// whole dictate -> AI-estimate -> review round trip, and capturing
/// "today" once when the sheet opens (the old behavior) meant a save
/// that happened to land after local midnight silently wrote yesterday's
/// date, so the entry never showed up in "today's" totals even though it
/// saved successfully. Same fix already applied correctly in
/// MealRecommendationView.logThisMeal.
///
/// A non-nil `date` pins the entry to that exact day regardless of when
/// save() runs -- used when logging for a specific PAST day (Home's
/// swipeable day view / NutritionView's viewingDate), where the day is a
/// deliberate choice the user already made by navigating there, not
/// something that should drift to "whatever now is".
struct LogMealView: View {
    var date: String? = nil
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
            caloriesText = String(result.calories)
            proteinText = String(result.proteinG)
            carbsText = String(result.carbsG)
            fatText = String(result.fatG)
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
                date: date ?? NutritionView.todayDateString(),
                label: label,
                calories: calories,
                proteinG: protein,
                carbsG: Int(carbsText),
                fatG: Int(fatText),
                source: usedAIEstimate ? "text_ai" : "manual"
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
