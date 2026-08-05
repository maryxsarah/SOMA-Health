import SwiftUI

/// Quick food entry -- either type numbers directly, or describe the
/// meal in plain words and let Claude estimate calories/macros first
/// (parse-meal-text). Either way it lands in the same editable fields
/// below, reviewed and adjustable before Save -- the AI path is an
/// assist, never a silent auto-log. Calories and protein are required
/// (the two numbers most people actually know off-hand); carbs/fat are
/// optional.
struct LogMealView: View {
    let date: String
    @Environment(\.dismiss) private var dismiss

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
    /// a number afterward (still AI-assisted provenance).
    @State private var usedAIEstimate = false

    private var calories: Int? { Int(caloriesText) }
    private var protein: Int? { Int(proteinText) }
    private var canSave: Bool { calories != nil && protein != nil && !isSaving }
    private var canEstimate: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEstimating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What did you eat? e.g. \"2 eggs, toast, and coffee with milk\"", text: $label, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        Task { await estimate() }
                    } label: {
                        if isEstimating {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Estimating…")
                            }
                        } else {
                            Label("Estimate calories & macros with AI", systemImage: "sparkles")
                        }
                    }
                    .disabled(!canEstimate)
                } footer: {
                    Text("Describe your meal and Soma will fill in the fields below -- review and adjust anything before saving.")
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
