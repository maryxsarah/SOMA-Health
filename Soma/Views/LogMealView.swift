import SwiftUI

/// Quick food entry -- type numbers directly, describe the meal in plain
/// words, or dictate it out loud (mic button, on-device speech-to-text)
/// -- either text path then lets Claude estimate calories/macros
/// (parse-meal-text). Every path lands in the same editable fields
/// below, reviewed and adjustable before Save -- the AI path is an
/// assist, never a silent auto-log. Calories and protein are required
/// (the two numbers most people actually know off-hand); carbs/fat are
/// optional.
struct LogMealView: View {
    let date: String
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
                        Label("Listening -- tap the mic when you're done, or just stop talking.", systemImage: "waveform")
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
                    Text("Type it, dictate it, or describe your meal in words -- Soma fills in the fields below either way. Review and adjust anything before saving.")
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
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
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
            label = result.label
            caloriesText = String(result.calories)
            proteinText = String(result.proteinG)
            carbsText = String(result.carbsG)
            fatText = String(result.fatG)
            usedAIEstimate = true
        } catch {
            errorMessage = "Couldn't estimate that -- try describing it differently, or enter the numbers below yourself."
        }
    }

    private func save() async {
        guard let calories, let protein else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await SupabaseClient.shared.logMeal(
                date: date,
                label: label,
                calories: calories,
                proteinG: protein,
                carbsG: Int(carbsText),
                fatG: Int(fatText),
                source: usedAIEstimate ? "text_ai" : "manual"
            )
            dismiss()
        } catch {
            errorMessage = "Couldn't save that entry. Try again."
        }
    }
}

#Preview {
    LogMealView(date: "2026-08-06")
}
